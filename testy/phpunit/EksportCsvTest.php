<?php
/**
 * Testy EKSPORTU CSV — klasa bez ani jednego testu jednostkowego (2.17).
 *
 * Audyt wymienia `CsvExport` na pierwszym miejscu listy klas niepilnowanych,
 * bo siedzi w niej JEDYNA ochrona przed formula arkusza kalkulacyjnego —
 * autor opisal ja w komentarzu jako „OBOWIAZKOWE (RCE u klienta)". Plik CSV
 * z komorka zaczynajaca sie od znaku rownosci jest w arkuszu FORMULA i wykona
 * sie po otwarciu przez koordynatora.
 *
 * Testujemy ZACHOWANIE (co wyjdzie w pliku i co pokaze zestawienie), nie sama
 * obecnosc klasy.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Automator\CsvExport;
use MP\Common\Csv;
use PHPUnit\Framework\TestCase;

/**
 * Ochrona przed formula arkusza + zestawienie na koncu eksportu.
 */
final class EksportCsvTest extends TestCase {

	/**
	 * Wartosci, ktore arkusz kalkulacyjny potraktuje jak formule.
	 *
	 * @return array<string, array{0: string}>
	 */
	public static function wartosci_grozne(): array {
		return array(
			'równa się'         => array( '=1+1' ),
			'wywołanie funkcji' => array( '=HYPERLINK("http://zly.example","klik")' ),
			'plus'              => array( '+1+1' ),
			'minus'             => array( '-1+1' ),
			'małpa'             => array( '@SUM(A1:A9)' ),
			'tabulator'         => array( "\tcokolwiek" ),
			'powrót karetki'    => array( "\rcokolwiek" ),
		);
	}

	/**
	 * Kazda grozna wartosc dostaje apostrof — arkusz pokaze tekst, nie wykona go.
	 *
	 * @dataProvider wartosci_grozne
	 *
	 * @param string $wartosc Wartosc surowa.
	 */
	public function test_wartosc_ktora_arkusz_uznalby_za_formule_jest_unieszkodliwiona( string $wartosc ): void {
		$wynik = Csv::harden( $wartosc );

		self::assertSame( "'" . $wartosc, $wynik );
		self::assertStringStartsWith( "'", $wynik, 'Formuła bez apostrofu wykona się po otwarciu pliku.' );
	}

	/**
	 * Zwykly tekst NIE jest kaleczony (ochrona nie moze psuc danych).
	 */
	public function test_zwykla_wartosc_zostaje_nietknieta(): void {
		self::assertSame( 'SRV/2026/0001', Csv::harden( 'SRV/2026/0001' ) );
		self::assertSame( 'Zamknięte', Csv::harden( 'Zamknięte' ) );
		self::assertSame( '', Csv::harden( '' ) );
		self::assertSame( '2026-03-01 08:00:00', Csv::harden( '2026-03-01 08:00:00' ) );
	}

	/**
	 * Ochrona dziala na KAZDEJ komorce wiersza, nie tylko na pierwszej.
	 */
	public function test_ochrona_obejmuje_kazda_komorke_wiersza(): void {
		$wiersz = Csv::row( array( 'SRV/2026/0001', '=1+1', 'nowe', '@SUM(A1)' ) );

		self::assertStringContainsString( "'=1+1", $wiersz );
		self::assertStringContainsString( "'@SUM(A1)", $wiersz );
		self::assertStringNotContainsString( ';=1+1', $wiersz, 'Formuła weszła do pliku bez ochrony.' );
	}

	/**
	 * Wiersz ma konwencje calego produktu: srednik jako separator, cudzyslow
	 * podwajany w srodku wartosci, znak konca linii na koncu.
	 */
	public function test_wiersz_trzyma_jedna_konwencje_zapisu(): void {
		self::assertSame( ';', Csv::SEP );
		self::assertSame( "a;b\n", Csv::row( array( 'a', 'b' ) ) );
		self::assertSame( "\"ma;średnik\";b\n", Csv::row( array( 'ma;średnik', 'b' ) ) );
		self::assertSame( "\"ma \"\"cudzysłów\"\"\";b\n", Csv::row( array( 'ma "cudzysłów"', 'b' ) ) );
	}

