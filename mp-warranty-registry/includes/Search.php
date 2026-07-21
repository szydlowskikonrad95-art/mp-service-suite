<?php
/**
 * Wyszukiwarka rejestru produktow (karta B: serial / klient / faktura / model).
 *
 * Zasady kontraktu:
 * - kazdy LIKE przez $wpdb->esc_like (serial z '_'/'%' NIE daje falszywych trafien),
 * - "po kliencie" mechanika ODWROCONA (P2.6): B pyta filtrem
 *   mp_customer_find_products, C oddaje {ids, truncated, limit}; B robi zwykle
 *   IN(...) z paginacja/COUNT u siebie; truncated => komunikat "doprecyzuj",
 * - degraded bez C: pole "klient" nieaktywne (customer_mode = unavailable),
 * - archiwalne domyslnie UKRYTE (jawny filtr je pokazuje).
 *
 * @package MP\Registry
 */

namespace MP\Registry;

use MP\Registry\Common\Str;

/**
 * Zapytania wyszukiwarki (odczyt, paginacja, COUNT).
 */
final class Search {

	/**
	 * Domyslny rozmiar strony listy produktow.
	 */
	public const PER_PAGE = 20;

	/**
	 * Wykonuje wyszukiwanie.
	 *
	 * @param array<string, mixed> $filters  Filtry: serial, model, invoice, customer, include_archived.
	 * @param int                  $page     Strona (od 1).
	 * @param int                  $per_page Rozmiar strony.
	 * @return array{rows: array<int, array<string, mixed>>, total: int, customer_mode: string}
	 *         customer_mode: off | ok | truncated | unavailable | empty.
	 */
	public static function query( array $filters, int $page = 1, int $per_page = self::PER_PAGE ): array {
		global $wpdb;

		$table = Tables::full( Tables::REGISTRY );
		$where = array();
		$args  = array();

		$customer_mode = 'off';
		$customer      = trim( (string) ( $filters['customer'] ?? '' ) );

		if ( '' !== $customer ) {
			if ( ! has_filter( 'mp_customer_find_products' ) ) {
				$customer_mode = 'unavailable';
			} else {
				$found = apply_filters( 'mp_customer_find_products', null, $customer );
				$ids   = is_array( $found ) && isset( $found['ids'] ) && is_array( $found['ids'] )
					? array_values( array_filter( array_map( 'absint', $found['ids'] ) ) )
					: array();

				if ( array() === $ids ) {
					return array(
						'rows'          => array(),
						'total'         => 0,
						'customer_mode' => 'empty',
					);
				}

				$customer_mode = ! empty( $found['truncated'] ) ? 'truncated' : 'ok';
				$where[]       = 'id IN (' . implode( ',', array_fill( 0, count( $ids ), '%d' ) ) . ')';
				$args          = array_merge( $args, $ids );
			}
		}

		$serial = trim( (string) ( $filters['serial'] ?? '' ) );

		if ( '' !== $serial ) {
			$where[] = 'serial_normalized LIKE %s';
			$args[]  = '%' . $wpdb->esc_like( Str::normalize_serial( $serial ) ) . '%';
		}

		$model = trim( (string) ( $filters['model'] ?? '' ) );

		if ( '' !== $model ) {
			$where[] = 'model LIKE %s';
			$args[]  = '%' . $wpdb->esc_like( $model ) . '%';
		}

		$invoice = trim( (string) ( $filters['invoice'] ?? '' ) );

		if ( '' !== $invoice ) {
			$where[] = 'purchase_document LIKE %s';
			$args[]  = '%' . $wpdb->esc_like( $invoice ) . '%';
		}

		if ( empty( $filters['include_archived'] ) ) {
			$where[] = 'archived = 0';
		}

		$where_sql = array() === $where ? '1=1' : implode( ' AND ', $where );
		$offset    = max( 0, ( max( 1, $page ) - 1 ) * $per_page );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared, WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare, WordPress.DB.PreparedSQLPlaceholders.ReplacementsWrongNumber -- tabela wlasna; WHERE budowane wylacznie ze stalych fraz wyzej, wartosci ZAWSZE placeholderami (liczba args = liczba placeholderow, sniff nie widzi dynamicznego WHERE).
		if ( array() === $args ) {
			$total = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$table} WHERE {$where_sql}" );
			$rows  = $wpdb->get_results(
				$wpdb->prepare( "SELECT * FROM {$table} WHERE {$where_sql} ORDER BY id DESC LIMIT %d OFFSET %d", $per_page, $offset ),
				ARRAY_A
			);
		} else {
			$total = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$table} WHERE {$where_sql}", $args ) );
			$rows  = $wpdb->get_results(
				$wpdb->prepare(
					"SELECT * FROM {$table} WHERE {$where_sql} ORDER BY id DESC LIMIT %d OFFSET %d",
					array_merge( $args, array( $per_page, $offset ) )
				),
				ARRAY_A
			);
		}
		// phpcs:enable

		return array(
			'rows'          => is_array( $rows ) ? $rows : array(),
			'total'         => $total,
			'customer_mode' => $customer_mode,
		);
	}
}
