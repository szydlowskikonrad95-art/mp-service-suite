<?php
/**
 * Archiwum produktu (soft delete: archived + deleted_at/by; DATABASE.md).
 *
 * FAIL-CLOSED (kontrakt mp_product_active_cases_count): bez dzialajacego
 * modulu spraw (C) NIE DA SIE potwierdzic braku aktywnych spraw, wiec
 * archiwizacja jest ODMAWIANA — nigdy "na slowo".
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * Archiwizacja i przywracanie produktow.
 */
final class Archive {

	/**
	 * Archiwizuje produkt (soft delete).
	 *
	 * @param int $product_registry_id ID produktu.
	 * @return true|array{error: string}
	 */
	public static function archive( int $product_registry_id ) {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			return array( 'error' => __( 'Archiwizować produkty może wyłącznie administrator systemu MP.', 'mp-warranty-registry' ) );
		}

		$row = self::get_product( $product_registry_id );

		if ( null === $row ) {
			return array( 'error' => __( 'Produkt o tym ID nie istnieje.', 'mp-warranty-registry' ) );
		}

		if ( '1' === (string) $row['archived'] ) {
			return array( 'error' => __( 'Ten produkt jest już w archiwum.', 'mp-warranty-registry' ) );
		}

		if ( ! has_filter( 'mp_product_active_cases_count' ) ) {
			return array( 'error' => __( 'Nie można potwierdzić braku aktywnych spraw (moduł spraw nieaktywny) — archiwizacja odmówiona.', 'mp-warranty-registry' ) );
		}

		$count = apply_filters( 'mp_product_active_cases_count', null, $product_registry_id );

		if ( ! is_numeric( $count ) ) {
			return array( 'error' => __( 'Moduł spraw nie odpowiedział jednoznacznie — archiwizacja odmówiona (FAIL-CLOSED).', 'mp-warranty-registry' ) );
		}

		if ( (int) $count > 0 ) {
			return array(
				'error' => sprintf(
					/* translators: %d: liczba aktywnych spraw. */
					__( 'Produkt ma %d aktywnych spraw — najpierw je zamknij.', 'mp-warranty-registry' ),
					(int) $count
				),
			);
		}

		self::set_archived( $product_registry_id, true );

		return true;
	}

	/**
	 * Przywraca produkt z archiwum (komunikat importu: "przywroc jawnie").
	 *
	 * @param int $product_registry_id ID produktu.
	 * @return true|array{error: string}
	 */
	public static function restore( int $product_registry_id ) {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			return array( 'error' => __( 'Przywracać produkty może wyłącznie administrator systemu MP.', 'mp-warranty-registry' ) );
		}

		$row = self::get_product( $product_registry_id );

		if ( null === $row ) {
			return array( 'error' => __( 'Produkt o tym ID nie istnieje.', 'mp-warranty-registry' ) );
		}

		if ( '1' !== (string) $row['archived'] ) {
			return array( 'error' => __( 'Ten produkt nie jest w archiwum.', 'mp-warranty-registry' ) );
		}

		self::set_archived( $product_registry_id, false );

		return true;
	}

	/**
	 * Zapis flagi archiwum + wpis historii (diff before/after).
	 *
	 * @param int  $product_registry_id ID produktu.
	 * @param bool $archived            Docelowy stan.
	 * @return void
	 */
	private static function set_archived( int $product_registry_id, bool $archived ): void {
		global $wpdb;

		$table    = Tables::full( Tables::REGISTRY );
		$actor_id = get_current_user_id();
		$now      = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytania przygotowane.
		if ( $archived ) {
			$wpdb->query(
				$wpdb->prepare(
					"UPDATE {$table} SET archived = 1, deleted_at = %s, deleted_by = %d, updated_at = %s WHERE id = %d",
					$now,
					$actor_id,
					$now,
					$product_registry_id
				)
			);
		} else {
			$wpdb->query(
				$wpdb->prepare(
					"UPDATE {$table} SET archived = 0, deleted_at = NULL, deleted_by = NULL, updated_at = %s WHERE id = %d",
					$now,
					$product_registry_id
				)
			);
		}
		// phpcs:enable

		ProductEvents::log(
			$product_registry_id,
			'PRODUCT_UPDATED',
			array(
				'archived' => array(
					'before' => $archived ? 0 : 1,
					'after'  => $archived ? 1 : 0,
				),
			),
			$actor_id
		);
	}

	/**
	 * Odczyt produktu po ID.
	 *
	 * @param int $product_registry_id ID produktu.
	 * @return array<string, mixed>|null
	 */
	private static function get_product( int $product_registry_id ): ?array {
		global $wpdb;

		$table = Tables::full( Tables::REGISTRY );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT id, archived FROM {$table} WHERE id = %d", $product_registry_id ),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $row ) ? $row : null;
	}
}
