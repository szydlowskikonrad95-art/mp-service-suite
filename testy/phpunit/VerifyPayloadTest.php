<?php
/**
 * Testy danych zakupu przekazywanych do sprawdzenia gwarancji.
 *
 * Kartka P1.4: „walidacja numeru dokumentu zakupu, numeru seryjnego i daty zakupu".
 * Kartka P2.2: status gwarancji ma miec CZTERY wartosci — aktywna / wygasla /
 * brak danych / WYMAGANA WERYFIKACJA. Czwarta powstaje wylacznie wtedy, gdy
 * rejestr dostanie dokument i date DO POROWNANIA (`WarrantyCheck::assemble`
 * liczy `purchase_doc_match` / `purchase_date_match` tylko przy niepustym
 * `$verify`). Bez tego ladunku czwarty status jest nieosiagalny.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\CaseRepo;
use PHPUnit\Framework\TestCase;

/**
 * Ladunek `$verify` dla filtra `mp_warranty_check`.
 */
final class VerifyPayloadTest extends TestCase {

	/**
	 * Komplet danych zakupu jedzie do rejestru pod kluczami z kontraktu.
	 */
	public function test_przekazuje_dokument_i_date(): void {
		$out = CaseRepo::verify_payload(
			array(
				'purchase_document' => 'FV/2026/0410',
				'purchase_date'     => '2026-04-12',
			)
		);

		self::assertSame(
			array(
				'purchase_doc'  => 'FV/2026/0410',
				'purchase_date' => '2026-04-12',
			),
			$out
		);
	}

	/**
	 * Sam dokument tez jedzie — rejestr sam zdecyduje, czego nie porownuje.
	 */
	public function test_sam_dokument_wystarczy(): void {
		$out = CaseRepo::verify_payload( array( 'purchase_document' => 'FV/2026/0410' ) );

		self::assertIsArray( $out );
		self::assertSame( 'FV/2026/0410', $out['purchase_doc'] );
		self::assertSame( '', $out['purchase_date'] );
	}

	/**
	 * Rodzaj „naprawa" ma te pola WYLACZONE — pusty ladunek musi byc NULL,
	 * inaczej kazda naprawa dostalaby status „wymagana weryfikacja".
	 */
	public function test_brak_danych_zakupu_daje_null(): void {
		self::assertNull( CaseRepo::verify_payload( array() ) );
		self::assertNull(
			CaseRepo::verify_payload(
				array(
					'purchase_document' => '',
					'purchase_date'     => '',
				)
			)
		);
	}

	/**
	 * Same biale znaki to brak danych, nie dane.
	 */
	public function test_biale_znaki_to_brak_danych(): void {
		self::assertNull(
			CaseRepo::verify_payload(
				array(
					'purchase_document' => "  \t ",
					'purchase_date'     => '   ',
				)
			)
		);
	}

	/**
	 * Wartosci sa przycinane — spacja z kopiuj-wklej nie psuje porownania.
	 */
	public function test_przycina_biale_znaki(): void {
		$out = CaseRepo::verify_payload(
			array(
				'purchase_document' => '  FV/2026/0410 ',
				'purchase_date'     => ' 2026-04-12 ',
			)
		);

		self::assertSame( 'FV/2026/0410', $out['purchase_doc'] );
		self::assertSame( '2026-04-12', $out['purchase_date'] );
	}
}
