<?php
/**
 * Ksiega SLA (P3.4 / SLA-1): utrzymuje wiersz wp_mp_case_sla per sprawa
 * (deadline + markery) oraz atomowa jednostke powiadomienia SEND-THEN-CLAIM.
 *
 * Wiersz zakladany na mp_case_created (pierwszy termin od status_changed_at =
 * verified_at) i przeliczany na mp_case_status_changed (nowy termin, markery
 * wyzerowane, wersja polityki stemplowana). Terminalny status => deadline NULL.
 *
 * `notify()` = atomowa jednostka: RE-VERIFY -> mail -> SUKCES => marker; FALSE =>
 * attempts+1 (+MAIL_FAILED / po 3 MAIL_FAILED_FINAL). Sweep (SLA-2) tylko wybiera
 * wymagalne sprawy i wola notify() pod GET_LOCK.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Ksiegowanie SLA + powiadomienia terminowe.
 */
final class Sla {

	/**
	 * Rodzaj powiadomienia: przypomnienie przed deadline.
	 */
	public const KIND_REMINDER = 'reminder';

	/**
	 * Rodzaj powiadomienia: eskalacja po deadline.
	 */
	public const KIND_ESCALATION = 'escalation';

	/**
	 * Max prob wysylki zanim marker zostaje ustawiony na sile (+MAIL_FAILED_FINAL).
	 */
	private const MAX_ATTEMPTS = 3;

	/**
	 * Flaga alarmu dla admina (mail nie doszedl po MAX_ATTEMPTS) — panel pokaze notice.
	 */
	public const ALERT_OPTION = 'mp_automator_mail_alert';

	/**
	 * Rejestruje nasluchy ksiegi (wolane z Plugin::boot).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'mp_case_created', array( self::class, 'on_case_created' ), 20, 1 );
		add_action( 'mp_case_status_changed', array( self::class, 'on_status_changed' ), 20, 4 );
	}

	/**
	 * Narodziny sprawy => zaloz wiersz SLA (pierwszy termin od status_changed_at).
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	public static function on_case_created( $case_id ): void {
		self::provision( (int) $case_id );
	}

	/**
	 * Zmiana statusu => przelicz termin + WYZERUJ markery (swiezy zegar).
	 *
	 * @param int    $case_id    ID sprawy.
	 * @param string $old_status Poprzedni (nieuzywany).
	 * @param string $new_status Nowy (nieuzywany — bierzemy z kontekstu).
	 * @param int    $actor_id   Kto (nieuzywany).
	 * @return void
	 */
	public static function on_status_changed( $case_id, $old_status, $new_status, $actor_id ): void {
		unset( $old_status, $new_status, $actor_id );
		self::provision( (int) $case_id );
	}

