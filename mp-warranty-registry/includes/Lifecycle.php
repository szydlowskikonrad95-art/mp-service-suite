<?php
/**
 * Cykl zycia pluginu MP Warranty & Serial Registry (aktywacja/deaktywacja).
 *
 * @package MP\Registry
 */

namespace MP\Registry;

use MP\Registry\Common\Roles;

/**
 * Aktywacja i deaktywacja pluginu.
 */
final class Lifecycle {

	/**
	 * Marker obecnosci modulu (wspolna mechanika uninstall — patrz Common\Uninstall).
	 */
	public const MODULE_MARKER = 'mp_module_registry';

	/**
	 * Opcja wersji schematu bazy (migracje startuja w D2).
	 */
	public const SCHEMA_OPTION = 'mp_registry_schema_version';

	/**
	 * Hak crona retencji plikow importu (D2 — kasuje sieroty w mp-imports/).
	 */
	public const IMPORTS_CRON = 'mp_registry_imports_sweep';

	/**
	 * Haki cron pluginu (czyszczone przy deaktywacji; lista rosnie z kodem).
	 *
	 * @var string[]
	 */
	public const CRON_HOOKS = array( self::IMPORTS_CRON );

	/**
	 * Aktywacja: role wspolne (idempotentnie), marker modulu, wersja schematu.
	 *
	 * @return void
	 */
	public static function activate(): void {
		Roles::ensure();

		if ( false === get_option( self::MODULE_MARKER, false ) ) {
			add_option( self::MODULE_MARKER, 1, '', false );
		}

		if ( false === get_option( self::SCHEMA_OPTION, false ) ) {
			add_option( self::SCHEMA_OPTION, '0', '', false );
		}

		Schema::migrate();
		self::schedule_imports_cron();
	}

	/**
	 * Planuje dobowy cron retencji plikow importu (idempotentnie).
	 *
	 * @return void
	 */
	private static function schedule_imports_cron(): void {
		if ( ! wp_next_scheduled( self::IMPORTS_CRON ) ) {
			wp_schedule_event( time() + HOUR_IN_SECONDS, 'daily', self::IMPORTS_CRON );
		}
	}

	/**
	 * Rejestruje handler crona retencji plikow importu (na boot).
	 *
	 * @return void
	 */
	public static function register_cron(): void {
		add_action(
			self::IMPORTS_CRON,
			static function (): void {
				global $wpdb;

				// Audyt #12: zamek jak w sweepie SLA — jeden przebieg sprzatania
				// plikow importu naraz; rownolegly wychodzi od razu.
				// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- zamek procesu.
				$got = (int) $wpdb->get_var( $wpdb->prepare( 'SELECT GET_LOCK(%s, 0)', 'mp_registry_imports_sweep' ) );

				if ( 1 !== $got ) {
					return;
				}

				try {
					Importer::sweep_import_files();
				} finally {
					$wpdb->get_var( $wpdb->prepare( 'SELECT RELEASE_LOCK(%s)', 'mp_registry_imports_sweep' ) );
					// phpcs:enable
				}
			}
		);
	}

	/**
	 * Migracja przy AKTUALIZACJI wtyczki (BEZ reaktywacji).
	 *
	 * Wolane na admin_init; gated wersja schematu => odpala zalegle migracje RAZ
	 * po podniesieniu wtyczki, potem no-op. Idempotentne (Migrations::run i
	 * Roles::ensure same sie pilnuja). Bez tego update dodajacy migracje (np.
	 * v1->v2 kolumna `category`) nie zastosowalby jej bez deaktywacji+aktywacji —
	 * schemat zostawalby stary i odczyty `SELECT category` sypalyby bledem.
	 * Spojnosc z Intake/Automator, ktore maja identyczny maybe_upgrade.
	 *
	 * @return void
	 */
	public static function maybe_upgrade(): void {
		if ( (int) get_option( self::SCHEMA_OPTION, 0 ) >= Schema::LATEST ) {
			return;
		}

		Roles::ensure();
		Schema::migrate();
		self::schedule_imports_cron();
	}

	/**
	 * Deaktywacja: wylacza crony pluginu; NICZEGO nie kasuje.
	 *
	 * @return void
	 */
	public static function deactivate(): void {
		foreach ( self::CRON_HOOKS as $hook ) {
			wp_clear_scheduled_hook( $hook );
		}
	}
}
