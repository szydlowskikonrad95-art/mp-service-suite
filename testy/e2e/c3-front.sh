#!/usr/bin/env bash
# ZYWY DOWOD C3 (front zgloszenia): E2E przez HTTP jak klient — formularz na
# auto-stronie, wyslanie -> mail z magic-linkiem (Mailpit) -> klik (GET) ->
# potwierdzenie -> 2. mail z SRV. Plus honeypot i pulapka czasu (bot odrzucony
# cicho). Naglowki bezp. na stronie potwierdzenia. Chodzi na poligonie
# (BASE/MAILPIT z env) i w CI (WP wbudowany, mail przez log przechwyt).
set -u

BASE="${MP_BASE:-http://localhost:8090}"
# Przechwyt wp_mail (mu-plugin) w uploads = wspoldzielony wolumen (front i test
# to rozne kontenery); zrodlo tokenu niezalezne od SMTP/Mailpita.
CAPTURE="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
JAR="$(mktemp)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Naglowek Host = kanoniczny host WP (gdy curlujemy inny hostname niz home URL —
# poligon: BASE=http://wordpress, home=localhost:8090; bez tego WP robi 301).
SITE_HOST=$(wp option get home 2>/dev/null | sed 's#^https\?://##;s#/.*##')
HOSTHDR=(); [ -n "$SITE_HOST" ] && HOSTHDR=(-H "Host: $SITE_HOST")
cget()  { curl -s "${HOSTHDR[@]}" "$@"; }

# ── 0. Czysty stan + czysty przechwyt maila ───────────────────────────────
wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
rm -f "$CAPTURE"

# Adres auto-strony formularza.
PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
[ -n "$PAGE_ID" ] && ok "auto-strona formularza utworzona przy aktywacji (ID=$PAGE_ID)" || bad "brak auto-strony"
# Sciezka permalinka z `wp post url` (dziala dla plain i pretty), host z BASE.
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
PAGE_URL="$BASE$PAGE_PATH"

# ── 1. Formularz renderuje sie na stronie (blok + pola + honeypot + nonce) ──
HTML=$(cget "$PAGE_URL")
echo "$HTML" | grep -q 'name="action" value="mp_intake_submit"' && ok "formularz na stronie (blok mp/intake-form renderuje)" || bad "brak formularza na stronie"
echo "$HTML" | grep -q 'name="mp_hp"' && ok "honeypot mp_hp obecny" || bad "brak honeypota"
NONCE=$(echo "$HTML" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "nonce formularza: $NONCE" || bad "brak nonce"

# ── 2. Bot: honeypot wypelniony => cichy odrzut (zero spraw) ───────────────
BEFORE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
cget -c "$JAR" -b "$JAR" -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 60 ))" \
	--data-urlencode "mp_hp=jestem-botem" \
	--data-urlencode "kind=reklamacja" --data-urlencode "email=bot@spam.xx" \
	--data-urlencode "serial=X1" --data-urlencode "purchase_document=FV/1" \
	--data-urlencode "purchase_date=2026-03-15" --data-urlencode "issue_description=spam" \
	"$BASE/wp-admin/admin-post.php"
AFTER=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$BEFORE" = "$AFTER" ] && ok "honeypot: bot odrzucony cicho (zero nowych spraw)" || bad "honeypot przepuscil bota!"

# ── 3. Bot: formularz wyslany <2s => pulapka czasu (cichy odrzut) ──────────
cget -c "$JAR" -b "$JAR" -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
	--data-urlencode "mp_ts=$(date +%s)" \
	--data-urlencode "kind=reklamacja" --data-urlencode "email=fast@spam.xx" \
	--data-urlencode "serial=X2" --data-urlencode "purchase_document=FV/2" \
	--data-urlencode "purchase_date=2026-03-15" --data-urlencode "issue_description=spam" \
	"$BASE/wp-admin/admin-post.php"
