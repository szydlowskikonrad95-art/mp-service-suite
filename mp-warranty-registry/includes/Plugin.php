<?php
/**
 * Rdzen pluginu MP Warranty & Serial Registry.
 *
 * @package MP\Registry
 */

namespace MP\Registry;

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
	}

	/**
	 * Laduje tlumaczenia pluginu (na init — wymog WP 6.7+).
	 *
	 * @return void
	 */
	public function load_textdomain(): void {
		load_plugin_textdomain(
			'mp-warranty-registry',
			false,
			dirname( plugin_basename( MP_REGISTRY_FILE ) ) . '/languages'
		);
	}
}
