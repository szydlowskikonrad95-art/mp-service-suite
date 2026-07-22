#!/usr/bin/env bash
# ZYWY DOWOD C6a (konto klienta + passwordless login + panel):
# - weryfikacja zaklada konto WP mp_client i ustawia customers.wp_user_id
# - edge: e-mail istniejacego usera (admin/personel) => podpiecie BEZ zmiany rol
# - panel "moje zgloszenia": klient widzi TYLKO swoje (IDOR)
# - login passwordless: happy path, jednorazowosc, wygasniecie, zly token
# - passwordless WYLACZNIE dla mp_client (admin/personel = odmowa)
# Chodzi na poligonie i w CI (job e2e-import).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ── Sprzatanie: tabele + pending options + testowe konta mp_client ──────────
wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_attachments; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done

ADMIN_EMAIL=$(wp user get 1 --field=user_email 2>/dev/null)

# ── 1. Weryfikacja zaklada konto WP mp_client + ustawia wp_user_id ──────────
OUT=$(wp mp case-create --kind=zapytanie --email='klient1@example.com' --name='Anna Klient' --desc='pytanie o gwarancje' 2>/dev/null)
CID1=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
SRV1=$(echo "$OUT" | grep '^case_number=' | cut -d= -f2)
TOK1=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$TOK1" >/dev/null 2>&1

CUST1=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CID1")
WPU1=$(q "SELECT COALESCE(wp_user_id,'NULL') FROM wp_mp_customers WHERE id=$CUST1")
[ -n "$WPU1" ] && [ "$WPU1" != "NULL" ] && ok "po weryfikacji: customers.wp_user_id ustawione ($WPU1)" || bad "wp_user_id niepodpiete ($WPU1)"

UID1=$(wp user get 'klient1@example.com' --field=ID 2>/dev/null)
ROLES1=$(wp user get "$UID1" --field=roles 2>/dev/null)
[ -n "$UID1" ] && echo "$ROLES1" | grep -q "mp_client" && ok "konto WP mp_client zalozone (user_id=$UID1, role=$ROLES1)" || bad "brak konta mp_client (uid=$UID1 role=$ROLES1)"
[ "$WPU1" = "$UID1" ] && ok "wp_user_id klienta == user_id konta WP" || bad "rozjazd wp_user_id($WPU1) vs user($UID1)"

