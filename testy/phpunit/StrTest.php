<?php
/**
 * Testy normalizacji numeru seryjnego (kontrakt serial_normalized).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Common\Str;
use PHPUnit\Framework\TestCase;

/**
 * "ABC-123" i "abc 123" to ten sam serial (DATABASE.md).
 */
final class StrTest extends TestCase {

	/**
	 * Przypadki kanoniczne z kontraktu.
	 *
	 * @return array<string, array{string, string}>
	 */
	public static function serial_provider(): array {
		return array(
			'male litery i spacja'   => array( 'abc 123', 'ABC123' ),
			'myslnik'                => array( 'ABC-123', 'ABC123' ),
			'mieszane separatory'    => array( ' a-b c--12 3 ', 'ABC123' ),
			'juz kanoniczny'         => array( 'ABC123', 'ABC123' ),
			'pusty'                  => array( '', '' ),
			'tab i nowa linia'       => array( "ab\t12\n3", 'AB123' ),
		);
	}

	/**
	 * Normalizacja daje postac kanoniczna.
	 *
	 * @dataProvider serial_provider
	 *
	 * @param string $raw      Wejscie.
	 * @param string $expected Oczekiwana postac.
	 */
	public function test_normalize_serial( string $raw, string $expected ): void {
		self::assertSame( $expected, Str::normalize_serial( $raw ) );
	}

	/**
	 * Dwa rozne zapisy tego samego seriala zbiegaja do jednej postaci.
	 */
	public function test_equivalent_spellings_collide(): void {
		self::assertSame(
			Str::normalize_serial( 'ABC-123' ),
			Str::normalize_serial( 'abc 123' )
		);
	}
}
