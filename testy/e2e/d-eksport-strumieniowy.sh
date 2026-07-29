#!/usr/bin/env bash
# ZYWY DOWOD (audyt 29.07): eksport CSV nie trzyma wszystkich spraw w pamieci.
#
# Co bylo zle: `collect()` sciagalo WSZYSTKIE pasujace sprawy do jednej tablicy PHP
# ZANIM cokolwiek poszlo do przegladarki, a paginacja szla przez OFFSET. Przy
# kilkudziesieciu tysiacach spraw koordynator klikal „Eksport" i dostawal biala strone
# albo blad limitu czasu — bez zadnej podpowiedzi, ze chodzi o rozmiar. Sam kod projektu
# w innym miejscu przyznaje, ze przy 5000 spraw robi sie „zauwazalnie wolno".
#
# Test mierzy SEDNO: zuzycie pamieci przy zestawieniu liczonym AKUMULACYJNIE (nowe)
# kontra zbieranie spraw do tablicy (stare). Rozne rzedy wielkosci = dowod.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# ── 1. SEDNO: pamiec NIE rosnie z liczba spraw ──────────────────────────────
# Porownujemy dwie drogi na tym samym zbiorze 20 000 spraw: akumulacja (nowa)
# kontra zbieranie do tablicy (tak dzialal `collect`).
POMIAR=$(wp eval '
	$ile = 20000;
	$make = static function ( $i ) {
		return array(
			"case_number" => "SRV/2026/" . $i, "status" => 0 === $i % 3 ? "zamknięte" : "nowe",
			"kind" => "reklamacja", "country" => "PL", "lang" => "pl",
			"created_at" => "2026-01-01 00:00:00", "closed_at" => "2026-01-02 00:00:00",
			"handling_seconds" => 0 === $i % 3 ? 3600 : null,
			"rejection_reason_code" => 0 === $i % 7 ? "brak_dowodu" : null,
		);
	};

	// (a) STARA droga: wszystkie sprawy w jednej tablicy.
	$start = memory_get_usage();
	$all = array();
	for ( $i = 1; $i <= $ile; $i++ ) { $all[] = $make( $i ); }
	$stara = memory_get_usage() - $start;
	unset( $all );

	// (b) NOWA droga: akumulator o stalym rozmiarze, sprawa po sprawie.
	$r = new ReflectionMethod( "MP\Automator\CsvExport", "accumulate" );
	$r->setAccessible( true );
	$acc = array( "total" => 0, "by_status" => array(), "by_reason" => array(), "closed" => 0, "sum_sec" => 0 );
	$start = memory_get_usage();
	for ( $i = 1; $i <= $ile; $i++ ) {
		$c = $make( $i );
		$code = null !== $c["rejection_reason_code"] ? (string) $c["rejection_reason_code"] : "";
		$r->invokeArgs( null, array( &$acc, $c, $code ) );
	}
	$nowa = memory_get_usage() - $start;

	echo wp_json_encode( array( "stara" => $stara, "nowa" => $nowa, "total" => $acc["total"] ) );
' 2>/dev/null)

STARA=$(echo "$POMIAR" | grep -oE '"stara":[0-9-]+' | cut -d: -f2)
NOWA=$(echo "$POMIAR" | grep -oE '"nowa":[0-9-]+' | cut -d: -f2)

if [ -n "${STARA:-}" ] && [ -n "${NOWA:-}" ] && [ "$STARA" -gt 0 ] 2>/dev/null; then
	ok "pomiar wykonany (stara droga: $STARA B, nowa: $NOWA B na 20 000 spraw)"
	# Prog z ogromnym zapasem: akumulator ma byc o RZAD WIELKOSCI lzejszy.
	if [ "$NOWA" -lt $(( STARA / 100 )) ] 2>/dev/null; then
		ok "SEDNO: pamiec akumulatora ponizej 1% tego, co zjadalo zbieranie do tablicy"
	else
		bad "akumulator zjada porownywalnie duzo pamieci ($NOWA vs $STARA) — zmiana nic nie dala"
	fi
else
	bad "nie udalo sie zmierzyc pamieci ($POMIAR)"
fi

# ── 2. Zestawienie liczy TO SAMO, co liczyla stara metoda ───────────────────
ZGODNE=$(wp eval '
	$a = new ReflectionMethod( "MP\Automator\CsvExport", "accumulate" );
	$f = new ReflectionMethod( "MP\Automator\CsvExport", "summary_finish" );
	$a->setAccessible( true ); $f->setAccessible( true );
	$acc = array( "total" => 0, "by_status" => array(), "by_reason" => array(), "closed" => 0, "sum_sec" => 0 );

	// 3 zamkniete po 2h + 2 otwarte, jedna odrzucona.
	$dane = array(
		array( "status" => "zamknięte", "handling_seconds" => 7200, "rejection_reason_code" => null ),
		array( "status" => "zamknięte", "handling_seconds" => 7200, "rejection_reason_code" => null ),
		array( "status" => "zamknięte", "handling_seconds" => 7200, "rejection_reason_code" => null ),
		array( "status" => "nowe",      "handling_seconds" => null, "rejection_reason_code" => null ),
		array( "status" => "odrzucone", "handling_seconds" => null, "rejection_reason_code" => "brak_dowodu" ),
	);
	foreach ( $dane as $c ) {
		$code = null !== $c["rejection_reason_code"] ? (string) $c["rejection_reason_code"] : "";
		$a->invokeArgs( null, array( &$acc, $c, $code ) );
	}
	$s = $f->invoke( null, $acc );
	echo wp_json_encode( array(
		"total" => $s["total"], "zamkniete" => $s["closed_count"],
		"status_zamkniete" => $s["by_status"]["zamknięte"] ?? 0,
		"powod" => $s["by_reason"]["brak_dowodu"] ?? 0,
		"srednia" => $s["avg_hours"], "suma" => $s["total_hours"],
	) );
' 2>/dev/null)

echo "$ZGODNE" | grep -q '"total":5' && ok "zestawienie: laczna liczba spraw = 5" || bad "zla laczna liczba ($ZGODNE)"
echo "$ZGODNE" | grep -q '"zamkniete":3' && ok "zestawienie: 3 sprawy zamkniete (czas obslugi liczony tylko dla nich)" || bad "zla liczba zamknietych ($ZGODNE)"
echo "$ZGODNE" | grep -q '"status_zamkniete":3' && ok "zestawienie: rozklad po statusie zgodny" || bad "zly rozklad po statusie ($ZGODNE)"
echo "$ZGODNE" | grep -q '"powod":1' && ok "zestawienie: rozklad powodow odrzucen zgodny" || bad "zly rozklad powodow ($ZGODNE)"
echo "$ZGODNE" | grep -q '"srednia":"2' && ok "zestawienie: sredni czas obslugi = 2 godziny" || bad "zla srednia ($ZGODNE)"
echo "$ZGODNE" | grep -q '"suma":"6' && ok "zestawienie: laczny czas obslugi = 6 godzin" || bad "zla suma godzin ($ZGODNE)"

# ── 3. Stara, pamieciozerna droga NIE ISTNIEJE (zeby nie wrocila bokiem) ────
MARTWA=$(wp eval 'echo method_exists( "MP\Automator\CsvExport", "collect" ) ? "jest" : "brak";' 2>/dev/null | tr -d '[:space:]')
[ "$MARTWA" = "brak" ] \
	&& ok "metoda zbierajaca wszystko do pamieci zostala usunieta (nie ma jak wrocic bokiem)" \
	|| bad "collect() dalej istnieje — grozi powrot starego zachowania"

# ── 4. Audyt wyniesienia danych ma liczbe spraw BEZ ich sciagania ───────────
# `handle()` bierze `total` z kontraktu, nie z policzenia zebranej tablicy.
KONTRAKT=$(wp eval '
	$r = apply_filters( "mp_cases_query", null, array(), 1, 1 );
	echo ( is_array( $r ) && isset( $r["total"] ) ) ? "ma-total" : "brak-total";
' 2>/dev/null | tr -d '[:space:]')
[ "$KONTRAKT" = "ma-total" ] \
	&& ok "kontrakt oddaje laczna liczbe spraw (audyt nie wymaga sciagania wszystkiego)" \
	|| bad "kontrakt nie oddaje total — audyt musialby liczyc po zebraniu calosci"

echo ""
echo "WYNIK EKSPORT-STRUMIENIOWY: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
