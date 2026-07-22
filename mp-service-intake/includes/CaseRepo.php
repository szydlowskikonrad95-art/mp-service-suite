<?php
/**
 * Narodziny i weryfikacja sprawy (rdzen C — flow z rundy krytyki C).
 *
 * FLOW: zgloszenie -> sprawa `unverified` (status NULL, SRV nadany od razu,
 * snapshot gwarancji z chwili zgloszenia [NIESIE PARTIE], token jednorazowy
 * = tylko HASH w bazie, TTL 24h) -> klik magic-linka: ATOMOWE potwierdzenie
 * (status NULL->'nowe', identity verified) -> DOPIERO TERAZ event CASE_CREATED
 * + akcja mp_case_created (Automator NIGDY nie widzi niepotwierdzonych).
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Tworzenie i potwierdzanie spraw serwisowych.
 */
final class CaseRepo {

	/**
	 * Ile godzin zyje magic-link weryfikacji (kontrakt: 24h).
	 */
	public const TOKEN_TTL_HOURS = 24;

	/**
	 * Ile godzin od zgloszenia mozna jeszcze potwierdzic (symetryczne z cronem sierot).
	 */
	public const CONFIRM_WINDOW_HOURS = 72;

	/**
	 * Tworzy sprawe NIEPOTWIERDZONA (status NULL) i zwraca surowy token.
	 *
	 * WALIDACJA SYNCHRONICZNA PRZED insertem (P1.4): odmowa = zwrot bledow
	 * {field, reason_code}, NIC nie ldauje w bazie ani w osi czasu. Snapshot
	 * gwarancji: pelna zwrotka mp_warranty_check z chwili zgloszenia (niesie
	 * model, gwarancje ORAZ PARTIE — kartka linia 47). Bez serialu / bez
	 * modulu B: snapshot NULL (sprawa bez produktu jest dozwolona).
	 *
	 * @param array<string, mixed> $input kind, email, name, phone, values (mapa pol), country, lang.
	 * @return array{case_id: int, case_number: string, token: string}|array{error: string, validation?: array<int, array{field: string, reason_code: string}>}
	 */
	public static function create( array $input ): array {
		global $wpdb;

		$kind   = (string) ( $input['kind'] ?? '' );
		$email  = (string) ( $input['email'] ?? '' );
		$values = is_array( $input['values'] ?? null ) ? $input['values'] : array();
		$today  = gmdate( 'Y-m-d' );

		$errors = self::collect_validation_errors( $kind, $email, $values, $today );

		if ( array() !== $errors ) {
			return array(
				'error'      => __( 'Formularz zawiera błędy — popraw zaznaczone pola.', 'mp-service-intake' ),
				'validation' => $errors,
			);
		}

		$serial   = trim( (string) ( $values['serial'] ?? '' ) );
		$snapshot = self::build_snapshot( $serial );

		$token = wp_generate_password( 48, false, false );
		$now   = gmdate( 'Y-m-d H:i:s' );
		$year  = (int) gmdate( 'Y' );

		$product_id = null;

		if ( null !== $snapshot && ! empty( $snapshot['found'] ) ) {
			$product_id = (int) $snapshot['product_id'];
		}

		// Serial-reuse P2.3: ten sam produkt ma ZWERYFIKOWANA sprawe w 30 dni =>
		// flaga possible_duplicate dla operatora (FLAGA, nie blokada — inaczej niz
		// twardy dedup 15 min z RateLimit). Dotyczy tylko seriali w rejestrze.
		$possible_duplicate = ( null !== $product_id && self::has_recent_verified_case_for_product( $product_id ) ) ? 1 : 0;

		$table = Tables::full( Tables::CASES );

		// Retry na wypadek kolizji case_number (UNIQUE) albo verify_token_hash.
		for ( $attempt = 0; $attempt < 5; $attempt++ ) {
			$case_number = SrvCounter::next( $year );

			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna; INSERT-pod-UNIQUE (case_number/token) = pas bezpieczenstwa.
			$inserted = $wpdb->insert(
				$table,
				array(
					'case_number'                      => $case_number,
					'customer_id'                      => null,
					'product_registry_id'              => $product_id,
					'kind'                             => $kind,
					'status'                           => null,
					'identity_status'                  => 'pending',
					'verify_token_hash'                => self::hash_token( $token ),
					'verify_token_expires_at'          => gmdate( 'Y-m-d H:i:s', time() + self::TOKEN_TTL_HOURS * HOUR_IN_SECONDS ),
					'verify_token_used_at'             => null,
					'possible_duplicate'               => $possible_duplicate,
					'form_data'                        => (string) wp_json_encode( self::form_data_from_values( $kind, $values ) ),
					'form_schema_version'              => 1,
					'warranty_snapshot'                => null === $snapshot ? null : (string) wp_json_encode( $snapshot ),
					'warranty_snapshot_schema_version' => null === $snapshot ? null : (int) ( $snapshot['schema_version'] ?? 1 ),
					'priority'                         => 'normal',
					'country'                          => substr( (string) ( $input['country'] ?? '' ), 0, 2 ),
					'lang'                             => substr( (string) ( $input['lang'] ?? '' ), 0, 10 ),
					'created_at'                       => $now,
					'updated_at'                       => $now,
				)
			);
			// phpcs:enable

			if ( 1 === (int) $inserted ) {
				$case_id = (int) $wpdb->insert_id;

				self::stash_pending_contact( $case_id, $input );

				return array(
					'case_id'     => $case_id,
					'case_number' => $case_number,
					'token'       => $token,
				);
			}
		}

		return array( 'error' => __( 'Nie udało się nadać numeru sprawy — spróbuj ponownie.', 'mp-service-intake' ) );
	}

