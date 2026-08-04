#!/usr/bin/env bash
# ZYWY DOWOD (2.27, czesc modulu zgloszen): KAZDA zwrotka kontraktowa niesie
# wersje schematu.
#
# Twarda regula kontraktu mowi, ze konsument ma poznac PO ZWROTCE, czy rozumie jej
# ksztalt. Strona rejestru dostala to wczesniej (`Repo::DETAILS_SCHEMA_VERSION`,
# `WarrantyCheck::SCHEMA_VERSION`), dziennik zdarzen tez (`CaseEvents::SCHEMA_VERSION`),
# a zwrotki modulu zgloszen zostaly bez wersji — poza jedna (`mp_case_get_context`).
# To byla druga polowka tej pozycji.
#
# ⛔ SKALARY SWIADOMIE ZOSTAJA BEZ WERSJI (ustalone) — liczba i lista identyfikatorow
# nie maja ksztaltu, ktory moglby sie rozjechac. Test tego pilnuje, zeby nikt nie
# „domknal" pozycji, doklejajac wersje tam, gdzie jej byc nie mialo.
#
# Exit 0 = OK. Test sprzata po sobie (jedna sprawa testowa).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

sprzataj() {
	wp db query "DELETE FROM wp_mp_service_cases WHERE id IN (SELECT case_id FROM wp_mp_consents WHERE email='wersja-zwrotki@example.com')" >/dev/null 2>&1
	wp db query "DELETE FROM wp_mp_consents WHERE email='wersja-zwrotki@example.com'" >/dev/null 2>&1
	wp db query "DELETE FROM wp_mp_customers WHERE email='wersja-zwrotki@example.com'" >/dev/null 2>&1
}
sprzataj

OUT=$(wp mp case-create --kind=zapytanie --email=wersja-zwrotki@example.com --name='Klient Wersja' \
	--desc='sprawa do sprawdzenia wersji zwrotki' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2 | tr -d '[:space:]')
TOK=$(echo "$OUT" | grep '^token=' | cut -d= -f2 | tr -d '[:space:]')
wp eval "MP\\Intake\\CaseRepo::verify( '$TOK' );" >/dev/null 2>&1
[ "${CID:-0}" -gt 0 ] && ok "sprawa testowa zalozona (#$CID)" || bad "nie udalo sie zalozyc sprawy testowej"

