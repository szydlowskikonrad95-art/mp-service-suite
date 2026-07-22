<?php
/**
 * Cykl zycia pluginu MP Workflow Automator (aktywacja/deaktywacja).
 *
 * @package MP\Automator
 */

namespace MP\Automator;

use MP\Automator\Common\Roles;

/**
 * Aktywacja i deaktywacja pluginu.
 */
final class Lifecycle {

	/**
	 * Marker obecnosci modulu (wspolna mechanika uninstall — patrz Common\Uninstall).
	 */
	public const MODULE_MARKER = 'mp_module_automator';

	/**
	 * Opcja wersji schematu bazy (migracje startuja w D2).
	 */
	public const SCHEMA_OPTION = 'mp_automator_schema_version';

	/**
	 * Haki cron pluginu (czyszczone przy deaktywacji; lista rosnie z kodem).
	 *
	 * @var string[]
	 */
	public const CRON_HOOKS = array();

	/**
	 * Aktywacja: role wspolne (idempotentnie), marker modulu, migracje schematu.
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
	}

	/**
	 * Upgrade bez reaktywacji (WP updater podmienia pliki, NIE reaktywuje).
	 *
	 * Wolane na admin_init; gated wersja schematu => odpala zalegle migracje
	 * RAZ po podniesieniu wtyczki, potem no-op. Idempotentne (Migrations::run
	 * i Roles::ensure same sie pilnuja). Bez tego update nie utworzylby tabel D
	 * (schemat pojawil sie dopiero teraz, po v0.1.0-szkielecie).
	 *
	 * @return void
	 */
	public static function maybe_upgrade(): void {
		if ( (int) get_option( Schema::VERSION_OPTION, 0 ) >= Schema::LATEST ) {
			return;
		}

		Roles::ensure();
		Schema::migrate();
	}

	/**
	 * Deaktywacja: wylacza crony pluginu; NICZEGO nie kasuje.
	 *
	 * @return void
	 */
	public static function deactivate(): void {
		// @phpstan-ignore foreach.emptyArray (CRON_HOOKS puste do czasu pierwszego crona — D7-8)
		foreach ( self::CRON_HOOKS as $hook ) {
			wp_clear_scheduled_hook( $hook );
		}
	}
}
