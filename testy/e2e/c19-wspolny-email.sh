#!/usr/bin/env bash
# ZYWY DOWOD C19 (znalezisko #10 audytu 27.07 — wspolny e-mail = cudze sprawy):
# Jeden adres e-mail moze obslugiwac WIELE OSOB (wspolna skrzynka sekretariatu
# w instytucji publicznej to norma). System NIE MOZE sklejac roznych osob:
# - inna osoba (inne nazwisko) => OSOBNY rekord klienta, dane pierwszej osoby NIETKNIETE
# - ta sama osoba (nazwisko rozni sie wielkoscia liter/spacjami) => TEN SAM rekord
# - oba rekordy dziela JEDNO konto WP (skrzynka = login, WP wymaga unikalnego e-maila)
# - "Wycofaj zgode i usun moje dane" przy koncie z >1 klientem => ODMOWA serwera,
#   nawet ze STARYM waznym nonce (jedna osoba nie moze skasowac danych DRUGIEJ);
#   panel zamiast formularzy pokazuje wyjasnienie.
# Wymaga MP_BASE. Chodzi na poligonie i w CI.
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
# UWAGA: q() usuwa CALE biale znaki z wyniku — oczekiwania tez pisz bez spacji.
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_attachments;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done

EMAIL='biuro@example.com'

# ── Krok 1: Anna zgłasza i weryfikuje (konto = 1 osoba) ──────────────────────
O1=$(wp mp case-create --kind=zapytanie --email="$EMAIL" --name='Anna Pierwsza' --desc='sprawa Anny' 2>/dev/null)
T1=$(echo "$O1" | grep '^token=' | cut -d= -f2)
C1=$(echo "$O1" | grep '^case_id=' | cut -d= -f2)
wp mp case-verify "$T1" >/dev/null 2>&1

# ── Krok 2: login + nonce POKI konto ma 1 osobe (realny atak: stara zakladka) ─
CUID=$(wp user get "$EMAIL" --field=ID 2>/dev/null)
wp user update "$CUID" --user_pass='Test12345!' >/dev/null 2>&1
JAR=/tmp/mp-c19-jar; rm -f "$JAR"
curl -s -c "$JAR" -o /dev/null "$MP_BASE/wp-login.php"
curl -s -c "$JAR" -b "$JAR" -o /dev/null \
	--data-urlencode "log=$EMAIL" --data-urlencode "pwd=Test12345!" \
	--data-urlencode "wp-submit=Zaloguj" --data-urlencode "redirect_to=$MP_BASE/wp-admin/" \
	"$MP_BASE/wp-login.php"
