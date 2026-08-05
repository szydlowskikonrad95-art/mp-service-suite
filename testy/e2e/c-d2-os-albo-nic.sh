#!/usr/bin/env bash
# ZYWY DOWOD D2 (koordynator, 2026-08-05): CaseRepo::change_status ignorowal
# wynik CaseEvents::log i robil COMMIT bezwarunkowo — przy nieudanym insercie
# zdarzenia status zmienial sie BEZ wpisu na osi, a README obiecuje os
# nieusuwalna i kompletna. FIX: nieudany zapis zdarzenia => ROLLBACK calej
# transakcji + blad EVENT_LOG_FAILED (stan albo z pelnym sladem, albo wcale).
#
# Kalibracja WBUDOWANA: asserty A1/A2 PADAJA na kodzie sprzed naprawy (status
# zmienial sie mimo braku wpisu). Awarie insertu wymuszamy PODMIANA NAZWY
# tabeli zdarzen w locie (RENAME TABLE) — jedyna czesc, ktora ma pasc.
# B to kontrola kierunku: z porzadna tabela zmiana przechodzi i ma wpis.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1

OUT=$(wp mp case-create --kind=reklamacja --email='d2@example.com' --name='Jan D2' --serial='D2-1' --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
TOK=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp eval "MP\\Intake\\CaseRepo::verify('$TOK');" >/dev/null 2>&1
[ -n "$CID" ] && [ "$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")" = "nowe" ] \
	&& ok "0: sprawa zalozona i potwierdzona (id=$CID, status=nowe)" || bad "0: setup padl"

# ── A. KALIBRACJA D2: tabela zdarzen ZEPSUTA w locie => zmiana ma NIE przejsc ─
wp db query "RENAME TABLE wp_mp_case_events TO wp_mp_case_events_d2bak" >/dev/null 2>&1
WYNIK=$(wp eval "echo json_encode(MP\\Intake\\CaseRepo::change_status($CID, 'w analizie', 'nowe', 1));" 2>/dev/null)
wp db query "RENAME TABLE wp_mp_case_events_d2bak TO wp_mp_case_events" >/dev/null 2>&1

STATUS_A=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
[ "$STATUS_A" = "nowe" ] \
	&& ok "A1: status NIE zmienil sie bez wpisu na osi (zostal 'nowe')" \
	|| bad "A1: status zmienil sie BEZ wpisu na osi (jest '$STATUS_A') — os klamie"
echo "$WYNIK" | grep -q 'EVENT_LOG_FAILED' \
	&& ok "A2: wolajacy dostal jawny blad EVENT_LOG_FAILED (nie cichy sukces)" \
	|| bad "A2: brak bledu EVENT_LOG_FAILED w wyniku: $WYNIK"
WPISY_A=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='STATUS_CHANGED'")
[ "$WPISY_A" = "0" ] && ok "A3: na osi zero wpisow STATUS_CHANGED (spojnie ze statusem)" \
	|| bad "A3: wpis STATUS_CHANGED istnieje mimo odmowy ($WPISY_A)"

# ── B. KONTROLA KIERUNKU: porzadna tabela => zmiana przechodzi Z wpisem ──────
# Jawny reset stanu: na kodzie sprzed naprawy sekcja A przecieka statusem
# (to jest sama wada) i B odbijalby sie o optimistic-lock zamiast mierzyc swoje.
wp db query "UPDATE wp_mp_service_cases SET status='nowe' WHERE id=$CID" >/dev/null 2>&1
WYNIK_B=$(wp eval "echo json_encode(MP\\Intake\\CaseRepo::change_status($CID, 'w analizie', 'nowe', 1));" 2>/dev/null)
STATUS_B=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
[ "$STATUS_B" = "wanalizie" ] \
	&& ok "B1: z porzadna tabela zmiana statusu przechodzi ('$STATUS_B')" \
	|| bad "B1: naprawa zepsula normalna zmiane statusu ('$STATUS_B', $WYNIK_B)"
WPISY_B=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='STATUS_CHANGED'")
[ "$WPISY_B" = "1" ] && ok "B2: zmiana ma dokladnie jeden wpis na osi" \
	|| bad "B2: zla liczba wpisow STATUS_CHANGED ($WPISY_B)"

echo "── D2: PASS=$PASS FAIL=$FAIL ──"
if [ "$(( PASS + FAIL ))" -lt 6 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane 6."
	exit 2
fi
[ "$FAIL" -eq 0 ]
