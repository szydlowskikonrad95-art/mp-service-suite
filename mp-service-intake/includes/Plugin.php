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