PAGE_ID=$(wp option get mp_account_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
PANEL1=$(curl -s -b "$JAR" "$MP_BASE$PAGE_PATH")
NONCE=$(echo "$PANEL1" | grep -o 'value="mp_intake_withdraw".*' | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "konto 1-osobowe: formularz wycofania DOSTEPNY (nonce jest)" || bad "brak nonce przy koncie 1-osobowym"

# ── Krok 3: Bartek (INNA osoba) zgłasza z tego samego adresu ─────────────────
O2=$(wp mp case-create --kind=zapytanie --email="$EMAIL" --name='Bartek Drugi' --desc='sprawa Bartka' 2>/dev/null)
T2=$(echo "$O2" | grep '^token=' | cut -d= -f2)
C2=$(echo "$O2" | grep '^case_id=' | cut -d= -f2)
wp mp case-verify "$T2" >/dev/null 2>&1

# ── Scenariusz A: dwie ROZNE osoby = dwa rekordy ─────────────────────────────
ILU=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE email='$EMAIL' AND anonymized_at IS NULL")
[ "$ILU" = "2" ] && ok "inna osoba = OSOBNY rekord klienta (jest $ILU)" || bad "osoby sklejone w jeden rekord (klientow: $ILU, oczekiwane 2)"

CUST1=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$C1")
CUST2=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$C2")
[ -n "$CUST1" ] && [ -n "$CUST2" ] && [ "$CUST1" != "$CUST2" ] \
	&& ok "sprawy naleza do ROZNYCH klientow ($CUST1 vs $CUST2)" \
	|| bad "sprawa Bartka wpieta w rekord Anny (customer_id: $CUST1 vs $CUST2)"

NAME1=$(q "SELECT name FROM wp_mp_customers WHERE id=${CUST1:-0}")
[ "$NAME1" = "AnnaPierwsza" ] && ok "dane Anny NIETKNIETE po zgloszeniu Bartka" || bad "dane Anny nadpisane cudzymi ($NAME1)"

WPU1=$(q "SELECT COALESCE(wp_user_id,0) FROM wp_mp_customers WHERE id=${CUST1:-0}")
WPU2=$(q "SELECT COALESCE(wp_user_id,0) FROM wp_mp_customers WHERE id=${CUST2:-0}")
[ "$WPU1" != "0" ] && [ "$WPU1" = "$WPU2" ] \
	&& ok "oba rekordy dziela jedno konto WP (skrzynka = login, uid=$WPU1)" \
	|| bad "rekordy nie dziela konta WP ($WPU1 vs $WPU2)"

# ── Scenariusz B: TA SAMA osoba wraca (normalizacja nazwiska) ────────────────
ID3=$(wp eval 'echo MP\Intake\Customers::upsert_by_email("biuro@example.com", "  anna   PIERWSZA ", "111222333");' 2>/dev/null)
[ "$ID3" = "$CUST1" ] && ok "ta sama osoba (inne spacje/wielkosc liter) = TEN SAM rekord" || bad "ta sama osoba dostala nowy rekord ($ID3 vs $CUST1)"
PHONE1=$(q "SELECT phone FROM wp_mp_customers WHERE id=${CUST1:-0}")
[ "$PHONE1" = "111222333" ] && ok "telefon tej samej osoby zaktualizowany" || bad "telefon niezaktualizowany ($PHONE1)"
NAME1B=$(q "SELECT name FROM wp_mp_customers WHERE id=${CUST1:-0}")
[ "$NAME1B" = "AnnaPierwsza" ] && ok "pisownia nazwiska Anny zachowana (pierwotna)" || bad "nazwisko Anny przepisane ($NAME1B)"
ILU2=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE email='$EMAIL' AND anonymized_at IS NULL")
[ "$ILU2" = "2" ] && ok "brak trzeciego rekordu po powrocie Anny" || bad "powrot Anny stworzyl duplikat (klientow: $ILU2)"

# ── Scenariusz C: wycofanie zgody przy koncie 2 osob => ODMOWA serwera ───────
wp eval "MP\Intake\Consents::record('$EMAIL', $C1, MP\Intake\Consents::KEY_PROCESSING, MP\Intake\Consents::VERSION, MP\Intake\Consents::processing_text());" >/dev/null 2>&1
wp db query "UPDATE wp_mp_consents SET customer_id=$CUST1 WHERE case_id=$C1" >/dev/null 2>&1

# Zamknij OBIE sprawy — bez tego eraser i tak by odroczyl (aktywna sprawa),
# a test ma dowodzic ODMOWY, nie odroczenia.
wp eval "apply_filters('mp_case_change_status', null, $C1, 'zamknięte', 'nowe', 1);" >/dev/null 2>&1
wp eval "apply_filters('mp_case_change_status', null, $C2, 'zamknięte', 'nowe', 1);" >/dev/null 2>&1

# POST ze STARYM (waznym) nonce z kroku 2 — serwer MUSI odmowic sam.
curl -s -b "$JAR" -o /dev/null --data-urlencode "action=mp_intake_withdraw" --data-urlencode "_mp_nonce=$NONCE" "$MP_BASE/wp-admin/admin-post.php"

# Po ID, nie po e-mailu — anonimizacja przepisuje email na anon-...@removed.invalid.
ANON=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE id IN (${CUST1:-0},${CUST2:-0}) AND anonymized_at IS NOT NULL")
[ "$ANON" = "0" ] && ok "ODMOWA: zaden klient nie zanonimizowany (cudze dane bezpieczne)" || bad "wycofanie skasowalo dane przy koncie wspoldzielonym! (zanonimizowanych: $ANON)"
WDR=$(q "SELECT COUNT(*) FROM wp_mp_consents WHERE case_id=$C1 AND withdrawn_at IS NOT NULL")
[ "$WDR" = "0" ] && ok "ODMOWA: zgoda Anny nie wycofana przez cudza sesje" || bad "zgoda wycofana mimo konta wspoldzielonego"
SPRAWY=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id IN ($C1,$C2)")
[ "$SPRAWY" = "2" ] && ok "obie sprawy istnieja nietkniete" || bad "sprawa znikla ($SPRAWY z 2)"

# ── Scenariusz D: panel konta wspoldzielonego mowi prawde (bez martwych form) ─
PANEL2=$(curl -s -b "$JAR" "$MP_BASE$PAGE_PATH")
echo "$PANEL2" | grep -q 'value="mp_intake_withdraw"' \
	&& bad "panel wspoldzielony wciaz pokazuje przycisk wycofania (obiecuje cos, czego POST odmowi)" \
	|| ok "panel wspoldzielony: formularz wycofania SCHOWANY"
echo "$PANEL2" | grep -q 'value="mp_intake_update_contact"' \
	&& bad "panel wspoldzielony wciaz pokazuje edycje danych (nadpisalaby cudze)" \
	|| ok "panel wspoldzielony: edycja danych SCHOWANA"
echo "$PANEL2" | grep -q 'korzysta' \
	&& ok "panel wspoldzielony: wyjasnienie dla klienta widoczne" \
	|| bad "brak wyjasnienia w panelu wspoldzielonym"

echo
echo "WYNIK C19: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
