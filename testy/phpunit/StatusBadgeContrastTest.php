<?php
/**
 * Kontrast plakietek statusu — bramka dostepnosci, nie kosmetyka.
 *
 * Klient koncowy to instytucja publiczna, wiec lista spraw musi spelniac
 * WCAG 2.1 AA. Plakietka to bialy tekst `font-size:.82em` na kolorowym tle =
 * MALY tekst => prog 4.5:1 (luzniejszy prog 3:1 dotyczy tylko duzego tekstu,
 * czyli >=18.66px bold albo >=24px — plakietka jest mniejsza).
 *
 * Test istnieje, bo trzy odcienie (`#d97706`, `#0891b2`, `#ea580c`) wygladaly
 * dobrze, a mialy 3.2-3.7:1. Oko tego nie zmierzy — liczby tak.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\Statuses;
use PHPUnit\Framework\TestCase;

/**
 * Kontrast bieli na tle kazdej plakietki statusu.
 */
final class StatusBadgeContrastTest extends TestCase {

	/**
	 * Prog WCAG 2.1 AA dla malego tekstu.
	 */
	private const PROG_AA = 4.5;

	/**
	 * Luminancja wzgledna kanalu wg WCAG (sRGB => linear).
	 *
	 * @param float $kanal Wartosc kanalu 0..1.
	 * @return float
	 */
	private function kanal( float $kanal ): float {
		return $kanal <= 0.03928 ? $kanal / 12.92 : ( ( $kanal + 0.055 ) / 1.055 ) ** 2.4;
	}

	/**
	 * Luminancja wzgledna koloru HEX (#rrggbb).
	 *
	 * @param string $hex Kolor.
	 * @return float
	 */
	private function luminancja( string $hex ): float {
		$hex = ltrim( $hex, '#' );

		$r = $this->kanal( (int) hexdec( substr( $hex, 0, 2 ) ) / 255 );
		$g = $this->kanal( (int) hexdec( substr( $hex, 2, 2 ) ) / 255 );
		$b = $this->kanal( (int) hexdec( substr( $hex, 4, 2 ) ) / 255 );

		return 0.2126 * $r + 0.7152 * $g + 0.0722 * $b;
	}

	/**
	 * Kontrast dwoch kolorow wg WCAG (zawsze >= 1).
	 *
	 * @param string $a Kolor 1.
	 * @param string $b Kolor 2.
	 * @return float
	 */
	private function kontrast( string $a, string $b ): float {
		$la = $this->luminancja( $a );
		$lb = $this->luminancja( $b );

		return ( max( $la, $lb ) + 0.05 ) / ( min( $la, $lb ) + 0.05 );
	}

	/**
	 * Sanity: licznik kontrastu zgadza sie ze znanymi wartosciami skrajnymi.
	 */
	public function test_licznik_kontrastu_jest_poprawny(): void {
		self::assertEqualsWithDelta( 21.0, $this->kontrast( '#ffffff', '#000000' ), 0.01, 'biel na czerni = 21:1' );
		self::assertEqualsWithDelta( 1.0, $this->kontrast( '#123456', '#123456' ), 0.01, 'ten sam kolor = 1:1' );
	}

	/**
	 * KAZDA plakietka rdzenia: bialy tekst musi miec >= 4.5:1.
	 */
	public function test_kazda_plakietka_spelnia_wcag_aa(): void {
		foreach ( Statuses::BADGE_COLORS as $slug => $tlo ) {
			$k = $this->kontrast( '#ffffff', $tlo );

			self::assertGreaterThanOrEqual(
				self::PROG_AA,
				$k,
				sprintf( 'status „%s" (%s): kontrast %.2f:1 ponizej progu AA %.1f:1', $slug, $tlo, $k, self::PROG_AA )
			);
		}
	}

	/**
	 * Kolor zapasowy (status wlasny z filtra D) tez musi byc czytelny.
	 */
	public function test_kolor_zapasowy_spelnia_wcag_aa(): void {
		self::assertGreaterThanOrEqual(
			self::PROG_AA,
			$this->kontrast( '#ffffff', Statuses::BADGE_COLOR_FALLBACK ),
			'neutralne tlo statusu wlasnego ponizej progu AA'
		);
	}

	/**
	 * Kazdy status rdzenia MA swoj kolor (zeby nowy status nie wpadl po cichu
	 * na szary fallback i nie zlal sie ze „zamknietym").
	 */
	public function test_kazdy_status_rdzenia_ma_wlasny_kolor(): void {
		foreach ( array_keys( Statuses::all() ) as $slug ) {
			self::assertArrayHasKey(
				$slug,
				Statuses::BADGE_COLORS,
				sprintf( 'status „%s" nie ma koloru plakietki', $slug )
			);
		}
	}

	/**
	 * Kolory rdzenia sa ROZNE — inaczej dwa statusy wygladaja identycznie.
	 */
	public function test_kolory_sie_nie_powtarzaja(): void {
		$kolory = array_values( Statuses::BADGE_COLORS );

		self::assertSame( count( $kolory ), count( array_unique( $kolory ) ), 'dwa statusy maja ten sam kolor' );
	}

	/**
	 * `badge_color()` zwraca kolor rdzenia, a dla obcego slug — fallback.
	 */
	public function test_badge_color_zwraca_fallback_dla_statusu_wlasnego(): void {
		self::assertSame( Statuses::BADGE_COLORS['nowe'], Statuses::badge_color( 'nowe' ) );
		self::assertSame( Statuses::BADGE_COLOR_FALLBACK, Statuses::badge_color( 'wyslane do producenta' ) );
		self::assertSame( Statuses::BADGE_COLOR_FALLBACK, Statuses::badge_color( '' ) );
	}
}
