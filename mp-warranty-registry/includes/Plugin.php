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
	 * Rejestruje hooki startowe: i18n + publiczne API Registry (API-KONTRAKT.md).
	 *
	 * @return void
	 */
	public function boot(): void {
		add_action( 'init', array( $this, 'load_textdomain' ) );
		add_filter( 'mp_warranty_check', array( WarrantyCheck::class, 'handle' ), 10, 4 );
		add_filter( 'mp_serial_usage_count', array( $this, 'serial_usage_count' ), 10, 2 );

		if ( is_admin() ) {
			Admin\ImportScreen::register();
			Admin\ImportEndpoints::register();
		}

		if ( defined( 'WP_CLI' ) && WP_CLI ) {
			Cli::register();
		}
	}

	/**
	 * Filtr mp_serial_usage_count — ile spraw uzywa serialu.
	 *
	 * Zasilany hookiem mp_case_count_by_product z C; bez C zwraca null
	 * ("brak danych", NIGDY zero — kontrakt karty B).
	 *
	 * @param mixed  $count  Wartosc wejsciowa filtra (ignorowana — B jest zrodlem).
	 * @param string $serial Surowy numer seryjny.
	 * @return int|null Liczba spraw lub null gdy brak zrodla danych.
	 */
	public function serial_usage_count( $count, string $serial ): ?int {
		$row = Repo::find_by_serial( $serial );

		if ( null === $row ) {
			return 0;
		}

		if ( ! has_filter( 'mp_case_count_by_product' ) ) {
			return null;
		}

		$counts = apply_filters( 'mp_case_count_by_product', null, (int) $row['id'] );

		return is_array( $counts ) ? (int) ( $counts['total'] ?? 0 ) : null;
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
