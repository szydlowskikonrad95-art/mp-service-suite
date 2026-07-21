<?php
/**
 * Testy parsera CSV — polski Excel (DoD P2.1).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Registry\CsvParser;
use PHPUnit\Framework\TestCase;

/**
 * Windows-1250, BOM, separatory, daty d.m.Y.
 */
final class CsvParserTest extends TestCase {

	/**
	 * BOM UTF-8 jest zdejmowany.
	 */
	public function test_bom_stripped(): void {
		self::assertSame( 'serial;model', CsvParser::to_utf8( "\xEF\xBB\xBFserial;model" ) );
	}

	/**
	 * Windows-1250 (polskie znaki) konwertowane do UTF-8.
	 */
	public function test_windows_1250_converted(): void {
		// Twarde bajty CP1250 (fixture niezalezna od konwertera): "część;łódź".
		$cp1250 = "cz\xEA\x9C\xE6;\xB3\xF3d\x9F";
		$result = CsvParser::to_utf8( $cp1250 );

		if ( function_exists( 'iconv' ) || class_exists( \UConverter::class ) ) {
			self::assertSame( 'część;łódź', $result );
		} else {
			// Srodowisko bez konwertera (np. nietypowa kompilacja PHP):
			// uczciwa odmowa zamiast cichego przeklamania znakow.
			self::assertNull( $result );
		}
	}

	/**
	 * Poprawny UTF-8 przechodzi bez zmian.
	 */
	public function test_utf8_untouched(): void {
		self::assertSame( 'żółć;ćma', CsvParser::to_utf8( 'żółć;ćma' ) );
	}

	/**
	 * Detekcja separatora: srednik (Excel PL) i przecinek.
	 */
	public function test_separator_detection(): void {
		self::assertSame( ';', CsvParser::detect_separator( 'serial;model;partia' ) );
		self::assertSame( ',', CsvParser::detect_separator( 'serial,model,batch' ) );
		self::assertSame( ';', CsvParser::detect_separator( 'serial' ) );
	}

	/**
	 * Naglowek mapowany po aliasach; brak kolumny serial => null.
	 */
	public function test_header_mapping(): void {
		$map = CsvParser::map_header( array( 'Numer_Seryjny', 'MODEL', 'partia', 'faktura', 'data_zakupu', 'gwarancja_do' ) );

		self::assertNotNull( $map );
		self::assertSame( 0, $map['serial'] );
		self::assertSame( 2, $map['batch'] );
		self::assertSame( 3, $map['purchase_doc'] );

		self::assertNull( CsvParser::map_header( array( 'model', 'partia' ) ) );
	}

	/**
	 * Daty: Y-m-d i d.m.Y (polski Excel) normalizowane; smiecie odrzucane.
	 */
	public function test_date_normalization(): void {
		self::assertSame( '2026-03-01', CsvParser::normalize_date( '2026-03-01' ) );
		self::assertSame( '2026-03-01', CsvParser::normalize_date( '1.03.2026' ) );
		self::assertSame( '2026-12-31', CsvParser::normalize_date( '31.12.2026' ) );
		self::assertNull( CsvParser::normalize_date( '' ) );
		self::assertFalse( CsvParser::normalize_date( '32.13.2026' ) );
		self::assertFalse( CsvParser::normalize_date( 'jutro' ) );
		self::assertFalse( CsvParser::normalize_date( '2026-13-40' ) );
	}

	/**
	 * Wiersz poprawny i wiersze bledne (pusty serial, zla data).
	 */
	public function test_parse_row(): void {
		$map = CsvParser::map_header( array( 'serial', 'model', 'partia', 'faktura', 'data_zakupu', 'gwarancja_do' ) );

		self::assertNotNull( $map );

		$ok = CsvParser::parse_row( array( 'ABC-123', 'XJ-500', 'B-1', 'FV/1', '1.03.2026', '2030-01-01' ), $map );

		self::assertTrue( $ok['ok'] );
		self::assertSame( 'ABC-123', $ok['row']['serial'] );
		self::assertSame( 'B-1', $ok['row']['batch'] );
		self::assertSame( '2026-03-01', $ok['row']['purchase_date'] );

		$empty_serial = CsvParser::parse_row( array( '', 'XJ', '', '', '', '' ), $map );

		self::assertFalse( $empty_serial['ok'] );

		$bad_date = CsvParser::parse_row( array( 'S1', '', '', '', 'zla-data', '' ), $map );

		self::assertFalse( $bad_date['ok'] );
	}
}
