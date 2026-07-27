#!/usr/bin/env bash
# ZYWY DOWOD C24 (znalezisko #11 audytu 27.07 — diagnostyka mowila "SLA pilnowane",
# choc sweep mogl stac od godzin):
# Test Stanu witryny sprawdzal TYLKO, czy zadanie jest zaplanowane — nigdy czy
# sie WYKONALO. WP-Cron odpala sie z odwiedzin strony; serwis B2B noca stoi,
# panel swieci na zielono, eskalacje stoja.
# Po naprawie: test porownuje WYKONANIE (log SWEEP_RUN) z progiem 2 interwalow
# (10 min) — zaplanowane-ale-martwe swieci na czerwono z instrukcja naprawy.
# Wymaga MP_BASE (spojnosc pakietu; test chodzi przez wp-cli).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

status() { wp eval '$r = MP\Automator\Admin\SiteHealthTests::test_cron(); echo (string) ($r["status"] ?? "");' 2>/dev/null | tr -d '[:space:]'; }

# ── 1. Swiezy przebieg sweepa => zielono (zaplanowane + WYKONANE) ────────────
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1
S1=$(status)
[ "$S1" = "good" ] && ok "swiezy przebieg: diagnostyka zielona (wykonanie potwierdzone)" || bad "po swiezym przebiegu status=$S1"

# ── 2. Sweep 'stoi od 20 minut' => czerwono mimo zaplanowanego zadania ───────
# Postarzamy WSZYSTKIE wpisy SWEEP_RUN (symulacja: cron nie odpala od 20 min).
wp db query "UPDATE wp_mp_workflow_events SET created_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL 20 MINUTE) WHERE event_type='SWEEP_RUN'" >/dev/null 2>&1
S2=$(status)
[ "$S2" = "critical" ] && ok "zaplanowane-ale-martwe: diagnostyka CZERWONA (wykonanie > 2 interwaly temu)" || bad "sweep stoi 20 min a status=$S2 (dawny falszywy spokoj)"

# ── 3. Sweep wraca => zielono ────────────────────────────────────────────────
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1
S3=$(status)
[ "$S3" = "good" ] && ok "po powrocie sweepa diagnostyka znow zielona" || bad "po przebiegu status=$S3"

echo
echo "WYNIK C24: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
