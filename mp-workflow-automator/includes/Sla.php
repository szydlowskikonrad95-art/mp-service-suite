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
	 * Prog digestu eskalacji (SLA-3, „bez lawiny"): gdy jeden sweep ma WIECEJ niz
	 * tyle wymagalnych eskalacji (reaktywacja / pierwsza instalacja / masa zaleglosci)
	 * — zamiast serii osobnych maili idzie JEDEN zbiorczy digest do koordynatora.
	 * Konfigurowalny opcja w SLA-4 (jak BATCH w Sweep).
	 */
	public const DIGEST_THRESHOLD = 5;

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

		// Kotwica + terminy z BIEZACEGO SlaConfig (wspolne z recompute_open — DRY
		// gwarantuje ze przeliczenie „Przelicz SLA" uzywa TEJ SAMEJ kotwicy co provision).
		$terms      = self::compute_terms( $ctx );
		$status     = $terms['status'];
		$deadline   = $terms['deadline'];
		$warning_at = $terms['warning'];

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
	 * Liczy terminy SLA z kontekstu sprawy wg BIEZACEGO SlaConfig: kotwica =
	 * status_changed_at (moment provision), deadline = kotwica + sla_hours×modyfikator,
	 * warning = deadline − warning_hours. Terminal / sla_hours=0 => deadline NULL.
	 * Wspolne dla provision() (REPLACE) i recompute_open() (UPDATE) — jedno zrodlo
	 * kotwicy (nieretroaktywnosc: przeliczenie liczy tak samo jak pierwsze zalozenie).
	 *
	 * @param array<string, mixed> $ctx Kontekst sprawy (mp_case_get_context).
	 * @return array{status: string, deadline: string|null, warning: string|null}
	 */
	private static function compute_terms( array $ctx ): array {
		$status   = isset( $ctx['status'] ) ? (string) $ctx['status'] : '';
		$priority = isset( $ctx['priority'] ) ? (string) $ctx['priority'] : 'normal';
		$base     = isset( $ctx['status_changed_at'] ) ? $ctx['status_changed_at'] : null;
		$deadline = SlaConfig::deadline_for( $status, is_string( $base ) ? $base : null, $priority );

		// Prog przypomnienia = deadline − warning_hours (SARGABLE dla sweepa SLA-2).
		$warning = null;

		if ( null !== $deadline ) {
			$warn_h = SlaConfig::for_status( $status )['warning_hours'];

			if ( $warn_h > 0 ) {
				$warning = gmdate( 'Y-m-d H:i:s', (int) strtotime( $deadline . ' UTC' ) - $warn_h * HOUR_IN_SECONDS );
			}
		}

		return array(
			'status'   => $status,
			'deadline' => $deadline,
			'warning'  => $warning,
		);
	}

	/**
	 * „PRZELICZ SLA" (SLA-4): dla WSZYSTKICH otwartych (nieterminalnych) spraw
	 * przelicza deadline_at/warning_at wg BIEZACEGO SlaConfig i stempluje wersje
	 * polityki. NIERETROAKTYWNOSC (twardy warunek):
	 *  - UPDATE (nie REPLACE) => markery reminder_sent_at/escalated_at + liczniki
	 *    attempts NIETKNIETE: etap juz przebyty NIE odpali ponownie (oś audytu bez
	 *    dubla; spojne z resync SLA-3).
	 *  - kotwica z compute_terms (status_changed_at) — nie „teraz wstecz".
	 *  - TERMINALNE sprawy pomijane w calosci.
	 *  - sprawa ktora PO przeliczeniu staje sie przeterminowana integruje sie ze
	 *    sweepem (flaga #8: tlumienie przypomnienia) => 1 powiadomienie, nie dubel.
	 * Iteruje WLASNA tabele case_sla (case_id) + kontekst per sprawa hookiem C —
	 * bez literalu cudzej tabeli. Zwraca liczbe DOTKNIETYCH (otwartych) spraw.
	 *
	 * @return int
	 */
	public static function recompute_open(): int {
		global $wpdb;

		$table = Tables::full( Tables::CASE_SLA );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; zbior case_id do przeliczenia.
		$case_ids = $wpdb->get_col( "SELECT case_id FROM {$table}" );
		// phpcs:enable

		$policy  = SlaConfig::policy_version();
		$now     = gmdate( 'Y-m-d H:i:s' );
		$touched = 0;

		foreach ( $case_ids as $cid ) {
			$cid = (int) $cid;
			$ctx = apply_filters( 'mp_case_get_context', 'not_found', $cid );

			// Sprawa zniknela => sierota; nie ruszamy (sweep sprzata osobno).
			if ( ! is_array( $ctx ) ) {
				continue;
			}

			$status = isset( $ctx['status'] ) ? (string) $ctx['status'] : '';

			// TERMINALNE (zamkniete/odrzucone) NIETKNIETE (twardy warunek odbioru).
			if ( SlaConfig::for_status( $status )['terminal'] ) {
				continue;
			}

			$terms = self::compute_terms( $ctx );

			// UPDATE: TYLKO terminy + wersja polityki + status + updated_at. Markery i
			// liczniki (reminder_sent_at/escalated_at/*_attempts) POZA setem => nietkniete.
			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna; obsluguje NULL deadline/warning.
			$wpdb->update(
				$table,
				array(
					'status'             => $terms['status'],
					'sla_policy_version' => $policy,
					'deadline_at'        => $terms['deadline'],
					'warning_at'         => $terms['warning'],
					'updated_at'         => $now,
				),
				array( 'case_id' => $cid ),
				array( '%s', '%d', '%s', '%s', '%s' ),
				array( '%d' )
			);
			// phpcs:enable

			++$touched;
		}

		return $touched;
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
			self::announce_sent( $case_id, $kind, $ref, $template );

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
	 * Wspolna galaz sukcesu wysylki (send-then-claim): marker + zdarzenie osi C
	 * (mp_sla_notified => SLA_*_SENT) + log D. Uzywana przez notify() (pojedynczo)
	 * i escalate_digest() (wsadowo) — os C ma byc identyczna w obu sciezkach.
	 *
	 * @param int    $case_id  ID sprawy.
	 * @param string $kind     Rodzaj.
	 * @param string $ref      recipient_ref (NO-PII).
	 * @param string $template template_key (do logu D).
	 * @return void
	 */
	private static function announce_sent( int $case_id, string $kind, string $ref, string $template ): void {
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
	}

	/**
	 * TLUMIENIE flagi #8 (SLA-3): sprawy JUZ po terminie (deadline_at<=NOW) z
	 * niewyslanym przypomnieniem i tak eskaluja — przypomnienie w tym samym sweepie
	 * byloby DRUGIM powiadomieniem. Zajmujemy marker reminder_sent_at (ksiegowosc
	 * wewnetrzna / idempotencja: kolejny sweep nie sprobuje przypomniec), ale BEZ
	 * maila i BEZ mp_sla_notified => ZERO SLA_REMINDER_SENT na osi C. Os C = audyt
	 * append-only (W3/RODO) i NIE moze klamac, ze przypomnienie poszlo. Marker =
	 * stan wewnetrzny, event = audyt zewnetrzny — rozjazd ZAMIERZONY. Zwraca liczbe
	 * zajetych markerow (SWEEP_RUN).
	 *
	 * @return int
	 */
	public static function claim_suppressed_reminders(): int {
		global $wpdb;

		$table = Tables::full( Tables::CASE_SLA );
		$now   = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; zbiorczy claim markera (bez maila/eventu).
		$affected = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET reminder_sent_at = %s, updated_at = %s
				WHERE deadline_at IS NOT NULL AND warning_at IS NOT NULL
					AND warning_at <= %s AND reminder_sent_at IS NULL AND deadline_at <= %s",
				$now,
				$now,
				$now,
				$now
			)
		);
		// phpcs:enable

		return (int) $affected;
	}

	/**
	 * Wysyla eskalacje dla zestawu spraw. Ponizej progu (DIGEST_THRESHOLD) — per
	 * sprawa (Sla::notify, pelny send-then-claim). Powyzej — JEDEN digest do
	 * koordynatora (SLA-3 „bez lawiny"): reaktywacja / pierwsza instalacja / masa
	 * zaleglosci nie wystrzeliwuje seria osobnych maili. Idempotentne (escalated_at).
	 *
	 * @param int[] $case_ids ID spraw wymagalnych do eskalacji.
	 * @return void
	 */
	public static function escalate( array $case_ids ): void {
		$case_ids = array_values( array_filter( array_map( 'intval', $case_ids ) ) );

		if ( empty( $case_ids ) ) {
			return;
		}

		if ( count( $case_ids ) <= self::DIGEST_THRESHOLD ) {
			foreach ( $case_ids as $cid ) {
				self::notify( $cid, self::KIND_ESCALATION );
			}

			return;
		}

		self::escalate_digest( $case_ids );
	}

	/**
	 * Jeden zbiorczy mail eskalacji do koordynatora dla MASY spraw po terminie
	 * (send-then-claim wsadowy): render digest -> 1 mail -> po sukcesie marker +
	 * os C (SLA_ESCALATED) per sprawa (kazda NAPRAWDE eskalowana, os mowi prawde).
	 * Brak koordynatora => marker + MAIL_SKIPPED per sprawa (bez retry-spamu). SMTP
	 * padl => attempts+1 per sprawa; po MAX_ATTEMPTS marker na sile + alarm admina
	 * (parytet ze sciezka pojedyncza), bez claimu retry nastepnym sweepem.
	 *
	 * @param int[] $case_ids ID spraw (>DIGEST_THRESHOLD).
	 * @return void
	 */
	private static function escalate_digest( array $case_ids ): void {
		// Re-verify: tylko istniejace sprawy w digescie (znikniete sprzata sweep osobno).
		$cases = array();

		foreach ( $case_ids as $cid ) {
			$ctx = apply_filters( 'mp_case_get_context', 'not_found', $cid );

			if ( is_array( $ctx ) ) {
				$number        = (string) ( $ctx['case_number'] ?? ( '#' . $cid ) );
				$cases[ $cid ] = Mailer::strip_crlf( $number );
			}
		}

		if ( empty( $cases ) ) {
			return;
		}

		$coord = self::coordinator();
		$addr  = $coord[0];
		$ref   = $coord[1];

		// Brak koordynatora = stan legalny: marker per sprawa (bez retry-spamu) + MAIL_SKIPPED.
		if ( '' === $addr ) {
			foreach ( array_keys( $cases ) as $cid ) {
				self::set_marker( $cid, self::KIND_ESCALATION );
				WorkflowEvents::log(
					WorkflowEvents::MAIL_SKIPPED_NO_RECIPIENT,
					array(
						'template_key'  => 'sla_escalation_digest',
						'recipient_ref' => $ref,
					),
					$cid
				);
			}

			return;
		}

		$rendered = self::render_digest( array_values( $cases ) );
		$ok       = Mailer::send( $addr, $rendered['subject'], $rendered['body'] );

		if ( $ok ) {
			// CLAIM wsadowy: kazda sprawa marker + SLA_ESCALATED na osi C (naprawde eskalowana).
			foreach ( array_keys( $cases ) as $cid ) {
				self::announce_sent( $cid, self::KIND_ESCALATION, $ref, 'sla_escalation_digest' );
			}

			return;
		}

		// SMTP padl: attempts+1 per sprawa; po MAX_ATTEMPTS marker na sile + alarm (parytet z notify()).
		foreach ( array_keys( $cases ) as $cid ) {
			$attempts = self::bump_attempts( $cid, self::KIND_ESCALATION );

			if ( $attempts >= self::MAX_ATTEMPTS ) {
				self::set_marker( $cid, self::KIND_ESCALATION );
				update_option( self::ALERT_OPTION, 1, false );
				WorkflowEvents::log(
					WorkflowEvents::MAIL_FAILED_FINAL,
					array(
						'template_key' => 'sla_escalation_digest',
						'error_code'   => 'smtp_failed',
						'attempts'     => $attempts,
					),
					$cid
				);
			}
		}

		WorkflowEvents::log(
			WorkflowEvents::MAIL_FAILED,
			array(
				'template_key' => 'sla_escalation_digest',
				'error_code'   => 'smtp_failed',
				'count'        => count( $cases ),
			)
		);
	}

	/**
	 * Sklada tresc digestu z szablonu sla_escalation_digest ({{liczba}}, {{lista}},
	 * {{data}}). Numery spraw juz po strip_crlf; temat single-line (podmienia tylko
	 * {{liczba}}=int, nigdy {{lista}} — brak CRLF w naglowku nawet gdy admin wklei
	 * {{lista}} do tematu).
	 *
	 * @param string[] $numbers Numery spraw (bezpieczne, strip_crlf).
	 * @return array{subject: string, body: string}
	 */
	private static function render_digest( array $numbers ): array {
		$tpl = MailTemplates::get( 'sla_escalation_digest' );

		// Defensywa: gdyby skasowano domyslny szablon (all() i tak bazuje na defaults()).
		if ( null === $tpl ) {
			$tpl = array(
				'subject' => 'ESKALACJA zbiorcza: {{liczba}} zgłoszeń po terminie',
				'body'    => "Dzień dobry,\n\nPo terminie ({{liczba}}):\n{{lista}}\n\nData: {{data}}",
			);
		}

		$lines = array();

		foreach ( $numbers as $n ) {
			$lines[] = '- ' . $n;
		}

		$map = array(
			'{{liczba}}' => (string) count( $numbers ),
			'{{lista}}'  => implode( "\n", $lines ),
			'{{data}}'   => (string) wp_date( 'Y-m-d H:i' ),
		);

		return array(
			'subject' => strtr( $tpl['subject'], array( '{{liczba}}' => $map['{{liczba}}'] ) ),
			'body'    => strtr( $tpl['body'], $map ),
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
