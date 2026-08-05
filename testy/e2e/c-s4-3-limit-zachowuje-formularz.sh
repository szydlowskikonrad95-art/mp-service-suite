#!/usr/bin/env bash
# ZYWY DOWOD S4 #3: odmowa przy limicie zgloszen NIE czysci formularza i mowi,
# CO zrobic zamiast czekania. Sprzed naprawy: komunikat „Spróbuj ponownie za
# jakiś czas" bez wskazowki, a wpisane pola gina (PRG bez 'values').
# Po naprawie: PRG niesie 'values' (opis usterki przezywa) i komunikat kieruje
# do wiadomosci w istniejacej sprawie.
# Kalibracja WBUDOWANA: oba asserty PADAJA na kodzie sprzed naprawy.
# Wymaga MP_BASE. Chodzi na poligonie i w CI (jak c6c-ochrona-zgloszen.sh).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

SESS="a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"   # staly klucz sesji PRG (32 hex) — nasz klucz transientu
EMAIL="s4-3@example.com"

reset() {
	wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_attachments; DELETE FROM wp_mp_rate_counters" >/dev/null 2>&1
	wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_intake_ctx_%' OR option_name LIKE '_transient_timeout_mp_intake_ctx_%'" >/dev/null 2>&1
}

PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
NONCE=$(curl -s "$MP_BASE$PAGE_PATH" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "nonce formularza pobrany" || bad "brak nonce formularza"

# submit <serial> [cookie] — reklamacja, zgoda=1, czas OK, opis rozpoznawalny.
submit() {
	local serial="$1" cookie="${2:-}"
	local args=()
	[ -n "$cookie" ] && args+=( -b "mp_intake_sess=$cookie" )
	curl -s -o /dev/null "${args[@]}" \
		--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
		--data-urlencode "mp_ts=$(( $(date +%s) - 60 ))" \
		--data-urlencode "kind=reklamacja" --data-urlencode "email=$EMAIL" --data-urlencode "customer_name=Klient Testowy" \
		--data-urlencode "mp_consent=1" \
		--data-urlencode "serial=$serial" --data-urlencode "purchase_document=FV/1" \
		--data-urlencode "purchase_date=2026-03-15" \
		--data-urlencode "issue_description=OPIS-USTERKI-MA-PRZEZYC" \
		"$MP_BASE/wp-admin/admin-post.php"
}

# ── Wyczerpanie limitu e-mail (3/doba) trzema udanymi zgloszeniami ──────────
reset
submit 'S4-3-A'; submit 'S4-3-B'; submit 'S4-3-C'
CNT=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CNT" = "3" ] && ok "3 zgloszenia przyjete (limit e-mail wyczerpany)" || bad "spodziewane 3 sprawy, jest $CNT"

# ── 4. zgloszenie: ODRZUCONE limitem, z ustalonym ciasteczkiem sesji PRG ────
submit 'S4-3-D' "$SESS"
CNT2=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CNT2" = "3" ] && ok "4. zgloszenie odrzucone limitem (nadal 3 sprawy)" || bad "limit przepuscil 4. ($CNT2)"

# ── Odczyt kontekstu PRG spod naszego klucza sesji ─────────────────────────
CTX=$(wp eval "
\$c = get_transient('mp_intake_ctx_$SESS');
if (!is_array(\$c)) { echo 'NOCTX'; return; }
\$v = \$c['values'] ?? null;
\$op = is_array(\$v) ? (string) (\$v['issue_description'] ?? '') : '';
echo (\$c['notice'] ?? ''), '||', (is_array(\$v) ? 'HASVALUES' : 'NOVALUES'), '||', \$op;
" 2>/dev/null)

NOTICE="${CTX%%||*}"
REST="${CTX#*||}"
HASV="${REST%%||*}"
OPIS="${REST##*||}"

# ASSERT 1 (kalibracja): wpisane pola przezywaja odmowe.
[ "$HASV" = "HASVALUES" ] && [ "$OPIS" = "OPIS-USTERKI-MA-PRZEZYC" ] \
	&& ok "formularz zachowany: opis usterki przezyl odmowe" \
	|| bad "formularz wyczyszczony po odmowie (HASV=$HASV opis='$OPIS')"

# ASSERT 2 (kalibracja): komunikat mowi, co zrobic zamiast czekania.
case "$NOTICE" in
	*"napisz wiadomość"*) ok "komunikat kieruje do wiadomosci w istniejacej sprawie" ;;
	*) bad "komunikat bez wskazowki co robic: '$NOTICE'" ;;
esac

# Kontrola: komunikat NIE jest starym „za jakiś czas" (dowod, ze to nowa tresc).
case "$NOTICE" in
	*"za jakiś czas"*) bad "komunikat to nadal stara tresc 'za jakiś czas'" ;;
	*) ok "stara tresc 'za jakiś czas' zniknela" ;;
esac

echo "── S4 #3: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
