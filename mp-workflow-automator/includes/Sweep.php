<?php
/**
 * Sweep SLA (P3.4 / SLA-2): cykliczny przebieg co 5 min, ktory wybiera sprawy
 * wymagalne (przypomnienie / eskalacja) i wola atomowa jednostke Sla::notify()
 * (send-then-claim). Jednorazowosc przebiegu = GET_LOCK; markery w tabeli daja
 * idempotencje (druga wysylka odsiana przez reminder_sent_at/escalated_at).
 *
 * Digest (>N eskalacji => jeden mail) + resync po reaktywacji = SLA-3.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Cron sweep terminow SLA.
 */
final class Sweep {

	/**
	 * Hak crona (czyszczony przy deaktywacji/uninstall).
	 */
	public const CRON_HOOK = 'mp_automator_sla_sweep';

	/**
	 * Nazwa wlasnego interwalu crona (5 minut).
	 */
	public const INTERVAL = 'mp_automator_5min';

	/**
	 * Nazwa zamka MySQL (jeden przebieg naraz w calej instalacji).
	 */
	private const LOCK = 'mp_sla_sweep';

	/**
	 * Limit spraw na jeden przebieg (paczka; konfigurowalny opcja w SLA-4).
	 */
	private const BATCH = 50;

	/**
	 * Rejestruje interwal + hak crona (wolane z Plugin::boot).
	 *
	 * @return void
	 */
	public static function register(): void {
		// phpcs:ignore WordPress.WP.CronInterval.ChangeDetected, WordPress.WP.CronInterval.CronSchedulesInterval -- 5-min interwal to WYMOG spec P3.4 (sweep SLA co 5 min); swiadoma decyzja, nie przypadek.
		add_filter( 'cron_schedules', array( self::class, 'add_interval' ) );
		add_action( self::CRON_HOOK, array( self::class, 'run' ) );
	}

	/**
	 * Dodaje 5-minutowy interwal do harmonogramow WP-Cron.
	 *
	 * @param array<string, array{interval: int, display: string}> $schedules Harmonogramy.
	 * @return array<string, array{interval: int, display: string}>
	 */
	public static function add_interval( $schedules ): array {
		if ( ! is_array( $schedules ) ) {
			$schedules = array();
		}

		$schedules[ self::INTERVAL ] = array(
			'interval' => 5 * MINUTE_IN_SECONDS,
			'display'  => __( 'Co 5 minut (MP SLA)', 'mp-workflow-automator' ),
		);

		return $schedules;
	}

	/**
	 * Planuje cron sweepa (idempotentnie — wolane z aktywacji/upgrade).
	 *
	 * @return void
	 */
	public static function schedule(): void {
		/*
		 * KOLEJNOSC MA ZNACZENIE (bug znaleziony 2026-07-26 przez diagnostyke
		 * Stanu witryny): aktywacja wtyczki odpala sie ZANIM `plugins_loaded`
		 * wykona `register()`, ktore dodaje nasz 5-minutowy interwal. Bez niego
		 * `wp_schedule_event()` odrzuca harmonogram jako nieznany i zwraca
		 * WP_Error — a poniewaz nikt tego nie sprawdzal, sweep SLA po prostu
		 * NIGDY sie nie planowal. Skutek: terminy, przypomnienia i eskalacje
		 * (P3.4) martwe, mimo ze system wyglada na sprawny.
		 *
		 * Dlatego filtr dokladamy tu defensywnie — `schedule()` ma dzialac
		 * niezaleznie od tego, czy plugin jest juz w pelni zaladowany.
		 */
		if ( ! has_filter( 'cron_schedules', array( self::class, 'add_interval' ) ) ) {
			// phpcs:ignore WordPress.WP.CronInterval.ChangeDetected, WordPress.WP.CronInterval.CronSchedulesInterval -- 5-min interwal to WYMOG spec P3.4.
			add_filter( 'cron_schedules', array( self::class, 'add_interval' ) );
		}

		if ( wp_next_scheduled( self::CRON_HOOK ) ) {
			return;
		}

		// Piaty argument `true` = zwroc WP_Error z POWODEM zamiast samego false.
		// Cicha porazka planowania oznacza martwe SLA, wiec chcemy znac przyczyne.
		$wynik = wp_schedule_event( time() + MINUTE_IN_SECONDS, self::INTERVAL, self::CRON_HOOK, array(), true );

		if ( is_wp_error( $wynik ) ) {
			error_log( // phpcs:ignore WordPress.PHP.DevelopmentFunctions.error_log_error_log
				'MP Automator: nie udalo sie zaplanowac sweepa SLA (' . self::CRON_HOOK . '): ' . $wynik->get_error_message()
			);
		}
	}

