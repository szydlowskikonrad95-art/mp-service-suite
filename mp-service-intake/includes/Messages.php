<?php
/**
 * Wiadomosci sprawy — wp_mp_messages (P1.5: historia wiadomosci klient<->serwis).
 *
 * Komunikacja NIE JEST audit-logiem: wiadomosci sa REDAGOWALNE przy RODO
 * (kwazi-identyfikatory), a events zostaja nietkniete. Event `mp_case_message_added`
 * niesie TYLKO wskazniki (case_id, message_id, author_type) — bez tresci.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Repozytorium wiadomosci spraw.
 */
final class Messages {

	/**
	 * Marker wartosci po redakcji RODO.
	 */
	public const REDACTED = '[ZREDAGOWANO-RODO]';

	/**
	 * Dodaje wiadomosc do sprawy i emituje mp_case_message_added (bez tresci).
	 *
	 * @param int      $case_id     ID sprawy.
	 * @param string   $author_type client|staff|system.
	 * @param int|null $author_id   ID autora (WP user; null dla system).
	 * @param string   $body        Tresc wiadomosci.
	 * @return int ID wiadomosci.
	 */
	public static function add( int $case_id, string $author_type, ?int $author_id, string $body ): int {
		global $wpdb;

		$now = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna.
		$wpdb->insert(
			Tables::full( Tables::MESSAGES ),
			array(
				'case_id'     => $case_id,
				'author_type' => in_array( $author_type, array( 'client', 'staff', 'system' ), true ) ? $author_type : 'system',
				'author_id'   => $author_id,
				'body'        => $body,
				'created_at'  => $now,
			)
		);
		// phpcs:enable

		$message_id = (int) $wpdb->insert_id;

		/**
		 * Sygnal dla D: dopisano wiadomosc (BEZ tresci — tylko wskazniki).
		 *
		 * @param int    $case_id     ID sprawy.
		 * @param int    $message_id  ID wiadomosci.
		 * @param string $author_type Typ autora.
		 */
		do_action( 'mp_case_message_added', $case_id, $message_id, $author_type );

		return $message_id;
	}

	/**
	 * Listener kontraktowy: wiadomosc systemowa od D (np. raport koncowy).
	 *
	 * @param int    $case_id ID sprawy.
	 * @param string $content Tresc wiadomosci systemowej.
	 * @return int ID wiadomosci.
	 */
	public static function add_system_message( int $case_id, string $content ): int {
		return self::add( $case_id, 'system', null, $content );
	}

	/**
	 * Wiadomosci sprawy (chronologicznie) — panel klienta / eksport.
	 *
	 * @param int $case_id ID sprawy.
	 * @return array<int, array<string, mixed>>
	 */
	public static function for_case( int $case_id ): array {
		global $wpdb;

		$table = Tables::full( Tables::MESSAGES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT * FROM {$table} WHERE case_id = %d ORDER BY id ASC",
				$case_id
			),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * Redaguje wiadomosci klienta (RODO) dla podanych spraw.
	 *
	 * @param array<int> $case_ids Sprawy klienta.
	 * @return int Liczba zredagowanych wiadomosci.
	 */
	public static function redact_for_cases( array $case_ids ): int {
		global $wpdb;

		$ids = array_values( array_filter( array_map( 'absint', $case_ids ) ) );

		if ( array() === $ids ) {
			return 0;
		}

		$placeholders = implode( ',', array_fill( 0, count( $ids ), '%d' ) );
		$table        = Tables::full( Tables::MESSAGES );
		$redacted     = self::REDACTED;

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared, WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare, WordPress.DB.PreparedSQLPlaceholders.ReplacementsWrongNumber -- tabela wlasna; lista %d w IN() budowana z count($ids) + 2 markery, sniff nie widzi dynamicznego IN.
		$affected = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET body = %s WHERE case_id IN ({$placeholders}) AND body <> %s",
				array_merge( array( $redacted ), $ids, array( $redacted ) )
			)
		);
		// phpcs:enable

		return (int) $affected;
	}
}
