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

use MP\Intake\CaseRepo;
use MP\Intake\Front\Login;
use PHPUnit\Framework\TestCase;

/**
 * Przeliczenie TTL na minuty dla komunikatow.
 */
final class KomunikatyTtlTest extends TestCase {

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

	/**
	 * To samo dla linku POTWIERDZAJACEGO zgloszenie: mail podaje liczbe godzin
	 * z `CaseRepo::TOKEN_TTL_HOURS`, wiec stala musi zostac sensowna. Tu tez
	 * stalo zaszyte slownie „24 godziny" i rozjechaloby sie po zmianie.
	 */
	public function test_link_potwierdzajacy_ma_sensowna_waznosc(): void {
		self::assertGreaterThanOrEqual( 1, CaseRepo::TOKEN_TTL_HOURS, 'ponizej godziny klient nie zdazy' );
		self::assertLessThanOrEqual( 72, CaseRepo::TOKEN_TTL_HOURS, 'powyzej 3 dni token przestaje byc jednorazowa weryfikacja' );
		self::assertSame( CaseRepo::TOKEN_TTL_HOURS, (int) CaseRepo::TOKEN_TTL_HOURS, 'godziny musza byc calkowite' );
	}

	/**
	 * Link potwierdzajacy zgloszenie ma zyc DLUZEJ niz link logowania:
	 * pierwszy klient dostaje raz i moze otworzyc wieczorem, drugi zamawia
	 * sam w chwili, gdy chce wejsc do panelu.
	 */
	public function test_potwierdzenie_zyje_dluzej_niz_logowanie(): void {
		self::assertGreaterThan(
			Login::TTL_SECONDS,
			CaseRepo::TOKEN_TTL_HOURS * 3600,
			'link potwierdzajacy powinien byc dluzszy niz sesyjny link logowania'
		);
	}
}