# ── 2. Edge: e-mail ISTNIEJACEGO usera (admin) => podpiecie BEZ zmiany rol ──
OUTA=$(wp mp case-create --kind=zapytanie --email="$ADMIN_EMAIL" --name='Admin jako klient' --desc='sprawa admina' 2>/dev/null)
CIDA=$(echo "$OUTA" | grep '^case_id=' | cut -d= -f2)
TOKA=$(echo "$OUTA" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$TOKA" >/dev/null 2>&1
CUSTA=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CIDA")
WPUA=$(q "SELECT COALESCE(wp_user_id,'NULL') FROM wp_mp_customers WHERE id=$CUSTA")
ADMIN_ROLES=$(wp user get 1 --field=roles 2>/dev/null)
[ "$WPUA" = "1" ] && ok "sprawa admina podpieta po user_id=1 (edge)" || bad "admin niepodpiety ($WPUA)"
echo "$ADMIN_ROLES" | grep -q "administrator" && ! echo "$ADMIN_ROLES" | grep -q "mp_client" && ok "role admina NIETKNIETE (nadal administrator, nie mp_client)" || bad "role admina zmienione! ($ADMIN_ROLES)"

# ── 3. Panel: klient1 widzi TYLKO swoje sprawy (IDOR) ──────────────────────
OUT2=$(wp mp case-create --kind=zapytanie --email='klient2@example.com' --name='Bob Klient' --desc='inna sprawa' 2>/dev/null)
CID2=$(echo "$OUT2" | grep '^case_id=' | cut -d= -f2)
SRV2=$(echo "$OUT2" | grep '^case_number=' | cut -d= -f2)
TOK2=$(echo "$OUT2" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$TOK2" >/dev/null 2>&1
[ -n "$SRV2" ] && ok "sprawa klienta2 zalozona ($SRV2) — setup IDOR" || bad "setup IDOR: sprawa klienta2 nie powstala (SRV2 puste)"

PANEL1=$(wp eval "wp_set_current_user($UID1); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)
echo "$PANEL1" | grep -q "$SRV1" && ok "panel klienta1 pokazuje jego sprawe ($SRV1)" || bad "panel nie pokazuje wlasnej sprawy"
{ [ -n "$SRV2" ] && echo "$PANEL1" | grep -q "$SRV2"; } && bad "IDOR! panel klienta1 pokazuje cudza sprawe ($SRV2)" || ok "panel klienta1 NIE pokazuje cudzej sprawy (IDOR-safe)"

# Niezalogowany => formularz logowania, ZERO danych spraw.
PANEL_ANON=$(wp eval "wp_set_current_user(0); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)
echo "$PANEL_ANON" | grep -q "mp_intake_login_request" && ! echo "$PANEL_ANON" | grep -q "$SRV1" && ok "niezalogowany: formularz logowania, zero spraw" || bad "niezalogowany widzi dane albo brak formularza"

# ── 4. Login passwordless: happy path + jednorazowosc ──────────────────────
LL=$(wp mp login-link 'klient1@example.com' 2>/dev/null)
SEL=$(echo "$LL" | grep '^selector=' | cut -d= -f2)
LTOK=$(echo "$LL" | grep '^token=' | cut -d= -f2)
[ -n "$SEL" ] && [ -n "$LTOK" ] && ok "login-link wystawiony dla klienta (selector+token)" || bad "login-link nie wystawil tokenu"

RES=$(wp mp login-consume "$SEL" "$LTOK" 2>/dev/null | grep '^user_id=' | cut -d= -f2)
[ "$RES" = "$UID1" ] && ok "login-consume loguje wlasciwego usera (user_id=$RES)" || bad "login-consume zwrocil $RES (oczekiwano $UID1)"

RES2=$(wp mp login-consume "$SEL" "$LTOK" 2>/dev/null | grep '^user_id=' | cut -d= -f2)
[ "$RES2" = "0" ] && ok "jednorazowosc: drugie uzycie linku odrzucone (user_id=0)" || bad "link zadzialal drugi raz! ($RES2)"

# ── 5. Login: zly token odrzucony ──────────────────────────────────────────
LL3=$(wp mp login-link 'klient1@example.com' 2>/dev/null)
SEL3=$(echo "$LL3" | grep '^selector=' | cut -d= -f2)
RESBAD=$(wp mp login-consume "$SEL3" 'zly-token-1234567890' 2>/dev/null | grep '^user_id=' | cut -d= -f2)
[ "$RESBAD" = "0" ] && ok "zly walidator odrzucony (user_id=0)" || bad "zly token zalogowal! ($RESBAD)"

# ── 6. Login: wygasly link odrzucony ───────────────────────────────────────
LL4=$(wp mp login-link 'klient1@example.com' 2>/dev/null)
SEL4=$(echo "$LL4" | grep '^selector=' | cut -d= -f2)
TOK4=$(echo "$LL4" | grep '^token=' | cut -d= -f2)
wp user meta update "$UID1" _mp_login_exp 1 >/dev/null 2>&1
RESEXP=$(wp mp login-consume "$SEL4" "$TOK4" 2>/dev/null | grep '^user_id=' | cut -d= -f2)
[ "$RESEXP" = "0" ] && ok "wygasly link odrzucony (user_id=0)" || bad "wygasly link zalogowal! ($RESEXP)"

# ── 7. Passwordless NIEDOSTEPNE dla admina/personelu ───────────────────────
LLADMIN=$(wp mp login-link "$ADMIN_EMAIL" 2>&1)
echo "$LLADMIN" | grep -qi "Brak konta klienta" && ! echo "$LLADMIN" | grep -q "^token=" && ok "passwordless odmowiony dla admina (nie mp_client)" || bad "admin dostal link passwordless! ($LLADMIN)"

echo
echo "WYNIK C6a: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
