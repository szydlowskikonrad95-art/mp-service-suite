<?php
/**
 * Testy silnika statusu gwarancji — daty graniczne (DoD P2.2).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Registry\WarrantyStatus;
use PHPUnit\Framework\TestCase;

/**
 * 4 statusy ze spec + granice dat (dzien konca gwarancji WLACZNIE).
 */
final class WarrantyStatusTest extends TestCase {

	/**
	 * Nieznaleziony serial => brak_danych.
	 */
	public function test_not_found_is_no_data(): void {
		self::assertSame( 'brak_danych', WarrantyStatus::compute( false, '2030-01-01' ) );
	}

	/**
	 * Znaleziony bez daty gwarancji => brak_danych.
	 */
	public function test_found_without_date_is_no_data(): void {
		self::assertSame( 'brak_danych', WarrantyStatus::compute( true, null ) );
		self::assertSame( 'brak_danych', WarrantyStatus::compute( true, '' ) );
	}

	/**
	 * Dzien konca gwarancji WLACZNIE aktywny; dzien po => wygasla.
	 */
	public function test_date_boundaries(): void {
		self::assertSame( 'aktywna', WarrantyStatus::compute( true, '2026-07-21', null, null, '2026-07-21' ) );
		self::assertSame( 'aktywna', WarrantyStatus::compute( true, '2026-07-22', null, null, '2026-07-21' ) );
		self::assertSame( 'wygasla', WarrantyStatus::compute( true, '2026-07-20', null, null, '2026-07-21' ) );
	}

	/**
	 * Niezgodnosc danych zakupu => weryfikacja (nie blokada — spec P2.2).
	 */
	public function test_purchase_mismatch_is_verification(): void {
		self::assertSame( 'weryfikacja', WarrantyStatus::compute( true, '2030-01-01', false, true, '2026-07-21' ) );
		self::assertSame( 'weryfikacja', WarrantyStatus::compute( true, '2030-01-01', true, false, '2026-07-21' ) );
		self::assertSame( 'weryfikacja', WarrantyStatus::compute( true, null, false, null, '2026-07-21' ) );
	}

	/**
	 * Zgodne lub nieweryfikowane dane zakupu NIE zmieniaja statusu.
	 */
	public function test_match_or_null_keeps_status(): void {
		self::assertSame( 'aktywna', WarrantyStatus::compute( true, '2030-01-01', true, true, '2026-07-21' ) );
		self::assertSame( 'aktywna', WarrantyStatus::compute( true, '2030-01-01', null, null, '2026-07-21' ) );
	}
}
