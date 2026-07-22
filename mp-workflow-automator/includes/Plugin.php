<?php
/**
 * Rdzen pluginu MP Workflow Automator.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

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
	 * Rejestruje hooki startowe (i18n, upgrade-bez-reaktywacji; moduly domenowe dochodza w D5-D6).
	 *
	 * @return void
	 */
	public function boot(): void {
		add_action( 'init', array( $this, 'load_textdomain' ) );
		add_action( 'admin_init', array( Lifecycle::class, 'maybe_upgrade' ) );

		// Statusy wlasne (P3.2): D = zrodlo definicji => publikuje je do walidatora C.
		add_filter( 'mp_registered_statuses', array( StatusDefs::class, 'register_statuses' ) );

		// Silnik regul: nasluch triggerow C/B (P3.1 = auto-przydzial na case_created).
		RuleEngine::register();

		// Ksiega SLA (P3.4): wiersz terminu na created + przeliczenie przy zmianie statusu.
		Sla::register();

		// Sweep SLA (P3.4/SLA-2): cron 5-min — przypomnienia przed / eskalacje po terminie.
		Sweep::register();
	}

	/**
	 * Laduje tlumaczenia pluginu (na init — wymog WP 6.7+).
	 *
	 * @return void
	 */
	public function load_textdomain(): void {
		load_plugin_textdomain(
			'mp-workflow-automator',
			false,
			dirname( plugin_basename( MP_AUTOMATOR_FILE ) ) . '/languages'
		);
	}
}
