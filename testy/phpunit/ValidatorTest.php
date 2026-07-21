<?php
/**
 * Testy walidatorow formularza (czyste funkcje P1.4).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\Validator;
use PHPUnit\Framework\TestCase;

/**
 * Data zakupu, serial, dokument, email — kody bledow bez surowych danych.
 */
final class ValidatorTest extends TestCase {

	private const TODAY = '2026-07-22';

	/**
	 * Poprawna data przechodzi.
	 */
	public function test_valid_date_passes(): void {
		self::assertNull( Validator::validate_purchase_date( '2026-03-15', self::TODAY ) );
	}

	/**
	 * Data z przyszlosci = DATE_FUTURE.
	 */
	public function test_future_date_rejected(): void {
		self::assertSame( 'DATE_FUTURE', Validator::validate_purchase_date( '2026-07-23', self::TODAY ) );
	}

	/**
	 * Dzisiejsza data jest OK (granica).
	 */
	public function test_today_is_ok(): void {
		self::assertNull( Validator::validate_purchase_date( self::TODAY, self::TODAY ) );
	}

	/**
	 * Nieistniejaca/zle sformatowana data = DATE_INVALID.
	 */
	public function test_garbage_dates_rejected(): void {
		foreach ( array( '2026-02-30', '15.03.2026', 'wczoraj', '2026-13-01', '2026-3-5' ) as $bad ) {
			self::assertSame( 'DATE_INVALID', Validator::validate_purchase_date( $bad, self::TODAY ), $bad );
		}
	}

	/**
	 * Data sprzed 1990 = DATE_TOO_OLD (ochrona przed literowka/atakiem).
	 */
	public function test_ancient_date_rejected(): void {
		self::assertSame( 'DATE_TOO_OLD', Validator::validate_purchase_date( '1980-01-01', self::TODAY ) );
	}

	/**
	 * Serial: ksztalt (istnienie sprawdza B).
	 */
	public function test_serial_shape(): void {
		self::assertNull( Validator::validate_serial( 'ABC-123' ) );
		self::assertSame( 'SERIAL_INVALID', Validator::validate_serial( 'x' ) );
		self::assertSame( 'SERIAL_INVALID', Validator::validate_serial( '---' ) );
		self::assertSame( 'SERIAL_INVALID', Validator::validate_serial( str_repeat( 'A', 101 ) ) );
	}

	/**
	 * E-mail.
	 */
	public function test_email(): void {
		self::assertTrue( Validator::is_email( 'jan@example.com' ) );
		self::assertFalse( Validator::is_email( 'jan(at)example' ) );
		self::assertFalse( Validator::is_email( '' ) );
	}

	/**
	 * Reklamacja bez dokumentu i daty = dwa bledy REQUIRED (nie insert).
	 */
	public function test_reklamacja_missing_required(): void {
		$errors = Validator::validate(
			'reklamacja',
			array(
				'serial'            => 'ABC-123',
				'issue_description' => 'Nie dziala',
			),
			self::TODAY
		);

		$fields = array_column( $errors, 'reason_code', 'field' );
		self::assertSame( 'REQUIRED', $fields['purchase_document'] ?? null );
		self::assertSame( 'REQUIRED', $fields['purchase_date'] ?? null );
	}

	/**
	 * Komplet poprawnej reklamacji = zero bledow.
	 */
	public function test_full_valid_reklamacja(): void {
		$errors = Validator::validate(
			'reklamacja',
			array(
				'serial'            => 'ABC-123',
				'purchase_document' => 'FV/2026/1',
				'purchase_date'     => '2026-03-15',
				'issue_description' => 'Nie grzeje',
			),
			self::TODAY
		);

		self::assertSame( array(), $errors );
	}

	/**
	 * Zapytanie nie wymaga serialu (sprawa bez produktu) — sam opis wystarczy.
	 */
	public function test_zapytanie_needs_only_description(): void {
		self::assertSame(
			array(),
			Validator::validate( 'zapytanie', array( 'issue_description' => 'Pytanie' ), self::TODAY )
		);
	}

	/**
	 * Nieznany rodzaj = KIND_INVALID (jeden blad, nie walidujemy pol).
	 */
	public function test_invalid_kind(): void {
		$errors = Validator::validate( 'wlamanie', array(), self::TODAY );
		self::assertCount( 1, $errors );
		self::assertSame( 'KIND_INVALID', $errors[0]['reason_code'] );
	}
}
