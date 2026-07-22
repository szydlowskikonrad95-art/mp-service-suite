#!/usr/bin/env bash
# ZYWY DOWOD C6b-1 (wiadomosci na panelu klienta):
# - historia wiadomosci renderuje sie w panelu (autor Serwis/Ty)
# - zalogowany klient wysyla wiadomosc na WLASNA sprawe (POST admin-post)
# - IDOR: klient NIE moze pisac na cudza sprawe (ownership blokuje mimo waznego nonce)
# - sprawa zamknieta: wysylka DOZWOLONA + nota (tabletop S5)
# Wymaga MP_BASE (front HTTP). Chodzi na poligonie i w CI (e2e-import).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_consents;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done

# ── Dwaj klienci ze sprawami (po weryfikacji = konta mp_client) ─────────────
O1=$(wp mp case-create --kind=zapytanie --email='c1@example.com' --name='Klient 1' --desc='sprawa 1' 2>/dev/null)
T1=$(echo "$O1" | grep '^token=' | cut -d= -f2); wp mp case-verify "$T1" >/dev/null 2>&1
O2=$(wp mp case-create --kind=zapytanie --email='c2@example.com' --name='Klient 2' --desc='sprawa 2' 2>/dev/null)
T2=$(echo "$O2" | grep '^token=' | cut -d= -f2); wp mp case-verify "$T2" >/dev/null 2>&1

UID1=$(wp user get 'c1@example.com' --field=ID 2>/dev/null)
CID1=$(q "SELECT s.id FROM wp_mp_service_cases s INNER JOIN wp_mp_customers c ON s.customer_id=c.id WHERE c.email='c1@example.com'")
CID2=$(q "SELECT s.id FROM wp_mp_service_cases s INNER JOIN wp_mp_customers c ON s.customer_id=c.id WHERE c.email='c2@example.com'")
[ -n "$CID1" ] && [ -n "$CID2" ] && ok "setup: dwie sprawy klientow (c1=$CID1, c2=$CID2)" || bad "setup spraw nieudany"

# Wiadomosc serwisu na sprawie c1 (do historii).
wp eval "MP\Intake\Messages::add($CID1, 'staff', 1, 'Odpowiedz serwisu do c1');" >/dev/null 2>&1

# ── 1. Panel c1: historia + formularz wysylki; ZERO sprawy c2 (IDOR render) ──
PANEL=$(wp eval "wp_set_current_user($UID1); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)
echo "$PANEL" | grep -q "Odpowiedz serwisu do c1" && ok "panel c1 pokazuje historie (wiadomosc serwisu)" || bad "panel bez historii"
echo "$PANEL" | grep -q 'name="action" value="mp_intake_message"' && ok "panel c1 ma formularz wysylki" || bad "brak formularza wysylki"

# ── 2. HTTP: logowanie c1 haslem -> wysylka wiadomosci na WLASNA sprawe ──────
wp user update "$UID1" --user_pass='Test12345!' >/dev/null 2>&1
JAR=/tmp/mp-c6b-jar; rm -f "$JAR"
curl -s -c "$JAR" -o /dev/null "$MP_BASE/wp-login.php"   # test cookie
curl -s -c "$JAR" -b "$JAR" -o /dev/null \
	--data-urlencode "log=c1@example.com" --data-urlencode "pwd=Test12345!" \
	--data-urlencode "wp-submit=Zaloguj" --data-urlencode "redirect_to=$MP_BASE/wp-admin/" \
	"$MP_BASE/wp-login.php"
LOGGED=$(curl -s -b "$JAR" "$MP_BASE/wp-admin/profile.php" -o /dev/null -w '%{http_code}')
[ "$LOGGED" = "200" ] && ok "klient c1 zalogowany (HTTP sesja)" || bad "logowanie c1 nieudane (HTTP $LOGGED)"

# Realny nonce z wyrenderowanego panelu (zwiazany z sesja HTTP — eval-nonce ma pusty session token).
PAGE_ID=$(wp option get mp_account_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
PANEL_HTTP=$(curl -s -b "$JAR" "$MP_BASE$PAGE_PATH")
FORM_CID=$(echo "$PANEL_HTTP" | grep -o 'name="case_id" value="[0-9]*"' | head -1 | grep -oE '[0-9]+')
# Nonce formularza WYSYLKI (nie danych kontaktowych) — kotwica na akcji mp_intake_message.
RNONCE=$(echo "$PANEL_HTTP" | grep -o 'value="mp_intake_message".*' | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
{ [ "$FORM_CID" = "$CID1" ] && [ -n "$RNONCE" ]; } && ok "panel HTTP c1: formularz wlasnej sprawy + realny nonce" || bad "panel HTTP: form_cid=$FORM_CID nonce=$RNONCE"

curl -s -b "$JAR" -o /dev/null \
	--data-urlencode "action=mp_intake_message" --data-urlencode "case_id=$CID1" \
	--data-urlencode "_mp_nonce=$RNONCE" --data-urlencode "body=Wiadomosc od klienta c1" \
	"$MP_BASE/wp-admin/admin-post.php"
CLIMSG=$(q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CID1 AND author_type='client'")
[ "$CLIMSG" = "1" ] && ok "klient c1 wyslal wiadomosc na wlasna sprawe (author_type=client)" || bad "wiadomosc klienta niezapisana ($CLIMSG)"

# ── 3. IDOR: c1 podmienia case_id na sprawe c2 z WAZNYM nonce => ownership blokuje ──
# Nonce = CSRF (jedna akcja, wazny dla c1); ownership = autoryzacja (sprawa c2 nie jego).
curl -s -b "$JAR" -o /dev/null \
	--data-urlencode "action=mp_intake_message" --data-urlencode "case_id=$CID2" \
	--data-urlencode "_mp_nonce=$RNONCE" --data-urlencode "body=Atak IDOR" \
	"$MP_BASE/wp-admin/admin-post.php"
IDOR=$(q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CID2 AND author_type='client'")
[ "$IDOR" = "0" ] && ok "cross-case POST blokowany (c1 nie dopisze do sprawy c2)" || bad "IDOR! c1 dopisal do sprawy c2 ($IDOR)"

# ── 4. Sprawa zamknieta: nota widoczna + wysylka nadal dozwolona ────────────
# REALNA droga (change_status, nie seed) — anty-drift #14 (slug 'zamknięte' z ę).
wp eval "apply_filters('mp_case_change_status', null, $CID1, 'zamknięte', 'nowe', 1);" >/dev/null 2>&1
PANELC=$(wp eval "wp_set_current_user($UID1); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)
echo "$PANELC" | grep -qi "zamkni" && ok "sprawa zamknieta: nota widoczna w panelu" || bad "brak noty zamkniecia"
echo "$PANELC" | grep -q 'name="action" value="mp_intake_message"' && ok "sprawa zamknieta: formularz wysylki nadal jest (S5)" || bad "brak formularza przy zamknietej"

echo
echo "WYNIK C6b-1: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
