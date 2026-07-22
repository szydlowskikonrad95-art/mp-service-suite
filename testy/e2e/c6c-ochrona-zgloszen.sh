#!/usr/bin/env bash
# ZYWY DOWOD C6c (ochrona zgloszen, P1.6): dedup twardy + rate-limit warstwowy.
# - dedup: ten sam (serial+email+rodzaj) w 15 min => 2. zgloszenie odrzucone
# - rate-limit e-mail (3/doba): 4. zgloszenie z tego samego maila odrzucone
# - retry po odrzuceniu (brak zgody) NIE jest falszywym duplikatem
# - zrodlo IP do rate-limitu = filtr mp_intake_client_ip (flaga #10): domyslnie
#   REMOTE_ADDR, filtr podmienia liczony IP; realna droga HTTP liczy IP z filtra
# Wymaga MP_BASE. Chodzi na poligonie i w CI (e2e-import).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

reset_all() {
	wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_attachments;" >/dev/null 2>&1
	wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_rl%' OR option_name LIKE '_transient_timeout_mp_rl%'" >/dev/null 2>&1
	wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
}

# Nonce formularza z auto-strony.
PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
NONCE=$(curl -s "$MP_BASE$PAGE_PATH" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "nonce formularza pobrany" || bad "brak nonce formularza"

# submit <email> <serial> — reklamacja, zgoda=1, czas OK (nie bot).
submit() {
	local email="$1" serial="$2"
	curl -s -o /dev/null \
		--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
		--data-urlencode "mp_ts=$(( $(date +%s) - 60 ))" \
		--data-urlencode "kind=reklamacja" --data-urlencode "email=$email" \
		--data-urlencode "mp_consent=1" \
		--data-urlencode "serial=$serial" --data-urlencode "purchase_document=FV/1" \
		--data-urlencode "purchase_date=2026-03-15" --data-urlencode "issue_description=usterka" \
		"$MP_BASE/wp-admin/admin-post.php"
}

# ── 1. Dedup twardy: ten sam serial+email+rodzaj w 15 min ───────────────────
reset_all
submit 'dup@example.com' 'DUP-1'
C1=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
submit 'dup@example.com' 'DUP-1'
C2=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$C1" = "1" ] && ok "1. zgloszenie przyjete (sprawa utworzona)" || bad "1. zgloszenie nie utworzone ($C1)"
[ "$C2" = "1" ] && ok "dedup: 2. identyczne zgloszenie ODRZUCONE (nadal 1 sprawa)" || bad "dedup przepuscil duplikat ($C2)"

# ── 2. Rate-limit e-mail (3/doba): 4. z tego samego maila odrzucone ─────────
reset_all
submit 'rate@example.com' 'RL-1'
submit 'rate@example.com' 'RL-2'
submit 'rate@example.com' 'RL-3'
C3=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
submit 'rate@example.com' 'RL-4'
C4=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$C3" = "3" ] && ok "3 zgloszenia z maila przyjete (limit 3/doba)" || bad "spodziewano 3 spraw, jest $C3"
[ "$C4" = "3" ] && ok "rate-limit e-mail: 4. zgloszenie ODRZUCONE (nadal 3 sprawy)" || bad "rate-limit e-mail przepuscil 4. ($C4)"

# ── 3. Retry po odrzuceniu (brak zgody) NIE jest duplikatem ─────────────────
reset_all
# bez zgody -> odrzucone, marker dedup NIE ustawiony
curl -s -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 60 ))" \
	--data-urlencode "kind=reklamacja" --data-urlencode "email=retry@example.com" \
	--data-urlencode "serial=RT-1" --data-urlencode "purchase_document=FV/1" \
	--data-urlencode "purchase_date=2026-03-15" --data-urlencode "issue_description=usterka" \
	"$MP_BASE/wp-admin/admin-post.php"
CR0=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
# ta sama tresc ze zgoda -> powinno przejsc (nie duplikat)
submit 'retry@example.com' 'RT-1'
CR1=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
{ [ "$CR0" = "0" ] && [ "$CR1" = "1" ]; } && ok "retry po odrzuceniu (brak zgody) NIE jest duplikatem (0->1)" || bad "retry zablokowany jako duplikat (CR0=$CR0 CR1=$CR1)"

