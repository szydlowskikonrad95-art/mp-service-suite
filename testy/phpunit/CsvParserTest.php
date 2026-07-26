<?php
/**
 * Testy parsera CSV — polski Excel (DoD P2.1).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Common\Str;
use MP\Registry\Categories;
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

	/**
	 * Semantyka RFC-4180 (escape PUSTY, tak jak wola Importer): backslash jest
	 * ZWYKLYM znakiem, cudzyslow escapuje sie podwojeniem. Z domyslnym escape
	 * ('\\') model „Kabel 3\4" albo sciezka konczaca sie backslashem rozwalaly
	 * podzial pola. Test pilnuje, zeby nikt nie cofnal jawnego argumentu.
	 */
	public function test_backslash_jest_zwyklym_znakiem(): void {
		$cells = str_getcsv( 'SN-1;Kabel 3\4;"D:\dane\";FV/1', ';', '"', '' );

		self::assertSame( 'SN-1', $cells[0] );
		self::assertSame( 'Kabel 3\4', $cells[1] );
		self::assertSame( 'D:\dane\\', $cells[2] );
		self::assertSame( 'FV/1', $cells[3] );
	}

	/**
	 * STRAZNIK: plik-przyklad DOLACZONY DO WTYCZKI (przyklady/) musi realnie
	 * przechodzic przez parser — inaczej klient dostaje przyklad, ktory nie
	 * importuje sie. Pilnuje tez, zeby zmiana parsera/slownika kategorii nie
	 * uniewaznila cicho zalacznika.
	 */
	public function test_dolaczony_przyklad_csv_importuje_sie_bez_bledow(): void {
		$path = dirname( __DIR__, 2 ) . '/mp-warranty-registry/przyklady/przyklad-import-produktow.csv';

		self::assertFileExists( $path );

		$raw = (string) file_get_contents( $path );
		$utf8 = CsvParser::to_utf8( $raw );

		// Plik MUSI byc czystym UTF-8: inaczej na serwerze bez iconv/intl
		// (patrz notice na ekranie importu) zostalby odrzucony.
		self::assertNotNull( $utf8, 'Przyklad musi byc w UTF-8 — bez tego padnie na serwerze bez iconv/intl.' );
		self::assertSame( $raw, $utf8, 'Przyklad nie powinien wymagac zadnej konwersji (ani BOM, ani CP1250).' );

		$lines = preg_split( '/\r\n|\r|\n/', trim( $utf8 ) );

		self::assertIsArray( $lines );

		$separator = CsvParser::detect_separator( $lines[0] );
		$map       = CsvParser::map_header( str_getcsv( $lines[0], $separator, '"', '' ) );

		self::assertNotNull( $map, 'Naglowek przykladu nie zostal rozpoznany (brak kolumny serial?).' );

		// Przyklad ma pokazywac WSZYSTKIE obslugiwane kolumny, nie tylko wymagana.
		foreach ( array( 'serial', 'model', 'batch', 'purchase_doc', 'purchase_date', 'warranty_until', 'category' ) as $column ) {
			self::assertArrayHasKey( $column, $map, "Przyklad nie pokazuje kolumny {$column}." );
		}

		$data_lines = array_slice( $lines, 1 );

		self::assertCount( 8, $data_lines );

		$rows = array();

		foreach ( $data_lines as $index => $line ) {
			$parsed = CsvParser::parse_row( str_getcsv( trim( $line ), $separator, '"', '' ), $map );

			self::assertTrue(
				$parsed['ok'],
				sprintf( 'Wiersz %d przykladu jest bledny: %s', $index + 2, $parsed['error'] ?? '' )
			);

			$rows[] = $parsed['row'];
		}

		// Import odrzuca duplikaty serialu (po normalizacji) — przyklad nie moze
		// sam w siebie wpadac.
		$normalized = array_map(
			static fn( array $row ): string => Str::normalize_serial( (string) $row['serial'] ),
			$rows
		);

		self::assertSame( $normalized, array_unique( $normalized ), 'Przyklad ma duplikat serialu po normalizacji.' );

		// Wariant „polski Excel" (15.02.2026) sprowadzony do Y-m-d.
		self::assertSame( '2026-02-15', $rows[2]['purchase_date'] );
		self::assertSame( '2028-02-15', $rows[2]['warranty_until'] );

		// Kategoria podana ETYKIETA (nie slugiem) tez ma trafic na slug.
		self::assertSame( 'audio', $rows[1]['category'] );
		self::assertSame( 'agd', $rows[3]['category'] );

		// Wiersz minimalny (tylko serial + model): daty puste, kategoria = fallback.
		self::assertNull( $rows[7]['purchase_date'] );
		self::assertNull( $rows[7]['warranty_until'] );
		self::assertSame( Categories::FALLBACK, $rows[7]['category'] );
	}
}
