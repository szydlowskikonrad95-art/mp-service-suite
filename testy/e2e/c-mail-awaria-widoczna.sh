#!/usr/bin/env bash
# ZYWY DOWOD (audyt 27.07 — soczewki „obserwowalnosc" i „awarie", dwa niezalezne trafienia):
# BUG: wysylka maili w Intake (magic-link, ponowny link, potwierdzenie z numerem SRV,
# link logowania) ignorowala wynik wp_mail(). Gdy hosting klienta odmawia wysylki,
# klient nie dostaje linku, formularz i tak mowi „sprawdz skrzynke", a w bazie ZERO
# sladu — nikt sie nie dowie, dlaczego zgloszenia przestaly sie potwierdzac.
# Wzorzec poprawny istnial obok, w Automatorze (Sla::notify: log MAIL_FAILED + alert).
# FIX: jedno gardlo wysylki w Mailer::deliver() — porazka zapisuje MAIL_FAILED na osi
# sprawy (gdy sprawa znana) + podnosi alert widoczny w Narzedzia -> Stan witryny.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

ALERT_OPT='mp_intake_mail_alert'

# ── 0. Seed: sprawa, do ktorej podepniemy zdarzenie ──────────────────────────
CID=$(wp eval '
 $r = MP\Intake\CaseRepo::create( array(
   "kind"   => "reklamacja",
   "email"  => "mail-awaria@example.com",
   "values" => array(
     "serial" => "MAILAWARIA1", "purchase_document" => "FV/MA/1", "purchase_date" => "2026-05-01",
     "issue_description" => "test widocznosci awarii poczty",
   ),
 ) );
 echo isset( $r["case_id"] ) ? $r["case_id"] : ( "ERR:" . ( $r["error"] ?? "?" ) );' 2>/dev/null | tr -d '[:space:]')
[[ "$CID" =~ ^[0-9]+$ ]] && ok "seed: sprawa testowa (id=$CID)" || bad "seed: brak sprawy ($CID)"

wp option delete "$ALERT_OPT" >/dev/null 2>&1
EV_BEFORE=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='MAIL_FAILED'")

# ── 1. SMTP ODMAWIA (pre_wp_mail => false) => slad MUSI powstac ──────────────
wp eval "add_filter('pre_wp_mail', '__return_false'); MP\\Intake\\Front\\Mailer::send_magic_link('mail-awaria@example.com', 'token-testowy', $CID);" >/dev/null 2>&1
EV_AFTER=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='MAIL_FAILED'")
[ "${EV_AFTER:-0}" -gt "${EV_BEFORE:-0}" ] 2>/dev/null \
	&& ok "awaria magic-linku ZAPISANA na osi sprawy (MAIL_FAILED)" \
	|| bad "awaria magic-linku BEZ SLADU (przed=$EV_BEFORE po=$EV_AFTER)"

ALERT=$(wp option get "$ALERT_OPT" --format=json 2>/dev/null)
[ -n "$ALERT" ] && [ "$ALERT" != "false" ] \
	&& ok "alert poczty podniesiony (widoczny w Stanie witryny)" \
	|| bad "alert poczty NIE podniesiony (opcja pusta)"

# rodzaj maila w payloadzie => obsluga wie, KTORY mail nie poszedl
KIND=$(q "SELECT payload FROM wp_mp_case_events WHERE case_id=$CID AND event_type='MAIL_FAILED' ORDER BY id DESC LIMIT 1")
echo "$KIND" | grep -q "magic_link" \
	&& ok "payload mowi KTORY mail padl (magic_link)" \
	|| bad "payload bez rodzaju maila ($KIND)"

# ── 2. Potwierdzenie z numerem SRV — ta sama sciezka ─────────────────────────
wp eval "add_filter('pre_wp_mail', '__return_false'); MP\\Intake\\Front\\Mailer::send_confirmation('mail-awaria@example.com', 'SRV/2026/09999', $CID);" >/dev/null 2>&1
CONF=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='MAIL_FAILED' AND payload LIKE '%potwierdzenie%'")
[ "${CONF:-0}" -ge 1 ] 2>/dev/null \
	&& ok "awaria maila z numerem SRV rowniez zapisana" \
	|| bad "mail z numerem SRV padl BEZ SLADU"

# ── 3. Link logowania (bez sprawy) => alert MUSI dzialac tez bez case_id ─────
wp option delete "$ALERT_OPT" >/dev/null 2>&1
wp eval "add_filter('pre_wp_mail', '__return_false'); MP\\Intake\\Front\\Mailer::send_login_link('mail-awaria@example.com', 'sel', 'tok');" >/dev/null 2>&1
ALERT2=$(wp option get "$ALERT_OPT" --format=json 2>/dev/null)
[ -n "$ALERT2" ] && [ "$ALERT2" != "false" ] \
	&& ok "awaria linku logowania (bez sprawy) tez podnosi alert" \
	|| bad "link logowania padl bez alertu"

# ── 4. PRZYPADEK BEZ PROBLEMU: wysylka OK => zero nowych sladow, alert czysty ─
wp option delete "$ALERT_OPT" >/dev/null 2>&1
BEFORE_OK=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='MAIL_FAILED'")
wp eval "MP\\Intake\\Front\\Mailer::send_magic_link('mail-awaria@example.com', 'token-testowy', $CID);" >/dev/null 2>&1
AFTER_OK=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='MAIL_FAILED'")
[ "$AFTER_OK" = "$BEFORE_OK" ] \
	&& ok "wysylka udana NIE zasmieca osi sprawy (brak falszywych MAIL_FAILED)" \
	|| bad "udana wysylka zapisala MAIL_FAILED! ($BEFORE_OK -> $AFTER_OK)"

ALERT3=$(wp option get "$ALERT_OPT" --format=json 2>/dev/null)
{ [ -z "$ALERT3" ] || [ "$ALERT3" = "false" ]; } \
	&& ok "udana wysylka NIE podnosi alertu" \
	|| bad "alert podniesiony mimo udanej wysylki ($ALERT3)"

# ── 5. Stan witryny WIDZI alert (nie tylko baza) ─────────────────────────────
wp eval "update_option('$ALERT_OPT', array('kind'=>'magic_link','time'=>gmdate('Y-m-d H:i:s')), false);" >/dev/null 2>&1
SH=$(wp eval '$t = MP\Intake\Admin\SiteHealthTests::test_poczta_wysylka(); echo isset($t["status"]) ? $t["status"] : "brak";' 2>/dev/null | tr -d '[:space:]')
[ "$SH" = "critical" ] || [ "$SH" = "recommended" ] \
	&& ok "Stan witryny zglasza problem z poczta (status=$SH)" \
	|| bad "Stan witryny NIE widzi awarii poczty (status=$SH)"

wp option delete "$ALERT_OPT" >/dev/null 2>&1

echo ""
echo "WYNIK C-MAIL-AWARIA: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
