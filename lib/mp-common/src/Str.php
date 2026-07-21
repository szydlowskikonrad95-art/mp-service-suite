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
}
