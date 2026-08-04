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
	 * Maks. liczba paczek na jeden przebieg (audyt #13): po dluzszym przestoju
	 * 5000 zaleglych spraw nadrabialo sie ~8 godzin (1 paczka / 5 min); teraz
	 * do 10 paczek na przebieg = zaleglosci schodza ~10x szybciej, a swiezy
	 * przebieg bez zaleglosci konczy po pierwszej niepelnej paczce.
	 */
	private const MAX_ROUNDS = 10;

	/**
	 * Limit ESKALACJI na runde — WIEKSZY niz BATCH, i to jest cala poprawka.
	 *
	 * Audyt 29.07: eskalacje szly ta sama paczka co przypomnienia (50), a prog
	 * „zbiorczego maila" (`Sla::DIGEST_THRESHOLD`) liczy sie na PRZEKAZANEJ LISCIE.
	 * Efekt: 500 zaleglych eskalacji = 10 rund x 50 = DZIESIEC osobnych „zbiorczych"
	 * maili do koordynatora w ciagu jednego przebiegu — dokladnie ta lawina, przed
	 * ktora digest mial chronic.
	 *
	 * Dlaczego wolno tu wiecej niz przy przypomnieniach: przypomnienie to JEDEN MAIL
	 * NA SPRAWE (dlatego pilnuje ich budzet MAIL_BUDGET), a eskalacja powyzej progu
	 * to JEDEN mail na cala liste. Wiekszy limit nie zwieksza wiec liczby wiadomosci —
	 * ZMNIEJSZA ja, scalajac wiecej spraw w jeden digest.
	 *
	 * BATCH * MAX_ROUNDS = tyle, ile przebieg i tak przerabial w 10 rundach, tylko teraz
	 * miesci sie w jednej. Powyzej tej liczby digestow bedzie wiecej niz jeden — to
	 * swiadomy sufit, nie przeoczenie (chroni pojedyncze zapytanie i dlugosc maila).
	 */
	private const ESCALATION_BATCH = self::BATCH * self::MAX_ROUNDS;

	/**
	 * Budzet MAILI na jeden przebieg (audyt kosztu 27.07).
	 *
	 * Same paczki tego nie ograniczaly: BATCH 50 x MAX_ROUNDS 10 to do 500
	 * wiadomosci wyslanych sekwencyjnie w JEDNYM zadaniu PHP. Zwykly hosting
	 * przepuszcza 200-500 maili na godzine, a 500 polaczen SMTP po ~0,3 s to
	 * kilka minut pracy — czyli takze realne ryzyko urwania przez limit czasu
	 * wykonania w polowie wysylki. Reszta poczeka na kolejny przebieg (5 minut);
	 * markery w tabeli terminow gwarantuja, ze nic nie przepadnie ani nie pojdzie
	 * dwa razy. Filtr pozwala hostingowi z wyzszym limitem podniesc prog.
	 */
	private const MAIL_BUDGET = 120;

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

			// Audyt 27.07: sprawy potwierdzone, gdy TA wtyczka byla wylaczona, maja
			// u siebie komplet sladow (C zapisal zdarzenie i wyemitowal akcje — tyle
			// ze nikt jej nie slyszal), wiec tick powyzej ich NIE dosle. Porownujemy
			// wiec wlasny stan z lista spraw C i doszywamy roznice.
			Sla::reconcile_untracked();

			$table = Tables::full( Tables::CASE_SLA );
			$now   = gmdate( 'Y-m-d H:i:s' );

			// Audyt #13: zaleglosci nadrabiane PETLA paczek (max MAX_ROUNDS na
			// przebieg) zamiast jednej paczki na 5 minut.
			$rounds  = 0;
			$sum_rem = 0;
			$sum_sup = 0;
			$sum_esc = 0;

			/**
			 * Budzet maili na przebieg (audyt kosztu 27.07) — hosting klienta ma
			 * swoj limit godzinowy, a jedno zadanie PHP swoj limit czasu.
			 *
			 * @param int $budget Domyslnie MAIL_BUDGET.
			 */
			$budzet_maili = (int) apply_filters( 'mp_sla_mail_budget', self::MAIL_BUDGET );
			$budzet_maili = max( 1, $budzet_maili );
			$przerwane    = false;

			do {
				++$rounds;

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

				$wyslane = 0;

				foreach ( $reminders as $case_id ) {
					if ( $sum_rem + $wyslane >= $budzet_maili ) {
						// Budzet wyczerpany: reszta ma marker NIETKNIETY, wiec kolejny
						// przebieg (za 5 minut) wezmie ja od tego samego miejsca.
						$przerwane = true;
						break;
					}

					Sla::notify( (int) $case_id, Sla::KIND_REMINDER );
					++$wyslane;
				}

				// TLUMIENIE flagi #8: sprawy po terminie z niewyslanym przypomnieniem —
				// zajmij marker reminder_sent_at BEZ maila i BEZ eventu osi C (dostana
				// eskalacje nizej, nie podwojne powiadomienie). Zamierzony rozjazd marker
				// (stan wewnetrzny) vs event (audyt) — patrz Sla::claim_suppressed_reminders.
				$suppressed = Sla::claim_suppressed_reminders();

				// ESKALACJE: termin minal, nieeskalowane. Masa (>DIGEST_THRESHOLD) => JEDEN
				// digest zamiast lawiny osobnych maili (SLA-3). Idempotencja przez escalated_at.
				//
				// Limit WLASNY (ESCALATION_BATCH), nie wspolny z przypomnieniami: prog digestu
				// liczy sie na przekazanej liscie, wiec ciecie po 50 dawalo 10 „zbiorczych"
				// maili zamiast jednego (audyt 29.07). Eskalacja powyzej progu to jeden mail
				// na cala liste, wiec wiekszy limit NIE zwieksza liczby wiadomosci.
				$escalations = $wpdb->get_col(
					$wpdb->prepare(
						"SELECT case_id FROM {$table}
						WHERE deadline_at IS NOT NULL AND deadline_at <= %s AND escalated_at IS NULL
						ORDER BY deadline_at ASC LIMIT %d",
						$now,
						self::ESCALATION_BATCH
					)
				);

				Sla::escalate( $escalations );

				$last_rem = count( $reminders );
				$last_esc = count( $escalations );

				// Liczymy REALNIE wyslane, nie znalezione — inaczej licznik w rejestrze
				// klamalby po przerwaniu budzetem (i zasugerowalby wyslanie maili,
				// ktore czekaja na nastepny przebieg).
				$sum_rem += $wyslane;
				$sum_sup += (int) $suppressed;
				$sum_esc += $last_esc;
				// Warunek kontynuacji per RODZAJ paczki — kazdy ma teraz swoj limit.
				// Porownanie eskalacji z BATCH byloby po zmianie limitu zwykla pomylka:
				// pelna paczka eskalacji to ESCALATION_BATCH, nie 50.
			} while ( ! $przerwane
				&& $rounds < self::MAX_ROUNDS
				&& ( self::BATCH === $last_rem || self::ESCALATION_BATCH === $last_esc ) );

			// 2.20: sprzatanie sierot NA KONIEC przebiegu, nigdy przed nim.
			// Pierwsza wersja wolala je na poczatku i kasowala wiersze, ZANIM
			// zamiatarka zdazyla je obsluzyc — licznik eskalacji zszedl ze 120 na 71
			// (zlapal to istniejacy test „jeden digest na przebieg"). Kolejnosc jest
			// tu czescia poprawnosci: najpierw robimy robote, potem sprzatamy.
			Sla::cleanup_orphans();

			WorkflowEvents::log(
				WorkflowEvents::SWEEP_RUN,
				array(
					'reminders'            => $sum_rem,
					'reminders_suppressed' => $sum_sup,
					'escalations'          => $sum_esc,
					'rounds'               => $rounds,
					'budzet_maili'         => $budzet_maili,
					'przerwany_budzetem'   => $przerwane ? 1 : 0,
				)
			);
		} finally {
			$wpdb->get_var( $wpdb->prepare( 'SELECT RELEASE_LOCK(%s)', self::LOCK ) );
		}
		// phpcs:enable
	}
}