	/**
	 * Potwierdza sprawe magic-linkiem (ATOMOWO) i emituje narodziny.
	 *
	 * Warunek atomowy (wyscig cron-DELETE vs klik, double-POST): status NULL,
	 * token zywy i niezuzyty, w oknie potwierdzenia. rows=0 => nie da sie.
	 *
	 * @param string $token Surowy token z magic-linka.
	 * @return array{case_id: int, case_number: string}|array{error: string, expired?: bool}
	 */
	public static function verify( string $token ): array {
		global $wpdb;

		if ( '' === trim( $token ) ) {
			return array( 'error' => __( 'Brak tokenu weryfikacji.', 'mp-service-intake' ) );
		}

		$table  = Tables::full( Tables::CASES );
		$hash   = self::hash_token( $token );
		$now    = gmdate( 'Y-m-d H:i:s' );
		$cutoff = gmdate( 'Y-m-d H:i:s', time() - self::CONFIRM_WINDOW_HOURS * HOUR_IN_SECONDS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytania przygotowane; UPDATE-warunkowy = potwierdzenie atomowe.
		$claimed = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table}
				SET status = 'nowe', identity_status = 'verified', verify_token_used_at = %s,
					verified_at = %s, status_changed_at = %s, updated_at = %s
				WHERE verify_token_hash = %s
					AND status IS NULL
					AND verify_token_used_at IS NULL
					AND verify_token_expires_at >= %s
					AND created_at >= %s",
				$now,
				$now,
				$now,
				$now,
				$hash,
				$now,
				$cutoff
			)
		);

		if ( 1 !== (int) $claimed ) {
			// Rozroznienie: juz potwierdzona (idempotencja UX) vs wygasla/nieznana.
			$already = $wpdb->get_var(
				$wpdb->prepare(
					"SELECT id FROM {$table} WHERE verify_token_hash = %s AND identity_status = 'verified'",
					$hash
				)
			);
			// phpcs:enable

			if ( null !== $already ) {
				return array( 'error' => __( 'To zgłoszenie zostało już potwierdzone.', 'mp-service-intake' ) );
			}

			return array(
				'error'   => __( 'Link weryfikacyjny wygasł lub jest nieprawidłowy.', 'mp-service-intake' ),
				'expired' => true,
			);
		}

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT id, case_number, kind, product_registry_id FROM {$table} WHERE verify_token_hash = %s",
				$hash
			),
			ARRAY_A
		);
		// phpcs:enable

		if ( ! is_array( $row ) ) {
			return array( 'error' => __( 'Sprawa zniknęła w trakcie potwierdzania.', 'mp-service-intake' ) );
		}

		$case_id     = (int) $row['id'];
		$customer_id = self::attach_customer_on_verify( $case_id );

		if ( $customer_id > 0 && Consents::attach_case_to_customer( $case_id, $customer_id ) > 0 ) {
			// Event CONSENT_RECORDED tylko gdy realnie zebrano zgode (front); CLI/bez zgody = brak.
			CaseEvents::log( $case_id, CaseEvents::CONSENT_RECORDED, array( 'consent_key' => Consents::KEY_PROCESSING ), null );
		}

		// Narodziny sprawy: event + akcja DOPIERO TERAZ (Automator nie widzial sierot).
		CaseEvents::log(
			$case_id,
			CaseEvents::CASE_CREATED,
			array(
				'case_number'         => (string) $row['case_number'],
				'rodzaj'              => (string) $row['kind'],
				'product_registry_id' => null === $row['product_registry_id'] ? null : (int) $row['product_registry_id'],
			),
			null
		);

		do_action( 'mp_case_created', $case_id );

		return array(
			'case_id'     => $case_id,
			'case_number' => (string) $row['case_number'],
		);
	}

	/**
	 * Zbiera bledy walidacji zgloszenia (kind + email + pola wg schematu).
	 *
	 * Czysta orkiestracja walidatorow — testowana jednostkowo.
	 *
	 * @param string               $kind   Rodzaj sprawy.
	 * @param string               $email  E-mail kontaktowy.
	 * @param array<string, mixed> $values Wartosci pol.
	 * @param string               $today  Dzis 'Y-m-d' (UTC).
	 * @return array<int, array{field: string, reason_code: string}>
	 */
	public static function collect_validation_errors( string $kind, string $email, array $values, string $today ): array {
		$errors = array();

		if ( '' === trim( $email ) || ! Validator::is_email( trim( $email ) ) ) {
			$errors[] = array(
				'field'       => 'email',
				'reason_code' => 'INVALID_EMAIL',
			);
		}

		$flat = array();

		foreach ( $values as $key => $value ) {
			$flat[ (string) $key ] = is_scalar( $value ) ? (string) $value : '';
		}

		return array_merge( $errors, Validator::validate( $kind, $flat, $today ) );
	}

	/**
	 * Buduje form_data (klucz => {label z chwili zlozenia, value, pii_sensitive})
	 * z wartosci + schematu rodzaju. Etykieta i flaga PII BIORA SIE ZE SCHEMATU
	 * z chwili zlozenia -> render historyczny nie zalezy od biezacej mapy.
	 *
	 * @param string               $kind   Rodzaj sprawy.
	 * @param array<string, mixed> $values Wartosci pol.
	 * @return array<string, array{label: string, value: string, pii_sensitive: bool}>
	 */
	public static function form_data_from_values( string $kind, array $values ): array {
		$out = array();

		foreach ( FormConfig::fields_for( $kind ) as $field ) {
			$key   = $field['key'];
			$value = trim( (string) ( $values[ $key ] ?? '' ) );

			if ( '' === $value ) {
				continue;
			}

			$out[ $key ] = array(
				'label'         => $field['label'],
				'value'         => $value,
				'pii_sensitive' => $field['pii_sensitive'],
			);
		}

		return $out;
	}

	/**
	 * Statusy TERMINALNE (sprawa zamknieta — RODO nie odracza).
	 */
	public const TERMINAL_STATUSES = array( 'zamkniete', 'odrzucone' );

	/**
	 * Sprawy klienta: [id, case_number, status, kind] (panel/eksport/RODO).
	 *
	 * @param int $customer_id ID klienta.
	 * @return array<int, array<string, mixed>>
	 */
	public static function for_customer( int $customer_id ): array {
		global $wpdb;

		$table = Tables::full( Tables::CASES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT id, case_number, status, kind, form_data, created_at FROM {$table} WHERE customer_id = %d ORDER BY id DESC",
				$customer_id
			),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * Kontekst sprawy dla D (funkcja kontraktowa `mp_case_get_context`).
	 *
	 * Zwraca FAKTY do dopasowania regul i maili. `kontakt` = runtime do maili,
	 * NIGDY do logow (NO-PII-IN-LOG). `kategoria` = kategoria PRODUKTU z B
	 * (runtime-fetch przez filter `mp_product_category`; brak produktu / brak
	 * listenera B => null — frozen zasada: brak danej -> warunek NIE-PASUJE).
	 * Sprawa nieistniejaca / niezweryfikowana (D nie widzi sierot) => string
	 * `'not_found'` (kontrakt API-KONTRAKT.md sekcja C).
	 *
	 * @param int $case_id ID sprawy.
	 * @return array<string, mixed>|string Kontekst albo 'not_found'.
	 */
	public static function get_context( int $case_id ) {
		global $wpdb;

		$cases     = Tables::full( Tables::CASES );
		$customers = Tables::full( Tables::CUSTOMERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne, zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT c.status, c.kind, c.priority, c.assigned_to, c.product_registry_id,
					c.country, c.lang, c.verified_at, c.status_changed_at, c.case_number,
					c.rejection_reason_code,
					cu.email AS contact_email, cu.name AS contact_name,
					cu.phone AS contact_phone, cu.anonymized_at AS contact_anonymized_at
				FROM {$cases} c
				LEFT JOIN {$customers} cu ON cu.id = c.customer_id
				WHERE c.id = %d AND c.identity_status = 'verified'",
				$case_id
			),
			ARRAY_A
		);
		// phpcs:enable

		if ( null === $row ) {
			return 'not_found';
		}

		// kategoria = kategoria produktu z B (P1.2); brak produktu -> null.
		$kategoria = null;

		if ( ! empty( $row['product_registry_id'] ) ) {
			$fetched = apply_filters( 'mp_product_category', null, (int) $row['product_registry_id'] );

			if ( is_string( $fetched ) && '' !== $fetched ) {
				$kategoria = $fetched;
			}
		}

		$anonymized = ! empty( $row['contact_anonymized_at'] );

		return array(
			'status'                => (string) $row['status'],
			'rodzaj'                => (string) $row['kind'],
			'priority'              => (string) $row['priority'],
			'assigned_to'           => null !== $row['assigned_to'] ? (int) $row['assigned_to'] : null,
			'kategoria'             => $kategoria,
			'kraj'                  => (string) $row['country'],
			'jezyk'                 => (string) $row['lang'],
			'verified_at'           => $row['verified_at'],
			'status_changed_at'     => $row['status_changed_at'],
			'case_number'           => (string) $row['case_number'],
			'rejection_reason_code' => $row['rejection_reason_code'],
			'kontakt'               => $anonymized
				? array(
					'email' => '',
					'name'  => '',
					'phone' => '',
				)
				: array(
					'email' => (string) $row['contact_email'],
					'name'  => (string) $row['contact_name'],
					'phone' => (string) $row['contact_phone'],
				),
			'schema_version'        => 1,
		);
	}

	/**
	 * Przydziela sprawe pracownikowi (funkcja kontraktowa `mp_case_assign`).
	 *
	 * OWNERSHIP: `assigned_to` siedzi w tabeli C, wiec D przydziela WYLACZNIE tu
	 * (round-robin liczy D u siebie i WOLA te funkcje z wynikiem). Walidacja:
	 * przydzielany user ma cap personelu (mp_agent), sprawa istnieje i jest
	 * verified. UPDATE + event `CASE_ASSIGNED {from,to,actor}` w JEDNEJ transakcji.
	 *
	 * @param int $case_id  ID sprawy.
	 * @param int $user_id  Pracownik (musi miec cap mp_agent).
	 * @param int $actor_id Kto przydziela (system/koordynator).
	 * @return array<string, mixed> {success, ...} lub {success:false, error_code}.
	 */
	public static function assign( int $case_id, int $user_id, int $actor_id ): array {
		global $wpdb;

		if ( ! user_can( $user_id, 'mp_agent' ) ) {
			return array(
				'success'    => false,
				'error_code' => 'INVALID_ASSIGNEE',
			);
		}

		$cases = Tables::full( Tables::CASES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$wpdb->query( 'START TRANSACTION' );

		$row = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT assigned_to FROM {$cases} WHERE id = %d AND identity_status = 'verified' FOR UPDATE",
				$case_id
			),
			ARRAY_A
		);

		if ( null === $row ) {
			$wpdb->query( 'ROLLBACK' );
			// phpcs:enable

			return array(
				'success'    => false,
				'error_code' => 'CASE_NOT_FOUND',
			);
		}

		$from = null !== $row['assigned_to'] ? (int) $row['assigned_to'] : null;

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$cases} SET assigned_to = %d, updated_at = %s WHERE id = %d AND identity_status = 'verified'",
				$user_id,
				gmdate( 'Y-m-d H:i:s' ),
				$case_id
			)
		);

		CaseEvents::log(
			$case_id,
			CaseEvents::CASE_ASSIGNED,
			array(
				'from'  => $from,
				'to'    => $user_id,
				'actor' => $actor_id,
			),
			$actor_id
		);

		$wpdb->query( 'COMMIT' );
		// phpcs:enable

		return array(
			'success'     => true,
			'assigned_to' => $user_id,
			'from'        => $from,
		);
	}

	/**
	 * Zmienia status sprawy (funkcja kontraktowa `mp_case_change_status`).
	 *
	 * Walidacja wg STATE_MACHINE.md: status istnieje (rdzen 7 + filtr D),
	 * optimistic-lock (WHERE status = expected), wymogi specjalne:
	 * - wejscie w 'odrzucone' WYMAGA rejection_reason_code,
	 * - z terminalnego wolno WYLACZNIE REOPEN do 'w analizie',
	 * - miedzy nieterminalnymi: przejscia liberalne.
	 * UPDATE + event STATUS_CHANGED w JEDNEJ transakcji; akcja
	 * `mp_case_status_changed` emitowana PO COMMIT.
	 *
	 * @param int         $case_id                ID sprawy.
	 * @param string      $new_status             Docelowy status.
	 * @param string      $expected_status        Status oczekiwany (optimistic-lock).
	 * @param int         $actor_id               Kto zmienia.
	 * @param string|null $rejection_reason_code  Kod powodu (wymagany dla 'odrzucone').
	 * @return array<string, mixed> {success, from, to} lub {success:false, error_code}.
	 */
	public static function change_status( int $case_id, string $new_status, string $expected_status, int $actor_id, ?string $rejection_reason_code = null ): array {
		global $wpdb;

		if ( ! Statuses::exists( $new_status ) ) {
			return array(
				'success'    => false,
				'error_code' => 'INVALID_STATUS',
			);
		}

		$is_rejection = ( 'odrzucone' === $new_status );

		if ( $is_rejection && ( null === $rejection_reason_code || '' === trim( $rejection_reason_code ) ) ) {
			return array(
				'success'    => false,
				'error_code' => 'REJECTION_REASON_REQUIRED',
			);
		}

		$cases = Tables::full( Tables::CASES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$wpdb->query( 'START TRANSACTION' );

		$row = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT status FROM {$cases} WHERE id = %d AND identity_status = 'verified' FOR UPDATE",
				$case_id
			),
			ARRAY_A
		);

		if ( null === $row ) {
			$wpdb->query( 'ROLLBACK' );
			// phpcs:enable

			return array(
				'success'    => false,
				'error_code' => 'CASE_NOT_FOUND',
			);
		}

		$from = (string) $row['status'];

		// Optimistic-lock: ktos zmienil status w miedzyczasie.
		if ( $from !== $expected_status ) {
			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- rollback.
			$wpdb->query( 'ROLLBACK' );
			// phpcs:enable

			return array(
				'success'    => false,
				'error_code' => 'STATUS_CONFLICT',
				'current'    => $from,
			);
		}

		// Z terminalnego wolno WYLACZNIE reopen do 'w analizie' (STATE_MACHINE).
		if ( Statuses::is_terminal( $from ) && Statuses::REOPEN_TARGET !== $new_status ) {
			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- rollback.
			$wpdb->query( 'ROLLBACK' );
			// phpcs:enable

			return array(
				'success'    => false,
				'error_code' => 'INVALID_TRANSITION',
			);
		}

		$now = gmdate( 'Y-m-d H:i:s' );

		// rejection_reason_code trzymamy tylko gdy sprawa jest 'odrzucone'
		// (reopen/inne przejscie czysci — kolumna niesie POWOD BIEZACEGO odrzucenia).
		$reason = $is_rejection ? $rejection_reason_code : null;

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane; WHERE status=expected = optimistic-lock.
		$affected = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$cases} SET status = %s, rejection_reason_code = %s, status_changed_at = %s, updated_at = %s
				WHERE id = %d AND status = %s AND identity_status = 'verified'",
				$new_status,
				$reason,
				$now,
				$now,
				$case_id,
				$expected_status
			)
		);

		if ( 1 !== (int) $affected ) {
			$wpdb->query( 'ROLLBACK' );
			// phpcs:enable

			return array(
				'success'    => false,
				'error_code' => 'STATUS_CONFLICT',
			);
		}

		$payload = array(
			'from'  => $from,
			'to'    => $new_status,
			'actor' => $actor_id,
		);

		if ( $is_rejection ) {
			$payload['rejection_reason_code'] = $rejection_reason_code;
		}

		CaseEvents::log( $case_id, CaseEvents::STATUS_CHANGED, $payload, $actor_id );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- commit.
		$wpdb->query( 'COMMIT' );
		// phpcs:enable

		// Akcja PO COMMIT — sluchacze (D: SLA/reguly) dostaja spojny stan.
		do_action( 'mp_case_status_changed', $case_id, $from, $new_status, $actor_id );

		return array(
			'success' => true,
			'from'    => $from,
			'to'      => $new_status,
		);
	}

	/**
	 * Regeneruje token weryfikacji dla sprawy niepotwierdzonej (resend admina).
	 *
	 * KAZDY resend = swiezy token, stary uniewazniony (nadpisanie hasha). TYLKO
	 * sprawy `pending` (zweryfikowanej nie ruszamy). Zwraca surowy token albo null.
	 *
	 * @param int $case_id ID sprawy.
	 * @return string|null Surowy token do magic-linka albo null (nie pending).
	 */
	public static function regenerate_token( int $case_id ): ?string {
		global $wpdb;

		$table = Tables::full( Tables::CASES );
		$token = wp_generate_password( 48, false, false );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$affected = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table}
				SET verify_token_hash = %s, verify_token_expires_at = %s, verify_token_used_at = NULL, updated_at = %s
				WHERE id = %d AND identity_status = 'pending'",
				self::hash_token( $token ),
				gmdate( 'Y-m-d H:i:s', time() + self::TOKEN_TTL_HOURS * HOUR_IN_SECONDS ),
				gmdate( 'Y-m-d H:i:s' ),
				$case_id
			)
		);
		// phpcs:enable

		return 1 === (int) $affected ? $token : null;
	}

	/**
	 * Sprawy niepotwierdzone (admin — zarzadzanie unverified).
	 *
	 * @param int $limit Limit wierszy.
	 * @return array<int, array<string, mixed>>
	 */
	public static function unverified_cases( int $limit = 100 ): array {
		global $wpdb;

		$table = Tables::full( Tables::CASES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT id, case_number, kind, created_at, verify_token_expires_at
				FROM {$table} WHERE identity_status = 'pending' ORDER BY created_at DESC LIMIT %d",
				$limit
			),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * E-mail sprawy niepotwierdzonej (z zapamietanych danych kontaktowych).
	 *
	 * @param int $case_id ID sprawy.
	 * @return string
	 */
	public static function pending_email( int $case_id ): string {
		$pending = get_option( 'mp_pending_contact_' . $case_id, array() );

		return is_array( $pending ) ? (string) ( $pending['email'] ?? '' ) : '';
	}

	/**
	 * Poprawia e-mail sprawy niepotwierdzonej (admin: „popraw mail + resend").
	 *
	 * @param int    $case_id ID sprawy.
	 * @param string $email   Nowy e-mail.
	 * @return void
	 */
	public static function set_pending_email( int $case_id, string $email ): void {
		$pending = get_option( 'mp_pending_contact_' . $case_id, array() );

		if ( ! is_array( $pending ) ) {
			$pending = array();
		}

		$pending['email'] = sanitize_email( $email );
		update_option( 'mp_pending_contact_' . $case_id, $pending, false );
	}

	/**
	 * Serial-reuse P2.3: czy produkt ma ZWERYFIKOWANA sprawe w ostatnich 30 dniach.
	 *
	 * @param int $product_id ID produktu w rejestrze.
	 * @return bool
	 */
	private static function has_recent_verified_case_for_product( int $product_id ): bool {
		global $wpdb;

		$table  = Tables::full( Tables::CASES );
		$cutoff = gmdate( 'Y-m-d H:i:s', time() - 30 * DAY_IN_SECONDS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$count = (int) $wpdb->get_var(
			$wpdb->prepare(
				"SELECT COUNT(*) FROM {$table} WHERE product_registry_id = %d AND identity_status = 'verified' AND verified_at >= %s",
				$product_id,
				$cutoff
			)
		);
		// phpcs:enable

		return $count > 0;
	}

	/**
	 * Liczba ZWERYFIKOWANYCH spraw dla produktu (serial-reuse — admin/registry P2.3).
	 *
	 * @param int $product_id ID produktu w rejestrze.
	 * @return int
	 */
	public static function verified_case_count_for_product( int $product_id ): int {
		global $wpdb;

		$table = Tables::full( Tables::CASES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		return (int) $wpdb->get_var(
			$wpdb->prepare(
				"SELECT COUNT(*) FROM {$table} WHERE product_registry_id = %d AND identity_status = 'verified'",
				$product_id
			)
		);
		// phpcs:enable
	}

	/**
	 * Czy klient ma sprawe AKTYWNA (nie-terminalna) — RODO odracza EN BLOC.
	 *
	 * @param int $customer_id ID klienta.
	 * @return bool
	 */
	public static function has_active_case( int $customer_id ): bool {
		global $wpdb;

		$table    = Tables::full( Tables::CASES );
		$terminal = self::TERMINAL_STATUSES;
		$in       = implode( ',', array_fill( 0, count( $terminal ), '%s' ) );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared, WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare -- tabela wlasna; lista %s z count(), sprawa aktywna = status poza terminalnymi.
		$count = (int) $wpdb->get_var(
			$wpdb->prepare(
				"SELECT COUNT(*) FROM {$table} WHERE customer_id = %d AND ( status IS NULL OR status NOT IN ({$in}) )",
				array_merge( array( $customer_id ), $terminal )
			)
		);
		// phpcs:enable

		return $count > 0;
	}

	/**
	 * Redaguje wartosci pol pii_sensitive w form_data spraw (RODO).
	 *
	 * @param array<int> $case_ids Sprawy.
	 * @return int Liczba zredagowanych spraw.
	 */
	public static function redact_pii_for_cases( array $case_ids ): int {
		global $wpdb;

		$table   = Tables::full( Tables::CASES );
		$changed = 0;

		foreach ( $case_ids as $case_id ) {
			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
			$raw = $wpdb->get_var( $wpdb->prepare( "SELECT form_data FROM {$table} WHERE id = %d", (int) $case_id ) );
			// phpcs:enable

			$data = json_decode( (string) $raw, true );

			if ( ! is_array( $data ) ) {
				continue;
			}

			$data = self::redact_pii_fields( $data );

			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
			$wpdb->query(
				$wpdb->prepare(
					"UPDATE {$table} SET form_data = %s, updated_at = %s WHERE id = %d",
					(string) wp_json_encode( $data ),
					gmdate( 'Y-m-d H:i:s' ),
					(int) $case_id
				)
			);
			// phpcs:enable

			++$changed;
		}

		return $changed;
	}

	/**
	 * Zamienia wartosci pol pii_sensitive na marker (czysta funkcja).
	 *
	 * @param array<string, mixed> $form_data Mapa pol.
	 * @return array<string, mixed>
	 */
	public static function redact_pii_fields( array $form_data ): array {
		foreach ( $form_data as $key => $field ) {
			if ( is_array( $field ) && ! empty( $field['pii_sensitive'] ) ) {
				$form_data[ $key ]['value'] = Messages::REDACTED;
			}
		}

		return $form_data;
	}

	/**
	 * Buduje snapshot gwarancji z serialu (pelna zwrotka mp_warranty_check).
	 *
	 * @param string $serial Surowy numer seryjny (moze byc pusty).
	 * @return array<string, mixed>|null Null = brak serialu / brak modulu B.
	 */
	private static function build_snapshot( string $serial ): ?array {
		if ( '' === $serial ) {
			return null;
		}

		if ( ! has_filter( 'mp_warranty_check' ) ) {
			return null;
		}

		$snapshot = apply_filters( 'mp_warranty_check', null, $serial, null, null );

		return is_array( $snapshot ) ? $snapshot : null;
	}

	/**
	 * Normalizuje form_data do ksztaltu {klucz: {label, value, pii_sensitive}}.
	 *
	 * Czysta funkcja (testowana jednostkowo). Etykieta i wartosc z chwili
	 * zlozenia -> render historyczny NIE zalezy od biezacej mapy formularza.
	 *
	 * @param mixed $raw Dane z formularza (mapa klucz => {label,value,pii_sensitive}).
	 * @return array<string, array{label: string, value: string, pii_sensitive: bool}>
	 */
	public static function normalize_form_data( $raw ): array {
		if ( ! is_array( $raw ) ) {
			return array();
		}

		$out = array();

		foreach ( $raw as $key => $field ) {
			if ( ! is_array( $field ) ) {
				continue;
			}

			$out[ (string) $key ] = array(
				'label'         => (string) ( $field['label'] ?? $key ),
				'value'         => (string) ( $field['value'] ?? '' ),
				'pii_sensitive' => ! empty( $field['pii_sensitive'] ),
			);
		}

		return $out;
	}

	/**
	 * Haszuje token weryfikacji (w bazie WYLACZNIE hash).
	 *
	 * @param string $token Surowy token.
	 * @return string Hash heksadecymalny.
	 */
	private static function hash_token( string $token ): string {
		return hash( 'sha256', $token );
	}

	/**
	 * Zapamietuje dane kontaktowe niepotwierdzonej sprawy (do momentu weryfikacji).
	 *
	 * Trzymane w meta-opcji per sprawa (unverified NIE tworzy jeszcze klienta —
	 * takeover-safe). Sprzatane przy weryfikacji lub przez cron sierot.
	 *
	 * @param int                  $case_id ID sprawy.
	 * @param array<string, mixed> $input   Dane wejsciowe (email/name/phone).
	 * @return void
	 */
	private static function stash_pending_contact( int $case_id, array $input ): void {
		update_option(
			'mp_pending_contact_' . $case_id,
			array(
				'email' => sanitize_email( (string) ( $input['email'] ?? '' ) ),
				'name'  => sanitize_text_field( (string) ( $input['name'] ?? '' ) ),
				'phone' => sanitize_text_field( (string) ( $input['phone'] ?? '' ) ),
			),
			false
		);
	}

	/**
	 * Przy weryfikacji: tworzy/podpina klienta z zapamietanych danych kontaktowych.
	 *
	 * @param int $case_id ID sprawy.
	 * @return int ID klienta (0 gdy brak danych kontaktowych).
	 */
	private static function attach_customer_on_verify( int $case_id ): int {
		global $wpdb;

		$pending = get_option( 'mp_pending_contact_' . $case_id, array() );

		if ( ! is_array( $pending ) || '' === (string) ( $pending['email'] ?? '' ) ) {
			return 0;
		}

		$customer_id = Customers::upsert_by_email(
			(string) $pending['email'],
			(string) ( $pending['name'] ?? '' ),
			(string) ( $pending['phone'] ?? '' )
		);

		// Konto WP klienta DOPIERO teraz (panel „moje zgloszenia"; edge personel/admin — Accounts).
		Accounts::ensure_for_customer( $customer_id, (string) $pending['email'], (string) ( $pending['name'] ?? '' ) );

		$table = Tables::full( Tables::CASES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET customer_id = %d, updated_at = %s WHERE id = %d",
				$customer_id,
				gmdate( 'Y-m-d H:i:s' ),
				$case_id
			)
		);
		// phpcs:enable

		delete_option( 'mp_pending_contact_' . $case_id );

		return $customer_id;
	}
}
