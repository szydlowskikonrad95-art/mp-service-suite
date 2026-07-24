#!/usr/bin/env bash
# ZYWY DOWOD (przebieg krok 8 — „po zamknieciu generuje raport koncowy"): przy przejsciu
# sprawy w status 'zamknięte' D sklada raport i dopisuje wpis SYSTEMOWY (mp_case_add_system_message)
# widoczny w panelu klienta. Tresc: numer SRV, rodzaj, data zamkniecia, czas obslugi, podziekowanie.
# Zdarzenie CLOSING_REPORT_GENERATED w rejestrze D. Zmiana NIE-koncowa => BRAK raportu. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
raw() { wp db query "$1" --skip-column-names 2>/dev/null; }

mk() { # $1=email $2=serial
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='Jan Kowalski' --serial="$2" --document='FV/2026/9' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\\Intake\\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}
chs() { wp eval "apply_filters('mp_case_change_status', null, $1, '$2', '$3', 1, null);" >/dev/null 2>&1; }

# ── 0. Czysty stan + seed domyslny ──────────────────────────────────────────
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1

CID=$(mk klient@example.com RAP-1)
SRV=$(q "SELECT case_number FROM wp_mp_service_cases WHERE id=$CID")
[ -n "$CID" ] && ok "sprawa utworzona i zweryfikowana ($SRV)" || bad "brak case_id"

# ── 1. Zmiana NIE-koncowa (nowe->w analizie) => BRAK raportu ─────────────────
chs "$CID" "w analizie" "nowe"
R0=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='CLOSING_REPORT_GENERATED'")
M0=$(q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CID AND author_type='system'")
[ "$R0" = "0" ] && [ "$M0" = "0" ] && ok "zmiana nie-koncowa (w analizie): BRAK raportu i wpisu systemowego" || bad "raport przy nie-zamknieciu (ev=$R0 msg=$M0)"

# ── 2. Zamkniecie (w analizie->zamknięte) => RAPORT KONCOWY ──────────────────
chs "$CID" "zamknięte" "w analizie"

CRG=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='CLOSING_REPORT_GENERATED'")
[ "$CRG" = "1" ] && ok "zdarzenie CLOSING_REPORT_GENERATED zapisane (audyt D)" || bad "brak CLOSING_REPORT_GENERATED ($CRG)"

MSYS=$(q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CID AND author_type='system'")
[ "$MSYS" = "1" ] && ok "wpis SYSTEMOWY dopisany do sprawy (widoczny w panelu klienta)" || bad "brak/za duzo wpisow systemowych ($MSYS)"

BODY=$(raw "SELECT body FROM wp_mp_messages WHERE case_id=$CID AND author_type='system' ORDER BY id DESC LIMIT 1")
echo "$BODY" | grep -q "$SRV" && ok "raport zawiera numer sprawy ($SRV)" || bad "raport bez numeru sprawy"
echo "$BODY" | grep -q "została zamknięta" && ok "raport: tresc o zamknieciu sprawy" || bad "raport bez tresci zamkniecia"
echo "$BODY" | grep -qi "Rodzaj zgłoszenia" && ok "raport: rodzaj zgloszenia" || bad "raport bez rodzaju"
echo "$BODY" | grep -qi "Czas obsługi" && ok "raport: czas obslugi" || bad "raport bez czasu obslugi"
echo "$BODY" | grep -qi "Dziękujemy" && ok "raport: podziekowanie (klient-friendly)" || bad "raport bez podziekowania"

# ── 3. NO-PII: raport nie zdradza kontaktu klienta ──────────────────────────
echo "$BODY" | grep -qiE "klient@example|Jan Kowalski" && bad "raport WYCIEKA kontakt klienta (PII)!" || ok "raport NO-PII (bez maila/imienia klienta)"

echo ""
echo "D-RAPORT-KONCOWY: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