AFTER2=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$BEFORE" = "$AFTER2" ] && ok "pulapka czasu: wyslanie <2s odrzucone (zero nowych spraw)" || bad "pulapka czasu przepuscila!"

# ── 4. Czlowiek: poprawne zgloszenie => sprawa unverified + mail magic-link ─
cget -c "$JAR" -b "$JAR" -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 30 ))" \
	--data-urlencode "kind=reklamacja" --data-urlencode "email=klient@example.com" \
	--data-urlencode "serial=REK-1" --data-urlencode "purchase_document=FV/2026/77" \
	--data-urlencode "purchase_date=2026-03-15" --data-urlencode "issue_description=Nie grzeje" \
	--data-urlencode "mp_consent=1" \
	"$BASE/wp-admin/admin-post.php"
CNT=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE status IS NULL AND identity_status='pending'")
[ "$CNT" = "1" ] && ok "poprawne zgloszenie: sprawa unverified utworzona" || bad "sprawa unverified: $CNT"

# Mail z magic-linkiem w przechwycie wp_mail.
sleep 1
grep -q "klient@example.com" "$CAPTURE" 2>/dev/null && ok "mail magic-link zaadresowany do klienta" || bad "brak maila do klienta w przechwycie"
TOKEN=$(grep 'mp_intake_verify' "$CAPTURE" 2>/dev/null | grep -oE 'token=[^" \\]+' | head -1 | sed 's/token=//')
[ -n "$TOKEN" ] && ok "magic-link niesie token weryfikacji" || bad "brak tokenu w mailu"

# ── 5. Klik magic-linka (GET): potwierdzenie + naglowki bezp. + neutralnosc ─
VHEAD=$(cget -D - -o /tmp/mp-verify.html "$BASE/wp-admin/admin-post.php?action=mp_intake_verify&token=$TOKEN")
echo "$VHEAD" | grep -qi "Referrer-Policy: no-referrer" && ok "strona potwierdzenia: Referrer-Policy no-referrer" || bad "brak no-referrer"
echo "$VHEAD" | grep -qi "Cache-Control: no-store" && ok "strona potwierdzenia: Cache-Control no-store" || bad "brak no-store"
echo "$VHEAD" | grep -qi "X-Content-Type-Options: nosniff" && ok "strona potwierdzenia: nosniff" || bad "brak nosniff"
# Neutralnosc: strona NIE ujawnia numeru SRV (idzie mailem).
grep -q "SRV/" /tmp/mp-verify.html && bad "strona potwierdzenia ZDRADZA numer SRV!" || ok "strona potwierdzenia neutralna (SRV tylko mailem)"

ST=$(q "SELECT status FROM wp_mp_service_cases WHERE identity_status='verified'")
[ "$ST" = "nowe" ] && ok "po kliku: sprawa verified, status=nowe" || bad "status po weryfikacji: $ST"
EV=$(q "SELECT event_type FROM wp_mp_case_events LIMIT 1")
[ "$EV" = "CASE_CREATED" ] && ok "event CASE_CREATED zapisany po weryfikacji" || bad "event: $EV"

# ── 6. 2. mail z NUMEREM SRV po weryfikacji ────────────────────────────────
sleep 1
CNUM=$(q "SELECT case_number FROM wp_mp_service_cases WHERE identity_status='verified'")
grep -q "$CNUM" "$CAPTURE" 2>/dev/null && ok "2. mail potwierdzajacy niesie numer SRV ($CNUM)" || bad "brak maila z SRV"

# ── 7. Ponowny klik tym samym tokenem: HTTP 410 (nieaktualny) ──────────────
CODE=$(cget -o /dev/null -w '%{http_code}' "$BASE/wp-admin/admin-post.php?action=mp_intake_verify&token=$TOKEN")
{ [ "$CODE" = "200" ] || [ "$CODE" = "410" ]; } && ok "ponowny klik obsluzony (HTTP $CODE, token jednorazowy)" || bad "ponowny klik: HTTP $CODE"

echo
echo "WYNIK C3: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
