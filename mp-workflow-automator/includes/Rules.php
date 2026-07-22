<?php
/**
 * Dostep do tabeli regul silnika (wp_mp_workflow_rules) + atomowy kursor round-robin.
 *
 * Kolumny STRUKTURALNE — ZAKAZ eval/wykonywania tekstu z bazy. Typy triggerow,
 * akcji i operatorow = ZAMKNIETE listy w kodzie (stale ponizej).
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Odczyt/zapis regul + round-robin.
 */
final class Rules {

	/**
	 * Triggery (zamknieta lista — mapa na hooki C/B w RuleEngine).
	 */
	public const TRIGGER_CASE_CREATED = 'case_created';

	/**
	 * Akcje (zamknieta lista; P3.1 = tylko przydzial).
	 */
	public const ACTION_ASSIGN = 'assign';

	/**
	 * Operatory warunku (zamknieta lista — r.D1/Kimi).
	 */
	public const OPERATORS = array( 'equals', 'not_equals', 'in_list', 'is_empty', 'is_not_empty' );

	/**
	 * Reguly WLACZONE dla triggera, posortowane: priority ASC, remis -> id ASC.
	 *
	 * Czytane RAZ na zdarzenie (jedna lista w pamieci — edycja w trakcie nie psuje
	 * przebiegu; r.D1). Zwraca wiersze surowe (parsowanie configu w RuleEngine).
	 *
	 * @param string $trigger_type Stala TRIGGER_*.
	 * @return array<int, array<string, mixed>>
	 */
	public static function enabled_for_trigger( string $trigger_type ): array {
		global $wpdb;

		$table = Tables::full( Tables::WORKFLOW_RULES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT id, trigger_type, condition_key, condition_operator, condition_value,
					action_type, action_config_json, priority
				FROM {$table}
				WHERE trigger_type = %s AND enabled = 1
				ORDER BY priority ASC, id ASC",
				$trigger_type
			),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * Atomowo podbija kursor round-robin reguly i zwraca indeks do puli.
	 *
	 * Wzorzec licznika SRV: `UPDATE ... SET rr_cursor=LAST_INSERT_ID(rr_cursor+1)`
	 * = jedno atomowe UPDATE, `insert_id` niesie NOWA wartosc (per-connection).
	 * Dwa rownoczesne zgloszenia NIGDY nie dostana tego samego indeksu (r.D1).
	 *
	 * @param int $rule_id ID reguly.
	 * @param int $count   Rozmiar (przefiltrowanej) puli (>0).
	 * @return int Indeks 0..count-1.
	 */
	public static function next_pool_index( int $rule_id, int $count ): int {
		global $wpdb;

		if ( $count < 1 ) {
			return 0;
		}

		$table = Tables::full( Tables::WORKFLOW_RULES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane; atomowy licznik.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET rr_cursor = LAST_INSERT_ID(rr_cursor + 1), updated_at = %s WHERE id = %d",
				gmdate( 'Y-m-d H:i:s' ),
				$rule_id
			)
		);

		// UWAGA: $wpdb->insert_id NIE odswieza sie po UPDATE (tylko INSERT/REPLACE) —
		// nowa wartosc licznika czytamy jawnie z sesji (wzorzec SrvCounter C).
		$cursor = (int) $wpdb->get_var( 'SELECT LAST_INSERT_ID()' );
		// phpcs:enable

		return ( $cursor - 1 ) % $count;
	}

	/**
	 * Wstawia regule (uzywane w seedzie/testach). Zwraca ID albo 0.
	 *
	 * @param array<string, mixed> $data Kolumny reguly.
	 * @return int
	 */
	public static function insert( array $data ): int {
		global $wpdb;

		$now = gmdate( 'Y-m-d H:i:s' );

		$row = array(
			'trigger_type'       => (string) ( $data['trigger_type'] ?? '' ),
			'condition_key'      => (string) ( $data['condition_key'] ?? '' ),
			'condition_operator' => (string) ( $data['condition_operator'] ?? 'equals' ),
			'condition_value'    => (string) ( $data['condition_value'] ?? '' ),
			'action_type'        => (string) ( $data['action_type'] ?? '' ),
			'action_config_json' => (string) wp_json_encode( $data['action_config'] ?? array() ),
			'priority'           => (int) ( $data['priority'] ?? 10 ),
			'enabled'            => ! empty( $data['enabled'] ) ? 1 : 0,
			'rr_cursor'          => 0,
			'source'             => (string) ( $data['source'] ?? 'user' ),
			'system_key'         => isset( $data['system_key'] ) ? (string) $data['system_key'] : null,
			'created_at'         => $now,
			'updated_at'         => $now,
		);

		$table = Tables::full( Tables::WORKFLOW_RULES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna.
		$wpdb->insert( $table, $row );
		// phpcs:enable

		return (int) $wpdb->insert_id;
	}
}
