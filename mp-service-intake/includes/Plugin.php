<?php
/**
 * Rdzen pluginu MP Service Intake.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Pojedyncza instancja pluginu; rejestruje hooki na plugins_loaded.
 */
final class Plugin {

	/**
	 * Instancja singletona.
	 *
	 * @var Plugin|null
	 */
	private static ?Plugin $instance = null;

	/**
	 * Zwraca (tworzac w razie potrzeby) instancje pluginu.
	 *
	 * @return Plugin Instancja.
	 */
	public static function instance(): Plugin {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}

		return self::$instance;
	}

	/**
	 * Rejestruje hooki startowe (i18n; moduly domenowe dochodza w D5-D6).
	 *
	 * @return void
	 */
	public function boot(): void {
		add_action( 'init', array( $this, 'load_textdomain' ) );

		Front\Frontend::register();
		Front\SubmissionHandler::register();
		Front\AccountPage::register();
		Front\Login::register();
		Lifecycle::register_cron();
		Privacy::register();

		// Upgrade bez reaktywacji (WP updater podmienia pliki): odpal zalegle migracje.
		add_action( 'admin_init', array( Lifecycle::class, 'maybe_upgrade' ) );

		if ( is_admin() ) {
			Admin\UnverifiedScreen::register();
		}

		// Listener kontraktowy: wiadomosc systemowa od D (np. raport koncowy).
		add_filter(
			'mp_case_add_system_message',
			static function ( $result, $case_id, $content ) {
				unset( $result );

				return Messages::add_system_message( (int) $case_id, (string) $content );
			},
			10,
			3
		);

		// Kontrakt D->C: kontekst sprawy (fakty do regul/maili; 'not_found' gdy brak).
		add_filter(
			'mp_case_get_context',
			static function ( $result, $case_id ) {
				unset( $result );

				return CaseRepo::get_context( (int) $case_id );
			},
			10,
			2
		);

		// Kontrakt C->D (read-only): pelna lista statusow = rdzen 7 (nieusuwalny) +
		// wlasne z mp_registered_statuses. C = kanoniczne zrodlo (Statuses::all);
		// panel admina D konsumuje przez ten hook, bez siegania w klase C.
		add_filter(
			'mp_all_statuses',
			static function ( $result ) {
				unset( $result );

				return Statuses::all();
			}
		);

		// Kontrakt D->C: przydzial sprawy (assigned_to nalezy do C — D wola te funkcje).
		add_filter(
			'mp_case_assign',
			static function ( $result, $case_id, $user_id, $actor_id ) {
				unset( $result );

				return CaseRepo::assign( (int) $case_id, (int) $user_id, (int) $actor_id );
			},
			10,
			4
		);

		// Kontrakt D->C: zmiana statusu (walidacja STATE_MACHINE + optimistic-lock;
		// emituje mp_case_status_changed PO COMMIT). assigned_to/status naleza do C.
		add_filter(
			'mp_case_change_status',
			static function ( $result, $case_id, $new_status, $expected_status, $actor_id, $rejection_reason_code = null ) {
				unset( $result );

				return CaseRepo::change_status(
					(int) $case_id,
					(string) $new_status,
					(string) $expected_status,
					(int) $actor_id,
					null === $rejection_reason_code ? null : (string) $rejection_reason_code
				);
			},
			10,
			6
		);

		// Kontrakt D->C: paginowana lista spraw do RAPORTOW/EKSPORTU/RESYNC D
		// (mp_cases_query). Respektuje ROLE wolajacego (mp_agent => tylko swoje);
		// zwraca pola ZMINIMALIZOWANE — surowy kontakt NIGDY nie wychodzi (RODO/T5).
		add_filter(
			'mp_cases_query',
			static function ( $result, $filters = array(), $page = 1, $per_page = 500 ) {
				unset( $result );

				return CaseRepo::query(
					is_array( $filters ) ? $filters : array(),
					(int) $page,
					(int) $per_page
				);
			},
			10,
			4
		);

		// Kontrakt D->C: autoryzacja toggle checklisty (mp_case_checklist_authorize).
		// C egzekwuje WLASNOSC/ROLE + emituje CHECKLIST_ITEM_TOGGLED; PO OK D zapisuje
		// stan u siebie (case_checklists nalezy do D).
		add_filter(
			'mp_case_checklist_authorize',
			static function ( $result, $case_id, $step_key, $completed, $actor_id ) {
				unset( $result );

				return CaseRepo::checklist_authorize(
					(int) $case_id,
					(string) $step_key,
					(bool) $completed,
					(int) $actor_id
				);
			},
			10,
			5
		);

		// Kontrakt B->C: wyjatek gwarancyjny zmienil stan => wpis na osi sprawy
		// (kartka relacja 3: kazda decyzja tworzy wpis w osi czasu). B emituje
		// mp_warranty_exception_changed PO COMMIT (active/revoked). case_id=NULL =
		// wyjatek globalny na produkt (brak sprawy) => no-op (EVENT_MODEL.md). Flaga #11.
		add_action(
			'mp_warranty_exception_changed',
			static function ( $exception_id, $product_registry_id, $case_id, $state ) {
				unset( $product_registry_id );

				$case_id = (int) $case_id;

				if ( $case_id <= 0 ) {
					return; // wyjatek globalny — brak sprawy do opisania.
				}

				if ( 'active' === $state ) {
					$event_type = CaseEvents::EXCEPTION_APPLIED;
				} elseif ( 'revoked' === $state ) {
					$event_type = CaseEvents::EXCEPTION_REVOKED;
				} else {
					return; // nieznany stan — nie logujemy smieci na osi.
				}

				$actor_id = get_current_user_id();

				// Payload STRUKTURALNY {exception_id} — bez reason/PII (EVENT_MODEL.md).
				CaseEvents::log(
					$case_id,
					$event_type,
					array( 'exception_id' => (int) $exception_id ),
					$actor_id > 0 ? $actor_id : null
				);
			},
			10,
			4
		);

		// Kontrakt D->C: powiadomienie SLA (przypomnienie/eskalacja) tworzy wpis na
		// osi sprawy (kartka relacja 3). D emituje mp_sla_notified PO wyslaniu maila;
		// wzorzec 1:1 jak listener wyjatkow. NO-PII (kind + recipient_ref, bez adresu).
		add_action(
			'mp_sla_notified',
			static function ( $case_id, $kind, $recipient_ref ) {
				$case_id = (int) $case_id;

				if ( $case_id <= 0 ) {
					return;
				}

				if ( 'reminder' === $kind ) {
					$event_type = CaseEvents::SLA_REMINDER_SENT;
				} elseif ( 'escalation' === $kind ) {
					$event_type = CaseEvents::SLA_ESCALATED;
				} else {
					return; // nieznany rodzaj — nie logujemy smieci na osi.
				}

				CaseEvents::log(
					$case_id,
					$event_type,
					array(
						'kind'          => (string) $kind,
						'recipient_ref' => (string) $recipient_ref,
					),
					null
				);
			},
			10,
			3
		);

		// Pasek admina WP: ukryty klientowi (mp_client bez uprawnien personelu) —
		// klient nie ma po co widziec kokpitu WP; personel/admin widza dalej.
		add_filter(
			'show_admin_bar',
			static function ( $show ) {
				if ( is_user_logged_in() && Accounts::is_client_only( wp_get_current_user() ) ) {
					return false;
				}

				return $show;
			}
		);

		if ( defined( 'WP_CLI' ) && WP_CLI ) {
			Cli::register();
		}
	}

	/**
	 * Laduje tlumaczenia pluginu (na init — wymog WP 6.7+).
	 *
	 * @return void
	 */
	public function load_textdomain(): void {
		load_plugin_textdomain(
			'mp-service-intake',
			false,
			dirname( plugin_basename( MP_INTAKE_FILE ) ) . '/languages'
		);
	}
}
