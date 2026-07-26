<?php
/**
 * Testy czystej logiki diagnostyki (Stan witryny).
 *
 * Same testy Site Health wymagaja WordPressa, ale DECYZJE, ktore podejmuja,
 * siedza w czystych funkcjach — i to one moga sie zepsuc po cichu.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Common\SiteHealth;
use PHPUnit\Framework\TestCase;

/**
 * Progi i warunki diagnostyki wdrozenia.
 */
final class SiteHealthTest extends TestCase {

	/**
	 * WP-Cron: wylaczony tylko gdy stala ISTNIEJE i jest prawdziwa.
	 *
	 * Pulapka: `defined('DISABLE_WP_CRON')` bywa prawda przy wartosci `false`
	 * (spotykane w wp-config generowanych przez hostingi) — wtedy cron DZIALA
	 * i alarmowanie klienta byloby falszywe.
	 */
	public function test_cron_wylaczony_tylko_gdy_stala_true(): void {
		self::assertTrue( SiteHealth::cron_wylaczony( true, true ), 'stala = true => cron wylaczony' );
		self::assertFalse( SiteHealth::cron_wylaczony( true, false ), 'stala zdefiniowana ale false => cron DZIALA' );
		self::assertFalse( SiteHealth::cron_wylaczony( false, false ), 'brak stalej => cron dziala' );
		self::assertFalse( SiteHealth::cron_wylaczony( false, true ), 'brak stalej => wartosc bez znaczenia' );
	}

	/**
	 * Limit uploadu: alarm tylko gdy serwer realnie mniejszy niz nasz limit.
	 *
	 * Pulapka: `wp_max_upload_size()` potrafi zwrocic 0 albo wartosc ujemna przy
	 * dziwnej konfiguracji — wtedy NIE straszymy, bo nie wiemy nic pewnego.
	 */
	public function test_upload_za_maly(): void {
		$nasz = 8388608; // 8 MB.

		self::assertTrue( SiteHealth::upload_za_maly( 2097152, $nasz ), '2 MB < 8 MB => alarm' );
		self::assertFalse( SiteHealth::upload_za_maly( 8388608, $nasz ), 'dokladnie tyle samo => OK' );
		self::assertFalse( SiteHealth::upload_za_maly( 67108864, $nasz ), '64 MB => OK' );
		self::assertFalse( SiteHealth::upload_za_maly( 0, $nasz ), 'nieznany limit => nie straszymy' );
	}

	/**
	 * Nadawca: rozpoznajemy domyslny adres rdzenia WP (`wordpress@domena`).
	 */
	public function test_nadawca_domyslny(): void {
		self::assertTrue( SiteHealth::nadawca_domyslny( 'wordpress@example.com' ) );
		self::assertTrue( SiteHealth::nadawca_domyslny( 'WordPress@Example.com' ), 'wielkosc liter bez znaczenia' );
		self::assertTrue( SiteHealth::nadawca_domyslny( '  wordpress@example.com  ' ), 'spacje obciete' );
		self::assertFalse( SiteHealth::nadawca_domyslny( 'serwis@example.com' ) );
		self::assertFalse( SiteHealth::nadawca_domyslny( 'kontakt.wordpress@example.com' ), 'tylko POCZATEK adresu' );
		self::assertFalse( SiteHealth::nadawca_domyslny( '' ) );
	}

	/**
	 * Struktura wyniku: Stan witryny wymaga konkretnych kluczy, inaczej ekran
	 * sie sypie albo test znika bez sladu.
	 */
	public function test_wynik_ma_wymagane_klucze(): void {
		$w = SiteHealth::wynik( 'mp_test', 'critical', 'Tytul', 'Opis', 'Naprawa' );

		foreach ( array( 'label', 'status', 'badge', 'description', 'actions', 'test' ) as $klucz ) {
			self::assertArrayHasKey( $klucz, $w, "brak klucza {$klucz}" );
		}

		self::assertSame( 'critical', $w['status'] );
		self::assertSame( 'red', $w['badge']['color'], 'krytyczny = czerwona plakietka' );
		self::assertStringContainsString( 'Opis', $w['description'] );
		self::assertStringContainsString( 'Naprawa', $w['actions'] );
	}

