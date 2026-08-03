<?php
/**
 * Testy naprawy 2.54 + 2.55 — formularz pyta o osobe, a odbicie z bledem
 * nie gubi tego, co czlowiek juz wpisal.
 *
 * Warstwa jednostkowa obejmuje CZYSTE funkcje. Zachowanie konta WordPressa
 * (nazwa wyswietlana i adres strony autora bez danych osobowych) sprawdza
 * test przegladarkowy `testy/e2e/c-tozsamosc-konta-klienta.sh` — tu nie ma
 * WordPressa, wiec udawanie go dalo by zielone swiatlo bez pokrycia.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\Front\SubmissionHandler;
use MP\Intake\Validator;
use PHPUnit\Framework\TestCase;

/**
 * Imie i nazwisko zglaszajacego: walidacja i przepisanie po bledzie.
 */
final class TozsamoscKlientaTest extends TestCase {

	/**
	 * Puste pole = REQUIRED. To jest korzen obu wad: bez nazwiska nazwa konta
	 * schodzila do e-maila, a ochrona przed sklejeniem osob nie startowala.
	 */
	public function test_puste_imie_odrzucone(): void {
		self::assertSame( 'REQUIRED', Validator::validate_customer_name( '' ) );
	}

	/**
	 * Same biale znaki to nadal puste pole (inaczej spacja obchodzi wymog).
	 */
	public function test_same_spacje_odrzucone(): void {
		self::assertSame( 'REQUIRED', Validator::validate_customer_name( "   \t \n " ) );
	}

	/**
	 * Zwykle nazwisko przechodzi — razem z tymi, ktore lubia wypadac przy
	 * zbyt sprytnej walidacji ksztaltu.
	 */
	public function test_prawdziwe_nazwiska_przechodza(): void {
		foreach ( array( 'Jan Kowalski', 'Żaneta Ćwikła-Śmiech', "Anna O'Brien", 'Ng', 'Jan Maria Rokita' ) as $name ) {
			self::assertNull( Validator::validate_customer_name( $name ), $name );
		}
	}

	/**
	 * Granica kolumny `customers.name` (VARCHAR(190)) liczona w ZNAKACH, nie
	 * bajtach — 190 polskich liter ma przejsc, 191 nie. Bez tego rozroznienia
	 * zapis konczylby sie komunikatem „blad zapisu do bazy" (poz. 2.4).
	 */
	public function test_granica_dlugosci_liczona_w_znakach(): void {
		self::assertNull( Validator::validate_customer_name( str_repeat( 'ą', 190 ) ) );
		self::assertSame( 'TOO_LONG', Validator::validate_customer_name( str_repeat( 'ą', 191 ) ) );
	}

	/**
	 * Odbicie z bledem przepisuje imie z powrotem do formularza — inaczej
	 * czlowiek poprawia zgode i odkrywa, ze zniknelo mu nazwisko.
	 */
	public function test_odbicie_z_bledem_nie_gubi_imienia(): void {
		$out = SubmissionHandler::echo_values(
			array( 'serial' => 'SN-1' ),
			'reklamacja',
			'audio',
			'jan@przyklad.pl',
			'Jan Kowalski'
		);

		self::assertSame( 'Jan Kowalski', $out['customer_name'] );
		self::assertSame( 'jan@przyklad.pl', $out['email'] );
		self::assertSame( 'audio', $out['category'] );
		self::assertSame( 'SN-1', $out['serial'] );
	}
}
