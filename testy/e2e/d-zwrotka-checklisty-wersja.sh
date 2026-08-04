#!/usr/bin/env bash
# ZYWY DOWOD: zwrotki kontraktowe karty sprawy nios� wersje ksztaltu — I NIE PSUJA ODBIORCY.
#
# Kontrakt (API-KONTRAKT.md): „Zwrotki niosa `schema_version`". `mp_case_checklist_state`
# i `mp_response_templates` jej nie mialy — czyli po zmianie ksztaltu odbiorca nie mialby
# jak odroznic starej odpowiedzi od nowej. To ta sama klasa co poz. 2.27, zamknieta wtedy
# w dwoch miejscach z pieciu.
#
# ⛔ WERSJA JEDZIE W KAZDEJ POZYCJI, NIE NA WIERZCHU LISTY — i to jest sedno tej naprawy:
# odbiorca (karta sprawy w module zgloszen) robi `foreach ( $steps as $step )` i czyta
# `$step['step_key']`. Doklejenie wersji jako kolejnego ELEMENTU listy podsuneloby mu
# liczbe tam, gdzie spodziewa sie kroku — zepsulibysmy cudzy ekran, zalatwiajac wlasny
# kontrakt. Dlatego test sprawdza OBIE rzeczy naraz: ze wersja jest i ze kroki dalej
# czytaja sie tak samo.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

OUT=$(wp mp case-create --kind=reklamacja --email="chk$RANDOM@example.com" --name='Jan Kowalski' \
	--serial="SEK-CHK$RANDOM" --document='FV/2026/6' --date='2026-05-01' --desc='zwrotka checklisty' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
TOKEN=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp eval "MP\\Intake\\CaseRepo::verify('$TOKEN');" >/dev/null 2>&1
[ -n "$CID" ] && ok "sprawa $CID gotowa (rodzaj reklamacja => checklista ma kroki)" || bad "brak sprawy"

# ── 1. mp_case_checklist_state ────────────────────────────────────────────
KROKI=$(wp eval --user=1 "
	\$s = apply_filters( 'mp_case_checklist_state', null, $CID );
	echo 'ile=' . count( (array) \$s );
	echo ';wersje=' . count( array_filter( (array) \$s, function( \$k ) { return isset( \$k['schema_version'] ); } ) );
	echo ';klucze=' . count( array_filter( (array) \$s, function( \$k ) { return isset( \$k['step_key'] ) && '' !== \$k['step_key']; } ) );
" 2>/dev/null | tr -d '[:space:]')

ILE=$(echo "$KROKI" | sed -n 's/.*ile=\([0-9]*\).*/\1/p')
WER=$(echo "$KROKI" | sed -n 's/.*wersje=\([0-9]*\).*/\1/p')
KL=$(echo "$KROKI" | sed -n 's/.*klucze=\([0-9]*\).*/\1/p')

[ "${ILE:-0}" -ge 1 ] 2>/dev/null && ok "checklista oddaje $ILE krokow (jest co wersjonowac)" || bad "checklista pusta ($KROKI)"
[ "${WER:-0}" = "${ILE:-0}" ] && [ "${ILE:-0}" -ge 1 ] 2>/dev/null \
	&& ok "SEDNO: KAZDY krok niesie schema_version ($WER z $ILE)" \
	|| bad "kroki bez wersji ksztaltu ($WER z $ILE)"
[ "${KL:-0}" = "${ILE:-0}" ] \
	&& ok "ODBIORCA NIETKNIETY: kazda pozycja to nadal krok ze step_key (foreach sie nie wywroci)" \
	|| bad "ksztalt pozycji rozjechal sie — odbiorca dostalby cos, co nie jest krokiem ($KL z $ILE)"

# ── 2. mp_response_templates (znalezione przegladem klasy) ────────────────
SZAB=$(wp eval --user=1 "
	\$t = apply_filters( 'mp_response_templates', null, 'reklamacja' );
	echo 'ile=' . count( (array) \$t );
	echo ';wersje=' . count( array_filter( (array) \$t, function( \$s ) { return isset( \$s['schema_version'] ); } ) );
	echo ';klucze=' . count( array_filter( (array) \$t, function( \$s ) { return isset( \$s['key'] ); } ) );
" 2>/dev/null | tr -d '[:space:]')
SILE=$(echo "$SZAB" | sed -n 's/.*ile=\([0-9]*\).*/\1/p')
SWER=$(echo "$SZAB" | sed -n 's/.*wersje=\([0-9]*\).*/\1/p')
SKL=$(echo "$SZAB" | sed -n 's/.*klucze=\([0-9]*\).*/\1/p')

if [ "${SILE:-0}" -ge 1 ] 2>/dev/null; then
	[ "${SWER:-0}" = "${SILE:-0}" ] \
		&& ok "szablony odpowiedzi: kazdy niesie wersje ($SWER z $SILE)" \
		|| bad "szablony odpowiedzi bez wersji ($SWER z $SILE)"
	[ "${SKL:-0}" = "${SILE:-0}" ] \
		&& ok "szablony zachowaly swoj ksztalt (klucz key na miejscu)" \
		|| bad "ksztalt szablonow rozjechal sie ($SKL z $SILE)"
else
	ok "brak szablonow dla tego rodzaju — nie ma czego wersjonowac (stan legalny)"
fi

echo ""
echo "WYNIK ZWROTKA-CHECKLISTY: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
