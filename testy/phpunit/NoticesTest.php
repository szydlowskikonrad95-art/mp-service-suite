<?php
/**
 * S4 #2: lista dozwolonych komunikatow `mp_notice`.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\Notices;
use PHPUnit\Framework\TestCase;

/**
 * Bramka Notices::filter — przepuszcza wylacznie komunikaty produktu.
 */
final class NoticesTest extends TestCase {

	/**
	 * Spreparowana tresc z linku nie przechodzi (zwraca pusty string).
	 *
	 * @return void
	 */
	public function test_odrzuca_dowolna_tresc(): void {
		$this->assertSame( '', Notices::filter( 'Zadzwoń pod 700-123-456 (5 zł/min), aby wznowić sprawę.' ) );
		$this->assertSame( '', Notices::filter( '<b>cokolwiek</b>' ) );
		$this->assertSame( '', Notices::filter( 'Status zmieniony' ) ); // prawie-legalny, ale nie 1:1
	}

	/**
	 * Pusty parametr => pusto (bez ramki komunikatu).
	 *
	 * @return void
	 */
	public function test_pusty_zostaje_pusty(): void {
		$this->assertSame( '', Notices::filter( '' ) );
	}

	/**
	 * Kazdy komunikat produktu przechodzi 1:1 (zaden legalny nie ginie po drodze).
	 *
	 * @return void
	 */
	public function test_kazdy_komunikat_produktu_przechodzi(): void {
		$allowed = Notices::allowed();

		$this->assertGreaterThanOrEqual( 20, count( $allowed ), 'Lista dozwolonych podejrzanie krótka — sprawdź, czy nie zniknęła.' );

		foreach ( $allowed as $msg ) {
			$this->assertSame( $msg, Notices::filter( $msg ), "Legalny komunikat odrzucony: {$msg}" );
		}
	}
}
