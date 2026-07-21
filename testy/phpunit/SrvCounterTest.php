<?php
/**
 * Testy formatu numeru sprawy SRV/RRRR/NNNN (czysta funkcja).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\SrvCounter;
use PHPUnit\Framework\TestCase;

/**
 * NNNN = min. 4 cyfry z zerami do 9999, potem naturalnie 5+ (kontrakt).
 */
final class SrvCounterTest extends TestCase {

	/**
	 * Pierwsza sprawa roku ma zera wiodace.
	 */
	public function test_first_case_is_padded(): void {
		self::assertSame( 'SRV/2026/0001', SrvCounter::format( 2026, 1 ) );
	}

	/**
	 * Setna/tysieczna sprawa — pelne 4 cyfry.
	 */
	public function test_padding_to_four_digits(): void {
		self::assertSame( 'SRV/2026/0042', SrvCounter::format( 2026, 42 ) );
		self::assertSame( 'SRV/2026/1000', SrvCounter::format( 2026, 1000 ) );
		self::assertSame( 'SRV/2026/9999', SrvCounter::format( 2026, 9999 ) );
	}

	/**
	 * Powyzej 9999 numer rosnie naturalnie do 5+ cyfr (bez ucinania).
	 */
	public function test_overflow_grows_naturally(): void {
		self::assertSame( 'SRV/2026/10000', SrvCounter::format( 2026, 10000 ) );
		self::assertSame( 'SRV/2026/123456', SrvCounter::format( 2026, 123456 ) );
	}

	/**
	 * Rok tez ma sztywne 4 cyfry.
	 */
	public function test_year_is_four_digits(): void {
		self::assertSame( 'SRV/2026/0001', SrvCounter::format( 2026, 1 ) );
	}
}