	/**
	 * Zaklada/przelicza wiersz SLA dla sprawy (REPLACE = reset markerow przy zmianie).
	 * Sprawa zniknela/niezweryfikowana => nic (defensywa sweepa czysci sieroty w SLA-2/3).
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	private static function provision( int $case_id ): void {
		global $wpdb;

		$ctx = apply_filters( 'mp_case_get_context', 'not_found', $case_id );

		if ( ! is_array( $ctx ) ) {
			return;
		}

		$status   = isset( $ctx['status'] ) ? (string) $ctx['status'] : '';
		$priority = isset( $ctx['priority'] ) ? (string) $ctx['priority'] : 'normal';
		$base     = isset( $ctx['status_changed_at'] ) ? $ctx['status_changed_at'] : null;
		$deadline = SlaConfig::deadline_for( $status, is_string( $base ) ? $base : null, $priority );

		// Prog przypomnienia = deadline − warning_hours (SARGABLE dla sweepa SLA-2).
		$warning_at = null;

		if ( null !== $deadline ) {
			$warn_h = SlaConfig::for_status( $status )['warning_hours'];

			if ( $warn_h > 0 ) {
				$warning_at = gmdate( 'Y-m-d H:i:s', (int) strtotime( $deadline . ' UTC' ) - $warn_h * HOUR_IN_SECONDS );
			}
		}

		$table = Tables::full( Tables::CASE_SLA );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna; REPLACE = swiezy zegar (reset markerow), obsluguje NULL deadline.
		$wpdb->replace(
			$table,
			array(
				'case_id'             => $case_id,
				'status'              => $status,
				'sla_policy_version'  => SlaConfig::policy_version(),
				'deadline_at'         => $deadline,
				'warning_at'          => $warning_at,
				'reminder_sent_at'    => null,
				'escalated_at'        => null,
				'reminder_attempts'   => 0,
				'escalation_attempts' => 0,
				'updated_at'          => gmdate( 'Y-m-d H:i:s' ),
			),
			array( '%d', '%s', '%d', '%s', '%s', '%s', '%s', '%d', '%d', '%s' )
		);
		// phpcs:enable
	}

	/**
	 * Atomowa jednostka powiadomienia SEND-THEN-CLAIM (wolana przez sweep SLA-2 pod
	 * GET_LOCK). RE-VERIFY -> odbiorca -> mail -> SUKCES => marker (+ mp_sla_notified
	 * dla osi C) ; brak adresu => MAIL_SKIPPED + marker (nie retry) ; FALSE => attempts+1
	 * (MAIL_FAILED; po MAX_ATTEMPTS marker na sile + MAIL_FAILED_FINAL + alarm admina).
	 *
	 * @param int    $case_id ID sprawy.
	 * @param string $kind    KIND_REMINDER | KIND_ESCALATION.
	 * @return void
	 */
	public static function notify( int $case_id, string $kind ): void {
		$ctx = apply_filters( 'mp_case_get_context', 'not_found', $case_id );

		// Sprawa zniknela => nic (sweep wyczysci wiersz osobno).
		if ( ! is_array( $ctx ) ) {
			return;
		}

		$is_reminder = ( self::KIND_REMINDER === $kind );
		$template    = $is_reminder ? 'sla_reminder' : 'sla_escalation';

		$resolved = self::resolve_recipient( $kind, $ctx );
		$addr     = $resolved[0];
		$ref      = $resolved[1];

		if ( '' === $addr ) {
			// Brak odbiorcy (nieprzydzielona bez koordynatora) = stan legalny;
			// marker ustawiony => brak retry-spamu (admin skonfiguruje koordynatora).
			self::set_marker( $case_id, $kind );
			WorkflowEvents::log(
				WorkflowEvents::MAIL_SKIPPED_NO_RECIPIENT,
				array(
					'template_key'  => $template,
					'recipient_ref' => $ref,
				),
				$case_id
			);

			return;
		}

		$rendered = MailTemplates::render( $template, $ctx );

		if ( null === $rendered ) {
			self::set_marker( $case_id, $kind );
			WorkflowEvents::log(
				WorkflowEvents::MAIL_FAILED,
				array(
					'template_key' => $template,
					'error_code'   => 'template_missing',
				),
				$case_id
			);

			return;
		}

		$ok = Mailer::send( $addr, $rendered['subject'], $rendered['body'] );

		if ( $ok ) {
			// CLAIM po sukcesie (send-then-claim): marker + wpis na osi C + log D.
			self::set_marker( $case_id, $kind );
			do_action( 'mp_sla_notified', $case_id, $kind, $ref );
			WorkflowEvents::log(
				WorkflowEvents::RULE_EXECUTED,
				array(
					'rule_id'       => 0,
					'trigger'       => 'sla',
					'action'        => Rules::ACTION_NOTIFY,
					'template_key'  => $template,
					'recipient_ref' => $ref,
					'result'        => 'success',
					'depth'         => 0,
				),
				$case_id
			);

			return;
		}

		// FALSE = chwilowa awaria SMTP (normalna sciezka): attempts+1, retry nastepnym sweepem.
		$attempts = self::bump_attempts( $case_id, $kind );

		if ( $attempts >= self::MAX_ATTEMPTS ) {
			self::set_marker( $case_id, $kind );
			update_option( self::ALERT_OPTION, 1, false );
			WorkflowEvents::log(
				WorkflowEvents::MAIL_FAILED_FINAL,
				array(
					'template_key' => $template,
					'error_code'   => 'smtp_failed',
					'attempts'     => $attempts,
				),
				$case_id
			);

			return;
		}

		WorkflowEvents::log(
			WorkflowEvents::MAIL_FAILED,
			array(
				'template_key' => $template,
				'error_code'   => 'smtp_failed',
				'attempts'     => $attempts,
			),
			$case_id
		);
	}

