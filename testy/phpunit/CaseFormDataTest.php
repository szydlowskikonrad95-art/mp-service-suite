<?php
/**
 * Testy normalizacji form_data (render historyczny niezalezny od biezacej mapy).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\CaseRepo;
use PHPUnit\Framework\TestCase;

/**
 * form_data = {klucz: {label z chwili zlozenia, value, pii_sensitive}}.
 */
final class CaseFormDataTest extends TestCase {

	/**
	 * Etykieta i wartosc przechowane z chwili zlozenia.
	 */
	public function test_keeps_label_and_value(): void {
		$out = CaseRepo::normalize_form_data(
			array(
				'issue' => array(
					'label' => 'Opis usterki',
					'value' => 'Nie wlacza sie',
				),
			)
		);

		self::assertSame( 'Opis usterki', $out['issue']['label'] );
		self::assertSame( 'Nie wlacza sie', $out['issue']['value'] );
	}

	/**
	 * pii_sensitive domyslnie FALSE, jawnie honorowane gdy podane.
	 */
	public function test_pii_flag_defaults_false_and_honored(): void {
		$out = CaseRepo::normalize_form_data(
			array(
				'zwykle' => array(
					'label' => 'Kolor',
					'value' => 'czarny',
				),
				'adres'  => array(
					'label'         => 'Adres odbioru',
					'value'         => 'ul. Testowa 1',
					'pii_sensitive' => true,
				),
			)
		);

		self::assertFalse( $out['zwykle']['pii_sensitive'] );
		self::assertTrue( $out['adres']['pii_sensitive'] );
	}

	/**
	 * Brak etykiety => klucz jako fallback (render sie nie wywali).
	 */
	public function test_missing_label_falls_back_to_key(): void {
		$out = CaseRepo::normalize_form_data(
			array(
				'serial' => array( 'value' => 'ABC123' ),
			)
		);

		self::assertSame( 'serial', $out['serial']['label'] );
	}

	/**
	 * Smieciowe wejscie => pusta mapa (zero fatali przy renderze).
	 */
	public function test_garbage_input_is_empty(): void {
		self::assertSame( array(), CaseRepo::normalize_form_data( 'nie tablica' ) );
		self::assertSame( array(), CaseRepo::normalize_form_data( array( 'x' => 'skalar' ) ) );
	}
}
