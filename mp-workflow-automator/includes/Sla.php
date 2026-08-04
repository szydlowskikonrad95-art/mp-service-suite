<?php
/**
 * Ksiega SLA (P3.4 / SLA-1): utrzymuje wiersz wp_mp_case_sla per sprawa
 * (deadline + markery) oraz atomowa jednostke powiadomienia SEND-THEN-CLAIM.
 *
 * Wiersz zakladany na mp_case_created (pierwszy termin od status_changed_at =
 * verified_at) i przeliczany na mp_case_status_changed (nowy termin, markery
 * wyzerowane, wersja polityki stemplowana). Terminalny status => deadline NULL.
 *
 * `notify()` = atomowa jednostka: RE-VERIFY -> mail -> SUKCES => marker; FALSE =>
 * attempts+1 (+MAIL_FAILED / po 3 MAIL_FAILED_FINAL). Sweep (SLA-2) tylko wybiera
 * wymagalne sprawy i wola notify() pod GET_LOCK.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Ksiegowanie SLA + powiadomienia terminowe.
 */
final class Sla {

	/**
	 * Rodzaj powiadomienia: przypomnienie przed deadline.
	 */
	public const KIND_REMINDER = 'reminder';

	/**
	 * Rodzaj powiadomienia: eskalacja po deadline.
	 */
	public const KIND_ESCALATION = 'escalation';

	/**
	 * Max prob wysylki zanim marker zostaje ustawiony na sile (+MAIL_FAILED_FINAL).
	 *
	 * PUBLICZNA od 2.12: powiadomienia silnika regul ponawiaja sie tyle samo razy
	 * (`RuleEngine::deliver`). Dwie osobne liczby rozjechalyby sie przy pierwszej
	 * zmianie, a administrator widzialby dwa rozne zachowania tej samej poczty.
	 */
	public const MAX_ATTEMPTS = 3;

	/**
	 * Prog digestu eskalacji (SLA-3, „bez lawiny"): gdy jeden sweep ma WIECEJ niz
	 * tyle wymagalnych eskalacji (reaktywacja / pierwsza instalacja / masa zaleglosci)
	 * — zamiast serii osobnych maili idzie JEDEN zbiorczy digest do koordynatora.
	 * Konfigurowalny opcja w SLA-4 (jak BATCH w Sweep).
	 */
	public const DIGEST_THRESHOLD = 5;

	/**
	 * Flaga alarmu dla admina: mail nie doszedl po MAX_ATTEMPTS.
	 *
	 * Audyt 29.07: ta opcja byla ZAPISYWANA i nigdy nieodczytywana — komentarz obiecywal
	 * „panel pokaze notice", a nie pokazywal nic. Sprawa dostawala trwaly marker „wyslano"
	 * i NIGDY wiecej przypomnienia ani eskalacji, a admin nie mial o tym zadnego sygnalu.
	 * Bliźniacza wtyczka (Intake) miala ten sam wzorzec w komplecie: zapis, gaszenie po
	 * udanej wysylce i odczyt w Narzedzia -> Stan witryny. Ksztalt wartosci jest teraz
	 * TAKI SAM jak tam ({kind, time}), zeby diagnostyka mogla powiedziec CO i KIEDY padlo.
	 */
	public const ALERT_OPTION = 'mp_automator_mail_alert';

	/**
	 * Paczka przy przeliczaniu terminow (audyt kosztu 27.07 — bez tego jedno
	 * kliniecie „Przelicz SLA" przy 15 tys. spraw to ~30 tys. zapytan w jednym
	 * zadaniu PHP, czyli timeout w polowie roboty).
	 */
	private const RECALC_BATCH = 200;

	/**
	 * Hak dokanczania przeliczania w tle (czyszczony przy deaktywacji/uninstall).
	 */
	public const RECALC_CONTINUE_HOOK = 'mp_automator_sla_recalc_continue';

	/**
	 * Rejestruje nasluchy ksiegi (wolane z Plugin::boot).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'mp_case_created', array( self::class, 'on_case_created' ), 20, 1 );
		add_action( 'mp_case_status_changed', array( self::class, 'on_status_changed' ), 20, 4 );
		add_action( self::RECALC_CONTINUE_HOOK, array( self::class, 'continue_recompute' ), 10, 1 );
	}

	/**
	 * Narodziny sprawy => zaloz wiersz SLA (pierwszy termin od status_changed_at).
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	public static function on_case_created( $case_id ): void {
		self::provision( (int) $case_id );
	}

	/**
	 * Zmiana statusu => przelicz termin + WYZERUJ markery (swiezy zegar).
	 *
	 * @param int    $case_id    ID sprawy.
	 * @param string $old_status Poprzedni (nieuzywany).
	 * @param string $new_status Nowy (nieuzywany — bierzemy z kontekstu).
	 * @param int    $actor_id   Kto (nieuzywany).
	 * @return void
	 */
	public static function on_status_changed( $case_id, $old_status, $new_status, $actor_id ): void {
		unset( $old_status, $new_status, $actor_id );
		self::provision( (int) $case_id );
	}

