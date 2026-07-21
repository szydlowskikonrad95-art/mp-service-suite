<?php
/**
 * Testy czystych regul wyjatkow gwarancyjnych (kontrakt karty B, r6)
 * oraz pasa NO-PII-IN-LOG historii produktu.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Registry\ProductEvents;
use MP\Registry\WarrantyExceptions;
use PHPUnit\Framework\TestCase;

/**
 * valid_until > NOW przy CREATE; reason wymagany <=500; payload bez reason.
 */
final class WarrantyExceptionsRulesTest extends TestCase {

	private const NOW = '2026-07-21 12:00:00';

	/**
	 * Brak terminu = bezterminowo (dozwolone).
	 */
	public function test_null_valid_until_means_indefinite(): void {
		$out = WarrantyExceptions::normalize_valid_until( null, self::NOW );
		self::assertNull( $out['value'] );
		self::assertNull( $out['error'] );
	}

	/**
	 * Sama data dostaje koniec dnia UTC.
	 */
	public function test_date_only_becomes_end_of_day(): void {
		$out = WarrantyExceptions::normalize_valid_until( '2026-08-01', self::NOW );
		self::assertSame( '2026-08-01 23:59:59', $out['value'] );
		self::assertNull( $out['error'] );
	}

	/**
	 * Termin z przeszlosci = odmowa (kontrakt: valid_until > NOW przy CREATE).
	 */
	public function test_past_valid_until_is_rejected(): void {
		$out = WarrantyExceptions::normalize_valid_until( '2026-07-20', self::NOW );
		self::assertNull( $out['value'] );
		self::assertNotNull( $out['error'] );
	}

	/**
	 * Dzisiejsza data o wczesniejszej godzinie = przeszlosc = odmowa.
	 */
	public function test_earlier_today_is_rejected(): void {
		$out = WarrantyExceptions::normalize_valid_until( '2026-07-21 11:59:59', self::NOW );
		self::assertNotNull( $out['error'] );
	}

	/**
	 * Smieciowy format = czytelna odmowa, nie ciche zero.
	 */
	public function test_garbage_format_is_rejected(): void {
		foreach ( array( 'jutro', '21.07.2026', '2026-13-40', '2026-02-30' ) as $garbage ) {
			$out = WarrantyExceptions::normalize_valid_until( $garbage, self::NOW );
			self::assertNotNull( $out['error'], "przeszlo: {$garbage}" );
		}
	}

	/**
	 * Pusty powod = odmowa; 500 znakow OK; 501 = odmowa.
	 */
	public function test_reason_required_and_capped(): void {
		self::assertNotNull( WarrantyExceptions::validate_reason( '' ) );
		self::assertNotNull( WarrantyExceptions::validate_reason( "  \n " ) );
		self::assertNull( WarrantyExceptions::validate_reason( str_repeat( 'a', 500 ) ) );
		self::assertNotNull( WarrantyExceptions::validate_reason( str_repeat( 'a', 501 ) ) );
	}

	/**
	 * Limit liczy ZNAKI (mb), nie bajty — 500 polskich znakow przechodzi.
	 */
	public function test_reason_limit_counts_characters_not_bytes(): void {
		self::assertNull( WarrantyExceptions::validate_reason( str_repeat( 'ż', 500 ) ) );
	}

	/**
	 * Pas NO-PII-IN-LOG: klucz reason NIGDY nie wchodzi do payloadu eventu.
	 */
	public function test_event_payload_never_contains_reason(): void {
		$out = ProductEvents::sanitize_payload(
			array(
				'exception_id' => 7,
				'reason'       => 'klient VIP, faktura FV/123 na Jana Kowalskiego',
				'typ'          => 'globalny',
			)
		);

		self::assertArrayNotHasKey( 'reason', $out );
		self::assertSame( 7, $out['exception_id'] );
	}

	/**
	 * Pola PII w diffie sprowadzone do {field, changed:true} — bez wartosci.
	 */
	public function test_pii_fields_masked_in_diff(): void {
		$out = ProductEvents::sanitize_payload(
			array(
				'purchase_document' => array(
					'before' => 'FV/2026/1 Jan Kowalski',
					'after'  => 'FV/2026/2 Jan Kowalski',
				),
				'model'             => array(
					'before' => 'A1',
					'after'  => 'A2',
				),
			)
		);

		self::assertSame(
			array(
				'field'   => 'purchase_document',
				'changed' => true,
			),
			$out['purchase_document']
		);
		self::assertSame( 'A2', $out['model']['after'] );
	}
}
