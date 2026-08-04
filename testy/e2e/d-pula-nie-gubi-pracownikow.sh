#!/usr/bin/env bash
# ZYWY DOWOD (2.51): ekran wyboru pracownikow do automatycznego przydzialu NIE
# gubi ich, gdy w witrynie przybywa kont klientow.
#
# Co bylo zle: `AssignmentPool::agents()` pobieral DWIESCIE PIERWSZYCH kont CALEJ
# witryny posortowanych po nazwie i dopiero potem odsiewal je w PHP po uprawnieniu
# `mp_agent`. `number` WordPress zamienia na LIMIT w zapytaniu, wiec obciecie szlo
# PRZED odsianiem. Konta klientow przybywaja SAME — modul zgloszen zaklada je przy
# potwierdzeniu zgloszenia — wiec po dwustu klientach o nazwach wczesniejszych
# alfabetycznie koordynator otwieral ekran puli i nie widzial ANI JEDNEGO
# pracownika. Bez komunikatu, bez bledu: pusta lista.
#
# Test zaklada 250 kont klientow o nazwach zaczynajacych sie na „Aaa" i dwoch
# pracownikow o nazwach na „Zzz" — czyli takich, ktore przy starym kodzie wypadaja
# poza pierwsza dwusetke. Sprzata WSZYSTKIE zalozone konta (pulapka #5: zostawione
# konto zmienia sklad personelu i wywala testy w miejscach bez zwiazku).
#
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Kasuje WSZYSTKIE konta zalozone przez ten test (login zaczyna sie od pula51_).
sprzataj() {
	wp eval '
		$ids = get_users( array( "search" => "pula51_*", "search_columns" => array( "user_login" ), "number" => 1000, "fields" => "ID" ) );
		require_once ABSPATH . "wp-admin/includes/user.php";
		foreach ( $ids as $id ) { wp_delete_user( (int) $id ); }
		echo count( $ids );
	' 2>/dev/null
}

USUNIETE=$(sprzataj)
echo "  --   stan wejsciowy posprzatany (skasowanych kont z poprzedniego przebiegu: ${USUNIETE:-0})"

