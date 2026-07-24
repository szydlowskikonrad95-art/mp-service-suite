<?php
/**
 * Testy formatu numeru sprawy SRV/RRRR/NNNNN (czysta funkcja).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\SrvCounter;
use PHPUnit\Framework\TestCase;

/**
 * NNNNN = min. 5 cyfr z zerami do 99999, potem naturalnie 6+ (spec klienta).
 */
final class SrvCounterTest extends TestCase {

	/**
	 * Pierwsza sprawa roku ma zera wiodace (5 cyfr).
	 */
	public function test_first_case_is_padded(): void {
		self::assertSame( 'SRV/2026/00001', SrvCounter::format( 2026, 1 ) );
	}

	/**
	 * Numer dopelniany do pelnych 5 cyfr.
	 */
	public function test_padding_to_five_digits(): void {
		self::assertSame( 'SRV/2026/00042', SrvCounter::format( 2026, 42 ) );
		self::assertSame( 'SRV/2026/01000', SrvCounter::format( 2026, 1000 ) );
		self::assertSame( 'SRV/2026/09999', SrvCounter::format( 2026, 9999 ) );
		self::assertSame( 'SRV/2026/99999', SrvCounter::format( 2026, 99999 ) );
	}

	/**
	 * Powyzej 99999 numer rosnie naturalnie do 6+ cyfr (bez ucinania).
	 */
	public function test_overflow_grows_naturally(): void {
		self::assertSame( 'SRV/2026/100000', SrvCounter::format( 2026, 100000 ) );
		self::assertSame( 'SRV/2026/123456', SrvCounter::format( 2026, 123456 ) );
	}

	/**
	 * Rok tez ma sztywne 4 cyfry.
	 */
	public function test_year_is_four_digits(): void {
		self::assertSame( 'SRV/2026/00001', SrvCounter::format( 2026, 1 ) );
	}
}
