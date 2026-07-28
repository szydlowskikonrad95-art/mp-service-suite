<?php
/**
 * Testy czystych regul zalacznikow (retencja per rodzaj, limity, typy).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\Attachments;
use PHPUnit\Framework\TestCase;

/**
 * Retencja liczona z rodzaju; limity i lista dozwolonych typow.
 */
final class AttachmentsRulesTest extends TestCase {

	/**
	 * Retencja reklamacji = 24 miesiace (kotwica: rekojmia 2 lata).
	 */
	public function test_retention_reklamacja_24_months(): void {
		self::assertSame(
			'2028-07-22 12:00:00',
			Attachments::retention_until_for_kind( 'reklamacja', '2026-07-22 12:00:00' )
		);
	}

	/**
	 * Retencja per rodzaj: naprawa/zwrot 12, zapytanie 3.
	 */
	public function test_retention_per_kind(): void {
		self::assertSame( '2027-07-22 00:00:00', Attachments::retention_until_for_kind( 'naprawa', '2026-07-22 00:00:00' ) );
		self::assertSame( '2027-07-22 00:00:00', Attachments::retention_until_for_kind( 'zwrot', '2026-07-22 00:00:00' ) );
		self::assertSame( '2026-10-22 00:00:00', Attachments::retention_until_for_kind( 'zapytanie', '2026-07-22 00:00:00' ) );
	}

	/**
	 * Nieznany rodzaj = domyslne 12 miesiecy (bezpieczny fallback).
	 */
	public function test_unknown_kind_defaults_12(): void {
		self::assertSame( '2027-07-22 00:00:00', Attachments::retention_until_for_kind( 'cos', '2026-07-22 00:00:00' ) );
	}

	/**
	 * Limity trzymaja klepniete wartosci (8 MB, 5 plikow, 2 GB pending).
	 */
	public function test_limits_frozen(): void {
		self::assertSame( 8388608, Attachments::MAX_BYTES );
		self::assertSame( 5, Attachments::MAX_PER_CASE );
		self::assertSame( 2147483648, Attachments::PENDING_CAP_BYTES );
	}

	/**
	 * Dozwolone typy PO TRESCI: JPG/PNG/WebP/PDF (i nic wiecej).
	 */
	public function test_allowed_types(): void {
		self::assertArrayHasKey( 'image/jpeg', Attachments::ALLOWED );
		self::assertArrayHasKey( 'image/png', Attachments::ALLOWED );
		self::assertArrayHasKey( 'image/webp', Attachments::ALLOWED );
		self::assertArrayHasKey( 'application/pdf', Attachments::ALLOWED );
		self::assertArrayNotHasKey( 'image/svg+xml', Attachments::ALLOWED );
		self::assertArrayNotHasKey( 'text/html', Attachments::ALLOWED );
		self::assertArrayNotHasKey( 'application/x-php', Attachments::ALLOWED );
	}

	/**
	 * Puste pole pliku (UPLOAD_ERR_NO_FILE) = brak zalacznika, NIE blad.
	 */
	public function test_no_file_is_not_error(): void {
		self::assertNull( Attachments::validate_upload( array( 'error' => UPLOAD_ERR_NO_FILE ) ) );
	}

	/**
	 * Blad uploadu (np. INI_SIZE) = komunikat, nie cichy sukces.
	 */
	public function test_upload_error_reported(): void {
		self::assertNotNull( Attachments::validate_upload( array( 'error' => UPLOAD_ERR_INI_SIZE ) ) );
	}

	/**
	 * Obowiazujacy limit = MNIEJSZA z dwoch wartosci: nasze 8 MB i limit serwera.
	 * Stub `wp_max_upload_size` udaje ciasny hosting (2 MB) — komunikat ma podawac
	 * liczbe SERWERA, bo to ona odrzuca plik.
	 */
	public function test_limit_bierze_ciasniejsza_wartosc(): void {
		self::assertSame( 2097152, Attachments::effective_max_bytes() );
		self::assertLessThan( Attachments::MAX_BYTES, Attachments::effective_max_bytes() );
	}

	/**
	 * Za duzy plik: komunikat podaje LIMIT, a nie rade „sprobuj ponownie"
	 * (druga proba tez by sie nie udala).
	 */
	public function test_za_duzy_plik_podaje_limit(): void {
		$msg = Attachments::validate_upload( array( 'error' => UPLOAD_ERR_INI_SIZE ) );

		self::assertNotNull( $msg );
		self::assertStringContainsString( '2 MB', $msg );
		self::assertStringNotContainsString( 'spróbuj ponownie', $msg );
	}

	/**
	 * Plik mieszczacy sie w naszej stalej, ale przekraczajacy limit serwera,
	 * dostaje komunikat o limicie — nie przechodzi po cichu.
	 */
	public function test_plik_ponad_limit_serwera_odrzucony(): void {
		$msg = Attachments::validate_upload(
			array(
				'error'    => UPLOAD_ERR_OK,
				'tmp_name' => '/etc/hostname',
				'size'     => 5242880,
			)
		);

		self::assertNotNull( $msg );
	}
}
