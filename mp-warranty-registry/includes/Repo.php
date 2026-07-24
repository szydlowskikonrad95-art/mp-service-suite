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

	/**
	 * Kategoria produktu po ID — dla haka kontraktowego `mp_product_category`
	 * (Intake `get_context.kategoria` => os przydzialu w Automatorze).
	 *
	 * Read-only. Brak produktu / brak kategorii => zwraca przekazany $default_value
	 * (kontrakt „brak danej = default, nie blad").
	 *
	 * @param mixed $default_value             Wartosc domyslna (zwykle null).
	 * @param int   $product_registry_id ID produktu.
	 * @return mixed Slug kategorii (string) albo $default_value.
	 */
	public static function category_for( $default_value, int $product_registry_id ) {
		global $wpdb;

		if ( $product_registry_id <= 0 ) {
			return $default_value;
		}

		$table = Tables::full( Tables::REGISTRY );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna przez Tables::full(), zapytanie przygotowane.
		$category = $wpdb->get_var(
			$wpdb->prepare( "SELECT category FROM {$table} WHERE id = %d", $product_registry_id )
		);
		// phpcs:enable

		return ( is_string( $category ) && '' !== $category ) ? $category : $default_value;
	}

	/**
	 * Detale produktu po ID — kontrakt B->C `mp_product_details` (karta sprawy w C).
	 * NIE weryfikuje dokumentu zakupu: status liczony z samej daty gwarancji
	 * (WarrantyStatus::compute z doc/date = null). $default_value gdy brak produktu.
	 *
	 * @param mixed $default_value       Wartosc domyslna (zwykle null).
	 * @param int   $product_registry_id ID produktu w rejestrze.
	 * @return array{id: int, serial: string, model: string, batch: string, purchase_document: string, purchase_date: string, warranty_until: string, warranty_status: string, archived: bool}|mixed
	 */
	public static function details_for( $default_value, int $product_registry_id ) {
		global $wpdb;

		if ( $product_registry_id <= 0 ) {
			return $default_value;
		}

		$table = Tables::full( Tables::REGISTRY );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna przez Tables::full(), zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT id, serial_display, model, batch, purchase_document, purchase_date, warranty_until, archived
				FROM {$table} WHERE id = %d",
				$product_registry_id
			),
			ARRAY_A
		);
		// phpcs:enable

		if ( ! is_array( $row ) ) {
			return $default_value;
		}

		$warranty_until = null !== $row['warranty_until'] ? (string) $row['warranty_until'] : '';

		return array(
			'id'                => (int) $row['id'],
			'serial'            => (string) $row['serial_display'],
			'model'             => (string) $row['model'],
			'batch'             => (string) $row['batch'],
			'purchase_document' => (string) $row['purchase_document'],
			'purchase_date'     => null !== $row['purchase_date'] ? (string) $row['purchase_date'] : '',
			'warranty_until'    => $warranty_until,
			'warranty_status'   => WarrantyStatus::compute( true, '' !== $warranty_until ? $warranty_until : null, null, null ),
			'archived'          => ! empty( $row['archived'] ),
		);
	}
}