# ── 1. SEDNO: kazda zwrotka KLUCZOWANA niesie wersje ────────────────────────
WYNIK=$(wp eval "
	wp_set_current_user( 1 );
	\$u = wp_get_current_user();
	\$u->add_cap( 'mp_coordinator' );
	\$u->add_cap( 'mp_system_admin' );

	\$wersja = MP\\Intake\\CaseRepo::SCHEMA_VERSION;
	\$zwrotki = array(
		'kontekst_sprawy'  => apply_filters( 'mp_case_get_context', null, $CID ),
		'lista_spraw'      => apply_filters( 'mp_cases_query', null, array(), 1, 5 ),
		'zmiana_statusu'   => apply_filters( 'mp_case_change_status', null, $CID, 'status-ktorego-nie-ma', 'nowe', 1 ),
		'przydzial'        => apply_filters( 'mp_case_assign', null, $CID, 999999, 1 ),
		'priorytet'        => apply_filters( 'mp_case_set_priority', null, $CID, 'nieistniejacy', 1 ),
		'checklista'       => apply_filters( 'mp_case_checklist_authorize', null, $CID, 'krok-ktorego-nie-ma', true, 1 ),
	);

	\$bez_wersji = array();
	\$zla_wersja = array();
	foreach ( \$zwrotki as \$nazwa => \$z ) {
		if ( ! is_array( \$z ) ) { \$bez_wersji[] = \$nazwa . '(nie-tablica)'; continue; }
		if ( ! isset( \$z['schema_version'] ) ) { \$bez_wersji[] = \$nazwa; continue; }
		if ( (int) \$z['schema_version'] !== (int) \$wersja ) { \$zla_wersja[] = \$nazwa; }
	}

	\$u->remove_cap( 'mp_coordinator' );
	\$u->remove_cap( 'mp_system_admin' );
	echo wp_json_encode( array( 'sprawdzonych' => count( \$zwrotki ), 'bez_wersji' => \$bez_wersji, 'zla_wersja' => \$zla_wersja ) );
" 2>/dev/null)

echo "$WYNIK" | grep -q '"sprawdzonych":6' \
	&& ok "sprawdzono komplet szesciu zwrotek kontraktowych modulu zgloszen" \
	|| bad "nie udalo sie zebrac zwrotek ($WYNIK)"
echo "$WYNIK" | grep -q '"bez_wersji":\[\]' \
	&& ok "SEDNO: KAZDA zwrotka kontraktowa niesie wersje schematu" \
	|| bad "zwrotki bez wersji schematu: $WYNIK"
echo "$WYNIK" | grep -q '"zla_wersja":\[\]' \
	&& ok "wszystkie zwrotki podaja TE SAMA wersje (jedno zrodlo: CaseRepo::SCHEMA_VERSION)" \
	|| bad "zwrotki podaja rozne wersje: $WYNIK"

# ── 2. Wersja jest STALA KLASY, nie liczba wpisana w kilku miejscach ────────
STALA=$(wp eval 'echo defined( "MP\Intake\CaseRepo::SCHEMA_VERSION" ) ? (string) MP\Intake\CaseRepo::SCHEMA_VERSION : "BRAK";' 2>/dev/null | tr -d '[:space:]')
[ "$STALA" != "BRAK" ] && [ "$STALA" -ge 1 ] 2>/dev/null \
	&& ok "wersja zwrotek jest stala klasy (CaseRepo::SCHEMA_VERSION = $STALA), a nie liczba przepisana w kilku miejscach" \
	|| bad "brak stalej wersji zwrotek ($STALA)"

# ── 3. PRZYPADEK BEZ WADY: skalary swiadomie BEZ wersji ────────────────────
SKALARY=$(wp eval "
	\$licznik = apply_filters( 'mp_product_active_cases_count', null, 1 );
	\$lista   = apply_filters( 'mp_cases_verified_ids', null, 30, 5 );
	echo wp_json_encode( array(
		'licznik_to_liczba' => is_int( \$licznik ),
		'lista_to_lista'    => is_array( \$lista ) && ( array() === \$lista || array_keys( \$lista ) === range( 0, count( \$lista ) - 1 ) ),
		'lista_bez_wersji'  => is_array( \$lista ) && ! isset( \$lista['schema_version'] ),
	) );
" 2>/dev/null)
echo "$SKALARY" | grep -q '"licznik_to_liczba":true' \
	&& ok "licznik aktywnych spraw dalej jest LICZBA (skalar swiadomie bez wersji)" \
	|| bad "licznik zmienil ksztalt ($SKALARY)"
echo "$SKALARY" | grep -q '"lista_bez_wersji":true' \
	&& ok "lista identyfikatorow dalej jest czysta lista (bez doklejonej wersji)" \
	|| bad "do listy identyfikatorow doklejono wersje — to psuje jej ksztalt ($SKALARY)"

# ── 4. PRZYPADEK BEZ WADY: dotychczasowe pola zwrotek na miejscu ───────────
POLA=$(wp eval "
	\$k = apply_filters( 'mp_case_get_context', null, $CID );
	\$q = apply_filters( 'mp_cases_query', null, array(), 1, 5 );
	echo wp_json_encode( array(
		'kontekst_ma_status' => is_array( \$k ) && isset( \$k['status'], \$k['case_number'], \$k['kontakt'] ),
		'lista_ma_wiersze'   => is_array( \$q ) && isset( \$q['rows'], \$q['total'], \$q['page'], \$q['per_page'] ),
	) );
" 2>/dev/null)
echo "$POLA" | grep -q '"kontekst_ma_status":true' \
	&& ok "kontekst sprawy ma komplet dotychczasowych pol (nic nie zniknelo)" \
	|| bad "kontekst sprawy zgubil pola ($POLA)"
echo "$POLA" | grep -q '"lista_ma_wiersze":true' \
	&& ok "lista spraw ma komplet dotychczasowych pol (rows/total/page/per_page)" \
	|| bad "lista spraw zgubila pola ($POLA)"

sprzataj
echo ""
echo "WYNIK 2.27-intake: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