	/**
	 * Okno ratunkowe w dniach — maksimum, jakie dopuszcza kontrakt modulu zgloszen.
	 *
	 * Sprawa bez wiersza terminow nigdy nie dostanie ani przydzialu, ani terminu,
	 * wiec im szersze okno, tym mniej takich spraw zostaje bez ratunku. Wezsze okno
	 * (30 dni) bylo wada 2.18: przy wiekszym ruchu najstarsze z niego wypadaly.
	 */
	private const RESCUE_DAYS = 365;

	/**
	 * Ile ID prosimy na jeden przebieg (maksimum kontraktu modulu zgloszen).
	 */
	private const RESCUE_LIMIT = 500;

	/**
	 * Kursor sprzatania sierot — do ktorego `case_id` doszlismy w tabeli terminow.
	 */
	public const ORPHAN_CURSOR_OPTION = 'mp_automator_orphan_cursor';

	/**
	 * Alarm: kontrakt sprawdzania spraw nie odpowiada, wiec NIE sprzatamy.
	 */
	public const ORPHAN_ALERT_OPTION = 'mp_automator_orphan_alert';

	/**
	 * Ile wierszy terminow sprawdzamy na jeden przebieg zamiatarki.
	 */
	private const ORPHAN_BATCH = 50;

	/**
	 * Ile „martwych" wierszy w paczce wystarczy, zeby podejrzewac awarie kontraktu.
	 */
	private const ORPHAN_SANITY_MIN = 5;

	/**
	 * Kasuje WIERSZE-SIEROTY w tabeli terminow (audyt 2.20).
	 *
	 * CZTERY komentarze w tym module zapowiadaly, ze osierocone wiersze posprzata
	 * zamiatarka („sweep sprzata osobno", „nie widzi sierot — nic nie robimy"),
	 * a w calym module nie bylo ANI JEDNEJ instrukcji kasowania poza czyszczeniem
	 * calej tabeli przy dezaktywacji. Wiersze po usunietych sprawach zostawaly
	 * w bazie bez konca. Obietnica z komentarza staje sie tu kodem.
	 *
	 * ⛔ DWA BEZPIECZNIKI, bo pomylka kasuje dane:
	 * 1. Brak zaczepu `mp_cases_existing_ids` = modul zgloszen nie odpowiada. Wtedy
	 *    KAZDY wiersz wygladalby na sierote — wychodzimy, nie ruszajac niczego.
	 * 2. Gdy w paczce NIC nie zyje, a martwych jest co najmniej kilka, to znacznie
	 *    bardziej prawdopodobne, ze padl kontrakt, niz ze wszystkie sprawy naraz
	 *    zniknely. Podnosimy alarm i NIE kasujemy.
	 *
	 * Kursor przesuwa sie po tabeli i zawija — inaczej zamiatarka w kolko badalaby
	 * ten sam poczatek tabeli, a sieroty lezace dalej nigdy nie trafilyby do paczki.
	 *
	 * @param int $limit Ile wierszy sprawdzic w tym przebiegu.
	 * @return int Liczba skasowanych wierszy.
	 */
	public static function cleanup_orphans( int $limit = self::ORPHAN_BATCH ): int {
		global $wpdb;

		// ⛔ Pytamy o ISTNIENIE sprawy, nie o to, czy widzimy jej kontekst. Kontekst
		// dostaja wylacznie sprawy zweryfikowane, wiec sprawa istniejaca, ale jeszcze
		// niepotwierdzona, wygladalaby stad jak nieistniejaca — i skasowalibysmy jej
		// wiersz terminow. Bez tego kontraktu NIE sprzatamy w ogole.
		if ( ! has_filter( 'mp_cases_existing_ids' ) ) {
			return 0;
		}

		$limit  = max( 1, min( 500, $limit ) );
		$table  = Tables::full( Tables::CASE_SLA );
		$kursor = (int) get_option( self::ORPHAN_CURSOR_OPTION, 0 );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$ids = $wpdb->get_col(
			$wpdb->prepare(
				"SELECT case_id FROM {$table} WHERE case_id > %d ORDER BY case_id ASC LIMIT %d",
				$kursor,
				$limit
			)
		);

		// Koniec tabeli — zawijamy i zaczynamy od poczatku przy nastepnym przebiegu.
		if ( array() === (array) $ids ) {
			if ( $kursor > 0 ) {
				update_option( self::ORPHAN_CURSOR_OPTION, 0, false );
			}

			return 0;
		}
		// phpcs:enable

		// JEDNO pytanie na cala paczke, nie jedno na wiersz. To ta sama klasa kosztu
		// co pozycja 2.22: zadanie cykliczne chodzace co piec minut nie moze skalowac
		// liczby zapytan z liczba sprawdzanych wierszy. Pytamy o ISTNIENIE sprawy —
		// sprawa niepotwierdzona istnieje, choc jej kontekstu stad nie widac.
		$ids      = array_map( 'intval', (array) $ids );
		$istnieja = array_flip( array_map( 'intval', (array) apply_filters( 'mp_cases_existing_ids', array(), $ids ) ) );
		$sieroty  = array();
		$zywe     = 0;

		foreach ( $ids as $case_id ) {
			if ( isset( $istnieja[ $case_id ] ) ) {
				++$zywe;

				continue;
			}

			$sieroty[] = $case_id;
		}

		update_option( self::ORPHAN_CURSOR_OPTION, (int) end( $ids ), false );

		if ( array() === $sieroty ) {
			if ( array() !== (array) get_option( self::ORPHAN_ALERT_OPTION, array() ) ) {
				delete_option( self::ORPHAN_ALERT_OPTION );
			}

			return 0;
		}

		// Bezpiecznik 2: cala paczka martwa => podejrzewamy kontrakt, nie dane.
		if ( 0 === $zywe && count( $sieroty ) >= self::ORPHAN_SANITY_MIN ) {
			update_option(
				self::ORPHAN_ALERT_OPTION,
				array(
					'powod' => 'kontrakt_nie_odpowiada',
					'ile'   => count( $sieroty ),
					'time'  => gmdate( 'Y-m-d H:i:s' ),
				),
				false
			);

			return 0;
		}

		$placeholders = implode( ', ', array_fill( 0, count( $sieroty ), '%d' ) );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared, WordPress.DB.PreparedSQLPlaceholders.ReplacementsWrongNumber, WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare -- tabela wlasna; liczba placeholderow ZMIENNA (tyle, ile sierot), wiec sniff nie policzy jej statycznie.
		$skasowane = (int) $wpdb->query(
			$wpdb->prepare( "DELETE FROM {$table} WHERE case_id IN ( {$placeholders} )", $sieroty )
		);
		// phpcs:enable

		if ( $skasowane > 0 ) {
			// JEDEN wpis zbiorczy na przebieg, nie jeden na wiersz — rejestry i tak
			// rosna bez retencji (osobna pozycja audytu), wiec nie dokladamy im halasu.
			WorkflowEvents::log(
				WorkflowEvents::SWEEP_RUN,
				array(
					'action' => 'cleanup_orphans',
					'ile'    => $skasowane,
				),
				null
			);
		}

		return $skasowane;
	}

