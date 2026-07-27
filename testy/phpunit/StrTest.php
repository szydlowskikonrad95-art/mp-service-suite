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

	/**
	 * Polska odmiana wg liczby — klient nie ma czytac „ma 1 aktywnych spraw".
	 *
	 * @return array<string, array{int, string}>
	 */
	public static function odmiana_provider(): array {
		return array(
			'jeden'                 => array( 1, 'sprawę' ),
			'dwa'                   => array( 2, 'sprawy' ),
			'cztery'                => array( 4, 'sprawy' ),
			'piec'                  => array( 5, 'spraw' ),
			'zero'                  => array( 0, 'spraw' ),
			'dwanascie (wyjatek)'   => array( 12, 'spraw' ),
			'trzynascie (wyjatek)'  => array( 13, 'spraw' ),
			'czternascie (wyjatek)' => array( 14, 'spraw' ),
			'dwadziescia dwa'       => array( 22, 'sprawy' ),
			'sto dwanascie'         => array( 112, 'spraw' ),
			'sto dwadziescia trzy'  => array( 123, 'sprawy' ),
			'sto'                   => array( 100, 'spraw' ),
		);
	}

	/**
	 * Kazda liczba dostaje wlasciwa forme.
	 *
	 * @dataProvider odmiana_provider
	 *
	 * @param int    $n        Liczba.
	 * @param string $expected Oczekiwana forma.
	 */
	public function test_odmiana( int $n, string $expected ): void {
		self::assertSame( $expected, Str::odmiana( $n, 'sprawę', 'sprawy', 'spraw' ) );
	}

	/**
	 * Dlugosc liczona w ZNAKACH, nie bajtach (polskie znaki nie zjadaja limitu 2x).
	 */
	public function test_len_liczy_znaki_nie_bajty(): void {
		self::assertSame( 6, Str::len( 'zażółć' ) );
		self::assertGreaterThan( Str::len( 'zażółć' ), strlen( 'zażółć' ) );
		self::assertSame( 0, Str::len( '' ) );
	}
}
