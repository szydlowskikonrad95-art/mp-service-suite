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
		\WP_CLI::add_command( 'mp exception-add', array( self::class, 'exception_add' ) );
		\WP_CLI::add_command( 'mp exception-revoke', array( self::class, 'exception_revoke' ) );
	}

	/**
	 * Przyznaje wyjatek gwarancyjny (wymaga --user z capability mp_system_admin).
	 *
	 * ## OPTIONS
	 *
	 * <serial>
	 * : Numer seryjny produktu (dowolna postac — normalizacja po stronie B).
	 *
	 * --reason=<tekst>
	 * : Powod wyjatku (wymagany, do 500 znakow).
	 *
	 * [--case=<id>]
	 * : ID sprawy (bez tego wyjatek jest GLOBALNY na produkt).
	 *
	 * [--until=<data>]
	 * : Waznosc: RRRR-MM-DD lub "RRRR-MM-DD GG:MM:SS" (UTC). Bez tego bezterminowo.
	 *
	 * @param string[]              $args       Argumenty pozycyjne: [0] serial.
	 * @param array<string, string> $assoc_args Flagi.
	 * @return void
	 */
	public static function exception_add( array $args, array $assoc_args ): void {
		$row = Repo::find_by_serial( (string) ( $args[0] ?? '' ) );

		if ( null === $row ) {
			\WP_CLI::error( 'Nie ma produktu o takim numerze seryjnym.' );
		}

		$case_id = isset( $assoc_args['case'] ) ? (int) $assoc_args['case'] : null;
		$result  = WarrantyExceptions::create(
			(int) $row['id'],
			$case_id,
			(string) ( $assoc_args['reason'] ?? '' ),
			isset( $assoc_args['until'] ) ? (string) $assoc_args['until'] : null
		);

		if ( isset( $result['error'] ) ) {
			\WP_CLI::error( (string) $result['error'] );
		}

		\WP_CLI::success( sprintf( 'Wyjatek #%d przyznany (%s).', $result['id'], null === $case_id ? 'globalny' : 'sprawa #' . $case_id ) );
	}

	/**
	 * Cofa wyjatek gwarancyjny (wymaga --user z capability mp_system_admin).
	 *
	 * ## OPTIONS
	 *
	 * <id>
	 * : ID wyjatku.
	 *
	 * @param string[] $args Argumenty pozycyjne: [0] ID wyjatku.
	 * @return void
	 */
	public static function exception_revoke( array $args ): void {
		$result = WarrantyExceptions::revoke( (int) ( $args[0] ?? 0 ) );

		if ( is_array( $result ) ) {
			\WP_CLI::error( (string) $result['error'] );
		}

		\WP_CLI::success( 'Wyjatek cofniety.' );
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
