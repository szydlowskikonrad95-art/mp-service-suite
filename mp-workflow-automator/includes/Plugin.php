<?php
/**
 * Rdzen pluginu MP Workflow Automator.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

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
	 * Rejestruje hooki startowe (i18n, upgrade-bez-reaktywacji; moduly domenowe dochodza w D5-D6).
	 *
	 * @return void
	 */
	public function boot(): void {
		// Audyt #14: obiecany w kontrakcie mechanizm zgodnosci wersji — WPIETY.
		// Niezgodnosc (plugin zbudowany na inna wersje kontraktu niz zaladowana
		// stala) = admin notice + degraded mode przez has_filter, NIGDY fatal.
		if ( ! Common\Contract::is_compatible( 1 ) ) {
			Common\Contract::register_mismatch_notice( 'MP Workflow Automator' );
		}

		add_action( 'admin_init', array( Lifecycle::class, 'maybe_upgrade' ) );

		// Statusy wlasne (P3.2): D = zrodlo definicji => publikuje je do walidatora C.
		add_filter( 'mp_registered_statuses', array( StatusDefs::class, 'register_statuses' ) );

		// Silnik regul: nasluch triggerow C/B (P3.1 = auto-przydzial na case_created).
		RuleEngine::register();

		// Ksiega SLA (P3.4): wiersz terminu na created + przeliczenie przy zmianie statusu.
		Sla::register();

		// Kontrakt C -> D (API-KONTRAKT.md §A): sprawy przestaly istniec => nasze
		// wiersze przypiete do spraw traca sens. Rejestr operacji ZOSTAJE (historia).
		// Audyt 27.07: kontrakt byl opisany w dokumentacji i na diagramie, ale po
		// stronie D nie mial ZADNEGO sluchacza — terminy i checklisty przezywaly
		// odinstalowanie Intake jako dane wiszace na nieistniejacych sprawach.
		add_action( 'mp_cases_data_erased', array( self::class, 'on_cases_data_erased' ) );

		// Sweep SLA (P3.4/SLA-2): cron 5-min — przypomnienia przed / eskalacje po terminie.
		Sweep::register();

		// Raport koncowy (przebieg krok 8): przy zamknieciu sprawy wpis systemowy w C.
		ClosingReport::register();

		// Eksport CSV spraw + zestawienie (P3.6): handler admin-post (bez menu —
		// przycisk podepnie panel admina D). Capability + nonce + audyt + anti-injection.
		CsvExport::register();

		// Akcja admina „Przelicz SLA" (P3.4/SLA-4): backend-handler-only (bez menu).
		Admin\SlaRecalcAction::register();

		// Pula pracownikow reguly przydzialu (audyt 29.07): bez tego handlera pula
		// jechala z instalacji PUSTA i nie bylo jej jak wypelnic — zgloszenia nie
		// trafialy do nikogo, a instrukcja kazala to ustawic w panelu jako krok 1.
		AssignmentPool::register();

		// Checklisty per typ + szablony odpowiedzi (P3.5): handlery admin-post
		// (bez menu — przycisk podepnie panel admina D). Toggle idzie przez hook C.
		ChecklistTemplates::register();
		Checklists::register();
		ResponseTemplates::register();

		// READ-API D->C dla karty sprawy personelu (C): stan checklisty, szablony
		// odpowiedzi, termin SLA jako filtry kontraktowe (kartka krok 7).
		CaseCardApi::register();

		// Panel admina D: menu automatora spinajace akcje (Przelicz SLA / Eksport CSV)
		// + read-only podglad regul/statusow/rejestru; slot na checklisty+szablony (P3.5).
		Admin\PanelScreen::register();

		// Warstwa ustawien (1.3.12): statusy wlasne, godziny terminow, reguly przydzialu
		// i przelacznik kasowania danych. Do 1.3.11 kazdy z tych mechanizmow ISTNIAL,
		// ale nie mial ani jednego wywolania z panelu — zamowienie zada „konfigurowalnych",
		// a konfigurowal je programista. Handlery zapisu MUSZA byc zarejestrowane
		// tu, obok ekranu, inaczej formularz POST-uje w prozne admin-post.php.
		StatusDefs::register();
		SlaConfig::register();
		Rules::register();
		Admin\SettingsScreen::register();

		// Diagnostyka wdrozenia (Narzedzia -> Stan witryny). NAJWAZNIEJSZY test
		// pakietu: bez WP-Crona terminy SLA, przypomnienia i eskalacje po prostu
		// nie chodza, a system wyglada na sprawny — awaria cicha.
		Admin\SiteHealthTests::register();
	}

	/**
	 * Sprawy skasowane przez C => czyscimy WLASNE wiersze przypiete do spraw.
	 *
	 * Rejestr operacji (workflow_events) ZOSTAJE — to historia dzialania
	 * automatyzacji, nie dane sprawy (OWNERSHIP.md). Opcje-tresci (szablony,
	 * checklisty, statusy wlasne, reguly) tez zostaja: przezywaja razem z
	 * konfiguracja modulu.
	 *
	 * @return void
	 */
	public static function on_cases_data_erased(): void {
		global $wpdb;

		foreach ( array( Tables::CASE_SLA, Tables::CASE_CHECKLISTS ) as $tabela ) {
			$pelna = Tables::full( $tabela );

			// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna (nazwa ze stalej); sygnal kontraktowy z uninstalla C.
			$wpdb->query( "DELETE FROM {$pelna}" );
		}

		WorkflowEvents::log(
			WorkflowEvents::SWEEP_RUN,
			array(
				'action' => 'cases_data_erased',
				'powod'  => 'uninstall_intake',
			)
		);
	}
}
