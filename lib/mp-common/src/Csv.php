<?php
/**
 * Zapis CSV bezpieczny dla arkusza kalkulacyjnego (wspolny dla 3 pluginow).
 *
 * ⛔ Po co ta klasa istnieje. Produkt zapisywal pliki CSV w DWOCH miejscach
 * i tylko JEDNO z nich bylo dokonczone:
 *   · eksport raportow (modul automatu) — ochrona przed formula arkusza na
 *     KAZDYM polu, znacznik kolejnosci bajtow, konwencja zgodna z RFC-4180;
 *   · raport bledow importu (modul rejestru) — wartosc z pliku uzytkownika
 *     szla do pliku SUROWA, bez znacznika i z inna konwencja ucieczki.
 *
 * To nie byly trzy przypadki, tylko jeden moduł dokonczony i drugi nie. Autor
 * sam opisal wage tej ochrony w komentarzu: „OBOWIAZKOWE (RCE u klienta)".
 *
 * Sciezka wyzwolenia jest zwykla, nie egzotyczna: ten sam numer seryjny dwa
 * razy w jednym pliku (albo ponowny import tego samego pliku) trafia do raportu
 * bledow, administrator go pobiera i otwiera w arkuszu — a komorka zaczynajaca
 * sie od znaku rownosci jest tam FORMULA i wykona sie.
 *
 * @package MP\Common
 */

namespace MP\Common;

/**
 * Wspolne reguly zapisu CSV.
 */
final class Csv {

	/**
	 * Separator kolumn (spojny w calym produkcie).
	 */
	public const SEP = ';';

	/**
	 * Znacznik kolejnosci bajtow — bez niego arkusz kalkulacyjny czyta polskie
	 * znaki jako krzaki. Wartosci z pliku klienta (numer seryjny, model) moga
	 * je zawierac, wiec dotyczy to takze raportu bledow.
	 */
	public const BOM = "\xEF\xBB\xBF";

	/**
	 * Znaki, od ktorych arkusz rozpoznaje FORMULE.
	 */
	private const ZNAKI_FORMULY = array( '=', '+', '-', '@', "\t", "\r" );

	/**
	 * Zabezpiecza pojedyncza wartosc przed wykonaniem jako formula.
	 *
	 * @param string $value Wartosc surowa.
	 * @return string
	 */
	public static function harden( string $value ): string {
		if ( '' === $value ) {
			return $value;
		}

		return in_array( $value[0], self::ZNAKI_FORMULY, true ) ? "'" . $value : $value;
	}

	/**
	 * Zabezpiecza caly wiersz.
	 *
	 * @param array<int, string> $cells Komorki surowe.
	 * @return array<int, string>
	 */
	public static function harden_row( array $cells ): array {
		return array_map( array( self::class, 'harden' ), $cells );
	}

	/**
	 * Sklada JEDEN wiersz CSV jako tekst — z ochrona przed formula i konwencja
	 * RFC-4180 (pusty znak ucieczki, tak jak czyta to arkusz kalkulacyjny).
	 *
	 * Wczesniej dwa moduly zapisywaly CSV dwiema roznymi konwencjami ucieczki
	 * (pusta i ukosnik wsteczny), co przy wartosci z ukosnikiem i cudzyslowem
	 * naraz psulo odczyt.
	 *
	 * @param array<int, string> $cells Komorki surowe.
	 * @return string Wiersz zakonczony znakiem nowej linii.
	 */
	public static function row( array $cells ): string {
		$safe = self::harden_row( $cells );

		$strumien = fopen( 'php://temp', 'r+' ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fopen -- bufor w pamieci, nie plik.

		if ( false === $strumien ) {
			// Awaryjnie: cytujemy recznie, zeby raport nie rozjechal kolumn.
			$reczne = array_map(
				static fn( string $p ): string => '"' . str_replace( '"', '""', $p ) . '"',
				$safe
			);

			return implode( self::SEP, $reczne ) . "\n";
		}

		// $escape PUSTY = RFC-4180 (jak arkusz kalkulacyjny). Jawnie, bo PHP 8.4+
		// odradza pominiecie argumentu, a jego wartosc domyslna ma sie zmienic.
		fputcsv( $strumien, $safe, self::SEP, '"', '' ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fputcsv -- bufor w pamieci.
		rewind( $strumien );
		$wiersz = (string) stream_get_contents( $strumien );
		fclose( $strumien ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fclose -- para do fopen.

		return $wiersz;
	}
}
