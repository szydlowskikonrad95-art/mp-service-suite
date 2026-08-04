#!/usr/bin/env bash
# ZYWY DOWOD: zwrotki terminow SLA nios� wersje ksztaltu — pojedyncza I HURTOWA.
#
# Kontrakt (API-KONTRAKT.md): „Zwrotki niosa `schema_version`". `mp_case_deadline`
# i jego hurtowy wariant `mp_case_deadlines` jej nie mialy. Hurtowy jest tu wazniejszy,
# niz wyglada: to on karmi KOLUMNE TERMINU na liscie spraw personelu, wiec po zmianie
# ksztaltu odbiorca nie mialby jak poznac, ze dostal starsza odpowiedz.
#
# ⛔ KSZTALT DOBRANY TAK, ZEBY NIE ZLAMAC ODBIORCY: wariant hurtowy oddaje mape
# `case_id => wiersz`, wiec wersja jedzie W KAZDYM WIERSZU, a nie jako dodatkowy klucz
# mapy — inaczej „schema_version" wygladaloby jak kolejne ID sprawy. Efekt uboczny jest
# dobry: wiersz z wariantu hurtowego ma teraz DOKLADNIE ten sam ksztalt, co zwrotka
# pojedyncza, i test to sprawdza.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

sprawa() {
	local OUT CID TOKEN
	OUT=$(wp mp case-create --kind=reklamacja --email="term$RANDOM@example.com" --name='Jan Kowalski' \
		--serial="SEK-TR$RANDOM" --document='FV/2026/7' --date='2026-05-01' --desc='zwrotka terminow' 2>/dev/null)
	CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
	TOKEN=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
	wp eval "MP\\Intake\\CaseRepo::verify('$TOKEN');" >/dev/null 2>&1
	echo "$CID"
}

A=$(sprawa); B=$(sprawa)
wp eval "MP\\Automator\\Sla::provision($A); MP\\Automator\\Sla::provision($B);" >/dev/null 2>&1
MA=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id IN ($A,$B)")
[ "${MA:-0}" = "2" ] && ok "dwie sprawy z wierszem terminu ($A, $B)" || bad "brak wierszy terminow ($MA)"

# ── 1. Zwrotka POJEDYNCZA ─────────────────────────────────────────────────
POJ=$(wp eval --user=1 "
	\$d = apply_filters( 'mp_case_deadline', null, $A );
	echo is_array( \$d ) ? 'wersja=' . ( \$d['schema_version'] ?? 'BRAK' ) . ';deadline=' . ( isset( \$d['deadline_at'] ) ? 'jest' : 'BRAK' ) : 'NIE-TABLICA';
" 2>/dev/null | tr -d '[:space:]')
echo "$POJ" | grep -q 'wersja=1;' \
	&& ok "SEDNO: pojedyncza zwrotka terminu niesie schema_version ($POJ)" \
	|| bad "pojedyncza zwrotka terminu bez wersji ksztaltu ($POJ)"
echo "$POJ" | grep -q 'deadline=jest' \
	&& ok "pola merytoryczne zwrotki nietkniete (deadline_at na miejscu)" \
	|| bad "zwrotka zgubila pola merytoryczne ($POJ)"

# ── 2. Zwrotka HURTOWA — i ten sam ksztalt wiersza ────────────────────────
HUR=$(wp eval --user=1 "
	\$m = apply_filters( 'mp_case_deadlines', null, array( $A, $B ) );
	\$m = (array) \$m;
	echo 'wierszy=' . count( \$m );
	echo ';zwersja=' . count( array_filter( \$m, function( \$w ) { return isset( \$w['schema_version'] ); } ) );
	echo ';klucze=' . implode( '/', array_map( 'strval', array_keys( \$m ) ) );
" 2>/dev/null | tr -d '[:space:]')
HW=$(echo "$HUR" | sed -n 's/.*wierszy=\([0-9]*\).*/\1/p')
HV=$(echo "$HUR" | sed -n 's/.*zwersja=\([0-9]*\).*/\1/p')

[ "${HW:-0}" = "2" ] && ok "wariant hurtowy oddal 2 wiersze jednym zapytaniem" || bad "hurtowy oddal $HW wierszy ($HUR)"
[ "${HV:-0}" = "${HW:-0}" ] && [ "${HW:-0}" -ge 1 ] 2>/dev/null \
	&& ok "SEDNO: KAZDY wiersz wariantu hurtowego niesie schema_version ($HV z $HW)" \
	|| bad "wiersze hurtowe bez wersji ($HV z $HW)"

# Klucze mapy MUSZA zostac numerami spraw — wersja nie moze udawac ID.
echo "$HUR" | grep -q "klucze=$A/$B\|klucze=$B/$A" \
	&& ok "ODBIORCA NIETKNIETY: mapa nadal kluczowana numerami spraw, bez obcych kluczy" \
	|| bad "w mapie hurtowej pojawil sie klucz, ktory nie jest ID sprawy ($HUR)"

# ── 3. Oba warianty oddaja TEN SAM ksztalt wiersza ────────────────────────
ZGODA=$(wp eval --user=1 "
	\$p = (array) apply_filters( 'mp_case_deadline', null, $A );
	\$h = (array) apply_filters( 'mp_case_deadlines', null, array( $A ) );
	\$w = (array) ( \$h[ $A ] ?? array() );
	\$kp = array_keys( \$p ); sort( \$kp );
	\$kh = array_keys( \$w ); sort( \$kh );
	echo \$kp === \$kh ? 'ZGODNE' : 'ROZNE:' . implode( ',', \$kp ) . '|' . implode( ',', \$kh );
" 2>/dev/null | tr -d '[:space:]')
[ "$ZGODA" = "ZGODNE" ] \
	&& ok "wiersz hurtowy ma DOKLADNIE ten sam zestaw pol co zwrotka pojedyncza" \
	|| bad "warianty rozjechaly sie ksztaltem ($ZGODA)"

echo ""
echo "WYNIK ZWROTKA-TERMINOW: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
