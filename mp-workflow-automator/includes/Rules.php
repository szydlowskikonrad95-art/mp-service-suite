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
	 * Trigger zmiany statusu (emitowany przez C PO COMMIT — ).
	 */
	public const TRIGGER_STATUS_CHANGED = 'status_changed';

	/**
	 * Trigger dodania wiadomosci (C); warunki po author_type (client/staff/system).
	 */
	public const TRIGGER_MESSAGE_ADDED = 'message_added';

	/**
	 * Akcje (zamknieta lista). = przydzial = zmiana statusu.
	 */
	public const ACTION_ASSIGN = 'assign';

	/**
	 * Akcja: zmiana statusu sprawy (wola kontraktowa C mp_case_change_status).
	 */
	public const ACTION_CHANGE_STATUS = 'change_status';

	/**
	 * Akcja: powiadomienie e-mail z szablonu. NIEMUTUJACA — przechodzi
	 * przez guard petli na kazdej glebokosci (powiadomienie o zmianie MUSI wyjsc).
	 */
	public const ACTION_NOTIFY = 'notify';

	/**
	 * Akcja: ustawienie priorytetu sprawy (wola kontraktowa C mp_case_set_priority).
	 * Silnik NADAJE priorytet wg regul (np. na case_created po kategorii/warunku).
	 */
	public const ACTION_SET_PRIORITY = 'set_priority';

	/**
	 * Akcje MUTUJACE stan sprawy — objete GUARDEM PETLI (mutacja tylko na
	 * glebokosci 0). Akcje spoza tej listy (mailowe — ) przechodza na kazdej
	 * glebokosci. Zamknieta lista w kodzie (ZAKAZ eval).
	 *
	 * @var string[]
	 */
	public const MUTATING_ACTIONS = array( self::ACTION_ASSIGN, self::ACTION_CHANGE_STATUS, self::ACTION_SET_PRIORITY );

	/**
	 * Czy akcja mutuje stan sprawy (podlega guardowi petli).
	 *
	 * @param string $action_type Stala ACTION_*.
	 * @return bool
	 */
	public static function is_mutating( string $action_type ): bool {
		return in_array( $action_type, self::MUTATING_ACTIONS, true );
	}

	/**
	 * Operatory warunku (zamknieta lista — r.D1/Kimi).
	 */
	public const OPERATORS = array( 'equals', 'not_equals', 'in_list', 'is_empty', 'is_not_empty' );

	/**
	 * Wersja zestawu seedow (podbicie = dosiew nowych; dosiew przy upgrade -> NEXT).
	 */
	public const SEED_VERSION = 2;

	/**
	 * Opcja sterujaca sianiem (warstwa ii uninstalla — pelny uninstall = swiezy siew).
	 */
	public const SEED_VERSION_OPTION = 'mp_automator_seed_version';

	/**
	 * Klucz systemowy domyslnej reguly przydzialu (rozpoznanie seeda).
	 */
	public const SYSTEM_KEY_DEFAULT_ASSIGN = 'default_assign';

	/**
	 * Klucz systemowy domyslnej reguly: mail do klienta przy zmianie statusu.
	 */
	public const SYSTEM_KEY_STATUS_MAIL_CLIENT = 'status_changed_client_mail';

	/**
	 * Klucz systemowy: mail do PRZYPISANEGO pracownika przy zmianie statusu
	 * (— spec „klient i pracownik po kazdej waznej zmianie"; self-skip gdy
	 * pracownik sam zmienil status — nie mailuje o wlasnej akcji).
	 */
	public const SYSTEM_KEY_STATUS_MAIL_STAFF = 'status_changed_staff_mail';

	/**
	 * Klucz systemowy: wiadomosc KLIENTA => mail do przypisanego agenta.
	 */
	public const SYSTEM_KEY_MSG_CLIENT_TO_AGENT = 'msg_client_to_agent';

	/**
	 * Klucz systemowy: wiadomosc STAFF => mail do klienta ( ; C sam nie maili).
	 */
	public const SYSTEM_KEY_MSG_STAFF_TO_CLIENT = 'msg_staff_to_client';

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

	/**
	 * Akcja admin-post ekranu ustawien (= akcja nonce). Do 1.3.12 `insert()` nie bylo
	 * wolane NIGDZIE w produkcie (jedyne wywolanie: test przez `wp eval`), a panel
	 * dawal wylacznie podglad do odczytu — regule przydzialu zakladal programista.
	 */
	public const ACTION_CONFIG = 'mp_automator_rules_config';

	/**
	 * Klucze warunku, ktore silnik NAPRAWDE widzi w kontekscie sprawy
	 * (`CaseRepo::context()`). Lista jest zamknieta celowo: klucz spoza kontekstu
	 * daje regule, ktora nigdy nie pasuje — i nikt sie o tym nie dowiaduje.
	 *
	 * @var array<int, string>
	 */
	public const CONDITION_KEYS = array( 'kategoria', 'kraj', 'jezyk', 'priority', 'rodzaj', 'status' );

	/**
	 * Wyzwalacze dozwolone na ekranie (= stale TRIGGER_* tej klasy). Lista zamknieta:
	 * wyzwalacz spoza niej daje regule, ktorej silnik nigdy nie odpyta.
	 *
	 * @var array<int, string>
	 */
	public const TRIGGERS = array(
		self::TRIGGER_CASE_CREATED,
		self::TRIGGER_STATUS_CHANGED,
		self::TRIGGER_MESSAGE_ADDED,
	);

	/**
	 * Typy akcji dozwolone na ekranie (= stale ACTION_* tej klasy).
	 *
	 * @var array<int, string>
	 */
	public const ACTIONS = array(
		self::ACTION_ASSIGN,
		self::ACTION_CHANGE_STATUS,
		self::ACTION_NOTIFY,
		self::ACTION_SET_PRIORITY,
	);

	/**
	 * Klucze warunku, ktorych NIC W PRODUKCIE NIE WYPELNIA (zawsze puste): ani
	 * formularz klienta, ani wiersz polecen. Regula na nich nie zadziala nigdy —
	 * ekran musi to powiedziec czlowiekowi ZANIM ja zapisze.
	 *
	 * @var array<int, string>
	 */
	public const CONDITION_KEYS_MARTWE = array( 'kraj', 'jezyk' );

	/**
	 * Rejestruje handler zapisu z ekranu ustawien.
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
		add_action( 'admin_post_nopriv_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
	}

	/**
	 * Wszystkie reguly do ekranu ustawien (rowniez wylaczone).
	 *
	 * @return array<int, array<string, mixed>>
	 */
	public static function all(): array {
		global $wpdb;

		$table = Tables::full( Tables::WORKFLOW_RULES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, bez parametrow.
		$rows = $wpdb->get_results(
			"SELECT id, trigger_type, condition_key, condition_operator, condition_value,
				action_type, action_config_json, priority, enabled, source, system_key
			FROM {$table} ORDER BY priority ASC, id ASC",
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * Aktualizuje regule. Reguly SYSTEMOWE (source=system) zostaja pod swoim
	 * `system_key` i nie zmieniaja typu akcji — inaczej ekran po cichu rozbrajalby
	 * powiadomienia, ktore produkt sieje przy instalacji.
	 *
	 * @param int                  $id   ID reguly.
	 * @param array<string, mixed> $data Pola do zapisu.
	 * @return bool Czy wiersz zostal zmieniony.
	 */
	public static function update( int $id, array $data ): bool {
		global $wpdb;

		if ( $id < 1 ) {
			return false;
		}

		$biezaca = self::by_id( $id );

		if ( null === $biezaca ) {
			return false;
		}

		$systemowa = 'system' === (string) $biezaca['source'];

		$row = array(
			'condition_key'      => in_array( (string) ( $data['condition_key'] ?? '' ), self::CONDITION_KEYS, true )
				? (string) $data['condition_key']
				: '',
			'condition_operator' => in_array( (string) ( $data['condition_operator'] ?? '' ), self::OPERATORS, true )
				? (string) $data['condition_operator']
				: 'equals',
			'condition_value'    => sanitize_text_field( (string) ( $data['condition_value'] ?? '' ) ),
			'priority'           => max( 0, (int) ( $data['priority'] ?? 10 ) ),
			'enabled'            => ! empty( $data['enabled'] ) ? 1 : 0,
			'updated_at'         => gmdate( 'Y-m-d H:i:s' ),
		);

		if ( ! $systemowa ) {
			$trigger = (string) ( $data['trigger_type'] ?? '' );
			$action  = (string) ( $data['action_type'] ?? '' );

			if ( in_array( $trigger, self::TRIGGERS, true ) ) {
				$row['trigger_type'] = $trigger;
			}

			if ( in_array( $action, self::ACTIONS, true ) ) {
				$row['action_type'] = $action;
			}
		}

		if ( isset( $data['action_config'] ) && is_array( $data['action_config'] ) ) {
			$row['action_config_json'] = (string) wp_json_encode( $data['action_config'] );
		}

		$table = Tables::full( Tables::WORKFLOW_RULES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna.
		$zmienione = $wpdb->update( $table, $row, array( 'id' => $id ) );
		// phpcs:enable

		return false !== $zmienione;
	}

	/**
	 * Kasuje regule WLASNA. Reguly systemowej nie kasujemy z ekranu — od wylaczenia
	 * jest przelacznik `enabled`, a skasowana wrocilaby dopiero przy reinstalacji
	 * (bramka SEED_VERSION jest jednorazowa).
	 *
	 * @param int $id ID reguly.
	 * @return bool
	 */
	public static function delete( int $id ): bool {
		global $wpdb;

		$regula = self::by_id( $id );

		if ( null === $regula || 'system' === (string) $regula['source'] ) {
			return false;
		}

		$table = Tables::full( Tables::WORKFLOW_RULES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna.
		$usuniete = $wpdb->delete( $table, array( 'id' => $id ), array( '%d' ) );
		// phpcs:enable

		return (bool) $usuniete;
	}

	/**
	 * Jedna regula po ID (albo null).
	 *
	 * @param int $id ID reguly.
	 * @return array<string, mixed>|null
	 */
	public static function by_id( int $id ): ?array {
		global $wpdb;

		$table = Tables::full( Tables::WORKFLOW_RULES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT * FROM {$table} WHERE id = %d", $id ),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $row ) ? $row : null;
	}

	/**
	 * Handler ekranu ustawien: capability => nonce => wiersze formularza.
	 * Wiersze istniejace ida przez update()/delete(), wiersz „nowa regula" przez insert().
	 *
	 * @return void
	 */
	public static function handle_config(): void {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die(
				esc_html__( 'Brak uprawnień do konfiguracji reguł przydziału.', 'mp-workflow-automator' ),
				'',
				array( 'response' => 403 )
			);
		}

		check_admin_referer( self::ACTION_CONFIG );

		$ref = wp_get_referer();
		$cel = false !== $ref ? $ref : admin_url();

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$rows = isset( $_POST['mp_rule'] ) && is_array( $_POST['mp_rule'] )
			// phpcs:ignore WordPress.Security.NonceVerification.Missing, WordPress.Security.ValidatedSanitizedInput.InputNotSanitized -- kazde pole sanityzowane w update().
			? (array) wp_unslash( $_POST['mp_rule'] )
			: array();

		$zmienione = 0;

		foreach ( $rows as $id => $row ) {
			$id = (int) $id;

			if ( $id < 1 || ! is_array( $row ) ) {
				continue;
			}

			if ( ! empty( $row['delete'] ) ) {
				if ( self::delete( $id ) ) {
					++$zmienione;
					self::log_config( 'delete', $id );
				}

				continue;
			}

			if ( self::update( $id, $row ) ) {
				++$zmienione;
				self::log_config( 'update', $id );
			}
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$nowa = isset( $_POST['mp_rule_new'] ) && is_array( $_POST['mp_rule_new'] )
			// phpcs:ignore WordPress.Security.NonceVerification.Missing, WordPress.Security.ValidatedSanitizedInput.InputNotSanitized -- pola sprawdzane nizej wobec list zamknietych.
			? (array) wp_unslash( $_POST['mp_rule_new'] )
			: array();

		$trigger = (string) ( $nowa['trigger_type'] ?? '' );
		$action  = (string) ( $nowa['action_type'] ?? '' );

		if ( in_array( $trigger, self::TRIGGERS, true ) && in_array( $action, self::ACTIONS, true ) ) {
			$klucz = (string) ( $nowa['condition_key'] ?? '' );

			$id = self::insert(
				array(
					'trigger_type'       => $trigger,
					'condition_key'      => in_array( $klucz, self::CONDITION_KEYS, true ) ? $klucz : '',
					'condition_operator' => in_array( (string) ( $nowa['condition_operator'] ?? '' ), self::OPERATORS, true )
						? (string) $nowa['condition_operator']
						: 'equals',
					'condition_value'    => sanitize_text_field( (string) ( $nowa['condition_value'] ?? '' ) ),
					'action_type'        => $action,
					'action_config'      => self::parse_config( (string) ( $nowa['action_config_json'] ?? '' ) ),
					'priority'           => max( 0, (int) ( $nowa['priority'] ?? 10 ) ),
					'enabled'            => ! empty( $nowa['enabled'] ),
					'source'             => 'user',
				)
			);

			if ( $id > 0 ) {
				++$zmienione;
				self::log_config( 'insert', $id );
			}
		}

		wp_safe_redirect(
			add_query_arg(
				array(
					'mp_settings_ok'    => 'reguly',
					'mp_settings_detal' => (string) $zmienione,
				),
				$cel
			)
		);
		exit;
	}

	/**
	 * Konfiguracja akcji z pola tekstowego (JSON). Niepoprawny JSON => pusta
	 * konfiguracja, NIE polowiczna — regula z polamana konfiguracja gorsza niz bez.
	 *
	 * @param string $json Surowa tresc pola.
	 * @return array<string, mixed>
	 */
	private static function parse_config( string $json ): array {
		if ( '' === trim( $json ) ) {
			return array();
		}

		$decoded = json_decode( $json, true );

		return is_array( $decoded ) ? $decoded : array();
	}

	/**
	 * Wpis do rejestru zdarzen o zmianie konfiguracji reguly (kto/kiedy/co).
	 *
	 * @param string $co Rodzaj zmiany (insert/update/delete).
	 * @param int    $id ID reguly.
	 * @return void
	 */
	private static function log_config( string $co, int $id ): void {
		WorkflowEvents::log(
			WorkflowEvents::CONFIG_CHANGED,
			array(
				'object' => 'rule',
				'id'     => $id,
				'action' => $co,
			),
			null,
			get_current_user_id()
		);
	}

	/**
	 * Sieje reguly domyslne — TYLKO gdy jeszcze nie zasiane (bramka SEED_VERSION).
	 *
	 * Idempotentne i JEDNORAZOWE per instalacja: skasowana regula NIE wraca przy
	 * kolejnej aktywacji (bramka wersji, nie sprawdzanie istnienia). Pelny uninstall
	 * (opt-in) kasuje SEED_VERSION_OPTION => reinstalacja sieje swiezo. Domyslna
	 * regula przydzialu ma PUSTA pule (admin/demo ja wypelnia) — do czasu sprawy
	 * ida ASSIGNMENT_UNMATCHED (swiadomy stan, nie cicha magia).
	 *
	 * @return void
	 */
	public static function maybe_seed_defaults(): void {
		if ( (int) get_option( self::SEED_VERSION_OPTION, 0 ) >= self::SEED_VERSION ) {
			return;
		}

		self::seed_if_absent(
			array(
				'trigger_type'  => self::TRIGGER_CASE_CREATED,
				'condition_key' => '',
				'action_type'   => self::ACTION_ASSIGN,
				'action_config' => array(
					// Notyfikacja przydzielonego pracownika = stale zachowanie na
					// hooku mp_case_assigned (kazdy przydzial), NIE flaga w regule.
					'pool' => array(),
				),
				'priority'      => 10,
				'enabled'       => 1,
				'source'        => 'system',
				'system_key'    => self::SYSTEM_KEY_DEFAULT_ASSIGN,
			)
		);

		// Domyslna: mail do KLIENTA przy KAZDEJ zmianie statusu (warunek pusty = zawsze).
		self::seed_if_absent(
			array(
				'trigger_type'  => self::TRIGGER_STATUS_CHANGED,
				'condition_key' => '',
				'action_type'   => self::ACTION_NOTIFY,
				'action_config' => array(
					'template_key' => 'status_changed_client',
					'recipient'    => 'client',
				),
				'priority'      => 10,
				'enabled'       => 1,
				'source'        => 'system',
				'system_key'    => self::SYSTEM_KEY_STATUS_MAIL_CLIENT,
			)
		);

		// Domyslna: mail do PRZYPISANEGO PRACOWNIKA przy zmianie statusu (spec „klient
		// i pracownik"). Odbiorca 'agent' = przydzielony; brak przydzialu => pominiecie
		// (MAIL_SKIPPED_NO_RECIPIENT). Self-skip (pracownik sam zmienil) w RuleEngine.
		self::seed_if_absent(
			array(
				'trigger_type'  => self::TRIGGER_STATUS_CHANGED,
				'condition_key' => '',
				'action_type'   => self::ACTION_NOTIFY,
				'action_config' => array(
					'template_key' => 'status_changed_staff',
					'recipient'    => 'agent',
				),
				'priority'      => 10,
				'enabled'       => 1,
				'source'        => 'system',
				'system_key'    => self::SYSTEM_KEY_STATUS_MAIL_STAFF,
			)
		);

		// Wiadomosc KLIENTA => mail do przypisanego AGENTA (klient odpowiedzial).
		self::seed_if_absent(
			array(
				'trigger_type'       => self::TRIGGER_MESSAGE_ADDED,
				'condition_key'      => 'author_type',
				'condition_operator' => 'equals',
				'condition_value'    => 'client',
				'action_type'        => self::ACTION_NOTIFY,
				'action_config'      => array(
					'template_key' => 'message_from_client',
					'recipient'    => 'agent',
				),
				'priority'           => 10,
				'enabled'            => 1,
				'source'             => 'system',
				'system_key'         => self::SYSTEM_KEY_MSG_CLIENT_TO_AGENT,
			)
		);

		// Wiadomosc STAFF => mail do KLIENTA (serwis odpowiedzial; C sam nie maili).
		self::seed_if_absent(
			array(
				'trigger_type'       => self::TRIGGER_MESSAGE_ADDED,
				'condition_key'      => 'author_type',
				'condition_operator' => 'equals',
				'condition_value'    => 'staff',
				'action_type'        => self::ACTION_NOTIFY,
				'action_config'      => array(
					'template_key' => 'message_from_staff',
					'recipient'    => 'client',
				),
				'priority'           => 10,
				'enabled'            => 1,
				'source'             => 'system',
				'system_key'         => self::SYSTEM_KEY_MSG_STAFF_TO_CLIENT,
			)
		);

		// Szablony maili sieja sie RAZEM z regulami (warstwa ii, jedna bramka).
		MailTemplates::seed_defaults();

		update_option( self::SEED_VERSION_OPTION, self::SEED_VERSION, false );
	}

	/**
	 * Sieje regule TYLKO gdy reguly o tym system_key jeszcze nie ma — idempotentnie.
	 * Dzieki temu podbicie SEED_VERSION DOSIEWA nowe reguly (docblock SEED_VERSION),
	 * bez duplikowania istniejacych na instalacjach po upgrade (bez reaktywacji).
	 *
	 * @param array<string, mixed> $data Kolumny reguly (z system_key).
	 * @return void
	 */
	private static function seed_if_absent( array $data ): void {
		$key = isset( $data['system_key'] ) ? (string) $data['system_key'] : '';

		if ( '' !== $key && self::has_system_key( $key ) ) {
			return;
		}

		self::insert( $data );
	}

	/**
	 * Czy istnieje regula o danym kluczu systemowym.
	 *
	 * @param string $system_key Klucz systemowy.
	 * @return bool
	 */
	private static function has_system_key( string $system_key ): bool {
		global $wpdb;

		$table = Tables::full( Tables::WORKFLOW_RULES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna przez Tables::full(), wartosc przez %s.
		$found = (int) $wpdb->get_var(
			$wpdb->prepare( "SELECT COUNT(*) FROM {$table} WHERE system_key = %s", $system_key )
		);
		// phpcs:enable

		return $found > 0;
	}
}
