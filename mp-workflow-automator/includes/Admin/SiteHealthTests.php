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
				'cron' => array( self::class, 'test_cron' ),
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
				__( 'Terminy SLA i przypomnienia NIE DZIAŁAJĄ — wyłączony WP-Cron', 'mp-workflow-automator' ),
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

		return SiteHealth::wynik(
			'mp_automator_cron',
			'good',
			__( 'Terminy SLA są pilnowane', 'mp-workflow-automator' ),
			sprintf(
				/* translators: %s: data i godzina nastepnego uruchomienia. */
				__( 'Zadanie sprawdzające terminy jest zaplanowane. Najbliższe uruchomienie: %s.', 'mp-workflow-automator' ),
				esc_html( wp_date( 'Y-m-d H:i', $nastepne ) )
			)
		);
	}
}
