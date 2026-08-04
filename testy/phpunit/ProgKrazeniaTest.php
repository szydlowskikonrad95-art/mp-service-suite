<?php
/**
 * Cz.1 pkt 3 (trzecia czesc) — PROG KRAZENIA jest WYPROWADZONY, nie wymyslony.
 *
 * Wykrywanie spraw krazacych stoi na jednej liczbie: ile godzin sprawa moze byc
 * w obsludze, zanim uznamy, ze krazy. Liczba dziedzinowa wzieta z sufitu brzmi
 * dokladnie tak samo madrze jak policzona — i wlasnie dlatego jest grozna: nikt
 * jej nigdy nie zakwestionuje, bo wyglada na przemyslana.
 *
 * Ta kontrola pilnuje, ze prog to RACHUNEK z konfiguracji produktu:
 *   suma godzin wszystkich statusow rdzenia × najwolniejszy modyfikator priorytetu.
 * Gdy ktos wpisze tam stala (albo prog przestanie isc za konfiguracja terminow),
 * kontrola pada — i o to chodzi.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Automator\Sla;
use MP\Automator\SlaConfig;
use PHPUnit\Framework\TestCase;

/**
 * Prog wykrywania spraw krazacych.
 */
final class ProgKrazeniaTest extends TestCase {

	/**
	 * Prog = suma godzin statusow × najwolniejszy modyfikator. Liczymy to w tescie
	 * DRUGI RAZ, z tych samych zrodel, i porownujemy — dzieki temu kontrola nie
	 * powtarza magicznej liczby, tylko powtarza RACHUNEK.
	 */
	public function test_prog_jest_wyprowadzony_z_konfiguracji_terminow(): void {
		$suma = 0;

		foreach ( SlaConfig::core_effective() as $konfiguracja ) {
			$suma += (int) $konfiguracja['sla_hours'];
		}

		$oczekiwany = (int) ceil( $suma * SlaConfig::slowest_priority_modifier() );

		self::assertSame(
			$oczekiwany,
			Sla::stale_threshold_hours(),
			'Próg przestał wynikać z konfiguracji terminów — czyli stał się liczbą wymyśloną.'
		);
	}

	/**
	 * Przy domyslnej konfiguracji: (24+0+48+24+120) × 2,0 = 432 godziny = 18 dni.
	 *
	 * Ta kontrola jest po to, zeby zmiana domyslnych godzin statusow albo
	 * modyfikatorow priorytetu NIE przeszla niezauwazona: przesuwa granice, po
	 * ktorej produkt mowi czlowiekowi „ta sprawa krazy".
	 *
	 * ⭐ I ZADZIALALA: 4.08 status „do uzupelnienia" dostal ZERO godzin (licznik stoi,
	 * gdy czekamy na klienta — standard branzowy), przez co suma spadla z 288 na 216,
	 * a prog z 576 na 432 godziny. Liczby ponizej sa wiec ZAKTUALIZOWANE SWIADOMIE,
	 * razem z ta zmiana — nie „naprawione, bo test padl". Prog nadal wynika z rachunku,
	 * czego pilnuje kontrola obok.
	 */
	public function test_domyslna_konfiguracja_daje_432_godziny(): void {
		self::assertSame( 216, array_sum( SlaConfig::core_defaults() ), 'Suma domyślnych godzin rdzenia się zmieniła.' );
		self::assertSame( 2.0, SlaConfig::slowest_priority_modifier(), 'Najwolniejszy priorytet przestał podwajać terminy.' );
		self::assertSame( 432, Sla::stale_threshold_hours() );
	}

	/**
	 * Prog jest DODATNI i STALY miedzy wywolaniami.
	 *
	 * ⚠️ Uczciwie o zakresie: to kontrola determinizmu, NIE kontrola filtra
	 * `mp_sla_stale_hours` — warstwa jednostkowa nie ma prawdziwego `add_filter`
	 * (stub tylko oddaje wartosc), wiec nadpisania progu nie da sie tu wykonac.
	 * Filtr jest sprawdzany na zywym WordPressie w `testy/e2e/d-cz1-3-krazenie.sh`.
	 */
	public function test_prog_jest_dodatni_i_staly(): void {
		$stary = Sla::stale_threshold_hours();

		self::assertGreaterThan( 0, $stary, 'Próg zerowy oskarżyłby o krążenie każdą sprawę.' );
		self::assertSame( $stary, Sla::stale_threshold_hours(), 'Próg nie może zmieniać się między wywołaniami.' );
	}
}
