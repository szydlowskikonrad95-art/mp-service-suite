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
	 * Pas bezpieczenstwa: max akcji reguł na JEDNO zdarzenie zewnetrzne (r.D1).
	 */
	private const ACTION_LIMIT = 100;

	/**
	 * Glebokosc przetwarzania per case_id (0 = zdarzenie zewnetrzne, >=1 = re-entrant
	 * z akcji reguły). Strażnik petli: mutacje TYLKO na glebokosci 0.
	 *
	 * @var array<int, int>
	 */
	private static array $depth = array();

	/**
	 * Licznik wykonanych akcji per case_id na JEDNO zdarzenie zewnetrzne (pas 100).
	 * Zerowany przy wejsciu na glebokosci 0, kasowany przy powrocie do 0.
	 *
	 * @var array<int, int>
	 */
	private static array $action_count = array();

	/**
	 * Rejestruje nasluchy triggerow (na init — wolane z Plugin::boot).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'mp_case_created', array( self::class, 'on_case_created' ), 10, 1 );
		add_action( 'mp_case_status_changed', array( self::class, 'on_status_changed' ), 10, 4 );
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
	 * Trigger `mp_case_status_changed` (C, PO COMMIT): uruchamia reguly zmiany
	 * statusu POD GUARDEM PETLI. Akcja zmien_status odpala kolejny status_changed,
	 * wiec bez guardu reguly A->B i B->A petliyby sie w nieskonczonosc.
	 *
	 * @param int    $case_id    ID sprawy.
	 * @param string $old_status Poprzedni status (nieuzywany — warunki z get_context).
	 * @param string $new_status Nowy status (nieuzywany — warunki z get_context).
	 * @param int    $actor_id   Kto zmienil (nieuzywany tutaj).
	 * @return void
	 */
	public static function on_status_changed( $case_id, $old_status, $new_status, $actor_id ): void {
		unset( $old_status, $new_status, $actor_id );
		self::run_status_rules( (int) $case_id );
	}

	/**
	 * Ewaluacja regul triggera status_changed ze STRAŻNIKIEM PETLI.
	 *
	 * Glebokosc per case_id: 0 = zdarzenie zewnetrzne (mutacje dozwolone),
	 * >=1 = re-entrant z akcji reguły (mutacje ZABLOKOWANE + RULE_LOOP_BLOCKED;
	 * akcje mailowe — P3.3 — przechodza na kazdej glebokosci). Pierwsza pasujaca
	 * mutacja wygrywa. Pas bezpieczenstwa: limit akcji na zdarzenie zewnetrzne.
	 * Ksiegowanie zdarzen dzieje sie ZAWSZE (guard dotyczy tylko akcji reguł).
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	public static function run_status_rules( int $case_id ): void {
		$depth = self::$depth[ $case_id ] ?? 0;

		self::$depth[ $case_id ] = $depth + 1;

		if ( 0 === $depth ) {
			self::$action_count[ $case_id ] = 0;
		}

		try {
			$ctx = apply_filters( 'mp_case_get_context', 'not_found', $case_id );

			// Sprawa zniknela / niezweryfikowana — nic nie robimy (guard i tak zejdzie w finally).
			if ( ! is_array( $ctx ) ) {
				return;
			}

			$rules   = Rules::enabled_for_trigger( Rules::TRIGGER_STATUS_CHANGED );
			$mutated = false;

			foreach ( $rules as $rule ) {
				if ( ! self::matches( $rule, $ctx ) ) {
					continue;
				}

				$action = (string) $rule['action_type'];
				$is_mut = Rules::is_mutating( $action );

				// STRAŻNIK PETLI: mutacja WYLACZNIE na glebokosci 0.
				if ( $is_mut && $depth >= 1 ) {
					WorkflowEvents::log(
						WorkflowEvents::RULE_LOOP_BLOCKED,
						array(
							'rule_id' => (int) $rule['id'],
							'action'  => $action,
							'depth'   => $depth,
						),
						$case_id
					);
					continue;
				}

				// Akcja MUTUJACA: pierwsza pasujaca wygrywa (kolejne pomijamy).
				if ( $is_mut && $mutated ) {
					continue;
				}

				// Dyspozytor akcji (P3.2: change_status; akcje mailowe dochodza w P3.3).
				if ( Rules::ACTION_CHANGE_STATUS !== $action ) {
					// Nieobslugiwana tu akcja (np. mail przed P3.3) — nie zuzywa budzetu.
					continue;
				}

				// Pas bezpieczenstwa: limit akcji na zdarzenie zewnetrzne.
				++self::$action_count[ $case_id ];

				if ( self::$action_count[ $case_id ] > self::ACTION_LIMIT ) {
					WorkflowEvents::log(
						WorkflowEvents::RULE_LIMIT_HIT,
						array(
							'rule_id' => (int) $rule['id'],
							'depth'   => $depth,
						),
						$case_id
					);
					break;
				}

				if ( self::do_change_status( $case_id, $ctx, $rule, $depth ) ) {
					$mutated = true;
				}
			}
		} finally {
			--self::$depth[ $case_id ];

			if ( self::$depth[ $case_id ] <= 0 ) {
				unset( self::$depth[ $case_id ], self::$action_count[ $case_id ] );
			}
		}
	}

	/**
	 * Wykonuje akcje zmiany statusu przez funkcje kontraktowa C (jedyna droga
	 * zapisu D). Optimistic-lock: expected = biezacy status z kontekstu. Wejscie
	 * w „odrzucone" WYMAGA kodu (kontrakt) — brak = odmowa wykonania (nie mutuj).
	 * Kazdy wynik logowany w RULE_EXECUTED (NO-PII: {rule_id, template/target, wynik}).
	 *
	 * @param int                  $case_id ID sprawy.
	 * @param array<string, mixed> $ctx     Kontekst sprawy (z mp_case_get_context).
	 * @param array<string, mixed> $rule    Wiersz reguły.
	 * @param int                  $depth   Glebokosc (do logu).
	 * @return bool True gdy status faktycznie zmieniony.
	 */
	private static function do_change_status( int $case_id, array $ctx, array $rule, int $depth ): bool {
		$config = json_decode( (string) $rule['action_config_json'], true );
		$new    = is_array( $config ) && isset( $config['new_status'] ) ? (string) $config['new_status'] : '';
		$code   = is_array( $config ) && isset( $config['rejection_reason_code'] ) ? (string) $config['rejection_reason_code'] : null;

		$log = static function ( string $result ) use ( $rule, $case_id, $new, $depth ): void {
			WorkflowEvents::log(
				WorkflowEvents::RULE_EXECUTED,
				array(
					'rule_id' => (int) $rule['id'],
					'trigger' => Rules::TRIGGER_STATUS_CHANGED,
					'action'  => Rules::ACTION_CHANGE_STATUS,
					'to'      => $new,
					'result'  => $result,
					'depth'   => $depth,
				),
				$case_id
			);
		};

		if ( '' === $new ) {
			$log( 'failed_no_target' );

			return false;
		}

		// „odrzucone" bez kodu = odmowa (UI reguł wymusi kod przy zapisie — admin P3.6).
		if ( 'odrzucone' === $new && ( null === $code || '' === trim( $code ) ) ) {
			$log( 'failed_reason_required' );

			return false;
		}

		$expected = isset( $ctx['status'] ) ? (string) $ctx['status'] : '';
		$result   = apply_filters( 'mp_case_change_status', null, $case_id, $new, $expected, 0, $code );
		$ok       = is_array( $result ) && ! empty( $result['success'] );

		$log( $ok ? 'success' : 'failed' );

		return $ok;
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
