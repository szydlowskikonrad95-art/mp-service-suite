<?php
/**
 * Testy „Stanu witryny" dla Rejestru gwarancji (B).
 *
 * Rejestr stoi na imporcie CSV, a klienci wysylaja pliki z polskiego Excela
 * (Windows-1250). Bez konwertera taki plik jest UCZCIWIE ODRZUCANY — lepiej,
 * zeby klient dowiedzial sie o tym z diagnostyki niz przy pierwszym imporcie
 * bazy produktow.
 *
 * @package MP\Registry\Admin
 */

namespace MP\Registry\Admin;

use MP\Registry\Common\SiteHealth;
use MP\Registry\CsvParser;

/**
 * Rejestracja testow Rejestru w Narzedzia -> Stan witryny.
 */
final class SiteHealthTests {

	/**
	 * Wpina testy w natywny ekran WP.
	 *
	 * @return void
	 */
	public static function register(): void {
		SiteHealth::register(
			'mp_registry',
			array(
				'csv_kodowanie' => array( self::class, 'test_kodowanie_csv' ),
				'cron_importow' => array( self::class, 'test_cron_importow' ),
			)
		);
	}

	/**
	 * Czy sprzatanie plikow importu jest zaplanowane (audyt cyklu zycia 27.07).
	 *
	 * Wgrane pliki CSV zawieraja dane klientow (numery seryjne, faktury, nazwiska).
	 * Zadanie usuwa je po zakonczeniu importu; gdy zniknie z listy zadan, pliki
	 * zostaja na serwerze bezterminowo, a nic tego nie sygnalizuje.
	 *
	 * @return array<string, mixed>
	 */
	public static function test_cron_importow(): array {
		if ( wp_next_scheduled( \MP\Registry\Lifecycle::IMPORTS_CRON ) ) {
			return SiteHealth::wynik(
				'mp_registry_cron_importow',
				'good',
				__( 'Sprzątanie plików importu jest zaplanowane', 'mp-warranty-registry' ),
				__( 'Codzienne zadanie usuwa wgrane pliki CSV po zakończonym imporcie.', 'mp-warranty-registry' )
			);
		}

		return SiteHealth::wynik(
			'mp_registry_cron_importow',
			'critical',
			__( 'Sprzątanie plików importu NIE JEST zaplanowane', 'mp-warranty-registry' ),
			__( 'Zadanie usuwające wgrane pliki CSV zniknęło z listy zadań WordPressa. Pliki zawierają dane klientów (numery seryjne, faktury, nazwiska) i będą zostawać na serwerze bezterminowo.', 'mp-warranty-registry' ),
			__( 'Wejdź w Wtyczki, wyłącz i włącz ponownie „MP Warranty & Serial Registry" — zadanie zostanie odtworzone.', 'mp-warranty-registry' )
		);
	}

	/**
	 * Konwerter iconv albo intl: bez nich import przyjmie WYLACZNIE pliki UTF-8.
	 *
	 * @return array<string, mixed>
	 */
	public static function test_kodowanie_csv(): array {
		if ( CsvParser::has_transcoder() ) {
			return SiteHealth::wynik(
				'mp_registry_csv_kodowanie',
				'good',
				__( 'Import CSV: pliki z polskiego Excela są obsługiwane', 'mp-warranty-registry' ),
				__( 'Serwer ma konwerter kodowania (iconv lub intl), więc plik zapisany przez Excela w Windows-1250 zostanie poprawnie odczytany razem z polskimi znakami.', 'mp-warranty-registry' )
			);
		}

		return SiteHealth::wynik(
			'mp_registry_csv_kodowanie',
			'recommended',
			__( 'Import CSV przyjmie tylko pliki UTF-8', 'mp-warranty-registry' ),
			__( 'Serwer nie ma ani rozszerzenia „iconv", ani „intl". Plik zapisany przez polskiego Excela (Windows-1250) zostanie odrzucony — celowo, żeby nie przekłamać polskich znaków w nazwach produktów.', 'mp-warranty-registry' ),
			__( 'Poproś hosting o włączenie rozszerzenia PHP „iconv" (albo „intl"). Alternatywnie zapisuj plik w Excelu przez „Zapisz jako → CSV UTF-8".', 'mp-warranty-registry' )
		);
	}
}
