<?php
/**
 * Parser CSV rejestru — odporny na polskiego Excela (spec P2.1).
 *
 * Windows-1250 -> UTF-8 (iconv), zdjecie BOM, separator ';' i ',',
 * naglowek mapowany po nazwach (z aliasami), daty Y-m-d oraz d.m.Y.
 * Czysta logika — testowana jednostkowo bez WP.
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * Normalizacja pliku CSV i parsowanie wierszy.
 */
final class CsvParser {

	/**
	 * Kanoniczne kolumny (naglowek seeda) => aliasy akceptowane.
	 */
	private const COLUMNS = array(
		'serial'         => array( 'serial', 'numer_seryjny', 'serial_number', 'sn' ),
		'model'          => array( 'model' ),
		'batch'          => array( 'partia', 'batch', 'partia_produkcyjna' ),
		'purchase_doc'   => array( 'dokument_zakupu', 'faktura', 'invoice', 'purchase_document' ),
		'purchase_date'  => array( 'data_zakupu', 'purchase_date' ),
		'warranty_until' => array( 'gwarancja_do', 'warranty_until', 'koniec_gwarancji' ),
	);

	/**
	 * Czy serwer ma czym konwertowac Windows-1250 -> UTF-8 (iconv lub intl).
	 *
	 * Bez zadnego z nich import przyjmie WYLACZNIE pliki juz w UTF-8
	 * (ekran admina pokazuje wtedy ostrzezenie).
	 *
	 * @return bool True gdy jest iconv lub UConverter.
	 */
	public static function has_transcoder(): bool {
		return function_exists( 'iconv' ) || class_exists( \UConverter::class );
	}

	/**
	 * Konwertuje surowa tresc pliku do UTF-8 bez BOM.
	 *
	 * Poprawne UTF-8 zostaje. Inaczej: Windows-1250 (polski Excel) przez
	 * iconv, a bez iconv przez UConverter (intl). Brak OBU konwerterow =
	 * null (uczciwa odmowa zamiast cichego przeklamania znakow; mbstring
	 * NIE zna CP1250 — fakt sprawdzony, ValueError).
	 *
	 * @param string $raw Surowe bajty pliku.
	 * @return string|null Tresc w UTF-8 lub null (nie da sie bezpiecznie).
	 */
	public static function to_utf8( string $raw ): ?string {
		if ( str_starts_with( $raw, "\xEF\xBB\xBF" ) ) {
			$raw = substr( $raw, 3 );
		}

		if ( 1 === preg_match( '//u', $raw ) ) {
			return $raw;
		}

		if ( function_exists( 'iconv' ) ) {
			$converted = iconv( 'CP1250', 'UTF-8//TRANSLIT', $raw );

			if ( false !== $converted ) {
				return $converted;
			}
		}

		if ( class_exists( \UConverter::class ) ) {
			$converted = \UConverter::transcode( $raw, 'UTF-8', 'windows-1250' );

			if ( false !== $converted ) {
				return $converted;
			}
		}

		return null;
	}

	/**
	 * Wykrywa separator z linii naglowka.
	 *
	 * @param string $header_line Pierwsza linia pliku.
	 * @return string ';' lub ','.
	 */
	public static function detect_separator( string $header_line ): string {
		return substr_count( $header_line, ';' ) >= substr_count( $header_line, ',' ) ? ';' : ',';
	}

	/**
	 * Mapuje naglowek na kolumny kanoniczne.
	 *
	 * @param string[] $header Komorki naglowka.
	 * @return array<string, int>|null Mapa kolumna=>indeks lub null (brak wymaganej kolumny serial).
	 */
	public static function map_header( array $header ): ?array {
		$map = array();

		foreach ( $header as $index => $cell ) {
			$key = strtolower( trim( (string) $cell ) );

			foreach ( self::COLUMNS as $canonical => $aliases ) {
				if ( in_array( $key, $aliases, true ) ) {
					$map[ $canonical ] = (int) $index;
				}
			}
		}

		return isset( $map['serial'] ) ? $map : null;
	}

	/**
	 * Parsuje pojedynczy wiersz danych wg mapy naglowka.
	 *
	 * @param string[]           $cells Komorki wiersza.
	 * @param array<string, int> $map   Mapa kolumn.
	 * @return array{ok: bool, row?: array<string, string|null>, error?: string}
	 */
	public static function parse_row( array $cells, array $map ): array {
		$get = static function ( string $column ) use ( $cells, $map ): string {
			return isset( $map[ $column ] ) ? trim( (string) ( $cells[ $map[ $column ] ] ?? '' ) ) : '';
		};

		$serial = $get( 'serial' );

		if ( '' === $serial ) {
			return array(
				'ok'    => false,
				'error' => 'pusty numer seryjny',
			);
		}

		$purchase_date = self::normalize_date( $get( 'purchase_date' ) );

		if ( false === $purchase_date ) {
			return array(
				'ok'    => false,
				'error' => 'niepoprawna data zakupu',
			);
		}

		$warranty_until = self::normalize_date( $get( 'warranty_until' ) );

		if ( false === $warranty_until ) {
			return array(
				'ok'    => false,
				'error' => 'niepoprawna data konca gwarancji',
			);
		}

		return array(
			'ok'  => true,
			'row' => array(
				'serial'         => $serial,
				'model'          => $get( 'model' ),
				'batch'          => $get( 'batch' ),
				'purchase_doc'   => $get( 'purchase_doc' ),
				'purchase_date'  => $purchase_date,
				'warranty_until' => $warranty_until,
			),
		);
	}

	/**
	 * Normalizuje date do Y-m-d.
	 *
	 * Puste = null (dozwolone). Akceptowane: Y-m-d oraz d.m.Y (polski Excel).
	 *
	 * @param string $value Wartosc z komorki.
	 * @return string|null|false Y-m-d, null (puste) lub false (niepoprawna).
	 */
	public static function normalize_date( string $value ) {
		if ( '' === $value ) {
			return null;
		}

		if ( 1 === preg_match( '/^(\d{4})-(\d{2})-(\d{2})$/', $value, $m ) ) {
			return checkdate( (int) $m[2], (int) $m[3], (int) $m[1] ) ? $value : false;
		}

		if ( 1 === preg_match( '/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/', $value, $m ) ) {
			return checkdate( (int) $m[2], (int) $m[1], (int) $m[3] )
				? sprintf( '%04d-%02d-%02d', (int) $m[3], (int) $m[2], (int) $m[1] )
				: false;
		}

		return false;
	}
}