# ── 4. Zrodlo IP do rate-limitu = filtr mp_intake_client_ip (flaga #10) ──────
# 4a. Jednostkowo na REALNEJ metodzie ktora wola handler (RateLimit::client_ip):
#     domyslnie = REMOTE_ADDR (regresja zero), filtr podmienia liczony IP.
IP_DEFAULT=$(wp eval '$_SERVER["REMOTE_ADDR"]="198.51.100.5"; echo \MP\Intake\RateLimit::client_ip();' 2>/dev/null)
[ "$IP_DEFAULT" = "198.51.100.5" ] && ok "client_ip() domyslnie = REMOTE_ADDR (regresja zero)" || bad "domyslny IP != REMOTE_ADDR (=$IP_DEFAULT)"

IP_FILTERED=$(wp eval '$_SERVER["REMOTE_ADDR"]="198.51.100.5"; add_filter("mp_intake_client_ip", function(){ return "203.0.113.77"; }); echo \MP\Intake\RateLimit::client_ip();' 2>/dev/null)
[ "$IP_FILTERED" = "203.0.113.77" ] && ok "filtr mp_intake_client_ip podmienia liczony IP (proxy-safe)" || bad "filtr nie zmienil IP (=$IP_FILTERED)"

# 4b. REALNA droga HTTP: wdrozenie za proxy podpina filtr (mu-plugin z naglowka).
#     Dowod: licznik rate-limitu bity dla IP z filtra, a NIE dla REMOTE_ADDR.
MU="wp-content/mu-plugins/mp-test-client-ip.php"
mkdir -p "wp-content/mu-plugins"
cat > "$MU" <<'PHP'
<?php
// TEST-ONLY: symuluje wdrozenie za proxy — podpina mp_intake_client_ip do
// naglowka X-MP-Test-IP. W PRODUKCJI wdrozeniowiec bierze ZAUFANE zrodlo IP,
// nie goly naglowek (X-Forwarded-For jest spoofowalny). Patrz SECURITY.md §7.
add_filter( 'mp_intake_client_ip', static function ( $ip ) {
	return isset( $_SERVER['HTTP_X_MP_TEST_IP'] )
		? sanitize_text_field( wp_unslash( $_SERVER['HTTP_X_MP_TEST_IP'] ) )
		: $ip;
} );
PHP

reset_all
FILTERED_IP="203.0.113.99"
curl -s -o /dev/null -H "X-MP-Test-IP: $FILTERED_IP" \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 60 ))" \
	--data-urlencode "kind=reklamacja" --data-urlencode "email=proxy@example.com" \
	--data-urlencode "mp_consent=1" \
	--data-urlencode "serial=PROXY-1" --data-urlencode "purchase_document=FV/1" \
	--data-urlencode "purchase_date=2026-03-15" --data-urlencode "issue_description=usterka" \
	"$MP_BASE/wp-admin/admin-post.php"

HASH_F=$(wp eval "echo md5('$FILTERED_IP');" 2>/dev/null)
HASH_R=$(wp eval "echo md5('127.0.0.1');" 2>/dev/null)
CNT_F=$(wp transient get "mp_rl_ip_$HASH_F" 2>/dev/null)
CNT_R=$(wp transient get "mp_rl_ip_$HASH_R" 2>/dev/null)
CASE_OK=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CASE_OK" = "1" ] && ok "zgloszenie za proxy przyjete (sprawa utworzona)" || bad "zgloszenie za proxy nie przeszlo ($CASE_OK)"
[ "$CNT_F" = "1" ] && ok "real-path: licznik rate-limitu bity dla IP z filtra ($FILTERED_IP)" || bad "licznik IP z filtra nie bity (=$CNT_F)"
[ -z "$CNT_R" ] && ok "real-path: REMOTE_ADDR (127.0.0.1) NIE liczony gdy filtr aktywny" || bad "REMOTE_ADDR liczony mimo filtra (=$CNT_R)"

rm -f "$MU"

echo
echo "WYNIK C6c: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
