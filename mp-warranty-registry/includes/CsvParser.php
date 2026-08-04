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
		'category'       => array( 'kategoria', 'category', 'kategoria_produktu' ),
	);

	/**
	 * Najkrotszy dopuszczalny numer seryjny — tyle samo, co `Validator::validate_serial()`
	 * na drugiej drodze wejscia (formularz). Jedna rzecz, jedna regula.
	 */
	public const MIN_SERIAL = 2;

	/**
	 * Limity dlugosci pol — LUSTRO szerokosci kolumn w `Schema.php`
	 * (`serial_display`/`serial_normalized` VARCHAR(100), `model` VARCHAR(190),
	 * `batch` VARCHAR(100), `purchase_document` VARCHAR(190)).
	 *
	 * ⚠️ Zmiana szerokosci kolumny MUSI isc razem ze zmiana tej tablicy — pilnuje
	 * tego test e2e, ktory czyta prawdziwe szerokosci z `information_schema`
	 * i porownuje je z tymi liczbami. Nie przepisuj ich „na oko".
	 */
	private const LIMITY = array(
		'serial'       => 100,
		'model'        => 190,
		'batch'        => 100,
		'purchase_doc' => 190,
	);

	/**
	 * Nazwy pol po polsku do komunikatu w raporcie bledow — administrator ma
	 * przeczytac, KTORE pole poprawic, a nie zgadywac z nazwy kolumny w bazie.
	 */
	private const ETYKIETY = array(
		'serial'       => 'numer seryjny',
		'model'        => 'model',
		'batch'        => 'partia produkcyjna',
		'purchase_doc' => 'dokument zakupu',
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

		// ⚠️ Plik NIE jest w calosci poprawnym UTF-8 — ale to jeszcze NIE znaczy, ze jest
		// w CP1250. Wczesniej kazdy JEDEN zly bajt (np. znak wklejony z Worda) kierowal
		// CALY plik do konwersji z CP1250, co reinterpretowalo poprawne polskie znaki UTF-8
		// jako pojedyncze bajty CP1250 => krzaki w calym pliku, bez ostrzezenia.
		// Znalezione czytaniem liniowym 30.07.
		//
		// Rozstrzygamy PROPORCJA, nie pojedynczym bajtem: liczymy, jaka czesc bajtow
		// wysokich (>= 0x80) sklada sie w POPRAWNE sekwencje UTF-8. Prawdziwy plik UTF-8
		// z drobnym uszkodzeniem ma ten udzial blisko 1. Plik CP1250 ma go niski — tam bajty
		// wysokie sa POJEDYNCZYMI znakami i tylko przypadkiem trafiaja w poprawna sekwencje
		// (np. „ćąą" = E6 B9 B9 to formalnie poprawna trojka UTF-8, dlatego samo „czy jest
		// jakakolwiek poprawna sekwencja" NIE wystarcza jako kryterium).
		if ( self::wyglada_na_uszkodzone_utf8( $raw ) ) {
			// Usuwamy WYLACZNIE nieprawidlowe bajty, reszta (polskie znaki) zostaje nietknieta.
			$oczyszczone = preg_replace( '/[\x00-\x08\x0B\x0C\x0E-\x1F]/', '', $raw );
			$oczyszczone = is_string( $oczyszczone ) ? $oczyszczone : $raw;

			if ( function_exists( 'iconv' ) ) {
				$bez_smieci = iconv( 'UTF-8', 'UTF-8//IGNORE', $oczyszczone );

				if ( false !== $bez_smieci && 1 === preg_match( '//u', $bez_smieci ) ) {
					return $bez_smieci;
				}
			}

			$bez_smieci = mb_convert_encoding( $oczyszczone, 'UTF-8', 'UTF-8' );

			if ( is_string( $bez_smieci ) && 1 === preg_match( '//u', $bez_smieci ) ) {
				return $bez_smieci;
			}
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
	 * Czy tresc to UTF-8 z drobnym uszkodzeniem (a nie plik w CP1250)?
	 *
	 * Kryterium: udzial bajtow wysokich (>= 0x80) skladajacych sie w POPRAWNE sekwencje
	 * UTF-8 w stosunku do wszystkich bajtow wysokich. Prog 0.9 — plik UTF-8 z kilkoma
	 * zlymi bajtami jest blisko 1, plik CP1250 znacznie nizej (tam bajty wysokie to
	 * pojedyncze znaki, trafiajace w poprawne sekwencje tylko przypadkiem).
	 *
	 * @param string $raw Surowe bajty (bez BOM).
	 * @return bool
	 */
	private static function wyglada_na_uszkodzone_utf8( string $raw ): bool {
		$wysokie = preg_match_all( '/[\x80-\xFF]/', $raw );

		if ( ! is_int( $wysokie ) || 0 === $wysokie ) {
			// Same bajty ASCII, a mimo to niepoprawne UTF-8 => bajty sterujace. Traktujemy
			// jak uszkodzone UTF-8 (czyszczenie), nie jak CP1250 (konwersja nic nie da).
			return true;
		}

		$dopasowania = array();
		$sekwencje   = preg_match_all(
			'/[\xC2-\xDF][\x80-\xBF]|[\xE0-\xEF][\x80-\xBF]{2}|[\xF0-\xF4][\x80-\xBF]{3}/',
			$raw,
			$dopasowania
		);

		if ( ! is_int( $sekwencje ) || 0 === $sekwencje ) {
			return false;
		}

		$bajty_w_sekwencjach = 0;

		foreach ( $dopasowania[0] as $sekwencja ) {
			$bajty_w_sekwencjach += strlen( $sekwencja );
		}

		return ( $bajty_w_sekwencjach / $wysokie ) >= 0.9;
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
		// ZŁA LICZBA KOLUMN = wiersz do raportu bledow, NIE do bazy.
		// Bez tej kontroli wiersz urwany (np. reczna edycja w Notatniku, przerwany eksport)
		// dawal dla brakujacych kolumn ciche PUSTE ciagi — nieodroznialne od pola celowo
		// pustego (puste daty sa legalne). Produkt wchodzil wtedy do rejestru BEZ daty zakupu
		// i gwarancji, a system liczyl klientowi status gwarancji z niepelnych danych.
		// Sprawdzamy OBECNOSC kolumny (array_key_exists), nie jej wartosc: pole legalnie puste
		// ma swoj separator, wiec indeks ISTNIEJE i jest pustym ciagiem. Wiersz urwany indeksu
		// nie ma wcale. Znalezione czytaniem liniowym 30.07.
		$brakujace = array();

		foreach ( $map as $kolumna => $indeks ) {
			if ( ! array_key_exists( $indeks, $cells ) ) {
				$brakujace[] = $kolumna;
			}
		}

		if ( array() !== $brakujace ) {
			return array(
				'ok'    => false,
				'error' => sprintf(
					'zla liczba kolumn (wiersz ma %d, brakuje: %s)',
					count( $cells ),
					implode( ', ', $brakujace )
				),
			);
		}

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

		// ⛔ DLUGOSCI. Produkt ZNA szerokosc kazdej kolumny i egzekwuje ja w formularzu
		// (`Validator::validate_serial` — 2..100 znakow, dokladnie tyle, ile ma kolumna),
		// ale DRUGIE drzwi do tej samej tabeli — import — nie sprawdzaly tego ani razu.
		// Numer o 249 znakach przechodzil przez parser i padal dopiero na zapisie, a admin
		// dostawal w raporcie „blad zapisu do bazy": komunikat, ktory NIE MOWI, co poprawic.
		// Granicy pilnowal silnik bazy, nie kod. Zmierzone na zywym demie (3.08).
		if ( mb_strlen( $serial ) < self::MIN_SERIAL ) {
			return array(
				'ok'    => false,
				'error' => sprintf(
					'numer seryjny ma %d znak(i), a wymagane sa co najmniej %d',
					mb_strlen( $serial ),
					self::MIN_SERIAL
				),
			);
		}

		foreach ( self::LIMITY as $kolumna => $limit ) {
			$wartosc = $get( $kolumna );

			if ( mb_strlen( $wartosc ) > $limit ) {
				return array(
					'ok'    => false,
					'error' => sprintf(
						'%s ma %d znakow, a limit to %d',
						self::ETYKIETY[ $kolumna ] ?? $kolumna,
						mb_strlen( $wartosc ),
						$limit
					),
				);
			}
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

		// Gwarancja konczaca sie przed zakupem to najczestsza literowka (rok z palca).
		//
		// Audyt 29.07: ta sama regula byla egzekwowana TYLKO przy recznej poprawce danych
		// produktu (`Repo::update`, od 1.1.0), a NIE przy imporcie — czyli przy glownej
		// drodze wejscia danych. Wiersz z zakupem 2026-08-01 i gwarancja do 2026-01-01
		// wjezdzal bez slowa i dostawal normalny status, bo `WarrantyStatus::compute()`
		// patrzy tylko na date konca. Pilnowalismy reguly tam, gdzie prawie nikt nie wchodzi.
		//
		// Kazda data z osobna jest juz sprawdzona wyzej; tu porownujemy je ZE SOBA.
		// Puste daty sa dozwolone (kolumny opcjonalne), wiec warunek tylko dla obu wypelnionych.
		if ( null !== $purchase_date && null !== $warranty_until && $warranty_until < $purchase_date ) {
			return array(
				'ok'    => false,
				'error' => 'gwarancja konczy sie przed data zakupu',
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
				'category'       => Categories::sanitize( $get( 'category' ) ),
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
