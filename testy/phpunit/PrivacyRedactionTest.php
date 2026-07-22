<?php
/**
 * Testy czystych regul RODO (redakcja pol PII w form_data, marker).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\CaseRepo;
use MP\Intake\Messages;
use PHPUnit\Framework\TestCase;

/**
 * Redakcja dotyka WYLACZNIE pol pii_sensitive; struktura/etykiety zostaja.
 */
final class PrivacyRedactionTest extends TestCase {

	/**
	 * Pole pii_sensitive => wartosc zamieniona na marker; pole zwykle bez zmian.
	 */
	public function test_redacts_only_pii_fields(): void {
		$out = CaseRepo::redact_pii_fields(
			array(
				'issue_description' => array(
					'label'         => 'Opis',
					'value'         => 'PESEL 900101...',
					'pii_sensitive' => true,
				),
				'serial'            => array(
					'label'         => 'Serial',
					'value'         => 'ABC-1',
					'pii_sensitive' => false,
				),
			)
		);

		self::assertSame( Messages::REDACTED, $out['issue_description']['value'] );
		self::assertSame( 'ABC-1', $out['serial']['value'] );
	}

	/**
	 * Etykiety i struktura pola PII ZOSTAJA (redakcja = tylko wartosc).
	 */
	public function test_keeps_labels_and_structure(): void {
		$out = CaseRepo::redact_pii_fields(
			array(
				'adres' => array(
					'label'         => 'Adres odbioru',
					'value'         => 'ul. Prywatna 1',
					'pii_sensitive' => true,
				),
			)
		);

		self::assertSame( 'Adres odbioru', $out['adres']['label'] );
		self::assertTrue( $out['adres']['pii_sensitive'] );
		self::assertSame( Messages::REDACTED, $out['adres']['value'] );
	}

	/**
	 * Brak pol PII => nic nie zmienione.
	 */
	public function test_no_pii_no_change(): void {
		$in  = array( 'serial' => array( 'label' => 'S', 'value' => 'X', 'pii_sensitive' => false ) );
		self::assertSame( $in, CaseRepo::redact_pii_fields( $in ) );
	}

	/**
	 * Marker redakcji jest staly i rozpoznawalny.
	 */
	public function test_redacted_marker(): void {
		self::assertSame( '[ZREDAGOWANO-RODO]', Messages::REDACTED );
	}
}