	/**
	 * RESYNC: sprawy zweryfikowane, o ktorych Automator nic nie wie (audyt 27.07).
	 *
	 * Reconcile z audytu #1 rozpoznaje sieroty po BRAKU zdarzenia narodzin w C —
	 * i dlatego NIE widzi drugiego wariantu tej samej awarii: gdy w chwili
	 * potwierdzenia ta wtyczka byla WYLACZONA, C zapisal zdarzenie i wyemitowal
	 * akcje poprawnie, tylko nikt jej nie sluchal. Sprawa wyglada na kompletna,
	 * a nigdy nie dostanie przydzialu ani terminu — cicho, na zawsze.
	 * Tu porownujemy liste C z wlasna tabela terminow i doszywamy roznice.
	 *
	 * @param int $limit Maksymalna liczba spraw na jeden przebieg.
	 * @return int Liczba doszytych spraw.
	 */
	public static function reconcile_untracked( int $limit = 20 ): int {
		global $wpdb;

		// 2.18: NAJSTARSZE PIERWSZE i najszersze okno, jakie kontrakt dopuszcza.
		// Mechanizm ratunkowy istnieje wlasnie dla spraw czekajacych najdluzej, a pytal
		// o 200 NAJNOWSZYCH z 30 dni — czyli przy ruchu powyzej ~7 zgloszen dziennie
		// najstarsze sprawy w ogole nie trafialy do zapytania i po miesiacu wypadaly
		// z okna BEZPOWROTNIE. Kolejnosc prosimy JAWNIE: domyslne zachowanie kontraktu
		// (najnowsze pierwsze) zostaje nietkniete dla kazdego innego konsumenta.
		$ids = apply_filters( 'mp_cases_verified_ids', array(), self::RESCUE_DAYS, self::RESCUE_LIMIT, 'ASC' );

		if ( ! is_array( $ids ) || array() === $ids ) {
			return 0;
		}

		$table = Tables::full( Tables::CASE_SLA );
		$ids   = array_values( array_unique( array_map( 'intval', $ids ) ) );

		// Ktore z nich JUZ znamy — JEDNYM zapytaniem, nie jednym na sprawe. Przy
		// szerszym oknie pytanie per sprawa oznaczaloby 500 zapytan na przebieg
		// zamiatarki (osobna pozycja audytu mowi wlasnie o zapytaniach w petli).
		$placeholders = implode( ', ', array_fill( 0, count( $ids ), '%d' ) );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared, WordPress.DB.PreparedSQLPlaceholders.ReplacementsWrongNumber, WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare -- tabela wlasna; liczba placeholderow ZMIENNA (tyle, ile ID).
		$znane_ids = (array) $wpdb->get_col(
			$wpdb->prepare( "SELECT case_id FROM {$table} WHERE case_id IN ( {$placeholders} )", $ids )
		);
		// phpcs:enable

		$znane_ids = array_flip( array_map( 'intval', $znane_ids ) );
		$doszyte   = 0;

		foreach ( $ids as $case_id ) {
			if ( $doszyte >= $limit ) {
				break;
			}

			$case_id = (int) $case_id;

			if ( isset( $znane_ids[ $case_id ] ) ) {
				continue;
			}

			// Sprawa nieznana => przejdz sciezke narodzin w TEJ SAMEJ kolejnosci co
			// przy zywym zdarzeniu: reguly (priorytet, potem przydzial) na haku 10,
			// termin na haku 20 — inaczej pierwszy termin policzylby sie przed
			// nadaniem priorytetu i wyszedlby inny niz u spraw obsluzonych normalnie.
			RuleEngine::on_case_created( $case_id );
			self::provision( $case_id );

			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, weryfikacja skutku.
			$po = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$table} WHERE case_id = %d", $case_id ) );
			// phpcs:enable

			if ( 0 === $po ) {
				continue; // sprawa zniknela/niezweryfikowana — nie nasza robota.
			}

			++$doszyte;

			WorkflowEvents::log(
				WorkflowEvents::SWEEP_RUN,
				array(
					'action' => 'resync_untracked',
					'powod'  => 'sprawa_bez_terminu',
				),
				$case_id
			);
		}

