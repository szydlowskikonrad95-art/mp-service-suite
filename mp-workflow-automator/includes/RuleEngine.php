<?php
/**
 * Silnik regul (P3.1): reaguje na mp_case_created, dopasowuje reguly przydzialu,
 * wykonuje auto-przydzial round-robinem i WOLA mp_case_assign w C (assigned_to
 * nalezy do C — OWNERSHIP; D nie pisze cudzej tabeli).
 *
 * Guard petli (r.D1): mutacje TYLKO na glebokosci 0 (zdarzenie zewnetrzne).
 * P3.1 ma tylko akcje przydzialu na case_created (D nie emituje case_created),
 * wiec petla nie wystepuje jeszcze — depth przekazywany, twardy guard dochodzi
 * z akcjami zmiany statusu (P3.2).
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Ewaluacja i wykonanie regul.
 */
final class RuleEngine {

	/**
	 * Rejestruje nasluchy triggerow (na init — wolane z Plugin::boot).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'mp_case_created', array( self::class, 'on_case_created' ), 10, 1 );
	}

	/**
	 * Trigger `mp_case_created`: uruchamia reguly przydzialu.
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	public static function on_case_created( $case_id ): void {
		self::run_assignment( (int) $case_id );
	}

	/**
	 * Dopasowuje reguly przydzialu dla sprawy i wykonuje PIERWSZA pasujaca
	 * (akcja mutujaca = pierwsza wygrywa; r.D1). Brak dopasowania / pusta pula
	 * => sprawa ZOSTAJE nieprzydzielona + ASSIGNMENT_UNMATCHED (swiadomy stan).
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	public static function run_assignment( int $case_id ): void {
		$ctx = apply_filters( 'mp_case_get_context', 'not_found', $case_id );

		// Sprawa zniknela / niezweryfikowana (D nie widzi sierot) — nic nie robimy.
		if ( ! is_array( $ctx ) ) {
			return;
		}

		$rules = Rules::enabled_for_trigger( Rules::TRIGGER_CASE_CREATED );

		foreach ( $rules as $rule ) {
			if ( Rules::ACTION_ASSIGN !== $rule['action_type'] ) {
				continue;
			}

			if ( ! self::matches( $rule, $ctx ) ) {
				continue;
			}

			$config = json_decode( (string) $rule['action_config_json'], true );
			$pool   = is_array( $config ) && isset( $config['pool'] ) && is_array( $config['pool'] )
				? array_map( 'intval', $config['pool'] )
				: array();

			// Pula FILTROWANA w runtime: user istnieje + ma cap agenta (r.D1).
			$pool = array_values(
				array_filter(
					$pool,
					static function ( int $uid ): bool {
						return $uid > 0 && user_can( $uid, 'mp_agent' );
					}
				)
			);

			if ( array() === $pool ) {
				// Regula pasuje, ale pula pusta/wygaszona — nie prubuj kolejnych mutacji.
				break;
			}

			$index = Rules::next_pool_index( (int) $rule['id'], count( $pool ) );
			$agent = $pool[ $index ];

			$result = apply_filters( 'mp_case_assign', null, $case_id, $agent, 0 );
			$ok     = is_array( $result ) && ! empty( $result['success'] );

			WorkflowEvents::log(
				WorkflowEvents::RULE_EXECUTED,
				array(
					'rule_id' => (int) $rule['id'],
					'trigger' => Rules::TRIGGER_CASE_CREATED,
					'action'  => Rules::ACTION_ASSIGN,
					'to'      => $agent,
					'result'  => $ok ? 'success' : 'failed',
					'depth'   => 0,
				),
				$case_id
			);

			// Akcja mutujaca wykonana (lub odmowa C) — pierwsza pasujaca konczy przebieg.
			return;
		}

		// Zadna regula nie trafila / pula pusta — swiadomy stan (nie cicha magia).
		WorkflowEvents::log(
			WorkflowEvents::ASSIGNMENT_UNMATCHED,
			array(
				'trigger' => Rules::TRIGGER_CASE_CREATED,
			),
			$case_id
		);
	}

	/**
	 * Czy regula pasuje do kontekstu sprawy. Pusty condition_key = pasuje ZAWSZE.
	 * Brak danej (wartosc null/nieustawiona) => equals/not_equals/in_list NIE-PASUJE,
	 * is_empty PASUJE, is_not_empty nie (frozen zasada: brak danej != blad).
	 *
	 * @param array<string, mixed> $rule Wiersz reguly.
	 * @param array<string, mixed> $ctx  Kontekst sprawy.
	 * @return bool
	 */
	private static function matches( array $rule, array $ctx ): bool {
		$key = (string) $rule['condition_key'];

		if ( '' === $key ) {
			return true;
		}

		$operator = (string) $rule['condition_operator'];
		$expected = (string) $rule['condition_value'];
		$actual   = array_key_exists( $key, $ctx ) && null !== $ctx[ $key ] ? (string) $ctx[ $key ] : null;

		switch ( $operator ) {
			case 'is_empty':
				return null === $actual || '' === $actual;

			case 'is_not_empty':
				return null !== $actual && '' !== $actual;

			case 'equals':
				return null !== $actual && $actual === $expected;

			case 'not_equals':
				// Brak danej NIE-PASUJE (spojnie: warunek nie da sie potwierdzic).
				return null !== $actual && $actual !== $expected;

			case 'in_list':
				if ( null === $actual ) {
					return false;
				}
				$list = array_map( 'trim', explode( ',', $expected ) );
				return in_array( $actual, $list, true );

			default:
				// Nieznany operator (nie z zamknietej listy) = NIE-PASUJE (bezpiecznie).
				return false;
		}
	}
}
