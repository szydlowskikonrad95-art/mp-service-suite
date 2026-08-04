<?php
/**
 * Poz. 2.14 — etykiety warunkow na ekranie automatyzacji stoja pod kluczami,
 * ktore produkt NAPRAWDE niesie.
 *
 * Wzorcowa awaria cicha: slownik etykiet mial klucz `priorytet`, a kontekst sprawy
 * niesie `priority`. Nazwa `priorytet` nie jest w produkcie definiowana NIGDZIE, wiec
 * `$pola[$klucz] ?? $klucz` po cichu wypisywal czlowiekowi klucz techniczny. Nic nie
 * padalo, nic nie logowalo — etykieta po prostu nie dzialala ani razu.
 *
 * Kontrola pilnuje TRZECH rzeczy naraz, bo sama wartosc „priority" zalatalaby
 * egzemplarz, a nie wzorzec:
 *   1. zaden klucz slownika nie jest widmem (⊆ `Rules::CONDITION_KEYS` + `author_type`),
 *   2. kazdy klucz kontekstu MA etykiete, i to TE SAMA co na blizniaczym ekranie
 *      ustawien — bo to on jest w tej sprawie wzorcem (`SettingsScreen::etykieta_warunku`),
 *   3. skutek dla czlowieka: opis warunku po priorytecie nie wypisuje klucza technicznego.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Automator\Admin\PanelScreen;
use MP\Automator\Admin\SettingsScreen;
use MP\Automator\Rules;
use PHPUnit\Framework\TestCase;

/**
 * Slownik etykiet warunku na ekranie automatyzacji.
 */
final class EtykietyWarunkowPaneluTest extends TestCase {

	/**
	 * `author_type` to jedyny klucz spoza `CONDITION_KEYS`, ktory kontekst naprawde
	 * niesie: dokłada go wyzwalacz wiadomosci (`RuleEngine::run_message_rules`).
	 */
	private const KLUCZ_WIADOMOSCI = 'author_type';

	/**
	 * Kazda etykieta panelu stoi pod kluczem, ktory produkt niesie.
	 *
	 * To jest kontrola, ktora lapie literowke 2.14: `priorytet` nie nalezy do
	 * zadnego kontekstu, wiec etykieta pod nim nie ma jak sie wykonac.
	 */
	public function test_slownik_nie_ma_kluczy_widm(): void {
		$dozwolone = array_merge( Rules::CONDITION_KEYS, array( self::KLUCZ_WIADOMOSCI ) );

		foreach ( array_keys( self::slownik_panelu() ) as $klucz ) {
			self::assertContains(
				$klucz,
				$dozwolone,
				sprintf(
					'Etykieta stoi pod kluczem „%s", ktorego kontekst sprawy nie niesie — nie wykona sie nigdy i nic o tym nie powie.',
					$klucz
				)
			);
		}
	}

	/**
	 * Kazdy klucz kontekstu ma na panelu etykiete PO LUDZKU — i dokladnie te sama,
	 * ktora pod tym kluczem pokazuje ekran ustawien.
	 *
	 * Blizniaczy ekran jest tu miara: ten sam produkt, ten sam slownik pojec. Rozjazd
	 * miedzy nimi zawsze znaczy, ze jeden z dwoch ekranów klamie czlowiekowi.
	 */
	public function test_kazdy_klucz_kontekstu_ma_te_sama_nazwe_co_na_ekranie_ustawien(): void {
		$panel = self::slownik_panelu();

		foreach ( Rules::CONDITION_KEYS as $klucz ) {
			self::assertArrayHasKey(
				$klucz,
				$panel,
				sprintf( 'Klucz kontekstu „%s" nie ma na panelu zadnej nazwy — ekran wypisze techniczna.', $klucz )
			);

			$ustawienia = (string) self::wywolaj( SettingsScreen::class, 'etykieta_warunku', array( $klucz ) );

			// Ekran ustawien dokleja martwym polom ostrzezenie „(pole zawsze puste…)";
			// porownujemy sama nazwe, bo ostrzezenie jest jego wlasnym zadaniem.
			$nazwa = explode( ' (', $ustawienia )[0];

			self::assertSame(
				$nazwa,
				$panel[ $klucz ],
				sprintf( 'Panel i ekran ustawien nazywaja klucz „%s" inaczej.', $klucz )
			);
		}
	}

	/**
	 * Skutek dla czlowieka: warunek po priorytecie czyta sie po polsku, a nie
	 * jako `priority to high`.
	 */
	public function test_warunek_po_priorytecie_czyta_sie_po_ludzku(): void {
		$opis = (string) self::wywolaj( PanelScreen::class, 'opis_warunku', array( 'priority', 'equals', 'high' ) );

		self::assertStringNotContainsString(
			'priority',
			$opis,
			'Opis warunku wypisuje klucz techniczny — etykieta nie zadzialala.'
		);
		self::assertSame( 'priorytet to high', $opis );
	}

	/**
	 * Slownik etykiet panelu (metoda prywatna — czytamy odbiciem, bo to szczegol
	 * ekranu, a nie API dla reszty produktu).
	 *
	 * @return array<string, string>
	 */
	private static function slownik_panelu(): array {
		/** @var array<string, string> $slownik */
		$slownik = self::wywolaj( PanelScreen::class, 'pola_warunku', array() );

		return $slownik;
	}

	/**
	 * Wywoluje metode prywatna klasy ekranu.
	 *
	 * @param class-string     $klasa   Klasa.
	 * @param string           $metoda  Nazwa metody.
	 * @param array<int,mixed> $argumenty Argumenty.
	 * @return mixed
	 */
	private static function wywolaj( string $klasa, string $metoda, array $argumenty ) {
		$refleksja = new ReflectionMethod( $klasa, $metoda );
		$refleksja->setAccessible( true );

		return $refleksja->invokeArgs( null, $argumenty );
	}
}
