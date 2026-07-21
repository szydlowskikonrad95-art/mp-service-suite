<?php
/**
 * Testy ksztaltu zwrotki mp_warranty_check (API-KONTRAKT.md) — czysta czesc.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Registry\WarrantyCheck;
use PHPUnit\Framework\TestCase;

/**
 * Zwrotka zgodna z kontraktem: komplet pol, partia dziedziczona, wyjatki.
 */
final class WarrantyCheckAssembleTest extends TestCase {

	/**
	 * Przykladowy wiersz rejestru.
	 *
	 * @return array<string, mixed>
	 */
	private function row(): array {
		return array(
			'id'                => 42,
			'serial_display'    => 'ABC-123',
			'serial_normalized' => 'ABC123',
			'model'             => 'XJ-500',
			'batch'             => 'B-2026-03',
			'purchase_document' => 'FV/2026/0017',
			'purchase_date'     => '2026-03-01',
			'warranty_until'    => '2030-01-01',
			'archived'          => '0',
			'updated_at'        => '2026-07-20 09:00:00',
		);
	}

	/**
	 * Zwrotka ma KOMPLET pol kontraktu (kotwica ksztaltu — schema_version 1).
	 */
	public function test_contract_shape_complete(): void {
		$result = WarrantyCheck::assemble( $this->row(), null, null );

		$expected_keys = array(
			'found', 'archived', 'purchase_doc_match', 'purchase_date_match', 'product_id',
			'serial_normalized', 'model', 'batch', 'status', 'warranty_until', 'is_overridden',
			'exception_id', 'override_until', 'override_reason', 'checked_at',
			'registry_updated_at', 'schema_version',
		);

		self::assertSame( $expected_keys, array_keys( $result ) );
		self::assertSame( 1, $result['schema_version'] );
	}

	/**
	 * OGNIWO PARTII (kontrola strazenika, kartka: sprawa "dziedziczy dane
	 * gwarancji, modelu i partii"): zwrotka niesie batch => snapshot sprawy
	 * (= pelna zwrotka) dziedziczy partie.
	 */
	public function test_batch_is_inherited_via_check(): void {
		$result = WarrantyCheck::assemble( $this->row(), null, null );

		self::assertSame( 'B-2026-03', $result['batch'] );
		self::assertSame( 'XJ-500', $result['model'] );
	}

	/**
	 * Serial nieznaleziony: found=false, pola produktu null, status brak_danych.
	 */
	public function test_not_found_shape(): void {
		$result = WarrantyCheck::assemble( null, null, null );

		self::assertFalse( $result['found'] );
		self::assertNull( $result['product_id'] );
		self::assertNull( $result['batch'] );
		self::assertSame( 'brak_danych', $result['status'] );
		self::assertFalse( $result['is_overridden'] );
	}

	/**
	 * Weryfikacja zakupu: zgodny dokument (case-insensitive), niezgodna data.
	 */
	public function test_verify_comparison(): void {
		$result = WarrantyCheck::assemble(
			$this->row(),
			null,
			array(
				'purchase_doc'  => 'fv/2026/0017',
				'purchase_date' => '2026-04-15',
			)
		);

		self::assertTrue( $result['purchase_doc_match'] );
		self::assertFalse( $result['purchase_date_match'] );
		self::assertSame( 'weryfikacja', $result['status'] );
	}

	/**
	 * Brak danych do porownania => match null (nie false).
	 */
	public function test_verify_missing_registry_data_is_null(): void {
		$row                      = $this->row();
		$row['purchase_document'] = '';

		$result = WarrantyCheck::assemble( $row, null, array( 'purchase_doc' => 'FV/1' ) );

		self::assertNull( $result['purchase_doc_match'] );
	}

	/**
	 * Aktywny wyjatek: is_overridden + pola exception_*; status FAKTYCZNY bez zmian.
	 */
	public function test_active_exception_fields(): void {
		$exception = array(
			'id'          => 11,
			'valid_until' => '2026-12-31 23:59:59',
			'reason'      => 'uznanie reklamacji mimo uplywu gwarancji',
		);

		$row                   = $this->row();
		$row['warranty_until'] = '2020-01-01';

		$result = WarrantyCheck::assemble( $row, $exception, null );

		self::assertSame( 'wygasla', $result['status'] );
		self::assertTrue( $result['is_overridden'] );
		self::assertSame( 11, $result['exception_id'] );
		self::assertSame( '2026-12-31 23:59:59', $result['override_until'] );
	}

	/**
	 * Bez wyjatku pola exception_* sa null (PHPDoc kontraktu).
	 */
	public function test_no_exception_fields_null(): void {
		$result = WarrantyCheck::assemble( $this->row(), null, null );

		self::assertNull( $result['exception_id'] );
		self::assertNull( $result['override_until'] );
		self::assertNull( $result['override_reason'] );
	}

	/**
	 * Produkt archiwalny: archived=true (Intake blokuje NOWE zgloszenia).
	 */
	public function test_archived_flag(): void {
		$row             = $this->row();
		$row['archived'] = '1';

		$result = WarrantyCheck::assemble( $row, null, null );

		self::assertTrue( $result['archived'] );
	}
}