	/**
	 * Kolor plakietki wynika ze statusu — zielony, pomaranczowy, czerwony.
	 */
	public function test_kolor_plakietki_wg_statusu(): void {
		self::assertSame( 'green', SiteHealth::wynik( 'a', 'good', 't', 'o' )['badge']['color'] );
		self::assertSame( 'orange', SiteHealth::wynik( 'b', 'recommended', 't', 'o' )['badge']['color'] );
		self::assertSame( 'red', SiteHealth::wynik( 'c', 'critical', 't', 'o' )['badge']['color'] );
	}

	/**
	 * Bez zalecenia naprawy sekcja „actions" ma byc PUSTA (a nie pustym <p>).
	 */
	public function test_brak_naprawy_daje_puste_actions(): void {
		self::assertSame( '', SiteHealth::wynik( 'd', 'good', 'Tytul', 'Opis' )['actions'] );
	}

	/**
	 * Pula auto-przydzialu: liczymy TYCH SAMYCH ludzi co silnik regul.
	 *
	 * Cicha awaria nr 2 (po cronie): regula jest wlaczona, wiec wyglada dobrze,
	 * ale pula pusta => sprawa nie trafia do nikogo i nikt nie dostaje maila.
	 */
	public function test_pracownikow_w_puli(): void {
		$agenci    = array( 2, 3 );
		$czy_agent = static function ( int $uid ) use ( $agenci ): bool {
			return in_array( $uid, $agenci, true );
		};

		self::assertSame( 0, SiteHealth::pracownikow_w_puli( array(), $czy_agent ), 'brak regul => zero' );
		self::assertSame( 0, SiteHealth::pracownikow_w_puli( array( '{"pool":[]}' ), $czy_agent ), 'pusta pula => zero' );
		self::assertSame( 2, SiteHealth::pracownikow_w_puli( array( '{"pool":[2,3]}' ), $czy_agent ) );
		self::assertSame( 1, SiteHealth::pracownikow_w_puli( array( '{"pool":[2,99]}' ), $czy_agent ), 'user bez uprawnien agenta sie NIE liczy' );
		self::assertSame( 1, SiteHealth::pracownikow_w_puli( array( '{"pool":[2,2]}' ), $czy_agent ), 'ten sam user dwa razy = jeden czlowiek' );
		self::assertSame( 2, SiteHealth::pracownikow_w_puli( array( '{"pool":[2]}', '{"pool":[3]}' ), $czy_agent ), 'dwie reguly sumuja sie' );
		self::assertSame( 1, SiteHealth::pracownikow_w_puli( array( '{"pool":["2"]}' ), $czy_agent ), 'id jako tekst z JSON tez liczymy' );
		self::assertSame( 0, SiteHealth::pracownikow_w_puli( array( '{"pool":[0,-5]}' ), $czy_agent ), 'zero i ujemne odpadaja' );
	}

	/**
	 * Zepsuta konfiguracja nie moze wywrocic diagnostyki ani udawac, ze pula jest.
	 */
	public function test_pracownikow_w_puli_znosi_smieci(): void {
		$czy_agent = static function ( int $uid ): bool {
			return $uid > 0;
		};

		self::assertSame( 0, SiteHealth::pracownikow_w_puli( array( null ), $czy_agent ), 'NULL w kolumnie' );
		self::assertSame( 0, SiteHealth::pracownikow_w_puli( array( '' ), $czy_agent ), 'pusty string' );
		self::assertSame( 0, SiteHealth::pracownikow_w_puli( array( 'to nie jest json' ), $czy_agent ) );
		self::assertSame( 0, SiteHealth::pracownikow_w_puli( array( '{"pool":"2,3"}' ), $czy_agent ), 'pula nie-tablica' );
		self::assertSame( 0, SiteHealth::pracownikow_w_puli( array( '{"template_key":"x"}' ), $czy_agent ), 'regula bez puli' );
	}
}