		return $doszyte;
	}

	/**
	 * Zaklada/przelicza wiersz SLA dla sprawy (REPLACE = reset markerow przy zmianie).
	 * Sprawa zniknela/niezweryfikowana => nic (defensywa sweepa czysci sieroty w SLA-2/3).
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	private static function provision( int $case_id ): void {
		global $wpdb;

		$ctx = apply_filters( 'mp_case_get_context', 'not_found', $case_id );

		if ( ! is_array( $ctx ) ) {
			return;
		}

		// Kotwica + terminy z BIEZACEGO SlaConfig (wspolne z recompute_open — DRY
		// gwarantuje ze przeliczenie „Przelicz SLA" uzywa TEJ SAMEJ kotwicy co provision).
		$terms      = self::compute_terms( $ctx );
		$status     = $terms['status'];
		$deadline   = $terms['deadline'];
		$warning_at = $terms['warning'];

		$table = Tables::full( Tables::CASE_SLA );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna; REPLACE = swiezy zegar (reset markerow), obsluguje NULL deadline.
		$wpdb->replace(
			$table,
			array(
				'case_id'             => $case_id,
				'status'              => $status,
				'sla_policy_version'  => SlaConfig::policy_version(),
				'deadline_at'         => $deadline,
				'warning_at'          => $warning_at,
				'reminder_sent_at'    => null,
				'escalated_at'        => null,
				'reminder_attempts'   => 0,
				'escalation_attempts' => 0,
				'updated_at'          => gmdate( 'Y-m-d H:i:s' ),
			),
			array( '%d', '%s', '%d', '%s', '%s', '%s', '%s', '%d', '%d', '%s' )
		);
		// phpcs:enable
	}

	/**
	 * Liczy terminy SLA z kontekstu sprawy wg BIEZACEGO SlaConfig: kotwica =
	 * status_changed_at (moment provision), deadline = kotwica + sla_hours×modyfikator,
	 * warning = deadline − warning_hours. Terminal / sla_hours=0 => deadline NULL.
	 * Wspolne dla provision() (REPLACE) i recompute_open() (UPDATE) — jedno zrodlo
	 * kotwicy (nieretroaktywnosc: przeliczenie liczy tak samo jak pierwsze zalozenie).
	 *
	 * @param array<string, mixed> $ctx Kontekst sprawy (mp_case_get_context).
	 * @return array{status: string, deadline: string|null, warning: string|null}
	 */
	private static function compute_terms( array $ctx ): array {
		$status   = isset( $ctx['status'] ) ? (string) $ctx['status'] : '';
		$priority = isset( $ctx['priority'] ) ? (string) $ctx['priority'] : 'normal';
		$base     = isset( $ctx['status_changed_at'] ) ? $ctx['status_changed_at'] : null;
		$deadline = SlaConfig::deadline_for( $status, is_string( $base ) ? $base : null, $priority );

		// Prog przypomnienia = deadline − warning_hours (SARGABLE dla sweepa SLA-2).
		$warning = null;

		if ( null !== $deadline ) {
			$warn_h = SlaConfig::for_status( $status )['warning_hours'];

			if ( $warn_h > 0 ) {
				$warning = gmdate( 'Y-m-d H:i:s', (int) strtotime( $deadline . ' UTC' ) - $warn_h * HOUR_IN_SECONDS );
			}
		}

		return array(
			'status'   => $status,
			'deadline' => $deadline,
			'warning'  => $warning,
		);
	}

	/**
	 * „PRZELICZ SLA" (SLA-4): dla WSZYSTKICH otwartych (nieterminalnych) spraw
	 * przelicza deadline_at/warning_at wg BIEZACEGO SlaConfig i stempluje wersje
	 * polityki. NIERETROAKTYWNOSC (twardy warunek):
	 *  - UPDATE (nie REPLACE) => markery reminder_sent_at/escalated_at + liczniki
	 *    attempts NIETKNIETE: etap juz przebyty NIE odpali ponownie (oś audytu bez
	 *    dubla; spojne z resync SLA-3).
	 *  - kotwica z compute_terms (status_changed_at) — nie „teraz wstecz".
	 *  - TERMINALNE sprawy pomijane w calosci.
	 *  - sprawa ktora PO przeliczeniu staje sie przeterminowana integruje sie ze
	 *    sweepem (flaga #8: tlumienie przypomnienia) => 1 powiadomienie, nie dubel.
	 * Iteruje WLASNA tabele case_sla (case_id) + kontekst per sprawa hookiem C —
	 * bez literalu cudzej tabeli. Zwraca liczbe DOTKNIETYCH (otwartych) spraw.
	 * Pracuje PACZKAMI: pelna paczka planuje dokanczanie w tle (audyt kosztu 27.07).
	 *
	 * @param int $after_id Przelicza sprawy o case_id WIEKSZYM niz podany (paginacja).
	 * @param int $limit    Rozmiar paczki (0 = RECALC_BATCH).
	 * @return int
	 */
	public static function recompute_open( int $after_id = 0, int $limit = 0 ): int {
		global $wpdb;

		$table = Tables::full( Tables::CASE_SLA );
		$limit = $limit > 0 ? $limit : self::RECALC_BATCH;

		// Audyt kosztu 27.07: dotad zapytanie szlo BEZ LIMIT, a potem leciala petla
		// z zapytaniem kontekstu i UPDATE-em na KAZDY wiersz. Przy 15 tys. spraw
		// (skala po ~2 latach) jedno kliniecie „Przelicz SLA" to ~30 tys. zapytan
		// w jednym zadaniu PHP — na wspoldzielonym hostingu pewny timeout, w dodatku
		// w POLOWIE przeliczania. Teraz paczka + dokanczanie w tle.
		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; zbior case_id do przeliczenia.
		$case_ids = $wpdb->get_col(
			$wpdb->prepare(
				"SELECT case_id FROM {$table} WHERE case_id > %d ORDER BY case_id ASC LIMIT %d",
				$after_id,
				$limit
			)
		);
		// phpcs:enable

		$policy  = SlaConfig::policy_version();
		$now     = gmdate( 'Y-m-d H:i:s' );
		$touched = 0;
		$last_id = $after_id;

		foreach ( $case_ids as $cid ) {
			$cid     = (int) $cid;
			$last_id = $cid;
			$ctx     = apply_filters( 'mp_case_get_context', 'not_found', $cid );

			// Sprawa zniknela => sierota; nie ruszamy (sweep sprzata osobno).
			if ( ! is_array( $ctx ) ) {
				continue;
			}

			$status = isset( $ctx['status'] ) ? (string) $ctx['status'] : '';

			// TERMINALNE (zamkniete/odrzucone) NIETKNIETE (twardy warunek odbioru).
			if ( SlaConfig::for_status( $status )['terminal'] ) {
				continue;
			}

			$terms = self::compute_terms( $ctx );

			// UPDATE: TYLKO terminy + wersja polityki + status + updated_at. Markery i
			// liczniki (reminder_sent_at/escalated_at/*_attempts) POZA setem => nietkniete.
			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna; obsluguje NULL deadline/warning.
			$wpdb->update(
				$table,
				array(
					'status'             => $terms['status'],
					'sla_policy_version' => $policy,
					'deadline_at'        => $terms['deadline'],
					'warning_at'         => $terms['warning'],
					'updated_at'         => $now,
				),
				array( 'case_id' => $cid ),
				array( '%s', '%d', '%s', '%s', '%s' ),
				array( '%d' )
			);
			// phpcs:enable

			++$touched;
		}

		// Paczka pelna => sa jeszcze sprawy do przeliczenia. Dokanczamy w tle, zamiast
		// trzymac zadanie admina otwarte az do timeoutu. Zdarzenie jednorazowe za
		// minute; przy braku WP-Crona nadrobi to i tak najblizszy przebieg sweepa
		// (przeliczenie jest idempotentne — markery i liczniki poza setem UPDATE).
		if ( count( $case_ids ) >= $limit && $last_id > $after_id ) {
			if ( ! wp_next_scheduled( self::RECALC_CONTINUE_HOOK, array( $last_id ) ) ) {
				wp_schedule_single_event( time() + MINUTE_IN_SECONDS, self::RECALC_CONTINUE_HOOK, array( $last_id ) );
			}
		}

		return $touched;
	}

	/**
	 * Dokanczanie przeliczania SLA w tle (kolejna paczka po ostatnim ID).
	 *
	 * @param int $after_id Ostatnie przeliczone case_id.
	 * @return void
	 */
	public static function continue_recompute( $after_id = 0 ): void {
		$touched = self::recompute_open( (int) $after_id );

		WorkflowEvents::log(
			WorkflowEvents::SLA_RECALCULATED,
			array(
				'cases_touched' => $touched,
				'tryb'          => 'dokanczanie_w_tle',
				'po_id'         => (int) $after_id,
			)
		);
	}

	/**
	 * Atomowa jednostka powiadomienia SEND-THEN-CLAIM (wolana przez sweep SLA-2 pod
	 * GET_LOCK). RE-VERIFY -> odbiorca -> mail -> SUKCES => marker (+ mp_sla_notified
	 * dla osi C) ; brak adresu => MAIL_SKIPPED + marker (nie retry) ; FALSE => attempts+1
	 * (MAIL_FAILED; po MAX_ATTEMPTS marker na sile + MAIL_FAILED_FINAL + alarm admina).
	 *
	 * @param int    $case_id ID sprawy.
	 * @param string $kind    KIND_REMINDER | KIND_ESCALATION.
	 * @return void
	 */
	public static function notify( int $case_id, string $kind ): void {
		$ctx = apply_filters( 'mp_case_get_context', 'not_found', $case_id );

		// Sprawa zniknela => nic (sweep wyczysci wiersz osobno).
		if ( ! is_array( $ctx ) ) {
			return;
		}

		$is_reminder = ( self::KIND_REMINDER === $kind );
		$template    = $is_reminder ? 'sla_reminder' : 'sla_escalation';

		$resolved = self::resolve_recipient( $kind, $ctx );
		$addr     = $resolved[0];
		$ref      = $resolved[1];

		if ( '' === $addr ) {
			// Brak odbiorcy (nieprzydzielona bez koordynatora) = stan legalny;
			// marker ustawiony => brak retry-spamu (admin skonfiguruje koordynatora).
			self::set_marker( $case_id, $kind );
			WorkflowEvents::log(
				WorkflowEvents::MAIL_SKIPPED_NO_RECIPIENT,
				array(
					'template_key'  => $template,
					'recipient_ref' => $ref,
				),
				$case_id
			);

			return;
		}

		$rendered = MailTemplates::render( $template, $ctx );

		if ( null === $rendered ) {
			self::set_marker( $case_id, $kind );
			WorkflowEvents::log(
				WorkflowEvents::MAIL_FAILED,
				array(
					'template_key' => $template,
					'error_code'   => 'template_missing',
				),
				$case_id
			);

			return;
		}

		$ok = Mailer::send( $addr, $rendered['subject'], $rendered['body'] );

		if ( $ok ) {
			// CLAIM po sukcesie (send-then-claim): marker + wpis na osi C + log D.
			self::announce_sent( $case_id, $kind, $ref, $template );

			// Udana wysylka gasi alarm — inaczej komunikat w Stanie witryny wisialby
			// wiecznie po jednej chwilowej odmowie serwera (parytet z Intake::Mailer).
			if ( array() !== (array) get_option( self::ALERT_OPTION, array() ) ) {
				delete_option( self::ALERT_OPTION );
			}

			return;
		}

		// FALSE = chwilowa awaria SMTP (normalna sciezka): attempts+1, retry nastepnym sweepem.
		$attempts = self::bump_attempts( $case_id, $kind );

		if ( $attempts >= self::MAX_ATTEMPTS ) {
			self::set_marker( $case_id, $kind );
			update_option(
				self::ALERT_OPTION,
				array(
					'kind' => $kind,
					'time' => gmdate( 'Y-m-d H:i:s' ),
				),
				false
			);
			WorkflowEvents::log(
				WorkflowEvents::MAIL_FAILED_FINAL,
				array(
					'template_key' => $template,
					'error_code'   => 'smtp_failed',
					'attempts'     => $attempts,
				),
				$case_id
			);

			return;
		}

		WorkflowEvents::log(
			WorkflowEvents::MAIL_FAILED,
			array(
				'template_key' => $template,
				'error_code'   => 'smtp_failed',
				'attempts'     => $attempts,
			),
			$case_id
		);
	}

	/**
	 * Wspolna galaz sukcesu wysylki (send-then-claim): marker + zdarzenie osi C
	 * (mp_sla_notified => SLA_*_SENT) + log D. Uzywana przez notify() (pojedynczo)
	 * i escalate_digest() (wsadowo) — os C ma byc identyczna w obu sciezkach.
	 *
	 * @param int    $case_id  ID sprawy.
	 * @param string $kind     Rodzaj.
	 * @param string $ref      recipient_ref (NO-PII).
	 * @param string $template template_key (do logu D).
	 * @return void
	 */
	private static function announce_sent( int $case_id, string $kind, string $ref, string $template ): void {
		self::set_marker( $case_id, $kind );
		do_action( 'mp_sla_notified', $case_id, $kind, $ref );
		WorkflowEvents::log(
			WorkflowEvents::RULE_EXECUTED,
			array(
				'rule_id'       => 0,
				'trigger'       => 'sla',
				'action'        => Rules::ACTION_NOTIFY,
				'template_key'  => $template,
				'recipient_ref' => $ref,
				'result'        => 'success',
				'depth'         => 0,
			),
			$case_id
		);
	}

	/**
	 * TLUMIENIE flagi #8 (SLA-3): sprawy JUZ po terminie (deadline_at<=NOW) z
	 * niewyslanym przypomnieniem i tak eskaluja — przypomnienie w tym samym sweepie
	 * byloby DRUGIM powiadomieniem. Zajmujemy marker reminder_sent_at (ksiegowosc
	 * wewnetrzna / idempotencja: kolejny sweep nie sprobuje przypomniec), ale BEZ
	 * maila i BEZ mp_sla_notified => ZERO SLA_REMINDER_SENT na osi C. Os C = audyt
	 * append-only (W3/RODO) i NIE moze klamac, ze przypomnienie poszlo. Marker =
	 * stan wewnetrzny, event = audyt zewnetrzny — rozjazd ZAMIERZONY. Zwraca liczbe
	 * zajetych markerow (SWEEP_RUN).
	 *
	 * @return int
	 */
	public static function claim_suppressed_reminders(): int {
		global $wpdb;

		$table = Tables::full( Tables::CASE_SLA );
		$now   = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; zbiorczy claim markera (bez maila/eventu).
		$affected = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET reminder_sent_at = %s, updated_at = %s
				WHERE deadline_at IS NOT NULL AND warning_at IS NOT NULL
					AND warning_at <= %s AND reminder_sent_at IS NULL AND deadline_at <= %s",
				$now,
				$now,
				$now,
				$now
			)
		);
		// phpcs:enable

		return (int) $affected;
	}

	/**
	 * Wysyla eskalacje dla zestawu spraw. Ponizej progu (DIGEST_THRESHOLD) — per
	 * sprawa (Sla::notify, pelny send-then-claim). Powyzej — JEDEN digest do
	 * koordynatora (SLA-3 „bez lawiny"): reaktywacja / pierwsza instalacja / masa
	 * zaleglosci nie wystrzeliwuje seria osobnych maili. Idempotentne (escalated_at).
	 *
	 * @param int[] $case_ids ID spraw wymagalnych do eskalacji.
	 * @return void
	 */
	public static function escalate( array $case_ids ): void {
		$case_ids = array_values( array_filter( array_map( 'intval', $case_ids ) ) );

		if ( empty( $case_ids ) ) {
			return;
		}

		if ( count( $case_ids ) <= self::DIGEST_THRESHOLD ) {
			foreach ( $case_ids as $cid ) {
				self::notify( $cid, self::KIND_ESCALATION );
			}

			return;
		}

		self::escalate_digest( $case_ids );
	}

	/**
	 * Jeden zbiorczy mail eskalacji do koordynatora dla MASY spraw po terminie
	 * (send-then-claim wsadowy): render digest -> 1 mail -> po sukcesie marker +
	 * os C (SLA_ESCALATED) per sprawa (kazda NAPRAWDE eskalowana, os mowi prawde).
	 * Brak koordynatora => marker + MAIL_SKIPPED per sprawa (bez retry-spamu). SMTP
	 * padl => attempts+1 per sprawa; po MAX_ATTEMPTS marker na sile + alarm admina
	 * (parytet ze sciezka pojedyncza), bez claimu retry nastepnym sweepem.
	 *
	 * @param int[] $case_ids ID spraw (>DIGEST_THRESHOLD).
	 * @return void
	 */
	private static function escalate_digest( array $case_ids ): void {
		// Re-verify: tylko istniejace sprawy w digescie (znikniete sprzata sweep osobno).
		$cases = array();

		foreach ( $case_ids as $cid ) {
			$ctx = apply_filters( 'mp_case_get_context', 'not_found', $cid );

			if ( is_array( $ctx ) ) {
				$number        = (string) ( $ctx['case_number'] ?? ( '#' . $cid ) );
				$cases[ $cid ] = Mailer::strip_crlf( $number );
			}
		}

		if ( empty( $cases ) ) {
			return;
		}

		$coord = self::coordinator();
		$addr  = $coord[0];
		$ref   = $coord[1];

		// Brak koordynatora = stan legalny: marker per sprawa (bez retry-spamu) + MAIL_SKIPPED.
		if ( '' === $addr ) {
			foreach ( array_keys( $cases ) as $cid ) {
				self::set_marker( $cid, self::KIND_ESCALATION );
				WorkflowEvents::log(
					WorkflowEvents::MAIL_SKIPPED_NO_RECIPIENT,
					array(
						'template_key'  => 'sla_escalation_digest',
						'recipient_ref' => $ref,
					),
					$cid
				);
			}

			return;
		}

		$rendered = self::render_digest( array_values( $cases ) );
		$ok       = Mailer::send( $addr, $rendered['subject'], $rendered['body'] );

		if ( $ok ) {
			// CLAIM wsadowy: kazda sprawa marker + SLA_ESCALATED na osi C (naprawde eskalowana).
			foreach ( array_keys( $cases ) as $cid ) {
				self::announce_sent( $cid, self::KIND_ESCALATION, $ref, 'sla_escalation_digest' );
			}

			// Udana wysylka gasi alarm (parytet z notify() i z Intake::Mailer).
			if ( array() !== (array) get_option( self::ALERT_OPTION, array() ) ) {
				delete_option( self::ALERT_OPTION );
			}

			return;
		}

		// SMTP padl: attempts+1 per sprawa; po MAX_ATTEMPTS marker na sile + alarm (parytet z notify()).
		foreach ( array_keys( $cases ) as $cid ) {
			$attempts = self::bump_attempts( $cid, self::KIND_ESCALATION );

			if ( $attempts >= self::MAX_ATTEMPTS ) {
				self::set_marker( $cid, self::KIND_ESCALATION );
				update_option(
					self::ALERT_OPTION,
					array(
						'kind' => self::KIND_ESCALATION,
						'time' => gmdate( 'Y-m-d H:i:s' ),
					),
					false
				);
				WorkflowEvents::log(
					WorkflowEvents::MAIL_FAILED_FINAL,
					array(
						'template_key' => 'sla_escalation_digest',
						'error_code'   => 'smtp_failed',
						'attempts'     => $attempts,
					),
					$cid
				);
			}
		}

		WorkflowEvents::log(
			WorkflowEvents::MAIL_FAILED,
			array(
				'template_key' => 'sla_escalation_digest',
				'error_code'   => 'smtp_failed',
				'count'        => count( $cases ),
			)
		);
	}

	/**
	 * Sklada tresc digestu z szablonu sla_escalation_digest ({{liczba}}, {{lista}},
	 * {{data}}). Numery spraw juz po strip_crlf; temat single-line (podmienia tylko
	 * {{liczba}}=int, nigdy {{lista}} — brak CRLF w naglowku nawet gdy admin wklei
	 * {{lista}} do tematu).
	 *
	 * @param string[] $numbers Numery spraw (bezpieczne, strip_crlf).
	 * @return array{subject: string, body: string}
	 */
	private static function render_digest( array $numbers ): array {
		$tpl = MailTemplates::get( 'sla_escalation_digest' );

		// Defensywa: gdyby skasowano domyslny szablon (all() i tak bazuje na defaults()).
		if ( null === $tpl ) {
			$tpl = array(
				'subject' => 'ESKALACJA zbiorcza: {{liczba}} zgłoszeń po terminie',
				'body'    => "Dzień dobry,\n\nPo terminie ({{liczba}}):\n{{lista}}\n\nData: {{data}}",
			);
		}

		$lines = array();

		foreach ( $numbers as $n ) {
			$lines[] = '- ' . $n;
		}

		$map = array(
			'{{liczba}}' => (string) count( $numbers ),
			'{{lista}}'  => implode( "\n", $lines ),
			'{{data}}'   => (string) wp_date( 'Y-m-d H:i' ),
		);

		return array(
			'subject' => strtr( $tpl['subject'], array( '{{liczba}}' => $map['{{liczba}}'] ) ),
			'body'    => strtr( $tpl['body'], $map ),
		);
	}

	/**
	 * Odbiorca wg rodzaju: przypomnienie => przypisany agent (nieprzydzielona =>
	 * koordynator); eskalacja => koordynator. Zwraca [adres, recipient_ref=kategoria].
	 *
	 * @param string               $kind Rodzaj.
	 * @param array<string, mixed> $ctx  Kontekst sprawy.
	 * @return array{0: string, 1: string}
	 */
	private static function resolve_recipient( string $kind, array $ctx ): array {
		if ( self::KIND_REMINDER === $kind ) {
			$uid = isset( $ctx['assigned_to'] ) ? $ctx['assigned_to'] : null;

			if ( null !== $uid ) {
				$user = get_userdata( (int) $uid );

				if ( $user && '' !== (string) $user->user_email ) {
					// recipient_ref w stylu kontraktu (API-KONTRAKT mp_sla_notified): user:ID, NO-PII.
					return array( (string) $user->user_email, 'user:' . (int) $uid );
				}
			}
			// Nieprzydzielona / agent bez adresu => koordynator (fallback jak przy SLA).
		}

		return self::coordinator();
	}

	/**
	 * Pierwszy uzytkownik z rola mp_coordinator (albo '' => MAIL_SKIPPED).
	 *
	 * @return array{0: string, 1: string}
	 */
	private static function coordinator(): array {
		$users = get_users(
			array(
				'role'   => 'mp_coordinator',
				'number' => 1,
				'fields' => array( 'user_email' ),
			)
		);
		$email = ! empty( $users ) && isset( $users[0]->user_email ) ? (string) $users[0]->user_email : '';

		// recipient_ref w stylu kontraktu (API-KONTRAKT): role:mp_coordinator, NO-PII.
		return array( $email, 'role:mp_coordinator' );
	}

	/**
	 * Ustawia marker wyslania (reminder_sent_at / escalated_at = NOW WHERE IS NULL).
	 *
	 * @param int    $case_id ID sprawy.
	 * @param string $kind    Rodzaj.
	 * @return void
	 */
	private static function set_marker( int $case_id, string $kind ): void {
		global $wpdb;

		$col   = ( self::KIND_REMINDER === $kind ) ? 'reminder_sent_at' : 'escalated_at';
		$table = Tables::full( Tables::CASE_SLA );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; nazwa kolumny z zamknietej listy (nie z inputu).
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET {$col} = %s, updated_at = %s WHERE case_id = %d AND {$col} IS NULL",
				gmdate( 'Y-m-d H:i:s' ),
				gmdate( 'Y-m-d H:i:s' ),
				$case_id
			)
		);
		// phpcs:enable
	}

	/**
	 * Podbija licznik prob dla rodzaju i zwraca NOWA wartosc.
	 *
	 * @param int    $case_id ID sprawy.
	 * @param string $kind    Rodzaj.
	 * @return int
	 */
	private static function bump_attempts( int $case_id, string $kind ): int {
		global $wpdb;

		$col   = ( self::KIND_REMINDER === $kind ) ? 'reminder_attempts' : 'escalation_attempts';
		$table = Tables::full( Tables::CASE_SLA );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; nazwa kolumny z zamknietej listy.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET {$col} = {$col} + 1, updated_at = %s WHERE case_id = %d",
				gmdate( 'Y-m-d H:i:s' ),
				$case_id
			)
		);

		return (int) $wpdb->get_var(
			$wpdb->prepare( "SELECT {$col} FROM {$table} WHERE case_id = %d", $case_id )
		);
		// phpcs:enable
	}
}
