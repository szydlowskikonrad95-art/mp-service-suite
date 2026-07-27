#!/usr/bin/env bash
# ZYWY DOWOD (audyt kosztu 27.07): jeden przebieg sweepa mogl wyslac do 500 maili.
#
# BATCH 50 x MAX_ROUNDS 10 = do 500 wiadomosci sekwencyjnie w JEDNYM zadaniu PHP.
# Zwykly hosting przepuszcza 200-500 maili/godzine, a 500 polaczen SMTP po ~0,3 s
# to kilka minut pracy — czyli takze ryzyko urwania przez limit czasu wykonania
# w polowie wysylki (czesc spraw z markerem, czesc bez).
# FIX: budzet maili na przebieg (filtr mp_sla_mail_budget). Reszta czeka na
# kolejny przebieg; markery gwarantuja, ze nic nie przepadnie ani nie pojdzie 2x.
#
# UWAGA METODOLOGICZNA: mierzymy RUCH GLOBALNY (ile markerow przybylo w calej
# tabeli), a nie los konkretnych spraw. Sweep bierze sprawy wg terminu ostrzezenia,
# a doszywanie sierot potrafi w tym samym przebiegu zalozyc terminy sprawom z
# wczesniejszych testow — wiec "ktore dokladnie" jest niestabilne, natomiast
# "ile lacznie" to dokladnie ta obietnica, ktorej pilnuje budzet.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

CZEKAJACE='SELECT COUNT(*) FROM wp_mp_case_sla WHERE deadline_at IS NOT NULL AND warning_at IS NOT NULL AND warning_at <= UTC_TIMESTAMP() AND reminder_sent_at IS NULL AND deadline_at > UTC_TIMESTAMP()'

# ── 0. Szesc spraw z wymagalnym przypomnieniem ──────────────────────────────
PRZESZLOSC=$(date -u -d '2 hours ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u -v-2H '+%Y-%m-%d %H:%M:%S')
PRZYSZLOSC=$(date -u -d '10 hours' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u -v+10H '+%Y-%m-%d %H:%M:%S')

for i in 1 2 3 4 5 6; do
	O=$(wp mp case-create --kind=zapytanie --email="budzet$i@example.com" --name="Budzet $i" --desc="test budzetu maili" 2>/dev/null)
	CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2)
	wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe' WHERE id=$CID" >/dev/null 2>&1
	wp db query "REPLACE INTO wp_mp_case_sla (case_id, status, sla_policy_version, deadline_at, warning_at, reminder_sent_at, escalated_at, updated_at)
		VALUES ($CID, 'nowe', 1, '$PRZYSZLOSC', '$PRZESZLOSC', NULL, NULL, '$PRZESZLOSC')" >/dev/null 2>&1
done

# Doszywanie sierot ZANIM zaczniemy mierzyc — inaczej pierwszy przebieg sweepa
# zalozylby nowe terminy w trakcie pomiaru i ruszyl licznik "czekajacych".
wp eval 'MP\Automator\Sla::reconcile_untracked(500);' >/dev/null 2>&1

PRZED=$(q "$CZEKAJACE")
[ "${PRZED:-0}" -ge 6 ] 2>/dev/null && ok "seed: co najmniej 6 spraw czeka na przypomnienie (jest $PRZED)" || bad "seed zly ($PRZED)"

# ── 1. Budzet 2 => przebieg wysyla DOKLADNIE 2 maile, reszta czeka ──────────
# pre_wp_mail => true: w kontenerze CI NIE MA serwera poczty, wiec kazda wysylka
# by padla, marker 'wyslano' nie zostalby postawiony (kod slusznie ponawia), a test
# mierzylby ponawianie zamiast budzetu. Wymuszamy determinizm.
wp eval "add_filter('pre_wp_mail', '__return_true'); add_filter('mp_sla_mail_budget', function(){ return 2; }); MP\\Automator\\Sweep::run();" >/dev/null 2>&1
PO=$(q "$CZEKAJACE")
ROZNICA=$(( PRZED - PO ))
[ "$ROZNICA" = "2" ] && ok "budzet dotrzymany: dokladnie 2 przypomnienia w przebiegu (bylo $PRZED, zostalo $PO)" || bad "budzet zlamany: wyslano $ROZNICA zamiast 2"

[ "${PO:-0}" -ge 1 ] 2>/dev/null && ok "reszta CZEKA z pustym markerem (nic nie przepadlo)" || bad "reszta zniknela z kolejki ($PO)"

LOG=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SWEEP_RUN' AND payload LIKE '%\"przerwany_budzetem\":1%'")
[ "${LOG:-0}" -ge 1 ] 2>/dev/null && ok "przerwanie budzetem ZAPISANE w rejestrze (nie ciche)" || bad "brak sladu przerwania w rejestrze"

LICZNIK=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SWEEP_RUN' AND payload LIKE '%\"reminders\":2%'")
[ "${LICZNIK:-0}" -ge 1 ] 2>/dev/null && ok "licznik pokazuje REALNIE wyslane (2), nie znalezione" || bad "licznik klamie o liczbie maili"

# ── 2. Kolejny przebieg z wiekszym budzetem dobiera zaleglosc ───────────────
wp eval "add_filter('pre_wp_mail', '__return_true'); add_filter('mp_sla_mail_budget', function(){ return 500; }); MP\\Automator\\Sweep::run();" >/dev/null 2>&1
PO2=$(q "$CZEKAJACE")
[ "${PO2:-9}" = "0" ] && ok "kolejny przebieg dobral cala zaleglosc (kolejka pusta)" || bad "zaleglosc nie zeszla ($PO2)"

# ── 3. Kontrola: pusty przebieg nie wysyla nic drugi raz ───────────────────
PRZED3=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE event_type='SLA_REMINDER_SENT'")
wp eval "add_filter('pre_wp_mail', '__return_true'); MP\\Automator\\Sweep::run();" >/dev/null 2>&1
PO3=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE event_type='SLA_REMINDER_SENT'")
[ "$PRZED3" = "$PO3" ] && ok "zero podwojnych przypomnien przy pustym przebiegu" || bad "podwojna wysylka ($PRZED3 -> $PO3)"

echo ""
echo "WYNIK D-BUDZET-MAILI: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
