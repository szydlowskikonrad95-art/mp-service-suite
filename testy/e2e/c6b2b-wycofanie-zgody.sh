#!/usr/bin/env bash
# ZYWY DOWOD C6b-2b (wycofanie zgody self-service + eraser, RODO):
# - wycofanie = withdrawn_at + event CONSENT_WITHDRAWN na sprawach (art. 7(3))
# - sprawa AKTYWNA => eraser ODRACZA (dane nietkniete, items_retained)
# - sprawa ZAMKNIETA => eraser USUWA (klient zanonimizowany)
# - FLAGA #6: e-mail w tabeli CONSENTS zredagowany przy usunieciu, tekst zgody ZOSTAJE
# Wymaga MP_BASE. Chodzi na poligonie i w CI (e2e-import).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Logowanie klienta haslem + zwrot nonce formularza wycofania z panelu.
# $1=email $2=uid $3=jar  -> echo nonce
login_and_withdraw_nonce() {
	local email="$1" uid="$2" jar="$3"
	wp user update "$uid" --user_pass='Test12345!' >/dev/null 2>&1
	rm -f "$jar"
	curl -s -c "$jar" -o /dev/null "$MP_BASE/wp-login.php"
	curl -s -c "$jar" -b "$jar" -o /dev/null \
		--data-urlencode "log=$email" --data-urlencode "pwd=Test12345!" \
		--data-urlencode "wp-submit=Zaloguj" --data-urlencode "redirect_to=$MP_BASE/wp-admin/" \
		"$MP_BASE/wp-login.php"
	local page_id page_path panel
	page_id=$(wp option get mp_account_page_id 2>/dev/null)
	page_path=$(wp post url "$page_id" 2>/dev/null | sed 's#^https\?://[^/]*##')
	panel=$(curl -s -b "$jar" "$MP_BASE$page_path")
	echo "$panel" | grep -o 'value="mp_intake_withdraw".*' | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//'
}

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_attachments;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done

# ── Scenariusz A: sprawa AKTYWNA => wycofanie + ODROCZENIE erasera ───────────
OA=$(wp mp case-create --kind=zapytanie --email='akt@example.com' --name='Aktywny' --desc='sprawa' 2>/dev/null)
TA=$(echo "$OA" | grep '^token=' | cut -d= -f2); wp mp case-verify "$TA" >/dev/null 2>&1
UIDA=$(wp user get 'akt@example.com' --field=ID 2>/dev/null)
CUSTA=$(q "SELECT id FROM wp_mp_customers WHERE email='akt@example.com'")
CIDA=$(q "SELECT id FROM wp_mp_service_cases WHERE customer_id=$CUSTA")
wp eval "MP\Intake\Consents::record('akt@example.com', $CIDA, MP\Intake\Consents::KEY_PROCESSING, MP\Intake\Consents::VERSION, MP\Intake\Consents::processing_text());" >/dev/null 2>&1
wp db query "UPDATE wp_mp_consents SET customer_id=$CUSTA WHERE case_id=$CIDA" >/dev/null 2>&1

NA=$(login_and_withdraw_nonce 'akt@example.com' "$UIDA" /tmp/mp-a-jar)
[ -n "$NA" ] && ok "panel HTTP (aktywny): nonce formularza wycofania" || bad "brak nonce wycofania (aktywny)"
curl -s -b /tmp/mp-a-jar -o /dev/null --data-urlencode "action=mp_intake_withdraw" --data-urlencode "_mp_nonce=$NA" "$MP_BASE/wp-admin/admin-post.php"

WDRA=$(q "SELECT withdrawn_at FROM wp_mp_consents WHERE customer_id=$CUSTA")
{ [ -n "$WDRA" ] && [ "$WDRA" != "NULL" ]; } && ok "zgoda wycofana (withdrawn_at ustawione, art. 7(3))" || bad "zgoda niewycofana ($WDRA)"
EVA=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CIDA AND event_type='CONSENT_WITHDRAWN'")
[ "$EVA" -ge 1 ] && ok "event CONSENT_WITHDRAWN na sprawie ($EVA)" || bad "brak eventu CONSENT_WITHDRAWN"
ANONA=$(q "SELECT COALESCE(anonymized_at,'NULL') FROM wp_mp_customers WHERE id=$CUSTA")
[ "$ANONA" = "NULL" ] && ok "sprawa AKTYWNA => eraser ODROCZYL (klient nietkniety)" || bad "klient zanonimizowany mimo aktywnej sprawy! ($ANONA)"

# ── Scenariusz B: sprawa ZAMKNIETA => wycofanie + USUNIECIE + FLAGA #6 ───────
OB=$(wp mp case-create --kind=zapytanie --email='zam@example.com' --name='Zamkniety' --desc='sprawa' 2>/dev/null)
TB=$(echo "$OB" | grep '^token=' | cut -d= -f2); wp mp case-verify "$TB" >/dev/null 2>&1
UIDB=$(wp user get 'zam@example.com' --field=ID 2>/dev/null)
CUSTB=$(q "SELECT id FROM wp_mp_customers WHERE email='zam@example.com'")
CIDB=$(q "SELECT id FROM wp_mp_service_cases WHERE customer_id=$CUSTB")
wp eval "MP\Intake\Consents::record('zam@example.com', $CIDB, MP\Intake\Consents::KEY_PROCESSING, MP\Intake\Consents::VERSION, MP\Intake\Consents::processing_text());" >/dev/null 2>&1
wp db query "UPDATE wp_mp_consents SET customer_id=$CUSTB WHERE case_id=$CIDB" >/dev/null 2>&1

NB=$(login_and_withdraw_nonce 'zam@example.com' "$UIDB" /tmp/mp-b-jar)
# Zamknij sprawe PO zalogowaniu (nonce juz pobrany), przed POST-em.
# REALNA droga (change_status, nie seed) — anty-drift #14 (slug 'zamknięte' z ę).
wp eval "apply_filters('mp_case_change_status', null, $CIDB, 'zamknięte', 'nowe', 1);" >/dev/null 2>&1
curl -s -b /tmp/mp-b-jar -o /dev/null --data-urlencode "action=mp_intake_withdraw" --data-urlencode "_mp_nonce=$NB" "$MP_BASE/wp-admin/admin-post.php"

EVB=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CIDB AND event_type='CONSENT_WITHDRAWN'")
[ "$EVB" -ge 1 ] && ok "event CONSENT_WITHDRAWN na sprawie zamknietej ($EVB)" || bad "brak eventu (zamknieta)"
ANONB=$(q "SELECT COALESCE(anonymized_at,'NULL') FROM wp_mp_customers WHERE id=$CUSTB")
{ [ "$ANONB" != "NULL" ] && [ -n "$ANONB" ]; } && ok "sprawa ZAMKNIETA => eraser USUNAL (klient zanonimizowany)" || bad "eraser nie usunal ($ANONB)"
CMAIL=$(q "SELECT email FROM wp_mp_consents WHERE customer_id=$CUSTB")
echo "$CMAIL" | grep -q "removed.invalid" && ok "FLAGA #6: e-mail w CONSENTS zredagowany ($CMAIL)" || bad "FLAGA #6: e-mail zgody NIEzredagowany ($CMAIL)"
CTXT=$(q "SELECT CHAR_LENGTH(consent_text) FROM wp_mp_consents WHERE customer_id=$CUSTB")
[ "${CTXT:-0}" -gt 0 ] && ok "tekst zgody ZOSTAJE (rozliczalnosc art. 7, dlugosc=$CTXT)" || bad "tekst zgody skasowany (utrata rozliczalnosci)"

echo
echo "WYNIK C6b-2b: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
