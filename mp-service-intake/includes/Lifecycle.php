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
	 * Upgrade bez reaktywacji (WP updater podmienia pliki, NIE reaktywuje).
	 *
	 * Wolane na admin_init; gated wersja schematu => odpala zalegle migracje
	 * RAZ po podniesieniu wtyczki, potem no-op. Idempotentne (Migrations::run
	 * i Roles::ensure same sie pilnuja). Bez tego update v0.2.0->v0.3.0 nie
	 * utworzylby tabel intake (schemat pojawil sie dopiero w C, po v0.2.0).
	 *
	 * @return void
	 */
	public static function maybe_upgrade(): void {
		// Cron POZA bramka wersji schematu (audyt cyklu zycia 27.07 — ta sama klasa
		// bledu co #103 w Automatorze, tam juz naprawiona, tu jeszcze nie byla).
		// Gdy schemat sie NIE zmienia, cala funkcja wychodzila w pierwszej linii —
		// wiec raz zniknietego zadania (migracja hostingu, wtyczka czyszczaca crony,
		// przywrocenie starszej kopii tabeli opcji) NIC by nie odtworzylo. A to
		// zadanie kasuje zalaczniki i porzucone zgloszenia RAZEM z danymi
		// kontaktowymi: jego cicha smierc = dane osobowe zostaja NA ZAWSZE (RODO).
		// wp_next_scheduled sprawia, ze wywolanie jest idempotentne i nic nie kosztuje.
		self::schedule_retention_cron();

		if ( (int) get_option( Schema::VERSION_OPTION, 0 ) >= Schema::LATEST ) {
			return;
		}

		Roles::ensure();
		Schema::migrate();
	}

	/**
	 * Planuje dzienny cron retencji, jesli go nie ma (idempotentne).
	 *
	 * @return void
	 */
	public static function schedule_retention_cron(): void {
		if ( ! wp_next_scheduled( self::RETENTION_CRON ) ) {
			wp_schedule_event( time() + HOUR_IN_SECONDS, 'daily', self::RETENTION_CRON );
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
				global $wpdb;

				// Audyt #12: zamek jak w sweepie SLA — dwa rownolegle przebiegi
				// retencji (cron + reczne wywolanie) nie danszuja na tych samych
				// plikach; drugi wychodzi od razu.
				// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- zamek procesu.
				$got = (int) $wpdb->get_var( $wpdb->prepare( 'SELECT GET_LOCK(%s, 0)', 'mp_intake_retention' ) );

				if ( 1 !== $got ) {
					return;
				}

				try {
					Attachments::run_retention_sweep();
					RateLimit::cleanup_expired();
					// RODO (audyt 27.07): porzucone zgloszenia niepotwierdzone
					// zostawaly w bazie RAZEM z danymi kontaktowymi na zawsze.
					CaseRepo::purge_abandoned_pending();
					// RODO (Z7): odroczone usuniecie danych po zamknieciu sprawy.
					// Panel obiecywal „dane usuniemy po zakonczeniu sprawy" —
					// ten przebieg jest wykonawca tej obietnicy.
					Privacy::run_deferred_erasures();
				} finally {
					$wpdb->get_var( $wpdb->prepare( 'SELECT RELEASE_LOCK(%s)', 'mp_intake_retention' ) );
					// phpcs:enable
				}
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
