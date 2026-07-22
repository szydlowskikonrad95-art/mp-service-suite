#!/usr/bin/env bash
# ZYWY DOWOD #16 (szlif Intake — to widzi klient). Trzy rzeczy:
#  1. pasek admina WP UKRYTY klientowi (mp_client), WIDOCZNY personelowi/adminowi;
#  2. arkusz CSS frontu (intake.css?ver) wpiety na stronie formularza i panelu;
#  3. CTA "Przejdz do panelu zgloszen" na stronie potwierdzenia (realny flow verify).
# Sam wyglad/rola — logika i walidacja serwera nietkniete.
# Wymaga MP_BASE. Chodzi na poligonie i w CI (e2e-import; mu-plugin przechwytu maila).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# ── 1. Pasek admina wg roli ────────────────────────────────────────────────
CLIENT_ID=$(wp user create mpklient16 mpklient16@example.com --role=mp_client --user_pass=x1 --porcelain 2>/dev/null)
AGENT_ID=$(wp user create mpagent16 mpagent16@example.com --role=mp_agent --user_pass=x2 --porcelain 2>/dev/null)
COORD_ID=$(wp user create mpcoord16 mpcoord16@example.com --role=mp_coordinator --user_pass=x3 --porcelain 2>/dev/null)

bar_for() { wp eval "wp_set_current_user( $1 ); echo apply_filters( 'show_admin_bar', true ) ? 'SHOW' : 'HIDE';" 2>/dev/null; }

[ "$(bar_for "$CLIENT_ID")" = "HIDE" ] && ok "mp_client: pasek admina UKRYTY" || bad "mp_client: pasek NIE ukryty"
[ "$(bar_for "$AGENT_ID")" = "SHOW" ] && ok "mp_agent: pasek WIDOCZNY (regresja personel)" || bad "mp_agent: pasek ukryty (regresja!)"
[ "$(bar_for "$COORD_ID")" = "SHOW" ] && ok "mp_coordinator: pasek WIDOCZNY (regresja personel)" || bad "mp_coordinator: pasek ukryty (regresja!)"
[ "$(bar_for 1)" = "SHOW" ] && ok "administrator: pasek WIDOCZNY (regresja admin)" || bad "administrator: pasek ukryty (regresja!)"

# sprzatanie userow testowych
for U in "$CLIENT_ID" "$AGENT_ID" "$COORD_ID"; do wp user delete "$U" --yes >/dev/null 2>&1; done

# ── 2. CSS frontu wpiety na formularzu i panelu ─────────────────────────────
FORM_PAGE=$(wp option get mp_intake_form_page_id 2>/dev/null)
ACCT_PAGE=$(wp option get mp_account_page_id 2>/dev/null)
FORM_PATH=$(wp post url "$FORM_PAGE" 2>/dev/null | sed 's#^https\?://[^/]*##')
ACCT_PATH=$(wp post url "$ACCT_PAGE" 2>/dev/null | sed 's#^https\?://[^/]*##')

curl -s "$MP_BASE$FORM_PATH" | grep -qE 'assets/css/intake\.css\?ver=' && ok "CSS intake.css?ver na stronie formularza" || bad "brak CSS na formularzu"
curl -s "$MP_BASE$ACCT_PATH" | grep -qE 'assets/css/intake\.css\?ver=' && ok "CSS intake.css?ver na stronie panelu" || bad "brak CSS na panelu"

# ── 3. CTA na stronie potwierdzenia (realny flow create -> token -> confirm) ─
CAPTURE="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
: > "$CAPTURE" 2>/dev/null || true
wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_consents;" >/dev/null 2>&1

FHTML=$(curl -s "$MP_BASE$FORM_PATH")
NONCE=$(echo "$FHTML" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
JAR=$(mktemp)

curl -s -o /dev/null -c "$JAR" \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 60 ))" \
	--data-urlencode "kind=zapytanie" --data-urlencode "email=cta16@example.com" \
	--data-urlencode "mp_consent=1" --data-urlencode "issue_description=Pytanie do CTA" \
	"$MP_BASE/wp-admin/admin-post.php"

TOKEN=$(grep 'mp_intake_verify' "$CAPTURE" 2>/dev/null | grep -oE 'token=[^"& \\]+' | head -1 | sed 's/token=//')
[ -n "$TOKEN" ] && ok "flow: token weryfikacji przechwycony" || bad "flow: brak tokenu (przechwyt maila?)"

# GET verify -> formularz POST 'Potwierdzam' (nonce)
curl -s -c "$JAR" -b "$JAR" -o /tmp/mp16-verify.html "$MP_BASE/wp-admin/admin-post.php?action=mp_intake_verify&token=$TOKEN"
VNONCE=$(grep -o 'name="_mp_nonce" value="[^"]*"' /tmp/mp16-verify.html | head -1 | sed 's/.*value="//;s/"//')

# POST confirm -> strona 'Zgloszenie potwierdzone' z CTA
curl -s -c "$JAR" -b "$JAR" -o /tmp/mp16-confirm.html \
	--data-urlencode "action=mp_intake_verify_confirm" --data-urlencode "_mp_nonce=$VNONCE" \
	--data-urlencode "token=$TOKEN" \
	"$MP_BASE/wp-admin/admin-post.php"

PANEL_URL=$(wp eval 'echo \MP\Intake\Front\AccountPage::url();' 2>/dev/null)

grep -q 'Przejdź do panelu' /tmp/mp16-confirm.html && ok "CTA 'Przejdz do panelu' na stronie potwierdzenia" || bad "brak CTA na potwierdzeniu"
grep -q 'class="mp-cta"' /tmp/mp16-confirm.html && ok "CTA wyroznione (link-przycisk)" || bad "CTA bez klasy mp-cta"
{ [ -n "$PANEL_URL" ] && grep -qF "$PANEL_URL" /tmp/mp16-confirm.html; } && ok "CTA linkuje do DYNAMICZNEGO URL panelu ($PANEL_URL)" || bad "CTA nie linkuje do panelu (URL=$PANEL_URL)"

rm -f "$JAR" /tmp/mp16-verify.html /tmp/mp16-confirm.html

echo
echo "WYNIK C16: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
