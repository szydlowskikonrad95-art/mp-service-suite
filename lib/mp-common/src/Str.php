<?php
/**
 * Operacje na tekstach wspolne dla 3 pluginow.
 *
 * @package MP\Common
 */

namespace MP\Common;

/**
 * Normalizacje tekstow zgodne z kontraktem (DATABASE.md).
 */
final class Str {

	/**
	 * Normalizuje numer seryjny do postaci kanonicznej.
	 *
	 * Kontrakt kolumny serial_normalized: wielkie litery, bez spacji i myslnikow
	 * ("ABC-123" i "abc 123" to TEN SAM serial).
	 *
	 * @param string $serial Surowy numer seryjny od uzytkownika/importu.
	 * @return string Postac kanoniczna.
	 */
	public static function normalize_serial( string $serial ): string {
		$stripped = (string) preg_replace( '/[\s\-]+/u', '', $serial );

		if ( function_exists( 'mb_strtoupper' ) ) {
			return mb_strtoupper( $stripped );
		}

		return strtoupper( $stripped );
	}

	/**
	 * Wybiera polska forme gramatyczna wg liczby (audyt 27.07).
	 *
	 * Polski ma TRZY formy mnogie (1 sprawa / 2-4 sprawy / 5+ spraw), a jezykiem
	 * ZRODLOWYM tego produktu jest polski — nie dowozimy plikow .mo, wiec wbudowany
	 * fallback `_n()` (n==1 ? forma1 : forma2) pokazywalby klientowi „ma 2 aktywnych
	 * spraw". Dlatego forme wybieramy jawnie, wg regul jezyka.
	 *
	 * @param int    $n        Liczba.
	 * @param string $forma_1  Dla 1 (np. „1 aktywną sprawę").
	 * @param string $forma_24 Dla 2-4 (np. „%d aktywne sprawy").
	 * @param string $forma_5  Dla 0 i 5+ (np. „%d aktywnych spraw").
	 * @return string Wybrana forma.
	 */
	public static function odmiana( int $n, string $forma_1, string $forma_24, string $forma_5 ): string {
		$n = abs( $n );

		if ( 1 === $n ) {
			return $forma_1;
		}

		$dziesiatki = $n % 100;
		$jednosci   = $n % 10;

		if ( $jednosci >= 2 && $jednosci <= 4 && ( $dziesiatki < 12 || $dziesiatki > 14 ) ) {
			return $forma_24;
		}

		return $forma_5;
	}

	/**
	 * Dlugosc tekstu w ZNAKACH, odporna na brak rozszerzenia mbstring (audyt 27.07).
	 *
	 * Walidator formularza lezy na sciezce KAZDEGO zgloszenia. Goly `mb_strlen()`
	 * na hostingu bez mbstring to nie degradacja funkcji, tylko blad krytyczny PHP —
	 * formularz publiczny przestaje dzialac w calosci. Reszta projektu owija te
	 * funkcje konsekwentnie; walidator byl jedynym wyjatkiem.
	 * Fallback liczy znaki UTF-8 (strlen liczylby BAJTY, wiec polskie znaki
	 * zjadalyby limit dwa razy szybciej).
	 *
	 * @param string $text Tekst.
	 * @return int Liczba znakow.
	 */
	public static function len( string $text ): int {
		if ( function_exists( 'mb_strlen' ) ) {
			return (int) mb_strlen( $text );
		}

		$znaki = preg_split( '//u', $text, -1, PREG_SPLIT_NO_EMPTY );

		return is_array( $znaki ) ? count( $znaki ) : strlen( $text );
	}
}
