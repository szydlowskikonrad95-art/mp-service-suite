#!/usr/bin/env bash
# ZYWY DOWOD C17 (rate-limit zadan magic-linku): ochrona skrzynek klientow i
# endpointu logowania przed zalewem linkami. Standard (OWASP anti-automation) —
# poza kartka, ale profeska bezpieczenstwa. Osobne liczniki od formularza zgloszen.
# - 5 zadan przechodzi, 6. z tego samego IP+email => BLOCK_RATE
# - limit per-IP: gdy IP wyczerpane, inny email z tego IP tez blokowany
# - limit per-email: gdy email wyczerpany, inne IP tez blokowane (ochrona skrzynki)
# - konfigurowalne filtrem mp_intake_login_rate_limits
# Deterministyczny (wp eval) — nie wymaga MP_BASE. Chodzi na poligonie i w CI.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

reset_login() {
	wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_rl_login%' OR option_name LIKE '_transient_timeout_mp_rl_login%'" >/dev/null 2>&1
}

# rl <ip> <email> => 'ok' albo 'rate' (jedno wywolanie check_login, bumpuje liczniki)
rl() {
	wp eval "echo \\MP\\Intake\\RateLimit::check_login('$1', '$2') ?? 'ok';" 2>/dev/null
}

# ── 1. 5 przechodzi, 6. z tego samego IP+email = BLOCK ──────────────────────
reset_login
R=""
for i in 1 2 3 4 5; do R="$R$(rl 10.0.0.1 klient@example.com)|"; done
SIXTH=$(rl 10.0.0.1 klient@example.com)
[ "$R" = "ok|ok|ok|ok|ok|" ] && ok "pierwsze 5 zadan linku przeszlo ($R)" || bad "nie wszystkie 5 przeszly ($R)"
[ "$SIXTH" = "rate" ] && ok "6. zadanie z tego samego IP+email ZABLOKOWANE (rate)" || bad "6. nie zablokowane ($SIXTH)"

# ── 2. Limit per-IP: IP wyczerpane => inny email z tego IP tez blok ─────────
reset_login
for i in 1 2 3 4 5; do rl 10.0.0.2 a@example.com >/dev/null; done
OTHER_EMAIL=$(rl 10.0.0.2 inny@example.com)
[ "$OTHER_EMAIL" = "rate" ] && ok "IP wyczerpane: inny email z tego IP tez blokowany (gate IP)" || bad "gate IP nie zadzialal ($OTHER_EMAIL)"

# ── 3. Limit per-email: email wyczerpany => inne IP tez blok (ochrona skrzynki) ─
reset_login
for ipn in 11 12 13 14 15; do rl "10.0.0.$ipn" ofiara@example.com >/dev/null; done
OTHER_IP=$(rl 10.0.0.99 ofiara@example.com)
[ "$OTHER_IP" = "rate" ] && ok "email wyczerpany: inne IP tez blokowane (ochrona skrzynki klienta)" || bad "gate email nie zadzialal ($OTHER_IP)"

# ── 4. Konfigurowalne filtrem (ip_max=2 => 3. blok) ─────────────────────────
reset_login
FILTERED=$(wp eval '
	add_filter("mp_intake_login_rate_limits", function($l){ $l["ip_max"]=2; return $l; });
	$r=array();
	for($i=0;$i<3;$i++){ $r[]=\MP\Intake\RateLimit::check_login("10.0.0.3","f@example.com") ?? "ok"; }
	echo implode("|",$r);
' 2>/dev/null)
[ "$FILTERED" = "ok|ok|rate" ] && ok "filtr obniza limit: ip_max=2 => 3. zablokowane ($FILTERED)" || bad "filtr nie zadzialal ($FILTERED)"

reset_login
echo ""
echo "C17-RATE-LIMIT-LOGIN: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
