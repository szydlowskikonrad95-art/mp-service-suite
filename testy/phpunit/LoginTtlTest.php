<?php
/**
 * Waznosc linku logowania podawana klientowi.
 *
 * Liczba minut idzie do DWOCH komunikatow (ekran prosby o link + tresc maila).
 * Wpisana slownie rozjechalaby sie po pierwszej zmianie TTL, a klient dostalby
 * „link nieaktualny" bez wyjasnienia — dlatego oba miejsca licza z jednej stalej
 * i to jest tu pilnowane.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\Front\Login;
use PHPUnit\Framework\TestCase;

/**
 * Przeliczenie TTL na minuty dla komunikatow.
 */
final class LoginTtlTest extends TestCase {

	/**
	 * Minuty zgadzaja sie z sekundami (zadnego „magicznego" 20 w tekstach).
	 */
	public function test_minuty_wynikaja_z_ttl(): void {
		self::assertSame( (int) round( Login::TTL_SECONDS / 60 ), Login::ttl_minutes() );
	}

	/**
	 * Komunikat nigdy nie moze powiedziec „0 minut" (TTL krotszy niz minuta).
	 */
	public function test_nigdy_zero_minut(): void {
		self::assertGreaterThanOrEqual( 1, Login::ttl_minutes() );
	}

	/**
	 * TTL zostaje krotki — link logowania to nie zaproszenie na tydzien.
	 * Gorna granica swiadoma: powyzej godziny link przestaje byc „sesyjny".
	 */
	public function test_ttl_jest_krotki(): void {
		self::assertGreaterThanOrEqual( 5 * 60, Login::TTL_SECONDS, 'ponizej 5 minut klient nie zdazy otworzyc maila' );
		self::assertLessThanOrEqual( 60 * 60, Login::TTL_SECONDS, 'powyzej godziny link przestaje byc sesyjny' );
	}

	/**
	 * TTL jest pelna wielokrotnoscia minuty — inaczej komunikat zaokragla
	 * i mowi cos innego niz robi kod (np. 90 s => „2 minuty").
	 */
	public function test_ttl_jest_pelna_liczba_minut(): void {
		self::assertSame( 0, Login::TTL_SECONDS % 60, 'TTL nie jest pelna liczba minut — komunikat zaokragli' );
	}
}
