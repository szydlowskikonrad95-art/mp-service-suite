<?php
/**
 * Testy SILNIKA TERMINOW (2.17 zasieg, 2.53 czulosc warstwy jednostkowej).
 *
 * Warstwa jednostkowa nie pilnowala dotad terminow ani priorytetu: pomiar
 * mutacyjny audytu podlozyl w tym miejscu trzy bledy i zestaw jednostkowy
 * pozostal ZIELONY (2.53) — skrocony termin naprawy ze 120 godzin do jednej
 * oraz ODWROCONY sens priorytetu (wysoki dostaje wiecej czasu zamiast mniej).
 * Bramka istniala pietro wyzej, w testach z zywym WordPressem, ktore chodza
 * tylko w CI — programista uruchamiajacy zestaw u siebie dostawal zielono
 * i nie dowiadywal sie nic.
 *
 * Liczby NIE sa przepisane ze stalych klasy (test przepisany z kodu przepusci
 * kazda zmiane kodu). Sa przepisane z OBIETNICY: dokumentacja-techniczna/
 * STATE_MACHINE.md — terminy rdzenia i modyfikator priorytetu.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Automator\SlaConfig;
use PHPUnit\Framework\TestCase;

/**
 * Terminy SLA: godziny per status, modyfikator priorytetu, prog ostrzezenia.
 */
final class SlaTerminyTest extends TestCase {

	/**
	 * Kotwica terminu (status_changed_at, UTC) — stala, zeby wynik byl dokladny.
	 */
	private const KOTWICA = '2026-03-01 08:00:00';

	/**
	 * Terminy rdzenia ze STATE_MACHINE.md — status => godziny.
	 *
	 * @return array<int, array{0: string, 1: int, 2: string}>
	 */
	public static function terminy_rdzenia(): array {
		return array(
			'nowe'            => array( 'nowe', 24, '2026-03-02 08:00:00' ),
			// ZERO GODZIN = BRAK TERMINU (4.08, standard branzowy): „do uzupelnienia" to
			// jedyny status, w ktorym czekamy na KLIENTA, wiec licznik stoi. Oczekiwana
			// wartoscia jest tu NULL i to jest CALA tresc tej zmiany — nie mozemy karac
			// terminem za milczenie klienta.
			'do uzupełnienia' => array( 'do uzupełnienia', 0, null ),
			'w analizie'      => array( 'w analizie', 48, '2026-03-03 08:00:00' ),
			'zaakceptowane'   => array( 'zaakceptowane', 24, '2026-03-02 08:00:00' ),
			'w naprawie'      => array( 'w naprawie', 120, '2026-03-06 08:00:00' ),
		);
	}

	/**
	 * Kazdy status rdzenia ma termin ZGODNY Z SPECYFIKACJA, co do godziny.
	 *
	 * To jest kontrola, ktorej brakowalo: skrocenie naprawy ze 120 godzin do
	 * jednej przechodzilo przez warstwe jednostkowa bez sladu.
	 *
	 * @dataProvider terminy_rdzenia
	 *
	 * @param string $status    Status rdzenia.
	 * @param int    $godziny   Obiecane godziny (STATE_MACHINE.md).
	 * @param string|null $oczekiwany Deadline liczony od KOTWICA; NULL = status bez terminu.
	 */
	public function test_terminy_rdzenia_zgodne_z_kartka( string $status, int $godziny, ?string $oczekiwany ): void {
		self::assertSame(
			$oczekiwany,
			SlaConfig::deadline_for( $status, self::KOTWICA, 'normal' ),
			sprintf(
				0 === $godziny
					? 'Status „%s" ma NIE mieć terminu (licznik stoi, czekamy na klienta).'
					: 'Status „%s" ma mieć %d godzin od zmiany statusu.',
				$status,
				$godziny
			)
		);
	}

	/**
	 * Wysoki priorytet SKRACA termin o polowe (naprawa: 120 h => 60 h).
	 */
	public function test_wysoki_priorytet_skraca_termin_o_polowe(): void {
		self::assertSame(
			'2026-03-03 20:00:00',
			SlaConfig::deadline_for( 'w naprawie', self::KOTWICA, 'high' )
		);
	}