	/**
	 * Zestawienie na koncu eksportu liczy to, co obiecuje: laczna liczba spraw,
	 * rozklad po statusach, rozklad powodow odrzucenia, czas obslugi.
	 */
	public function test_zestawienie_liczy_sprawy_statusy_i_czas(): void {
		$podsumowanie = self::zestawienie(
			array(
				array( 'status' => 'zamknięte', 'closed_at' => '2026-03-01 12:00:00', 'handling_seconds' => 7200, 'kod' => '' ),
				array( 'status' => 'zamknięte', 'closed_at' => '2026-03-01 12:00:00', 'handling_seconds' => 7200, 'kod' => '' ),
				array( 'status' => 'nowe', 'closed_at' => null, 'handling_seconds' => null, 'kod' => '' ),
				array( 'status' => 'odrzucone', 'closed_at' => '2026-03-02 09:00:00', 'handling_seconds' => 3600, 'kod' => 'brak_dowodu' ),
				array( 'status' => 'odrzucone', 'closed_at' => '2026-03-02 09:00:00', 'handling_seconds' => 3600, 'kod' => 'brak_dowodu' ),
			)
		);

		self::assertSame( 5, $podsumowanie['total'] );
		self::assertSame( 2, $podsumowanie['by_status']['zamknięte'] );
		self::assertSame( 1, $podsumowanie['by_status']['nowe'] );
		self::assertSame( 2, $podsumowanie['by_status']['odrzucone'] );
		self::assertSame( 2, $podsumowanie['by_reason']['brak_dowodu'] );
		self::assertSame( 4, $podsumowanie['closed_count'] );
		self::assertSame( '1.50', $podsumowanie['avg_hours'] );
		self::assertSame( '6.00', $podsumowanie['total_hours'] );
	}

	/**
	 * Eksport bez ani jednej sprawy nie dzieli przez zero i nie klamie zerem
	 * w miejscu sredniej.
	 */
	public function test_zestawienie_pustego_eksportu_nie_dzieli_przez_zero(): void {
		$podsumowanie = self::zestawienie( array() );

		self::assertSame( 0, $podsumowanie['total'] );
		self::assertSame( 0, $podsumowanie['closed_count'] );
		self::assertSame( '', $podsumowanie['avg_hours'], 'Brak spraw to brak średniej, nie „0 godzin".' );
		self::assertSame( array(), $podsumowanie['by_status'] );
	}

	/**
	 * Czas obslugi w godzinach: puste dla braku, dwa miejsca po przecinku.
	 */
	public function test_czas_obslugi_w_godzinach(): void {
		$hours = new ReflectionMethod( CsvExport::class, 'hours' );
		$hours->setAccessible( true );

		self::assertSame( '', $hours->invoke( null, null ) );
		self::assertSame( '2.00', $hours->invoke( null, 7200 ) );
		self::assertSame( '0.50', $hours->invoke( null, 1800 ) );
	}

	/**
	 * Sklada zestawienie z listy spraw (ta sama droga, co strumien eksportu:
	 * akumulator sprawa po sprawie + domkniecie).
	 *
	 * @param array<int, array<string, mixed>> $sprawy Sprawy.
	 * @return array<string, mixed>
	 */
	private static function zestawienie( array $sprawy ): array {
		$accumulate = new ReflectionMethod( CsvExport::class, 'accumulate' );
		$finish     = new ReflectionMethod( CsvExport::class, 'summary_finish' );
		$accumulate->setAccessible( true );
		$finish->setAccessible( true );

		$acc = array(
			'total'     => 0,
			'by_status' => array(),
			'by_reason' => array(),
			'closed'    => 0,
			'timed'     => 0,
			'sum_sec'   => 0,
		);

		foreach ( $sprawy as $sprawa ) {
			$kod = (string) ( $sprawa['kod'] ?? '' );
			unset( $sprawa['kod'] );
			$accumulate->invokeArgs( null, array( &$acc, $sprawa, $kod ) );
		}

		return (array) $finish->invoke( null, $acc );
	}
}
