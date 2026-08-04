<?php
/**
 * Testy „Stanu witryny" dla Automatora (D).
 *
 * NAJWAZNIEJSZY TEST CALEGO PAKIETU: WP-Cron. Bez niego SLA, przypomnienia
 * przed terminem i eskalacje po terminie NIE DZIALAJA — a system wyglada na
 * sprawny, bo formularz przyjmuje zgloszenia. To awaria cicha: nikt jej nie
 * zauwazy, dopoki klient nie zapyta „czemu nikt do mnie nie oddzwonil".
 *
 * @package MP\Automator\Admin
 */

namespace MP\Automator\Admin;

use MP\Automator\Rules;
use MP\Automator\Sla;
use MP\Automator\Sweep;
use MP\Automator\Common\SiteHealth;

/**
 * Rejestracja testow Automatora w Narzedzia -> Stan witryny.
 */
final class SiteHealthTests {

	/**
	 * Wpina testy w natywny ekran WP.
	 *
	 * @return void
	 */
	public static function register(): void {
		SiteHealth::register(
			'mp_automator',
			array(
				'cron'   => array( self::class, 'test_cron' ),
				'pula'   => array( self::class, 'test_pula_przydzialu' ),
				'poczta' => array( self::class, 'test_poczta_wysylka' ),
			)
		);
	}

	/**
	 * Poczta automatu: czy przypomnienia i eskalacje faktycznie wychodza.
	 *
	 * Audyt 29.07: `Sla` zapisywala flage awarii i NIKT jej nie czytal. Po trzech
	 * nieudanych probach sprawa dostaje trwaly marker „wyslano" i nie dostanie juz
	 * przypomnienia ani eskalacji tego rodzaju — a z zewnatrz system wyglada zdrowo.
	 * Typowy scenariusz: hosting przycina wysylke na godzine (limit maili), sweep
	 * trafia w to okno trzy razy pod rzad i cichnie NA STALE.
	 * Odpowiednik `test_poczta_wysylka` z Intake — ten sam ksztalt flagi, ten sam wynik.
	 *
	 * @return array<string, mixed>
	 */
	public static function test_poczta_wysylka(): array {
		$alert = get_option( Sla::ALERT_OPTION, array() );

		if ( ! is_array( $alert ) || array() === $alert ) {
			return SiteHealth::wynik(
				'mp_automator_poczta_awaria',
				'good',
				__( 'Poczta automatu: przypomnienia i eskalacje wychodzą bez błędu', 'mp-workflow-automator' ),
				__( 'Serwer poczty nie odrzucił żadnego powiadomienia od ostatniego sprawdzenia.', 'mp-workflow-automator' )
			);
		}

		$rodzaje = array(
			'reminder'   => __( 'przypomnienie przed terminem', 'mp-workflow-automator' ),
			'escalation' => __( 'eskalacja po przekroczeniu terminu', 'mp-workflow-automator' ),
		);

		$kind  = isset( $alert['kind'] ) ? (string) $alert['kind'] : '';
		$nazwa = $rodzaje[ $kind ] ?? __( 'powiadomienie o terminie', 'mp-workflow-automator' );
		$kiedy = isset( $alert['time'] ) ? (string) $alert['time'] : '';

		return SiteHealth::wynik(
			'mp_automator_poczta_awaria',
			'critical',
			__( 'Poczta automatu: powiadomienie o terminie NIE zostało wysłane', 'mp-workflow-automator' ),
			sprintf(
				/* translators: 1: rodzaj powiadomienia, 2: data i godzina ostatniej nieudanej proby (UTC). */
				__( 'Serwer poczty odrzucił: %1$s (ostatnia nieudana próba: %2$s UTC). Sprawy, których to dotyczyło, NIE dostaną już tego powiadomienia ponownie — sprawdź je ręcznie na liście spraw. Skonfiguruj wysyłkę (SMTP) i sprawdź limity hostingu; komunikat zgaśnie sam po pierwszej udanej wysyłce.', 'mp-workflow-automator' ),
				$nazwa,
				'' === $kiedy ? __( 'brak daty', 'mp-workflow-automator' ) : $kiedy
			)
		);
	}