	/**
	 * Niski priorytet WYDLUZA termin dwukrotnie (naprawa: 120 h => 240 h).
	 */
	public function test_niski_priorytet_wydluza_termin_dwukrotnie(): void {
		self::assertSame(
			'2026-03-11 08:00:00',
			SlaConfig::deadline_for( 'w naprawie', self::KOTWICA, 'low' )
		);
	}

	/**
	 * SEDNO: sam KIERUNEK priorytetu. Pilna sprawa ma termin WCZESNIEJSZY niz
	 * zwykla, a zwykla wczesniejszy niz malo pilna. Odwrocenie sensu (wysoki
	 * priorytet = wiecej czasu) przechodzilo dotad przez zestaw jednostkowy.
	 */
	public function test_kierunek_priorytetu_pilne_maja_mniej_czasu(): void {
		$pilne  = SlaConfig::deadline_for( 'w naprawie', self::KOTWICA, 'high' );
		$zwykle = SlaConfig::deadline_for( 'w naprawie', self::KOTWICA, 'normal' );
		$luzne  = SlaConfig::deadline_for( 'w naprawie', self::KOTWICA, 'low' );

		self::assertNotNull( $pilne );
		self::assertNotNull( $zwykle );
		self::assertNotNull( $luzne );
		self::assertLessThan( $zwykle, $pilne, 'Wysoki priorytet musi mieć termin WCZEŚNIEJSZY niż zwykły.' );
		self::assertLessThan( $luzne, $zwykle, 'Zwykły priorytet musi mieć termin wcześniejszy niż niski.' );
	}

	/**
	 * Nieznany priorytet zachowuje sie jak zwykly (bez wyjatku i bez skracania).
	 */
	public function test_nieznany_priorytet_liczy_sie_jak_zwykly(): void {
		self::assertSame(
			SlaConfig::deadline_for( 'w naprawie', self::KOTWICA, 'normal' ),
			SlaConfig::deadline_for( 'w naprawie', self::KOTWICA, 'krytyczny-wymyslony' )
		);
	}

	/**
	 * Statusy terminalne NIE maja terminu (sprawy zamknietej nie pilnujemy).
	 */
	public function test_statusy_terminalne_bez_terminu(): void {
		self::assertNull( SlaConfig::deadline_for( 'zamknięte', self::KOTWICA, 'normal' ) );
		self::assertNull( SlaConfig::deadline_for( 'odrzucone', self::KOTWICA, 'normal' ) );
	}

	/**
	 * Brak kotwicy = brak terminu (nie „teraz", zeby przeliczenie nie bylo
	 * retroaktywne i nie tworzylo terminu z powietrza).
	 */
	public function test_brak_kotwicy_to_brak_terminu(): void {
		self::assertNull( SlaConfig::deadline_for( 'w naprawie', null, 'normal' ) );
		self::assertNull( SlaConfig::deadline_for( 'w naprawie', '', 'normal' ) );
	}

	/**
	 * Prog ostrzezenia domyslnie = 25% terminu (naprawa 120 h => 30 h przed).
	 */
	public function test_prog_ostrzezenia_to_cwierc_terminu(): void {
		$cfg = SlaConfig::for_status( 'w naprawie' );

		self::assertSame( 120, $cfg['sla_hours'] );
		self::assertSame( 30, $cfg['warning_hours'] );
		self::assertFalse( $cfg['terminal'] );
	}

	/**
	 * Status spoza rdzenia (i bez definicji wlasnej) = brak pilnowania.
	 */
	public function test_status_nieznany_nie_dostaje_terminu_z_powietrza(): void {
		$cfg = SlaConfig::for_status( 'status-ktorego-nie-ma' );

		self::assertSame( 0, $cfg['sla_hours'] );
		self::assertTrue( $cfg['terminal'] );
		self::assertNull( SlaConfig::deadline_for( 'status-ktorego-nie-ma', self::KOTWICA, 'normal' ) );
	}
}