	/**
	 * Odbiorca wg rodzaju: przypomnienie => przypisany agent (nieprzydzielona =>
	 * koordynator); eskalacja => koordynator. Zwraca [adres, recipient_ref=kategoria].
	 *
	 * @param string               $kind Rodzaj.
	 * @param array<string, mixed> $ctx  Kontekst sprawy.
	 * @return array{0: string, 1: string}
	 */
	private static function resolve_recipient( string $kind, array $ctx ): array {
		if ( self::KIND_REMINDER === $kind ) {
			$uid = isset( $ctx['assigned_to'] ) ? $ctx['assigned_to'] : null;

			if ( null !== $uid ) {
				$user = get_userdata( (int) $uid );

				if ( $user && '' !== (string) $user->user_email ) {
					// recipient_ref w stylu kontraktu (API-KONTRAKT mp_sla_notified): user:ID, NO-PII.
					return array( (string) $user->user_email, 'user:' . (int) $uid );
				}
			}
			// Nieprzydzielona / agent bez adresu => koordynator (fallback jak przy SLA).
		}

		return self::coordinator();
	}

	/**
	 * Pierwszy uzytkownik z rola mp_coordinator (albo '' => MAIL_SKIPPED).
	 *
	 * @return array{0: string, 1: string}
	 */
	private static function coordinator(): array {
		$users = get_users(
			array(
				'role'   => 'mp_coordinator',
				'number' => 1,
				'fields' => array( 'user_email' ),
			)
		);
		$email = ! empty( $users ) && isset( $users[0]->user_email ) ? (string) $users[0]->user_email : '';

		// recipient_ref w stylu kontraktu (API-KONTRAKT): role:mp_coordinator, NO-PII.
		return array( $email, 'role:mp_coordinator' );
	}

	/**
	 * Ustawia marker wyslania (reminder_sent_at / escalated_at = NOW WHERE IS NULL).
	 *
	 * @param int    $case_id ID sprawy.
	 * @param string $kind    Rodzaj.
	 * @return void
	 */
	private static function set_marker( int $case_id, string $kind ): void {
		global $wpdb;

		$col   = ( self::KIND_REMINDER === $kind ) ? 'reminder_sent_at' : 'escalated_at';
		$table = Tables::full( Tables::CASE_SLA );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; nazwa kolumny z zamknietej listy (nie z inputu).
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET {$col} = %s, updated_at = %s WHERE case_id = %d AND {$col} IS NULL",
				gmdate( 'Y-m-d H:i:s' ),
				gmdate( 'Y-m-d H:i:s' ),
				$case_id
			)
		);
		// phpcs:enable
	}

	/**
	 * Podbija licznik prob dla rodzaju i zwraca NOWA wartosc.
	 *
	 * @param int    $case_id ID sprawy.
	 * @param string $kind    Rodzaj.
	 * @return int
	 */
	private static function bump_attempts( int $case_id, string $kind ): int {
		global $wpdb;

		$col   = ( self::KIND_REMINDER === $kind ) ? 'reminder_attempts' : 'escalation_attempts';
		$table = Tables::full( Tables::CASE_SLA );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; nazwa kolumny z zamknietej listy.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET {$col} = {$col} + 1, updated_at = %s WHERE case_id = %d",
				gmdate( 'Y-m-d H:i:s' ),
				$case_id
			)
		);

		return (int) $wpdb->get_var(
			$wpdb->prepare( "SELECT {$col} FROM {$table} WHERE case_id = %d", $case_id )
		);
		// phpcs:enable
	}
}