	/**
	 * Pula auto-przydzialu: pusta = sprawy nie trafiaja do nikogo.
	 *
	 * Druga cicha awaria po cronie. Regula `default_assign` jest zakladana przy
	 * aktywacji z PUSTA pula (nie zgadujemy, kto ma dostawac sprawy), wiec na
	 * swiezej instalacji auto-przydzial nie robi nic: sprawa wpada, silnik loguje
	 * ASSIGNMENT_UNMATCHED do rejestru operacji i na tym koniec. Z zewnatrz
	 * wyglada to jak dzialajacy system — az ktos zapyta, czemu nikt nie odebral
	 * zgloszenia. Pule filtruje jeszcze runtime (user musi miec cap `mp_agent`),
	 * wiec liczymy TYCH SAMYCH pracownikow co RuleEngine, nie surowy JSON.
	 *
	 * @return array<string, mixed>
	 */
	public static function test_pula_przydzialu(): array {
		$konfiguracje = array();

		foreach ( Rules::enabled_for_trigger( Rules::TRIGGER_CASE_CREATED ) as $rule ) {
			if ( Rules::ACTION_ASSIGN === $rule['action_type'] ) {
				$konfiguracje[] = $rule['action_config_json'];
			}
		}

		$regula_jest = array() !== $konfiguracje;
		$pracownikow = SiteHealth::pracownikow_w_puli(
			$konfiguracje,
			static function ( int $uid ): bool {
				return user_can( $uid, 'mp_agent' );
			}
		);

		if ( ! $regula_jest ) {
			return SiteHealth::wynik(
				'mp_automator_pula',
				'recommended',
				__( 'Automatyczny przydział spraw jest wyłączony', 'mp-workflow-automator' ),
				__( 'Nie ma włączonej reguły przydzielającej nowe zgłoszenia. Sprawy będą czekać, aż ktoś przypisze je ręcznie na liście zgłoszeń.', 'mp-workflow-automator' ),
				// Audyt ekranow 27.07: poprzednia tresc odsylala do edycji reguly w panelu,
				// ktory jest TYLKO DO ODCZYTU — instrukcja prowadzila donikad.
				__( 'Regułę przydziału zakłada wtyczka przy instalacji. Jeśli jej nie ma (np. została skasowana), włącz i wyłącz wtyczkę MP Workflow Automator — reguła zostanie odtworzona.', 'mp-workflow-automator' )
			);
		}

		if ( 0 === $pracownikow ) {
			return SiteHealth::wynik(
				'mp_automator_pula',
				'recommended',
				__( 'Nowe zgłoszenia nie trafiają do nikogo — pusta lista pracowników', 'mp-workflow-automator' ),
				__( 'Reguła automatycznego przydziału jest włączona, ale nie wskazano ani jednego pracownika serwisu (albo wskazane osoby straciły uprawnienia). Zgłoszenia będą przyjmowane i widoczne na liście, lecz nikt nie dostanie ich do obsługi ani powiadomienia mailem.', 'mp-workflow-automator' ),
				// Audyt ekranow 27.07: pula pracownikow NIE jest lista w regule — wynika z
				// przypisanej roli. Tresc mowi teraz to, co user realnie ma zrobic.
				__( 'Wejdź w Użytkownicy, otwórz osobę, która ma obsługiwać zgłoszenia, i nadaj jej rolę „Pracownik serwisu MP". Zgłoszenia rozdzielają się między wszystkie osoby z tą rolą.', 'mp-workflow-automator' )
			);
		}

		return SiteHealth::wynik(
			'mp_automator_pula',
			'good',
			__( 'Nowe zgłoszenia są automatycznie przydzielane', 'mp-workflow-automator' ),
			sprintf(
				/* translators: %d: liczba pracownikow w puli przydzialu. */
				_n(
					'Zgłoszenia są rozdzielane po kolei między %d pracownika serwisu.',
					'Zgłoszenia są rozdzielane po kolei między %d pracowników serwisu.',
					$pracownikow,
					'mp-workflow-automator'
				),
				$pracownikow
			)
		);
	}

