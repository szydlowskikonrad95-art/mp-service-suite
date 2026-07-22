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
		if ( ! wp_next_scheduled( self::CRON_HOOK ) ) {
			wp_schedule_event( time() + MINUTE_IN_SECONDS, self::INTERVAL, self::CRON_HOOK );
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
			$table = Tables::full( Tables::CASE_SLA );

			// PRZYPOMNIENIA: prog warning minal, jeszcze niewyslane, termin aktywny.
			$reminders = $wpdb->get_col(
				$wpdb->prepare(
					"SELECT case_id FROM {$table}
					WHERE deadline_at IS NOT NULL AND warning_at IS NOT NULL
						AND warning_at <= %s AND reminder_sent_at IS NULL
					ORDER BY warning_at ASC LIMIT %d",
					gmdate( 'Y-m-d H:i:s' ),
					self::BATCH
				)
			);

			foreach ( $reminders as $case_id ) {
				Sla::notify( (int) $case_id, Sla::KIND_REMINDER );
			}

			// ESKALACJE: termin minal, jeszcze nieeskalowane.
			$escalations = $wpdb->get_col(
				$wpdb->prepare(
					"SELECT case_id FROM {$table}
					WHERE deadline_at IS NOT NULL AND deadline_at <= %s AND escalated_at IS NULL
					ORDER BY deadline_at ASC LIMIT %d",
					gmdate( 'Y-m-d H:i:s' ),
					self::BATCH
				)
			);

			foreach ( $escalations as $case_id ) {
				Sla::notify( (int) $case_id, Sla::KIND_ESCALATION );
			}

			WorkflowEvents::log(
				WorkflowEvents::SWEEP_RUN,
				array(
					'reminders'   => count( $reminders ),
					'escalations' => count( $escalations ),
				)
			);
		} finally {
			$wpdb->get_var( $wpdb->prepare( 'SELECT RELEASE_LOCK(%s)', self::LOCK ) );
		}
		// phpcs:enable
	}
}
