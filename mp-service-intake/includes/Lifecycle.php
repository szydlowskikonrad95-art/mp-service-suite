<?php
/**
 * Cykl zycia pluginu MP Service Intake (aktywacja/deaktywacja).
 *
 * @package MP\Intake
 */

namespace MP\Intake;

use MP\Intake\Common\Roles;

/**
 * Aktywacja i deaktywacja pluginu.
 */
final class Lifecycle {

	/**
	 * Marker obecnosci modulu (wspolna mechanika uninstall — patrz Common\Uninstall).
	 */
	public const MODULE_MARKER = 'mp_module_intake';

	/**
	 * Opcja wersji schematu bazy (migracje startuja w D2).
	 */
	public const SCHEMA_OPTION = 'mp_intake_schema_version';

	/**
	 * Hak cron retencji zalacznikow (kasuje po retention_until).
	 */
	public const RETENTION_CRON = 'mp_intake_retention_sweep';

	/**
	 * Haki cron pluginu (czyszczone przy deaktywacji; lista rosnie z kodem).
	 *
	 * @var string[]
	 */
	public const CRON_HOOKS = array( self::RETENTION_CRON );

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
		Front\Frontend::ensure_page();
		Front\AccountPage::ensure_page();

		if ( ! wp_next_scheduled( self::RETENTION_CRON ) ) {
			wp_schedule_event( time() + HOUR_IN_SECONDS, 'daily', self::RETENTION_CRON );
		}

		if ( ! function_exists( 'finfo_open' ) ) {
			add_action( 'admin_notices', array( self::class, 'notice_missing_fileinfo' ) );
		}
	}

	/**
	 * Admin notice: brak ext-fileinfo (upload zalacznikow odmawia MIME po tresci).
	 *
	 * @return void
	 */
	public static function notice_missing_fileinfo(): void {
		echo '<div class="notice notice-error"><p>';
		echo esc_html__( 'MP Service Intake: brak rozszerzenia PHP „fileinfo" — załączniki nie będą przyjmowane (weryfikacja typu pliku po treści jest wymagana). Poproś administratora serwera o włączenie ext-fileinfo.', 'mp-service-intake' );
		echo '</p></div>';
	}

	/**
	 * Rejestruje hook crona retencji (na init — wolane z Plugin::boot).
	 *
	 * @return void
	 */
	public static function register_cron(): void {
		add_action(
			self::RETENTION_CRON,
			static function (): void {
				Attachments::run_retention_sweep();
			}
		);
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
