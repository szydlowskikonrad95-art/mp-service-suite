<?php
/**
 * Numer sprawy SRV/RRRR/NNNN — licznik ATOMOWY per rok (spec P1.3, sekcja 4).
 *
 * Jedna kwerenda robi init roku I podbicie (bez add_option, bez read-modify-write):
 *   INSERT ... VALUES (year, 1) ON DUPLICATE KEY UPDATE value = LAST_INSERT_ID(value + 1)
 * -> LAST_INSERT_ID() zwraca NOWA wartosc licznika w tej samej sesji. Format:
 * SRV/RRRR/NNNN, NNNN = min. 4 cyfry z zerami do 9999, potem naturalnie 5+.
 * Unikalnosc twarda przez UNIQUE (case_number) w tabeli spraw (pas + retry).
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Generator kolejnych numerow spraw.
 */
final class SrvCounter {

	/**
	 * Zwraca nastepny numer sprawy dla danego roku (atomowo).
	 *
	 * @param int $year Rok kalendarzowy (UTC — spojnie z created_at).
	 * @return string Numer w formacie SRV/RRRR/NNNN.
	 */
	public static function next( int $year ): string {
		global $wpdb;

		$table = Tables::full( Tables::SRV_COUNTERS );

		// LAST_INSERT_ID(1) w VALUES ustawia sesyjny LAST_INSERT_ID takze na
		// PIERWSZYM wierszu roku (galaz ON DUPLICATE odpala dopiero od drugiego);
		// bez tego pierwszy numer roku bylby 0 zamiast 1.
		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; jedna kwerenda = atomowy init+podbicie licznika (kontrakt P1.3).
		$wpdb->query(
			$wpdb->prepare(
				"INSERT INTO {$table} (year, value) VALUES (%d, LAST_INSERT_ID(1))
				ON DUPLICATE KEY UPDATE value = LAST_INSERT_ID(value + 1)",
				$year
			)
		);

		$value = (int) $wpdb->get_var( 'SELECT LAST_INSERT_ID()' );
		// phpcs:enable

		return self::format( $year, $value );
	}

	/**
	 * Sklada numer sprawy (czysta funkcja — testowana jednostkowo).
	 *
	 * @param int $year  Rok.
	 * @param int $value Kolejna wartosc licznika (>=1).
	 * @return string SRV/RRRR/NNNN.
	 */
	public static function format( int $year, int $value ): string {
		return sprintf( 'SRV/%04d/%04d', $year, $value );
	}
}
