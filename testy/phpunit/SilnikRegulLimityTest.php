<?php
/**
 * Testy PASOW BEZPIECZENSTWA silnika reguł i powiadomień (2.17, 2.53).
 *
 * Pomiar mutacyjny audytu podniosl limit akcji reguł na jedno zdarzenie
 * TYSIACKROTNIE i zestaw jednostkowy pozostal zielony (2.53). Limit jest
 * jedyna rzecza, ktora stoi miedzy petla regul (reguła zmienia status =>
 * zdarzenie => reguła zmienia status) a lawina akcji i maili.
 *
 * ⚠️ UCZCIWIE, ZEBY NIKT NIE ODCZYTAL TEGO MOCNIEJ: to jest kontrola WARTOSCI
 * obiecanego pasa, nie kontrola jego DZIALANIA. Wykonanie limitu wymaga bazy
 * i zywego WordPressa — bramka zachowania siedzi w `testy/e2e/d-p31-*.sh`.
 * Ten plik pilnuje tego, co dotad nie bylo pilnowane NIGDZIE w warstwie
 * jednostkowej: ze nikt nie podniesie pasa przez pomylke i nie zobaczy tego
 * dopiero w CI (albo u klienta).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Automator\RuleEngine;
use MP\Automator\Sla;
use PHPUnit\Framework\TestCase;

/**
 * Wartosci pasow bezpieczenstwa automatyzacji.
 */
final class SilnikRegulLimityTest extends TestCase {

	/**
	 * Limit akcji reguł na JEDNO zdarzenie zewnetrzne = 100.
	 *
	 * 100 to liczba z projektu (r.D1): dosc, zeby zaden prawdziwy scenariusz
	 * jej nie dotknal, i malo dosc, zeby petla regul zatrzymala sie w tej samej
	 * sekundzie, w ktorej powstala.
	 */
	public function test_limit_akcji_na_zdarzenie_to_sto(): void {
		self::assertSame( 100, self::stala( RuleEngine::class, 'ACTION_LIMIT' ) );
	}

	/**
	 * Limit jest PASEM, nie dekoracja: ma byc dodatni i rzedu setek. Ta kontrola
	 * lapie takze podniesienie go „na chwile" o rzad wielkosci.
	 */
	public function test_limit_akcji_zostaje_w_rozsadnym_rzedzie_wielkosci(): void {
		$limit = self::stala( RuleEngine::class, 'ACTION_LIMIT' );

		self::assertGreaterThan( 0, $limit, 'Limit 0 zatrzymałby automatyzację całkowicie.' );
		self::assertLessThanOrEqual( 1000, $limit, 'Limit powyżej tysiąca przestaje być pasem bezpieczeństwa.' );
	}

	/**
	 * Nieudana wysylka powiadomienia ponawiana jest 3 razy, nie w nieskonczonosc.
	 */
	public function test_liczba_ponowien_powiadomienia_to_trzy(): void {
		self::assertSame( 3, Sla::MAX_ATTEMPTS );
	}

	/**
	 * Powyzej 5 spraw eskalacja idzie JEDNA zbiorcza wiadomoscia, nie osobnymi.
	 */
	public function test_prog_wiadomosci_zbiorczej_to_piec_spraw(): void {
		self::assertSame( 5, Sla::DIGEST_THRESHOLD );
	}

	/**
	 * Odczyt stalej klasy (takze prywatnej) — pas bezpieczenstwa nie musi byc
	 * publiczny, zeby byl pilnowany.
	 *
	 * @param string $klasa  Nazwa klasy.
	 * @param string $stala  Nazwa stalej.
	 * @return int
	 */
	private static function stala( string $klasa, string $stala ): int {
		$ref = new ReflectionClass( $klasa );

		self::assertTrue( $ref->hasConstant( $stala ), sprintf( 'Brak stałej %s::%s.', $klasa, $stala ) );

		return (int) $ref->getConstant( $stala );
	}
}