	/**
	 * WP-Cron: wylaczony albo bez zaplanowanego zadania = martwe SLA.
	 *
	 * Sprawdzamy DWIE rzeczy, bo kazda psuje osobno:
	 * 1) stala DISABLE_WP_CRON (czesty zabieg wydajnosciowy na hostingach),
	 * 2) czy nasze zadanie jest realnie zaplanowane (mogl je zdjac inny plugin
	 *    albo nieudana aktywacja).
	 *
	 * @return array<string, mixed>
	 */
	public static function test_cron(): array {
		$wylaczony   = SiteHealth::cron_wylaczony( defined( 'DISABLE_WP_CRON' ), (bool) ( defined( 'DISABLE_WP_CRON' ) ? constant( 'DISABLE_WP_CRON' ) : false ) );
		$zaplanowane = (bool) wp_next_scheduled( Sweep::CRON_HOOK );

		if ( $wylaczony ) {
			return SiteHealth::wynik(
				'mp_automator_cron',
				'critical',
				__( 'Terminy obsługi zgłoszeń (SLA) i przypomnienia NIE DZIAŁAJĄ — wyłączony WP-Cron', 'mp-workflow-automator' ),
				__( 'W konfiguracji strony ustawiono DISABLE_WP_CRON. System dalej przyjmuje zgłoszenia, ale nie pilnuje terminów: nie wyśle przypomnienia przed upływem SLA ani nie zgłosi eskalacji po terminie. Awaria jest niewidoczna — wygląda, jakby wszystko działało.', 'mp-workflow-automator' ),
				__( 'Jeśli hosting wyłączył WP-Cron celowo, ustaw w panelu zadanie systemowe (cron) wywołujące wp-cron.php co 5 minut. To standardowa i zalecana konfiguracja.', 'mp-workflow-automator' )
			);
		}

		if ( ! $zaplanowane ) {
			return SiteHealth::wynik(
				'mp_automator_cron',
				'critical',
				__( 'Brak zaplanowanego zadania pilnującego terminów SLA', 'mp-workflow-automator' ),
				__( 'WP-Cron działa, ale zadanie Automatora nie jest zaplanowane — mógł je usunąć inny dodatek albo aktywacja nie dokończyła się poprawnie. Skutek jest ten sam: terminy i eskalacje stoją.', 'mp-workflow-automator' ),
				__( 'Wyłącz i włącz ponownie wtyczkę „MP Workflow Automator" — zadanie zaplanuje się od nowa.', 'mp-workflow-automator' )
			);
		}

		$nastepne = (int) wp_next_scheduled( Sweep::CRON_HOOK );

		// Audyt #11: „zaplanowane" != „wykonuje się". WP-Cron odpala się z ruchu
		// na stronie — serwis B2B nocą stoi, a panel świecił na zielono, bo test
		// sprawdzał tylko plan. Porównujemy WYKONANIE (log SWEEP_RUN) z progiem
		// dwóch interwałów (2 × 5 min).
		$prog_s = 10 * MINUTE_IN_SECONDS;

		// 2.21: pytamy BICIE SERCA (jedna nadpisywana opcja), nie rejestr zdarzen.
		// Wczesniej odpowiedz na „czy cron chodzi" wyciagalismy z ostatniego wpisu
		// SWEEP_RUN, wiec rejestr musial rosnac o wiersz co piec minut TYLKO po to,
		// zeby ten ekran mial czego szukac. Zapas: gdy bicia serca jeszcze nie ma
		// (instalacja sprzed tej wersji), pytamy rejestr — inaczej po aktualizacji
		// Stan witryny na chwile przestalby widziec przebiegi, ktore byly.
		$ostatni = (string) get_option( Sweep::HEARTBEAT_OPTION, '' );

		if ( '' === $ostatni ) {
			$ostatni = \MP\Automator\WorkflowEvents::last_time( \MP\Automator\WorkflowEvents::SWEEP_RUN );
		}

		if ( null !== $ostatni && ( time() - (int) strtotime( $ostatni . ' +0000' ) ) > $prog_s ) {
			return SiteHealth::wynik(
				'mp_automator_cron',
				'critical',
				__( 'Pilnowanie terminów SLA STOI — zadanie zaplanowane, ale się nie wykonuje', 'mp-workflow-automator' ),
				sprintf(
					/* translators: %s: data i godzina ostatniego wykonania. */
					__( 'Ostatni przebieg sprawdzania terminów: %s (GMT). Zadanie jest zaplanowane, ale od ponad dwóch interwałów się nie uruchomiło — WP-Cron odpala się z odwiedzin strony, więc bez ruchu (np. nocą) przypomnienia i eskalacje stoją, choć wszystko wygląda na sprawne.', 'mp-workflow-automator' ),
					esc_html( $ostatni )
				),
				__( 'Ustaw w panelu hostingu zadanie systemowe (cron) wywołujące wp-cron.php co 5 minut — wtedy terminy są pilnowane niezależnie od ruchu na stronie.', 'mp-workflow-automator' )
			);
		}

		if ( null === $ostatni && $nastepne > 0 && ( time() - $nastepne ) > $prog_s ) {
			return SiteHealth::wynik(
				'mp_automator_cron',
				'critical',
				__( 'Pilnowanie terminów SLA nie wystartowało — WP-Cron się nie odpala', 'mp-workflow-automator' ),
				__( 'Zadanie sprawdzania terminów jest zaplanowane w przeszłości i nigdy się nie wykonało. WP-Cron uruchamia się z odwiedzin strony — bez ruchu nic nie ruszy.', 'mp-workflow-automator' ),
				__( 'Wejdź na stronę (dowolna wizyta odpala zaległe zadania) albo ustaw w panelu hostingu zadanie systemowe (cron) wywołujące wp-cron.php co 5 minut.', 'mp-workflow-automator' )
			);
		}

		return SiteHealth::wynik(
			'mp_automator_cron',
			'good',
			__( 'Terminy obsługi zgłoszeń (SLA) są pilnowane', 'mp-workflow-automator' ),
			sprintf(
				/* translators: 1: data nastepnego uruchomienia, 2: data ostatniego wykonania albo myslnik. */
				__( 'Zadanie sprawdzające terminy jest zaplanowane (najbliższe: %1$s) i realnie się wykonuje (ostatni przebieg: %2$s GMT).', 'mp-workflow-automator' ),
				esc_html( wp_date( 'Y-m-d H:i', $nastepne ) ),
				esc_html( null !== $ostatni ? $ostatni : __( 'pierwszy przed nami', 'mp-workflow-automator' ) )
			)
		);
	}
}
