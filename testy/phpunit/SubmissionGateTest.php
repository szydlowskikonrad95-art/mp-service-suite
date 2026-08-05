<?php
/**
 * Testy bramki zgloszenia: przepisanie wartosci po odbiciu + wymog zalacznika.
 *
 * Specyfikacja P1.2: „wymagane pola i zalaczniki zalezne od wybranej kategorii
 * produktu". Regula wymagalnosci siedzi w `FormConfig` (CategoryAttachmentsTest),
 * tu sprawdzamy dwa styki, na ktorych ta regula moglaby przeciec:
 *
 * 1. `echo_values` — po odbiciu formularza z bledem KATEGORIA musi wrocic.
 *    Bez niej lista wraca do „— wybierz —", znikaja pola kategorii i znika
 *    oznaczenie wymaganego zalacznika: klient poprawia jedno pole i dostaje
 *    formularz o innym ksztalcie niz wyslal.
 * 2. `has_usable_attachment` — wymog spelnia wylacznie plik, ktory PRZEJDZIE
 *    walidacje, a nie sam fakt wybrania pliku w przegladarce.
 *
 * ⚠️ Przypadek POZYTYWNY (dobry plik => true) NIE jest testowalny jednostkowo:
 * `Attachments::validate_upload` uzywa `is_uploaded_file()`, ktore poza realnym
 * POST-em zawsze zwraca false. Pokrywa go zywy test `testy/e2e/c-zalaczniki-kategoria.sh`
 * (wysylka formularza przez HTTP z prawdziwym plikiem).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\Front\SubmissionHandler;
use PHPUnit\Framework\TestCase;

/**
 * Czyste funkcje bramki zgloszenia.
 */
final class SubmissionGateTest extends TestCase {

	/**
	 * Kategoria wraca do formularza po odbiciu z bledem (rdzen poprawki).
	 */
	public function test_echo_values_zwraca_kategorie(): void {
		$out = SubmissionHandler::echo_values( array( 'serial' => 'SN1' ), 'reklamacja', 'agd', 'k@example.com' );

		self::assertSame( 'agd', $out['category'] );
		self::assertSame( 'reklamacja', $out['kind'] );
		self::assertSame( 'k@example.com', $out['email'] );
	}

	/**
	 * Wartosci pol przezywaja odbicie (klient nie przepisuje formularza od zera).
	 */
	public function test_echo_values_nie_gubi_pol(): void {
		$out = SubmissionHandler::echo_values(
			array(
				'serial'            => 'SN1',
				'issue_description' => 'nie wlacza sie',
			),
			'naprawa',
			'',
			'k@example.com'
		);

		self::assertSame( 'SN1', $out['serial'] );
		self::assertSame( 'nie wlacza sie', $out['issue_description'] );
	}

	/**
	 * Brak wyboru kategorii przepisuje sie jako pusty string, nie znika z tablicy —
	 * inaczej renderer nie odroznilby „nie wybrano" od „nie wiem".
	 */
	public function test_echo_values_pusta_kategoria_zostaje_kluczem(): void {
		$out = SubmissionHandler::echo_values( array(), 'zapytanie', '', 'k@example.com' );

		self::assertArrayHasKey( 'category', $out );
		self::assertSame( '', $out['category'] );
	}

	/**
	 * Zero plikow = wymog niespelniony.
	 */
	public function test_brak_plikow_nie_spelnia_wymogu(): void {
		self::assertFalse( SubmissionHandler::has_usable_attachment( array() ) );
	}

	/**
	 * Puste pole pliku (UPLOAD_ERR_NO_FILE) nie spelnia wymogu — mimo ze
	 * `validate_upload` zwraca dla niego null („brak zalacznika, nie blad").
	 */
	public function test_puste_pole_pliku_nie_spelnia_wymogu(): void {
		self::assertFalse(
			SubmissionHandler::has_usable_attachment( array( array( 'error' => UPLOAD_ERR_NO_FILE ) ) )
		);
	}

	/**
	 * Plik odrzucony przez serwer (za duzy wg limitu PHP) nie spelnia wymogu —
	 * inaczej sprawa powstalaby bez obowiazkowego zdjecia, a klient dowiedzialby
	 * sie o tym z notki PO fakcie.
	 */
	public function test_plik_z_bledem_uploadu_nie_spelnia_wymogu(): void {
		self::assertFalse(
			SubmissionHandler::has_usable_attachment( array( array( 'error' => UPLOAD_ERR_INI_SIZE ) ) )
		);
	}

	/**
	 * Podstawiona sciezka (plik nie z uploadu) nie spelnia wymogu.
	 */
	public function test_plik_spoza_uploadu_nie_spelnia_wymogu(): void {
		self::assertFalse(
			SubmissionHandler::has_usable_attachment(
				array(
					array(
						'error'    => UPLOAD_ERR_OK,
						'tmp_name' => '/etc/passwd',
						'size'     => 10,
					),
				)
			)
		);
	}

	/**
	 * Kilka niezdatnych plikow to dalej brak zalacznika (petla nie „sumuje" prob).
	 */
	public function test_kilka_niezdatnych_plikow_to_dalej_brak(): void {
		self::assertFalse(
			SubmissionHandler::has_usable_attachment(
				array(
					array( 'error' => UPLOAD_ERR_NO_FILE ),
					array( 'error' => UPLOAD_ERR_PARTIAL ),
					array( 'error' => UPLOAD_ERR_INI_SIZE ),
				)
			)
		);
	}
}
