#!/usr/bin/env bash
# ZYWY DOWOD D2-BLIZNIAKI (koordynator, 2026-08-05): naprawa WZORCA, nie egzemplarza.
#
# D2 (#287) objelo WYLACZNIE change_status. Ten sam ksztalt zostal w dwoch
# blizniakach tego samego pliku: assign() i set_priority() wolaly CaseEvents::log
# w otwartej transakcji, IGNOROWALY wynik i robily bezwarunkowy COMMIT — przydzial
# albo zmiana priorytetu zostawaly w bazie BEZ wpisu na osi, ktora README obiecuje
# jako nieusuwalna i kompletna.
#
# DRUGA WADA, ta sama klasa: alarm dla administratora. `EventWrite::insert` podnosi
# go W SRODKU transakcji, wiec ROLLBACK go zabiera — administrator nie dostaje ZADNEGO
# sygnalu o gubionych wpisach. Dotyczy to takze samego change_status z #287 (moja
# wlasna luka). Wzorzec poprawny lezal w tym repo od dawna: WarrantyExceptions
# ponawia alarm PO wycofaniu transakcji.
#
# Kalibracja WBUDOWANA: A1/A2/B1/B2 PADAJA na kodzie sprzed naprawy (mutacja
# zostawala bez sladu), a A3/B3/C1 PADAJA na alarmie zabranym przez rollback
# (C1 takze na kodzie PO #287 — to dowod, ze naprawiamy wzorzec, nie egzemplarz).
# Sekcja D to kontrola kierunku: ze sprawna tabela wszystkie trzy operacje
# przechodza i maja swoj wpis.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Awarie dziennika wymuszamy PODMIANA NAZWY tabeli zdarzen — jedyna czesc, ktora
# ma pasc. DDL robimy PRZED operacja, wiec nie miesza sie z jej transakcja.
zepsuj()  { wp db query "RENAME TABLE wp_mp_case_events TO wp_mp_case_events_bak" >/dev/null 2>&1; }
napraw()  { wp db query "RENAME TABLE wp_mp_case_events_bak TO wp_mp_case_events" >/dev/null 2>&1; }
alarm_zeruj() { wp eval 'delete_option("mp_event_write_alert"); wp_cache_delete("mp_event_write_alert","options");' >/dev/null 2>&1; }
alarm_jest()  { wp eval 'echo is_array(get_option("mp_event_write_alert", null)) ? "TAK" : "NIE";' 2>/dev/null; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_workflow_rules;" >/dev/null 2>&1

AG=$(wp user get blizagent --field=ID 2>/dev/null); [ -z "$AG" ] && AG=$(wp user create blizagent 'bliz@example.com' --role=mp_agent --user_pass=x --porcelain 2>/dev/null)

OUT=$(wp mp case-create --kind=reklamacja --email='bliz@example.com' --name='Jan Bliz' --serial='BLIZ-1' --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
TOK=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp eval "MP\\Intake\\CaseRepo::verify('$TOK');" >/dev/null 2>&1
[ -n "$CID" ] && [ "$(q "SELECT identity_status FROM wp_mp_service_cases WHERE id=$CID")" = "verified" ] \
	&& ok "0: sprawa zalozona i potwierdzona (id=$CID)" || bad "0: setup padl"

# ── A. BLIZNIAK 1: assign() ─────────────────────────────────────────────────
alarm_zeruj; zepsuj
WYN_A=$(wp eval "echo json_encode(MP\\Intake\\CaseRepo::assign($CID, $AG, 1));" 2>/dev/null)
napraw

PRZYP_A=$(q "SELECT IFNULL(assigned_to,'BRAK') FROM wp_mp_service_cases WHERE id=$CID")
[ "$PRZYP_A" = "BRAK" ] \
	&& ok "A1: przydzial NIE zostal w bazie bez wpisu na osi" \
	|| bad "A1: sprawa przydzielona BEZ sladu na osi (assigned_to=$PRZYP_A) — os klamie"
echo "$WYN_A" | grep -q 'EVENT_LOG_FAILED' \
	&& ok "A2: assign zwrocil jawny EVENT_LOG_FAILED" \
	|| bad "A2: assign nie zglosil bledu zapisu sladu: $WYN_A"
[ "$(alarm_jest)" = "TAK" ] \
	&& ok "A3: alarm dla administratora PRZEZYL wycofanie transakcji" \
	|| bad "A3: alarm zniknal razem z rollbackiem — administrator bez sygnalu"

# ── B. BLIZNIAK 2: set_priority() ───────────────────────────────────────────
PRIO_PRZED=$(q "SELECT priority FROM wp_mp_service_cases WHERE id=$CID")
alarm_zeruj; zepsuj
WYN_B=$(wp eval "echo json_encode(MP\\Intake\\CaseRepo::set_priority($CID, 'high', 1));" 2>/dev/null)
napraw

PRIO_PO=$(q "SELECT priority FROM wp_mp_service_cases WHERE id=$CID")
[ "$PRIO_PO" = "$PRIO_PRZED" ] \
	&& ok "B1: priorytet NIE zmienil sie bez wpisu na osi (zostal '$PRIO_PO')" \
	|| bad "B1: priorytet zmieniony BEZ sladu ('$PRIO_PRZED' -> '$PRIO_PO')"
echo "$WYN_B" | grep -q 'EVENT_LOG_FAILED' \
	&& ok "B2: set_priority zwrocil jawny EVENT_LOG_FAILED" \
	|| bad "B2: set_priority nie zglosil bledu zapisu sladu: $WYN_B"
[ "$(alarm_jest)" = "TAK" ] \
	&& ok "B3: alarm dla administratora PRZEZYL wycofanie transakcji" \
	|| bad "B3: alarm zniknal razem z rollbackiem — administrator bez sygnalu"

# ── C. EGZEMPLARZ Z #287: change_status gubil ALARM (moja wlasna luka) ───────
# Sama odmowa dzialala od #287 — brakowalo sygnalu dla administratora.
alarm_zeruj; zepsuj
WYN_C=$(wp eval "echo json_encode(MP\\Intake\\CaseRepo::change_status($CID, 'w analizie', 'nowe', 1));" 2>/dev/null)
napraw

[ "$(alarm_jest)" = "TAK" ] \
	&& ok "C1: change_status — alarm PRZEZYL wycofanie (luka z #287 zamknieta)" \
	|| bad "C1: change_status wycofuje zmiane, ale alarm ginie w rollbacku"
echo "$WYN_C" | grep -q 'EVENT_LOG_FAILED' \
	&& ok "C2: change_status dalej zwraca EVENT_LOG_FAILED (#287 nietkniete)" \
	|| bad "C2: regresja na #287: $WYN_C"
[ "$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")" = "nowe" ] \
	&& ok "C3: change_status dalej nie zmienia statusu bez sladu (#287 nietkniete)" \
	|| bad "C3: regresja na #287 — status zmieniony bez wpisu"

# ── D. KONTROLA KIERUNKU: sprawna tabela => wszystko dziala i ma swoj wpis ───
# Jawny reset stanu: na kodzie SPRZED naprawy sekcje A i B przeciekaja mutacja
# (to jest sama wada), a obie operacje sa idempotentne — bez resetu D mierzylaby
# „nic sie nie zmienilo" zamiast wlasnego przedmiotu. Po resecie D jest zielona
# w OBU stanach kodu, czyli jest prawdziwa kontrola kierunku.
wp db query "UPDATE wp_mp_service_cases SET assigned_to=NULL, priority='normal' WHERE id=$CID" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_case_events WHERE case_id=$CID AND event_type IN ('CASE_ASSIGNED','PRIORITY_CHANGED')" >/dev/null 2>&1
alarm_zeruj
wp eval "MP\\Intake\\CaseRepo::assign($CID, $AG, 1);" >/dev/null 2>&1
[ "$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID")" = "$AG" ] \
	&& ok "D1: ze sprawna tabela przydzial przechodzi" || bad "D1: naprawa zepsula normalny przydzial"
[ "$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CASE_ASSIGNED'")" = "1" ] \
	&& ok "D2: przydzial ma dokladnie jeden wpis na osi" || bad "D2: zla liczba wpisow CASE_ASSIGNED"

wp eval "MP\\Intake\\CaseRepo::set_priority($CID, 'high', 1);" >/dev/null 2>&1
[ "$(q "SELECT priority FROM wp_mp_service_cases WHERE id=$CID")" = "high" ] \
	&& ok "D3: ze sprawna tabela zmiana priorytetu przechodzi" || bad "D3: naprawa zepsula zmiane priorytetu"
[ "$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='PRIORITY_CHANGED'")" = "1" ] \
	&& ok "D4: zmiana priorytetu ma dokladnie jeden wpis na osi" || bad "D4: zla liczba wpisow PRIORITY_CHANGED"

[ "$(alarm_jest)" = "NIE" ] \
	&& ok "D5: przy sprawnym dzienniku ZADEN alarm nie powstaje (brak falszywych alarmow)" \
	|| bad "D5: alarm podniesiony mimo udanych zapisow"

echo "── D2-BLIZNIAKI: PASS=$PASS FAIL=$FAIL ──"
if [ "$(( PASS + FAIL ))" -lt 15 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane 15."
	exit 2
fi
[ "$FAIL" -eq 0 ]
