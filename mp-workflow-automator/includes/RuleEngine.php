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
		add_action( 'mp_case_message_added', array( self::class, 'on_message_added' ), 10, 3 );
		add_action( 'mp_case_assigned', array( self::class, 'on_case_assigned' ), 10, 4 );
	}

	/**
	 * Trigger `mp_case_assigned` (C, PO COMMIT): ZASADA kazdy przydzial (auto i
	 * reczny, dowolny caller) => mail do NOWO przypisanego pracownika. Nie jest
	 * to regula z tabeli — to stale zachowanie (gwarancja S10), wiec nie podlega
	 * dopasowaniu warunkow. Akcja mailowa, nie mutuje => zero ryzyka petli.
	 *
	 * @param int      $case_id  ID sprawy.
	 * @param int|null $from     Poprzedni przypisany (nieuzywany).
	 * @param int      $to       Nowo przypisany pracownik.
	 * @param int      $actor_id Kto przydzielil (nieuzywany).
	 * @return void
	 */
	public static function on_case_assigned( $case_id, $from, $to, $actor_id ): void {
		unset( $actor_id );

		// Re-assign do TEGO SAMEGO agenta = brak realnej zmiany => zero redundantnego
		// maila (auto-sciezka bezpieczna: from=null; guard chroni reczny re-assign).
		if ( null !== $from && (int) $from === (int) $to ) {
			return;
		}

		self::notify_assignment( (int) $case_id, (int) $to );
	}

	/**
	 * Trigger `mp_case_created`: uruchamia reguly przydzialu.
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	public static function on_case_created( $case_id ): void {
		// Priorytet PRZED przydzialem i PRZED wierszem SLA (RuleEngine hook=10 < Sla=20),
		// zeby pierwszy termin liczyl sie z nadanego priorytetu.
		self::run_priority( (int) $case_id );
		self::run_assignment( (int) $case_id );
	}

	/**
	 * Silnik NADAJE priorytet: dopasowuje reguly set_priority na case_created i wykonuje
	 * PIERWSZA pasujaca (mutacja = pierwsza wygrywa; r.D1). Brak reguly => priorytet
	 * domyslny sprawy ('normal') zostaje. Wola kontrakt C `mp_case_set_priority`.
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	public static function run_priority( int $case_id ): void {
		$ctx = apply_filters( 'mp_case_get_context', 'not_found', $case_id );

		// Sprawa zniknela / niezweryfikowana (D nie widzi sierot) — nic nie robimy.
		if ( ! is_array( $ctx ) ) {
			return;
		}

		$rules = Rules::enabled_for_trigger( Rules::TRIGGER_CASE_CREATED );

		foreach ( $rules as $rule ) {
			if ( Rules::ACTION_SET_PRIORITY !== $rule['action_type'] ) {
				continue;
			}

			if ( ! self::matches( $rule, $ctx ) ) {
				continue;
			}

			$config   = json_decode( (string) $rule['action_config_json'], true );
			$priority = is_array( $config ) && isset( $config['priority'] ) ? (string) $config['priority'] : '';

			$result = apply_filters( 'mp_case_set_priority', null, $case_id, $priority, 0 );
			$ok     = is_array( $result ) && ! empty( $result['success'] );

			WorkflowEvents::log(
				WorkflowEvents::RULE_EXECUTED,
				array(
					'rule_id'  => (int) $rule['id'],
					'trigger'  => Rules::TRIGGER_CASE_CREATED,
					'action'   => Rules::ACTION_SET_PRIORITY,
					'priority' => $priority,
					'result'   => $ok ? 'success' : 'failed',
					'depth'    => 0,
				),
				$case_id
			);

			// Pierwsza pasujaca mutacja wygrywa — kolejne set_priority pomijamy.
			return;
		}
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
		unset( $old_status, $new_status );
		// actor_id do kontekstu: powiadomienie pracownika pomija AUTORA zmiany
		// (nie mailuje pracownika o jego wlasnej akcji — self-skip w resolve_recipient).
		self::run_rules( (int) $case_id, Rules::TRIGGER_STATUS_CHANGED, array( 'actor_id' => (int) $actor_id ) );
	}

	/**
	 * Trigger `mp_case_message_added` (C): reguly po dodaniu wiadomosci, warunki po
	 * `author_type` (client/staff/system — wstrzykiwany do kontekstu, bo get_context
	 * go nie zna). Domyslnie: wiadomosc KLIENTA => mail do przypisanego agenta;
	 * wiadomosc STAFF => mail do klienta (C sam nie maili — domena D).
	 *
	 * @param int    $case_id     ID sprawy.
	 * @param int    $message_id  ID wiadomosci (nieuzywany — NO-PII, bez tresci).
	 * @param string $author_type Typ autora: client|staff|system.
	 * @return void
	 */
	public static function on_message_added( $case_id, $message_id, $author_type ): void {
		unset( $message_id );
		self::run_rules(
			(int) $case_id,
			Rules::TRIGGER_MESSAGE_ADDED,
			array( 'author_type' => (string) $author_type )
		);
	}

	/**
	 * Ewaluacja regul danego triggera ze STRAŻNIKIEM PETLI (wspolna dla
	 * status_changed i message_added).
	 *
	 * Glebokosc per case_id: 0 = zdarzenie zewnetrzne (mutacje dozwolone),
	 * >=1 = re-entrant z akcji reguły (mutacje ZABLOKOWANE + RULE_LOOP_BLOCKED;
	 * akcje mailowe przechodza na kazdej glebokosci). Pierwsza pasujaca mutacja
	 * wygrywa. Pas bezpieczenstwa: limit akcji na zdarzenie zewnetrzne. Ksiegowanie
	 * dzieje sie ZAWSZE (guard dotyczy tylko akcji reguł).
	 *
	 * @param int                  $case_id   ID sprawy.
	 * @param string               $trigger   Stala Rules::TRIGGER_*.
	 * @param array<string, mixed> $extra_ctx Fakty zdarzenia doklejane do kontekstu.
	 * @return void
	 */
	public static function run_rules( int $case_id, string $trigger, array $extra_ctx = array() ): void {
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

			// Fakty zdarzenia niedostepne w kontekscie sprawy (np. author_type dla
			// message_added) — wstrzykiwane do dopasowania warunkow.
			if ( array() !== $extra_ctx ) {
				$ctx = array_merge( $ctx, $extra_ctx );
			}

			$rules   = Rules::enabled_for_trigger( $trigger );
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

				// Dyspozytor akcji: change_status (mutacja) / notify (mail P3.3).
				// Nieznana akcja = ignoruj (nie zuzywa budzetu).
				if ( Rules::ACTION_CHANGE_STATUS !== $action && Rules::ACTION_NOTIFY !== $action ) {
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

				if ( Rules::ACTION_CHANGE_STATUS === $action ) {
					if ( self::do_change_status( $case_id, $ctx, $rule, $depth, $trigger ) ) {
						$mutated = true;
					}
				} else {
					self::do_notify( $case_id, $ctx, $rule, $depth, $trigger );
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
	 * @param string               $trigger Trigger, ktory odpalil regule (do logu).
	 * @return bool True gdy status faktycznie zmieniony.
	 */
	private static function do_change_status( int $case_id, array $ctx, array $rule, int $depth, string $trigger ): bool {
		$config = json_decode( (string) $rule['action_config_json'], true );
		$new    = is_array( $config ) && isset( $config['new_status'] ) ? (string) $config['new_status'] : '';
		$code   = is_array( $config ) && isset( $config['rejection_reason_code'] ) ? (string) $config['rejection_reason_code'] : null;

		$log = static function ( string $result ) use ( $rule, $case_id, $new, $depth, $trigger ): void {
			WorkflowEvents::log(
				WorkflowEvents::RULE_EXECUTED,
				array(
					'rule_id' => (int) $rule['id'],
					'trigger' => $trigger,
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
	 * Akcja notify (P3.3): renderuje szablon i wysyla mail przez Mailer (jedyna
	 * brama egress). Odbiorca bez adresu (klient zanonimizowany / agent
	 * nieprzydzielony) = LEGALNE pominiecie (MAIL_SKIPPED_NO_RECIPIENT, nie awaria).
	 * Log NO-PII: {template_key, recipient_ref=kategoria} — NIGDY adres ani tresc.
	 *
	 * @param int                  $case_id ID sprawy.
	 * @param array<string, mixed> $ctx     Kontekst sprawy.
	 * @param array<string, mixed> $rule    Wiersz reguły.
	 * @param int                  $depth   Glebokosc (do logu).
	 * @param string               $trigger Trigger, ktory odpalil regule (do logu).
	 * @return void
	 */
	private static function do_notify( int $case_id, array $ctx, array $rule, int $depth, string $trigger ): void {
		$config       = json_decode( (string) $rule['action_config_json'], true );
		$template_key = is_array( $config ) && isset( $config['template_key'] ) ? (string) $config['template_key'] : '';
		$recipient    = is_array( $config ) && isset( $config['recipient'] ) ? (string) $config['recipient'] : 'client';

		$resolved = self::resolve_recipient( $recipient, $ctx );
		$addr     = $resolved[0];
		$ref      = $resolved[1];

		if ( '' === $addr ) {
			WorkflowEvents::log(
				WorkflowEvents::MAIL_SKIPPED_NO_RECIPIENT,
				array(
					'template_key'  => $template_key,
					'recipient_ref' => $ref,
				),
				$case_id
			);

			return;
		}

		$rendered = MailTemplates::render( $template_key, $ctx );

		// DEDUP-OKNO (best-effort): identyczny mail (adresat+tresc) w oknie => pomin.
		if ( null !== $rendered
			&& ! MailDedup::claim( $addr, $rendered['dedup_key'], MailDedup::window_for( $template_key ) )
		) {
			WorkflowEvents::log(
				WorkflowEvents::MAIL_DEDUPED,
				array(
					'template_key'  => $template_key,
					'recipient_ref' => $ref,
				),
				$case_id
			);

			return;
		}

		$result = 'failed_template_missing';

		if ( null !== $rendered ) {
			$result = Mailer::send( $addr, $rendered['subject'], $rendered['body'] ) ? 'success' : 'failed';
		}

		WorkflowEvents::log(
			WorkflowEvents::RULE_EXECUTED,
			array(
				'rule_id'       => (int) $rule['id'],
				'trigger'       => $trigger,
				'action'        => Rules::ACTION_NOTIFY,
				'template_key'  => $template_key,
				'recipient_ref' => $ref,
				'result'        => $result,
				'depth'         => $depth,
			),
			$case_id
		);
	}

	/**
	 * Rozwiazuje adres odbiorcy z kategorii (client/agent/coordinator). Zwraca
	 * [adres, recipient_ref] gdzie recipient_ref = KATEGORIA (NO-PII do logu,
	 * nigdy adres). Brak adresu => pierwszy element ''.
	 *
	 * @param string               $recipient Kategoria odbiorcy.
	 * @param array<string, mixed> $ctx       Kontekst sprawy.
	 * @return array{0: string, 1: string}
	 */
	private static function resolve_recipient( string $recipient, array $ctx ): array {
		if ( 'client' === $recipient ) {
			$email = isset( $ctx['kontakt']['email'] ) ? (string) $ctx['kontakt']['email'] : '';

			return array( $email, 'client' );
		}

		if ( 'agent' === $recipient ) {
			$uid = isset( $ctx['assigned_to'] ) && null !== $ctx['assigned_to'] ? (int) $ctx['assigned_to'] : 0;

			if ( 0 === $uid ) {
				return array( '', 'agent' );
			}

			// Self-skip: pracownik NIE dostaje maila o zmianie, ktora SAM wprowadzil
			// (actor_id wstrzykiwany dla status_changed). Inni pracownicy/koordynator
			// zmieniajacy jego sprawe => mail dochodzi normalnie.
			$actor = isset( $ctx['actor_id'] ) ? (int) $ctx['actor_id'] : 0;

			if ( $actor > 0 && $actor === $uid ) {
				return array( '', 'agent_self' );
			}

			$user = get_userdata( $uid );

			return array( $user ? (string) $user->user_email : '', 'agent' );
		}

		if ( 'coordinator' === $recipient ) {
			$users = get_users(
				array(
					'role'   => 'mp_coordinator',
					'number' => 1,
					'fields' => array( 'user_email' ),
				)
			);
			$email = ! empty( $users ) && isset( $users[0]->user_email ) ? (string) $users[0]->user_email : '';

			return array( $email, 'coordinator' );
		}

		return array( '', $recipient );
	}

	/**
	 * Mail powiadamiajacy pracownika o przydziale (szablon assignment_notify).
	 * Agent bez adresu => MAIL_SKIPPED_NO_RECIPIENT (nie awaria). Log NO-PII.
	 *
	 * @param int $case_id  ID sprawy.
	 * @param int $agent_id Nowo przypisany pracownik.
	 * @return void
	 */
	private static function notify_assignment( int $case_id, int $agent_id ): void {
		$user = $agent_id > 0 ? get_userdata( $agent_id ) : false;
		$addr = $user ? (string) $user->user_email : '';

		if ( '' === $addr ) {
			WorkflowEvents::log(
				WorkflowEvents::MAIL_SKIPPED_NO_RECIPIENT,
				array(
					'template_key'  => 'assignment_notify',
					'recipient_ref' => 'agent',
				),
				$case_id
			);

			return;
		}

		$ctx = apply_filters( 'mp_case_get_context', 'not_found', $case_id );

		if ( ! is_array( $ctx ) ) {
			return;
		}

		$rendered = MailTemplates::render( 'assignment_notify', $ctx );

		// DEDUP-OKNO (best-effort): identyczny mail przydzialu w oknie => pomin.
		if ( null !== $rendered
			&& ! MailDedup::claim( $addr, $rendered['dedup_key'], MailDedup::window_for( 'assignment_notify' ) )
		) {
			WorkflowEvents::log(
				WorkflowEvents::MAIL_DEDUPED,
				array(
					'template_key'  => 'assignment_notify',
					'recipient_ref' => 'agent',
				),
				$case_id
			);

			return;
		}

		$result = 'failed_template_missing';

		if ( null !== $rendered ) {
			$result = Mailer::send( $addr, $rendered['subject'], $rendered['body'] ) ? 'success' : 'failed';
		}

		WorkflowEvents::log(
			WorkflowEvents::RULE_EXECUTED,
			array(
				'rule_id'       => 0,
				'trigger'       => 'assigned',
				'action'        => Rules::ACTION_NOTIFY,
				'template_key'  => 'assignment_notify',
				'recipient_ref' => 'agent',
				'result'        => $result,
				'depth'         => 0,
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