	/**
	 * Jeden przebieg sweepa: pod GET_LOCK wybiera wymagalne przypomnienia i
	 * eskalacje, wola Sla::notify() (send-then-claim). Drugi rownolegly proces
	 * wychodzi od razu (self-healing). Ksieguje SWEEP_RUN.
	 *
	 * @return void
	 */
	public static function run(): void {
		global $wpdb;

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- zamek procesu + tabela wlasna.
		$got = (int) $wpdb->get_var( $wpdb->prepare( 'SELECT GET_LOCK(%s, 0)', self::LOCK ) );

		if ( 1 !== $got ) {
			return; // inny przebieg trwa — wychodzimy (idempotencja przez lock).
		}

		try {
			/**
			 * Tick sweepa SLA (kontrakt, patrz API-KONTRAKT.md): odbiorcy moga
			 * doszyc zaleglosci ZANIM przebieg wybierze wymagalne terminy.
			 * Intake (C) uzywa go do reconcile spraw zweryfikowanych, ktorym
			 * awaria urwala zdarzenie narodzin (audyt #1) — doszyte sprawy
			 * dostaja SLA/przydzial natychmiast, terminy lapie kolejny przebieg.
			 */
			do_action( 'mp_sla_sweep_tick' );
			$table = Tables::full( Tables::CASE_SLA );
			$now   = gmdate( 'Y-m-d H:i:s' );

			// PRZYPOMNIENIA (mail): prog warning minal, niewyslane, ale termin JESZCZE
			// aktywny (deadline w PRZYSZLOSCI). Sprawy juz po terminie NIE dostaja
			// przypomnienia — i tak eskaluja (flaga #8); ich marker zajmuje krok nizej.
			$reminders = $wpdb->get_col(
				$wpdb->prepare(
					"SELECT case_id FROM {$table}
					WHERE deadline_at IS NOT NULL AND warning_at IS NOT NULL
						AND warning_at <= %s AND reminder_sent_at IS NULL AND deadline_at > %s
					ORDER BY warning_at ASC LIMIT %d",
					$now,
					$now,
					self::BATCH
				)
			);

			foreach ( $reminders as $case_id ) {
				Sla::notify( (int) $case_id, Sla::KIND_REMINDER );
			}

			// TLUMIENIE flagi #8: sprawy po terminie z niewyslanym przypomnieniem —
			// zajmij marker reminder_sent_at BEZ maila i BEZ eventu osi C (dostana
			// eskalacje nizej, nie podwojne powiadomienie). Zamierzony rozjazd marker
			// (stan wewnetrzny) vs event (audyt) — patrz Sla::claim_suppressed_reminders.
			$suppressed = Sla::claim_suppressed_reminders();

			// ESKALACJE: termin minal, nieeskalowane. Masa (>DIGEST_THRESHOLD) => JEDEN
			// digest zamiast lawiny osobnych maili (SLA-3). Idempotencja przez escalated_at.
			$escalations = $wpdb->get_col(
				$wpdb->prepare(
					"SELECT case_id FROM {$table}
					WHERE deadline_at IS NOT NULL AND deadline_at <= %s AND escalated_at IS NULL
					ORDER BY deadline_at ASC LIMIT %d",
					$now,
					self::BATCH
				)
			);

			Sla::escalate( $escalations );

			WorkflowEvents::log(
				WorkflowEvents::SWEEP_RUN,
				array(
					'reminders'            => count( $reminders ),
					'reminders_suppressed' => (int) $suppressed,
					'escalations'          => count( $escalations ),
				)
			);
		} finally {
			$wpdb->get_var( $wpdb->prepare( 'SELECT RELEASE_LOCK(%s)', self::LOCK ) );
		}
		// phpcs:enable
	}
}
