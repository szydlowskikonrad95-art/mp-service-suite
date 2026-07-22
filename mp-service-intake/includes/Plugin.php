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
