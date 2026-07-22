#!/usr/bin/env bash
# ZYWY DOWOD C6b-2a (edycja danych kontaktowych, art. 16):
# - panel pokazuje formularz danych (prefill name/phone + email read-only)
# - zalogowany klient zapisuje nowe name/phone (POST) -> rekord zaktualizowany
# - e-mail (klucz tozsamosci) NIE zmieniany
# Wymaga MP_BASE. Chodzi na poligonie i w CI (e2e-import).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_consents;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done

# Klient ze sprawa (po weryfikacji = konto + rekord klienta z name/phone).
O1=$(wp mp case-create --kind=zapytanie --email='dane@example.com' --name='Jan Stary' --desc='sprawa' 2>/dev/null)
T1=$(echo "$O1" | grep '^token=' | cut -d= -f2); wp mp case-verify "$T1" >/dev/null 2>&1
UID1=$(wp user get 'dane@example.com' --field=ID 2>/dev/null)
CUSTID=$(q "SELECT id FROM wp_mp_customers WHERE email='dane@example.com'")

# ── 1. Panel: formularz danych z prefillem + email read-only ────────────────
PANEL=$(wp eval "wp_set_current_user($UID1); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)
echo "$PANEL" | grep -q 'name="action" value="mp_intake_update_contact"' && ok "panel ma formularz danych kontaktowych" || bad "brak formularza danych"
echo "$PANEL" | grep -q 'value="Jan Stary"' && ok "formularz prefilluje aktualne imie (Jan Stary)" || bad "brak prefillu imienia"
echo "$PANEL" | grep -q 'dane@example.com' && ok "e-mail pokazany (read-only)" || bad "brak e-maila w panelu"

# ── 2. HTTP: logowanie + zapis nowych danych ────────────────────────────────
wp user update "$UID1" --user_pass='Test12345!' >/dev/null 2>&1
JAR=/tmp/mp-c6b2-jar; rm -f "$JAR"
curl -s -c "$JAR" -o /dev/null "$MP_BASE/wp-login.php"
curl -s -c "$JAR" -b "$JAR" -o /dev/null \
	--data-urlencode "log=dane@example.com" --data-urlencode "pwd=Test12345!" \
	--data-urlencode "wp-submit=Zaloguj" --data-urlencode "redirect_to=$MP_BASE/wp-admin/" \
	"$MP_BASE/wp-login.php"

PAGE_ID=$(wp option get mp_account_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
PANEL_HTTP=$(curl -s -b "$JAR" "$MP_BASE$PAGE_PATH")
# Nonce formularza danych = pierwszy _mp_nonce (formularz danych renderuje sie przed sprawami).
RNONCE=$(echo "$PANEL_HTTP" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$RNONCE" ] && ok "panel HTTP: nonce formularza danych" || bad "brak nonce"

curl -s -b "$JAR" -o /dev/null \
	--data-urlencode "action=mp_intake_update_contact" \
	--data-urlencode "_mp_nonce=$RNONCE" \
	--data-urlencode "name=Jan Nowy" --data-urlencode "phone=600100200" \
	"$MP_BASE/wp-admin/admin-post.php"

NEWNAME=$(q "SELECT name FROM wp_mp_customers WHERE id=$CUSTID")
NEWPHONE=$(q "SELECT phone FROM wp_mp_customers WHERE id=$CUSTID")
NEWMAIL=$(q "SELECT email FROM wp_mp_customers WHERE id=$CUSTID")
echo "$NEWNAME" | grep -q "JanNowy" && ok "imie zaktualizowane (art. 16): $NEWNAME" || bad "imie nie zapisane: $NEWNAME"
[ "$NEWPHONE" = "600100200" ] && ok "telefon zaktualizowany: $NEWPHONE" || bad "telefon nie zapisany: $NEWPHONE"
[ "$NEWMAIL" = "dane@example.com" ] && ok "e-mail NIE zmieniony (klucz tozsamosci)" || bad "e-mail zmieniony! $NEWMAIL"

echo
echo "WYNIK C6b-2a: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
