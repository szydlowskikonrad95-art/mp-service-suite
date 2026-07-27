<?php
/**
 * Sufity dlugosci pol formularza.
 *
 * Powod istnienia: pola `text` i `textarea` wpadaly w `default: return null`
 * w `validate_value`, czyli nie mialy zadnego limitu. Zgloszenie ze 100 tys.
 * znakow opisu weszlo do bazy w calosci (sprawdzone atakiem na zywym WP) —
 * a stamtad idzie do karty sprawy, panelu klienta i maila do pracownika.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\Validator;
use PHPUnit\Framework\TestCase;

/**
 * Limity znakow i ich egzekwowanie w walidacji.
 */
final class LimityDlugosciTest extends TestCase {

	/**
	 * Dzis (walidacja typu wymaga daty odniesienia).
	 */
	private const DZIS = '2026-07-27';

	/**
	 * Kazdy typ swobodnego tekstu MA sufit — zaden nie wpada w „bez limitu".
	 */
	public function test_pola_tekstowe_maja_limit(): void {
		self::assertGreaterThan( 0, Validator::limit_znakow( 'textarea' ), 'textarea bez limitu' );
		self::assertGreaterThan( 0, Validator::limit_znakow( 'text' ), 'text bez limitu' );
	}

	/**
	 * Limity sa rozsadne: opis miesci normalna relacje, ale nie powiesc.
	 */
	public function test_limity_sa_rozsadne(): void {
		$textarea = Validator::limit_znakow( 'textarea' );
		$text     = Validator::limit_znakow( 'text' );

		self::assertGreaterThanOrEqual( 1000, $textarea, 'ponizej 1000 znakow klient nie opisze usterki' );
		self::assertLessThanOrEqual( 20000, $textarea, 'powyzej 20 tys. to juz nie opis, tylko zaladunek bazy' );
		self::assertGreaterThanOrEqual( 100, $text, 'jednolinijkowe pole musi pomiescic model/objaw' );
		self::assertLessThan( $textarea, $text, 'pole jednolinijkowe nie moze byc pojemniejsze niz opis' );
	}

	/**
	 * Tekst w granicy przechodzi, o jeden znak dluzszy — nie.
	 */
	public function test_granica_dziala_dokladnie(): void {
		$limit = Validator::limit_znakow( 'textarea' );

		self::assertNull(
			Validator::validate_value( 'textarea', str_repeat( 'a', $limit ), self::DZIS ),
			'tekst DOKLADNIE na limicie musi przejsc'
		);
		self::assertSame(
			'TOO_LONG',
			Validator::validate_value( 'textarea', str_repeat( 'a', $limit + 1 ), self::DZIS ),
			'jeden znak ponad limit musi zostac odrzucony'
		);
	}

	/**
	 * Atak z realnego przebiegu: 100 tys. znakow opisu.
	 */
	public function test_sto_tysiecy_znakow_odrzucone(): void {
		self::assertSame(
			'TOO_LONG',
			Validator::validate_value( 'textarea', str_repeat( 'x', 100000 ), self::DZIS )
		);
		self::assertSame(
			'TOO_LONG',
			Validator::validate_value( 'text', str_repeat( 'x', 100000 ), self::DZIS )
		);
	}

	/**
	 * Limit liczy ZNAKI, nie bajty — inaczej polski opis mialby po cichu
	 * mniejszy limit niz angielski (ą/ę to 2 bajty w UTF-8).
	 */
	public function test_limit_liczy_znaki_nie_bajty(): void {
		$limit = Validator::limit_znakow( 'textarea' );
		$polski = str_repeat( 'ą', $limit );

		self::assertSame( $limit, mb_strlen( $polski ), 'kontrola samego testu' );
		self::assertGreaterThan( $limit, strlen( $polski ), 'polskie znaki zajmuja wiecej bajtow' );
		self::assertNull(
			Validator::validate_value( 'textarea', $polski, self::DZIS ),
			'polski tekst na limicie ZNAKOW musi przejsc'
		);
	}

	/**
	 * Typy z wlasna, ciasniejsza walidacja nie dostaja drugiego sufitu
	 * (serial 100, dokument 190 — pilnowane w swoich metodach).
	 */
	public function test_typy_z_wlasna_walidacja_bez_dodatkowego_limitu(): void {
		foreach ( array( 'email', 'serial', 'document', 'date', 'tel' ) as $typ ) {
			self::assertSame( 0, Validator::limit_znakow( $typ ), "typ {$typ} nie powinien miec limitu ogolnego" );
		}

		self::assertSame( 'SERIAL_INVALID', Validator::validate_value( 'serial', str_repeat( 'S', 101 ), self::DZIS ) );
		self::assertSame( 'DOCUMENT_INVALID', Validator::validate_value( 'document', str_repeat( 'D', 191 ), self::DZIS ) );
	}
}
