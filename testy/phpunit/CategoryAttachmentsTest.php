<?php
/**
 * Testy regul ZALACZNIKOW zaleznych od kategorii produktu.
 *
 * Kartka P1.2 (Plugin 1, cytat 1:1): „wymagane pola i zalaczniki zalezne od
 * wybranej kategorii produktu". Pola dzialaly (FormConfig::category_fields),
 * zalaczniki NIE — we wszystkich kategoriach identyczne, zawsze opcjonalne.
 *
 * Regula klepnieta przez Dzidka 28.07: AGD i elektronarzedzia wymagaja zdjecia
 * tabliczki znamionowej, audio i „inne" zostaja opcjonalne.
 *
 * ⚠️ Fallback jest MIEKKI z rozmyslem: brak kategorii i kategoria nieznana NIE
 * wymagaja zalacznika. Kategoria jest polem opcjonalnym formularza — twardy
 * fallback zablokowalby kazde zgloszenie bez wyboru kategorii.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\FormConfig;
use PHPUnit\Framework\TestCase;

/**
 * Wymagalnosc i etykieta zalacznika per kategoria (czysta funkcja).
 */
final class CategoryAttachmentsTest extends TestCase {

	/**
	 * AGD: zdjecie tabliczki znamionowej OBOWIAZKOWE.
	 */
	public function test_agd_wymaga_zalacznika(): void {
		self::assertTrue( FormConfig::attachments_for( 'agd' )['required'] );
	}

	/**
	 * Elektronarzedzia: zdjecie tabliczki / nr partii OBOWIAZKOWE.
	 */
	public function test_elektronarzedzia_wymagaja_zalacznika(): void {
		self::assertTrue( FormConfig::attachments_for( 'elektronarzedzia' )['required'] );
	}

	/**
	 * Audio i „inne": zalacznik dalej opcjonalny (zero regresji dla tych kategorii).
	 */
	public function test_audio_i_inne_opcjonalne(): void {
		self::assertFalse( FormConfig::attachments_for( 'audio' )['required'] );
		self::assertFalse( FormConfig::attachments_for( 'inne' )['required'] );
	}

	/**
	 * Brak wyboru kategorii = zalacznik opcjonalny (kategoria to pole opcjonalne).
	 */
	public function test_brak_kategorii_nie_wymaga(): void {
		self::assertFalse( FormConfig::attachments_for( '' )['required'] );
	}

	/**
	 * Kategoria spoza slownika = bezpieczny fallback, nie blokuje zgloszenia.
	 */
	public function test_nieznana_kategoria_nie_wymaga(): void {
		self::assertFalse( FormConfig::attachments_for( 'kategoria-ktorej-nie-ma' )['required'] );
	}

	/**
	 * Kazda kategoria ma etykiete — klient musi wiedziec CO ma wgrac, a nie
	 * zobaczyc samą gwiazdke „wymagane".
	 */
	public function test_kazda_kategoria_ma_etykiete(): void {
		foreach ( FormConfig::CATEGORY_SLUGS as $category ) {
			$rules = FormConfig::attachments_for( $category );

			self::assertIsString( $rules['label'] );
			self::assertNotSame( '', $rules['label'], "pusta etykieta zalacznika dla kategorii: {$category}" );
		}
	}

	/**
	 * Etykieta kategorii wymagajacej nazywa KONKRET (tabliczka znamionowa),
	 * a nie ogolne „zalaczniki" — inaczej klient wgra cokolwiek.
	 */
	public function test_etykieta_wymaganej_mowi_co_wgrac(): void {
		self::assertStringContainsString( 'tabliczk', FormConfig::attachments_for( 'agd' )['label'] );
		self::assertStringContainsString( 'tabliczk', FormConfig::attachments_for( 'elektronarzedzia' )['label'] );
	}

	/**
	 * Mapa dla warstwy klienckiej (JS) pokrywa WSZYSTKIE kategorie ze slownika —
	 * inaczej JS przy zmianie kategorii nie mialby czego przelaczyc.
	 */
	public function test_mapa_dla_js_pokrywa_wszystkie_kategorie(): void {
		$map = FormConfig::category_attachment_map();

		foreach ( FormConfig::CATEGORY_SLUGS as $category ) {
			self::assertArrayHasKey( $category, $map );
			self::assertArrayHasKey( 'required', $map[ $category ] );
			self::assertArrayHasKey( 'label', $map[ $category ] );
		}
	}

	/**
	 * Kontrola typu: `required` to BOOL, nie „1"/„true" — JS i serwer porownuja
	 * scisle, a string „0" jest prawdziwy w PHP.
	 */
	public function test_required_jest_boolem(): void {
		foreach ( FormConfig::CATEGORY_SLUGS as $category ) {
			self::assertIsBool( FormConfig::attachments_for( $category )['required'] );
		}
	}
}
