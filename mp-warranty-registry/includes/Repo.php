<?php
/**
 * Odczyty rejestru (tabele wlasne B — wylacznie tu, przez Tables::full()).
 *
 * @package MP\Registry
 */

namespace MP\Registry;

use MP\Registry\Common\Str;

/**
 * Repozytorium odczytow Registry.
 */
final class Repo {

	/**
	 * Znajduje produkt po numerze seryjnym (postac dowolna — normalizacja tu).
	 *
	 * @param string $serial Surowy numer seryjny.
	 * @return array<string, mixed>|null Wiersz rejestru lub null.
	 */
	public static function find_by_serial( string $serial ): ?array {
		global $wpdb;

		$normalized = Str::normalize_serial( $serial );

		if ( '' === $normalized ) {
			return null;
		}

		$table = Tables::full( Tables::REGISTRY );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna przez Tables::full(), zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT * FROM {$table} WHERE serial_normalized = %s", $normalized ),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $row ) ? $row : null;
	}

	/**
	 * Aktywny wyjatek gwarancyjny dla produktu (PRECEDENS z kontraktu).
	 *
	 * Odczyt deterministyczny: per-sprawa > globalny (case-first), potem
	 * valid_until DESC, id DESC, LIMIT 1. Aktywnosc Z DATY:
	 * status='active' AND (valid_until IS NULL OR valid_until >= NOW).
	 * Wyjatek z case_id honorowany TYLKO gdy $case_id sie zgadza;
	 * case_id NULL = globalny na produkt.
	 *
	 * @param int      $product_registry_id ID produktu.
	 * @param int|null $case_id             Sprawa pytajaca (lub null).
	 * @return array<string, mixed>|null Wiersz wyjatku lub null.
	 */
	public static function get_active_exception( int $product_registry_id, ?int $case_id ): ?array {
		global $wpdb;

		$table = Tables::full( Tables::EXCEPTIONS );
		$now   = gmdate( 'Y-m-d H:i:s' );

		if ( null === $case_id ) {
			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
			$row = $wpdb->get_row(
				$wpdb->prepare(
					"SELECT * FROM {$table}
					WHERE product_registry_id = %d AND status = 'active' AND case_id IS NULL
					AND ( valid_until IS NULL OR valid_until >= %s )
					ORDER BY valid_until DESC, id DESC LIMIT 1",
					$product_registry_id,
					$now
				),
				ARRAY_A
			);
			// phpcs:enable
		} else {
			// Case-first: wyjatek tej sprawy wygrywa z globalnym.
			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
			$row = $wpdb->get_row(
				$wpdb->prepare(
					"SELECT * FROM {$table}
					WHERE product_registry_id = %d AND status = 'active'
					AND ( case_id = %d OR case_id IS NULL )
					AND ( valid_until IS NULL OR valid_until >= %s )
					ORDER BY ( case_id IS NOT NULL ) DESC, valid_until DESC, id DESC LIMIT 1",
					$product_registry_id,
					$case_id,
					$now
				),
				ARRAY_A
			);
			// phpcs:enable
		}

		return is_array( $row ) ? $row : null;
	}
}