# ── 1. Dwoch pracownikow: jeden przez ROLE, drugi przez uprawnienie nadane
#      pojedynczemu kontu. Kryterium puli to CAPABILITY, wiec obaj maja sie liczyc.
AGENCI=$(wp eval '
	$out = array();

	$rola = wp_insert_user( array(
		"user_login"   => "pula51_agent_rola",
		"user_pass"    => wp_generate_password( 20 ),
		"user_email"   => "pula51-rola@example.com",
		"display_name" => "Zzz Pracownik Z Roli",
		"role"         => "mp_agent",
	) );

	if ( is_wp_error( $rola ) ) {
		// Rola moze nie istniec (uninstall kasuje role) — wtedy samo uprawnienie.
		$rola = wp_insert_user( array(
			"user_login"   => "pula51_agent_rola",
			"user_pass"    => wp_generate_password( 20 ),
			"user_email"   => "pula51-rola@example.com",
			"display_name" => "Zzz Pracownik Z Roli",
		) );
		if ( ! is_wp_error( $rola ) ) {
			$u = new WP_User( (int) $rola );
			$u->add_cap( "mp_agent" );
		}
	}

	$wprost = wp_insert_user( array(
		"user_login"   => "pula51_agent_wprost",
		"user_pass"    => wp_generate_password( 20 ),
		"user_email"   => "pula51-wprost@example.com",
		"display_name" => "Zzz Pracownik Z Uprawnieniem",
	) );

	if ( ! is_wp_error( $wprost ) ) {
		$u = new WP_User( (int) $wprost );
		$u->add_cap( "mp_agent" );
	}

	$out["rola"]   = is_wp_error( $rola ) ? 0 : (int) $rola;
	$out["wprost"] = is_wp_error( $wprost ) ? 0 : (int) $wprost;
	echo wp_json_encode( $out );
' 2>/dev/null)

ID_ROLA=$(echo "$AGENCI" | grep -oE '"rola":[0-9]+' | cut -d: -f2)
ID_WPROST=$(echo "$AGENCI" | grep -oE '"wprost":[0-9]+' | cut -d: -f2)
{ [ -n "${ID_ROLA:-}" ] && [ "${ID_ROLA:-0}" -gt 0 ] && [ "${ID_WPROST:-0}" -gt 0 ]; } \
	&& ok "dwoch pracownikow zalozonych (przez role: #$ID_ROLA, przez uprawnienie: #$ID_WPROST)" \
	|| bad "nie udalo sie zalozyc pracownikow ($AGENCI)"

# ── 2. Pracownicy widoczni, ZANIM przybeda klienci (proba kontrolna) ─────────
WIDAC_PRZED=$(wp eval "
	\$ids = array_map( static function ( \$u ) { return (int) \$u->ID; }, MP\\Automator\\AssignmentPool::agents() );
	echo ( in_array( $ID_ROLA, \$ids, true ) && in_array( $ID_WPROST, \$ids, true ) ) ? 'OBAJ' : 'BRAK';
" 2>/dev/null | tr -d '[:space:]')
[ "$WIDAC_PRZED" = "OBAJ" ] \
	&& ok "proba kontrolna: przy malej witrynie obaj pracownicy sa na liscie" \
	|| bad "pracownicy nie sa widoczni nawet BEZ kont klientow ($WIDAC_PRZED) — test bada nie to, co trzeba"

# ── 3. 250 kont klientow o nazwach WCZESNIEJSZYCH alfabetycznie ─────────────
ILE_KLIENTOW=$(wp eval '
	$zrobione = 0;
	for ( $i = 1; $i <= 250; $i++ ) {
		$nr = str_pad( (string) $i, 3, "0", STR_PAD_LEFT );
		$id = wp_insert_user( array(
			"user_login"   => "pula51_klient_" . $nr,
			"user_pass"    => wp_generate_password( 20 ),
			"user_email"   => "pula51-klient-" . $nr . "@example.com",
			"display_name" => "Aaa Klient " . $nr,
		) );
		if ( ! is_wp_error( $id ) ) { ++$zrobione; }
	}
	echo $zrobione;
' 2>/dev/null | tr -d '[:space:]')
[ "${ILE_KLIENTOW:-0}" -ge 250 ] \
	&& ok "witryna urosla o 250 kont klientow (nazwy sortuja sie PRZED pracownikami)" \
	|| bad "zalozono tylko ${ILE_KLIENTOW:-0} kont klientow — test nie przekracza limitu 200"

# ── 4. SEDNO: pracownicy DALEJ sa na liscie puli ────────────────────────────
WYNIK=$(wp eval "
	\$agenci = MP\\Automator\\AssignmentPool::agents();
	\$ids    = array_map( static function ( \$u ) { return (int) \$u->ID; }, \$agenci );
	\$klient = get_user_by( 'login', 'pula51_klient_001' );
	echo wp_json_encode( array(
		'ile'         => count( \$ids ),
		'ma_role'     => in_array( $ID_ROLA, \$ids, true ),
		'ma_wprost'   => in_array( $ID_WPROST, \$ids, true ),
		'ma_klienta'  => \$klient ? in_array( (int) \$klient->ID, \$ids, true ) : false,
	) );
" 2>/dev/null)

echo "$WYNIK" | grep -q '"ma_role":true' \
	&& ok "SEDNO 2.51: pracownik z rola JEST na liscie mimo 250 kont klientow przed nim" \
	|| bad "pracownik z rola ZNIKNAL z listy puli ($WYNIK)"
echo "$WYNIK" | grep -q '"ma_wprost":true' \
	&& ok "SEDNO 2.51: pracownik z uprawnieniem nadanym wprost tez JEST na liscie" \
	|| bad "pracownik z uprawnieniem nadanym wprost zniknal z listy ($WYNIK)"
echo "$WYNIK" | grep -q '"ma_klienta":false' \
	&& ok "klient NIE trafia do puli (odsiew po uprawnieniu dalej dziala)" \
	|| bad "konto klienta weszlo do puli pracownikow ($WYNIK)"

# ── 5. Sprzatanie: zadne konto testowe nie zostaje ──────────────────────────
sprzataj >/dev/null 2>&1
ZOSTALO=$(wp eval 'echo count( get_users( array( "search" => "pula51_*", "search_columns" => array( "user_login" ), "number" => 1000, "fields" => "ID" ) ) );' 2>/dev/null | tr -d '[:space:]')
[ "${ZOSTALO:-9}" = "0" ] \
	&& ok "wszystkie 252 konta testowe skasowane (sklad personelu wraca do stanu sprzed testu)" \
	|| bad "zostalo ${ZOSTALO} kont testowych — nastepny test dostanie inny sklad personelu"

echo ""
echo "WYNIK D-PULA-2.51: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
