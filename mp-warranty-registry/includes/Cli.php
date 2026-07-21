<?php
/**
 * Komendy WP-CLI Registry (napedzaja tez testy integracyjne).
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * `wp mp import-products <plik.csv>` — import przez TEN SAM silnik batchy
 * co UI (job + porcje po 100; kazdy batch = osobne wywolanie procesora).
 */
final class Cli {

	/**
	 * Rejestruje komendy (wolane tylko pod WP-CLI).
	 *
	 * @return void
	 */
	public static function register(): void {
		\WP_CLI::add_command( 'mp import-products', array( self::class, 'import_products' ) );
	}

	/**
	 * Importuje produkty z pliku CSV.
	 *
	 * @param string[] $args Argumenty pozycyjne: [0] sciezka pliku.
	 * @return void
	 */
	public static function import_products( array $args ): void {
		$source = (string) ( $args[0] ?? '' );
		$job    = Importer::create_job_from_file( $source );

		if ( isset( $job['error'] ) ) {
			\WP_CLI::error( (string) $job['error'] );
		}

		\WP_CLI::log( sprintf( 'Job #%d: %d wierszy danych.', $job['job_id'], $job['total'] ) );

		do {
			$result = Importer::process_batch( (int) $job['job_id'], (string) $job['token'] );

			if ( 'error' === $result['status'] ) {
				\WP_CLI::error( (string) $result['message'] );
			}

			\WP_CLI::log( sprintf( 'Postep: %d/%d (bledy: %d)', $result['processed'], $result['total'], $result['errors'] ) );
		} while ( 'processing' === $result['status'] );

		\WP_CLI::success( sprintf( 'Import zakonczony: %d/%d, bledy: %d.', $result['processed'], $result['total'], $result['errors'] ) );
	}
}
