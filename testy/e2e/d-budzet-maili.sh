#!/usr/bin/env bash
# ZYWY DOWOD (audyt kosztu 27.07): jeden przebieg sweepa mogl wyslac do 500 maili.
#
# BATCH 50 x MAX_ROUNDS 10 = do 500 wiadomosci sekwencyjnie w JEDNYM zadaniu PHP.
# Zwykly hosting przepuszcza 200-500 maili/godzine, a 500 polaczen SMTP po ~0,3 s
# to kilka minut pracy — czyli takze ryzyko urwania przez limit czasu wykonania
# w polowie wysylki (czesc spraw z markerem, czesc bez).
# FIX: budzet maili na przebieg (filtr mp_sla_mail_budget). Reszta czeka na
# kolejny przebieg; markery gwarantuja, ze nic nie przepadnie ani nie pojdzie 2x.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ── 0. Czysty stan + 6 spraw z wymagalnym przypomnieniem ────────────────────
wp db query "DELETE FROM wp_mp_case_sla;" >/dev/null 2>&1
PRZESZLOSC=$(date -u -d '2 hours ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u -v-2H '+%Y-%m-%d %H:%M:%S')
PRZYSZLOSC=$(date -u -d '10 hours' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u -v+10H '+%Y-%m-%d %H:%M:%S')

IDS=""
for i in 1 2 3 4 5 6; do
	O=$(wp mp case-create --kind=zapytanie --email="budzet$i@example.com" --name="Budzet $i" --desc="test budzetu maili" 2>/dev/null)
	CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2)
	wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe' WHERE id=$CID" >/dev/null 2>&1
	wp db query "INSERT INTO wp_mp_case_sla (case_id, status, sla_policy_version, deadline_at, warning_at, reminder_sent_at, escalated_at, updated_at)
		VALUES ($CID, 'nowe', 1, '$PRZYSZLOSC', '$PRZESZLOSC', NULL, NULL, '$PRZESZLOSC')" >/dev/null 2>&1
	IDS="$IDS $CID"
done

DO_WYSLANIA=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE reminder_sent_at IS NULL AND warning_at <= UTC_TIMESTAMP() AND deadline_at > UTC_TIMESTAMP()")
[ "$DO_WYSLANIA" = "6" ] && ok "seed: 6 spraw czeka na przypomnienie" || bad "seed zly ($DO_WYSLANIA)"

# ── 1. Budzet 2 => przebieg wysyla DOKLADNIE 2, reszta czeka ────────────────
wp eval "add_filter('mp_sla_mail_budget', function(){ return 2; }); MP\\Automator\\Sweep::run();" >/dev/null 2>&1

WYSLANE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE reminder_sent_at IS NOT NULL")
[ "$WYSLANE" = "2" ] && ok "budzet dotrzymany: wyslane 2 z 6" || bad "budzet zlamany (wyslane $WYSLANE, oczekiwane 2)"

CZEKA=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE reminder_sent_at IS NULL")
[ "$CZEKA" = "4" ] && ok "pozostale 4 sprawy NIETKNIETE (marker pusty => nic nie przepadlo)" || bad "reszta w zlym stanie ($CZEKA)"

LOG=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SWEEP_RUN' AND payload LIKE '%\"przerwany_budzetem\":1%'")
[ "${LOG:-0}" -ge 1 ] 2>/dev/null && ok "przerwanie budzetem ZAPISANE w rejestrze (nie ciche)" || bad "brak sladu przerwania w rejestrze"

LICZNIK=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SWEEP_RUN' AND payload LIKE '%\"reminders\":2%'")
[ "${LICZNIK:-0}" -ge 1 ] 2>/dev/null && ok "licznik pokazuje REALNIE wyslane (2), nie znalezione (6)" || bad "licznik klamie o liczbie maili"

# ── 2. Kolejny przebieg dobiera reszte (nic nie zaginelo) ───────────────────
wp eval "add_filter('mp_sla_mail_budget', function(){ return 100; }); MP\\Automator\\Sweep::run();" >/dev/null 2>&1
WYSLANE2=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE reminder_sent_at IS NOT NULL")
[ "$WYSLANE2" = "6" ] && ok "kolejny przebieg dobral reszte (6/6 — zaleglosc schodzi)" || bad "reszta nie doszla ($WYSLANE2)"

# ── 3. Kontrola: trzeci przebieg NIE wysyla nic drugi raz ───────────────────
PRZED3=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE event_type='SLA_REMINDER_SENT'")
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1
PO3=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE event_type='SLA_REMINDER_SENT'")
[ "$PRZED3" = "$PO3" ] && ok "zero podwojnych przypomnien przy pustym przebiegu" || bad "podwojna wysylka ($PRZED3 -> $PO3)"

echo ""
echo "WYNIK D-BUDZET-MAILI: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
