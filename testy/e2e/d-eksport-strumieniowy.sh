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

# ── 5. POZYCJA 2.50: „Liczba spraw zamknietych" liczy SPRAWY ZAMKNIETE ──────
# Co bylo zle: ten wiersz zestawienia rosl tylko wtedy, gdy DALO SIE policzyc czas
# obslugi. Sprawa zamknieta z uszkodzonym albo cofnietym znacznikiem zmiany statusu
# (czas obslugi pusty) stala w rozkladzie po statusach jako zamknieta, a w wierszu
# „Liczba spraw zamknietych" jej NIE BYLO. Koordynator dostawal w jednym pliku dwie
# liczby o tej samej nazwie, ktore sie nie zgadzaly, bez slowa wyjasnienia.
# Test NIC nie zapisuje do bazy — dane wchodza przez kontrakt `mp_cases_query`.
ANOMALIA=$(wp eval '
	$a = new ReflectionMethod( "MP\Automator\CsvExport", "accumulate" );
	$f = new ReflectionMethod( "MP\Automator\CsvExport", "summary_finish" );
	$a->setAccessible( true ); $f->setAccessible( true );
	$acc = array( "total" => 0, "by_status" => array(), "by_reason" => array(), "closed" => 0, "timed" => 0, "sum_sec" => 0 );

	// 3 sprawy ZAMKNIETE, ale trzecia ma znacznik zmiany statusu WCZESNIEJSZY niz
	// data utworzenia — kontrakt oddaje wtedy `closed_at`, ale `handling_seconds` = null.
	$dane = array(
		array( "status" => "zamknięte", "closed_at" => "2026-02-01 12:00:00", "handling_seconds" => 7200 ),
		array( "status" => "zamknięte", "closed_at" => "2026-02-01 12:00:00", "handling_seconds" => 7200 ),
		array( "status" => "zamknięte", "closed_at" => "2025-12-31 23:00:00", "handling_seconds" => null ),
		array( "status" => "nowe",      "closed_at" => null,                  "handling_seconds" => null ),
	);
	foreach ( $dane as $c ) { $a->invokeArgs( null, array( &$acc, $c, "" ) ); }

	$s = $f->invoke( null, $acc );
	echo wp_json_encode( array(
		"zamkniete"        => $s["closed_count"],
		"status_zamkniete" => $s["by_status"]["zamknięte"] ?? 0,
		"z_czasem"         => $s["timed_count"] ?? -1,
		"srednia"          => $s["avg_hours"],
	) );
' 2>/dev/null)

echo "$ANOMALIA" | grep -q '"zamkniete":3' \
	&& ok "SEDNO 2.50: 3 sprawy zamkniete w rozkladzie = 3 w wierszu „Liczba spraw zamknietych\"" \
	|| bad "wiersz „Liczba spraw zamknietych\" nie zgadza sie z rozkladem po statusach ($ANOMALIA)"
echo "$ANOMALIA" | grep -q '"status_zamkniete":3' \
	&& ok "rozklad po statusach widzi 3 sprawy zamkniete" \
	|| bad "zly rozklad po statusach ($ANOMALIA)"
echo "$ANOMALIA" | grep -q '"z_czasem":2' \
	&& ok "osobna wielkosc: 2 sprawy z policzonym czasem obslugi (podstawa sredniej)" \
	|| bad "brak osobnej liczby spraw z policzonym czasem ($ANOMALIA)"
echo "$ANOMALIA" | grep -q '"srednia":"2' \
	&& ok "srednia dalej dzieli sie przez sprawy Z CZASEM = 2 godziny (sprawa bez czasu jej nie zanizyla)" \
	|| bad "zla srednia — sprawa bez czasu weszla do dzielenia ($ANOMALIA)"

# Ta sama anomalia w GOTOWYM PLIKU, ktory dostaje koordynator (nie w samych liczbach).
CSV=$(wp eval '
	add_filter( "mp_cases_query", static function ( $r, $filters, $page, $per ) {
		$mk = static function ( $nr, $status, $closed, $sec ) {
			return array(
				"case_number" => $nr, "status" => $status, "kind" => "reklamacja",
				"country" => "PL", "lang" => "pl", "created_at" => "2026-01-15 10:00:00",
				"closed_at" => $closed, "handling_seconds" => $sec, "rejection_reason_code" => null,
			);
		};
		if ( $page > 1 ) { return array( "rows" => array(), "total" => 4 ); }
		return array(
			"rows" => array(
				$mk( "SRV/2026/1", "zamknięte", "2026-02-01 12:00:00", 7200 ),
				$mk( "SRV/2026/2", "zamknięte", "2026-02-01 12:00:00", 7200 ),
				$mk( "SRV/2026/3", "zamknięte", "2025-12-31 23:00:00", null ),
				$mk( "SRV/2026/4", "nowe",      null,                  null ),
			),
			"total" => 4,
		);
	}, 99, 4 );

	$s = new ReflectionMethod( "MP\Automator\CsvExport", "stream" );
	$s->setAccessible( true );
	$s->invoke( null, array() );
' 2>/dev/null)

# Etykiety maja spacje, wiec fputcsv je cytuje — sprawdzamy dokladny ksztalt wiersza.
WIERSZ=$(echo "$CSV" | grep -F 'Liczba spraw zamkniętych' | head -1 | tr -d '\r')
[ "$WIERSZ" = '"Liczba spraw zamkniętych";3' ] \
	&& ok "plik dla koordynatora: „Liczba spraw zamknietych\";3 zgodne ze statusami" \
	|| bad "w pliku stoi [$WIERSZ] zamiast \"Liczba spraw zamkniętych\";3"
echo "$CSV" | grep -qF '"W tym z policzonym czasem obsługi";2' \
	&& ok "plik nazywa druga wielkosc wprost: „W tym z policzonym czasem obslugi\";2" \
	|| bad "plik nie rozroznia obu wielkosci"
echo "$CSV" | grep -qF '"Sprawy zamknięte bez policzonego czasu obsługi";1' \
	&& ok "plik pokazuje roznice (1 sprawa) zamiast milczec" \
	|| bad "roznica miedzy liczbami nie jest w pliku nazwana"
echo "$CSV" | grep -qF 'Brak znacznika zmiany statusu' \
	&& ok "plik wyjasnia, SKAD roznica (koordynator czyta CSV bez nas)" \
	|| bad "brak przypisu tlumaczacego roznice"

# Zdrowe dane: przypisu NIE MA (zestawienie nie strasza bez powodu).
CSV_OK=$(wp eval '
	add_filter( "mp_cases_query", static function ( $r, $filters, $page, $per ) {
		if ( $page > 1 ) { return array( "rows" => array(), "total" => 1 ); }
		return array( "rows" => array( array(
			"case_number" => "SRV/2026/9", "status" => "zamknięte", "kind" => "reklamacja",
			"country" => "PL", "lang" => "pl", "created_at" => "2026-01-15 10:00:00",
			"closed_at" => "2026-01-15 12:00:00", "handling_seconds" => 7200,
			"rejection_reason_code" => null,
		) ), "total" => 1 );
	}, 99, 4 );
	$s = new ReflectionMethod( "MP\Automator\CsvExport", "stream" );
	$s->setAccessible( true );
	$s->invoke( null, array() );
' 2>/dev/null)

echo "$CSV_OK" | grep -qF 'Sprawy zamknięte bez policzonego czasu obsługi' \
	&& bad "przy zdrowych danych zestawienie doklada wiersz o roznicy, ktorej nie ma" \
	|| ok "przy zdrowych danych zestawienie milczy o roznicy (obie liczby rowne)"

echo ""
echo "WYNIK EKSPORT-STRUMIENIOWY: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
