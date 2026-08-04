<?php
/**
 * Testy DEFINICJI STATUSOW WLASNYCH (2.17 — `StatusDefs` bez testu jednostkowego).
 *
 * Przez ten kod przechodzi kazdy status dodany przez koordynatora z ekranu
 * ustawien: etykieta widoczna dla klienta, znacznik „terminalny" (czyli czy
 * sprawa przestaje byc pilnowana terminem) i godziny SLA. Blad tutaj nie wywala
 * niczego glosno — po prostu status zachowuje sie inaczej, niz ustawiono.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Automator\StatusDefs;
use PHPUnit\Framework\TestCase;

/**
 * Porzadkowanie definicji statusu wlasnego przed zapisem.
 */
final class StatusyWlasneTest extends TestCase {

	/**
	 * Komplet pol przechodzi bez zmiany wartosci.
	 */
	public function test_pelna_definicja_przechodzi_bez_zmian(): void {
		$def = StatusDefs::sanitize_def(
			array(
				'label'         => 'U dostawcy',
				'active'        => true,
				'terminal'      => false,
				'sla_hours'     => 48,
				'warning_hours' => 12,
			)
		);

		self::assertSame( 'U dostawcy', $def['label'] );
		self::assertTrue( $def['active'] );
		self::assertFalse( $def['terminal'] );
		self::assertSame( 48, $def['sla_hours'] );
		self::assertSame( 12, $def['warning_hours'] );
	}

	/**
	 * Definicja niepelna dostaje komplet pol — zapis nie moze polec na braku
	 * klucza, a status nie moze powstac „bez zdania" w sprawie terminalnosci.
	 */
	public function test_niepelna_definicja_dostaje_komplet_pol(): void {
		$def = StatusDefs::sanitize_def( array() );

		self::assertSame(
			array( 'label', 'active', 'terminal', 'sla_hours', 'warning_hours' ),
			array_keys( $def )
		);
		self::assertSame( '', $def['label'] );
		self::assertFalse( $def['active'] );
		self::assertFalse( $def['terminal'] );
		self::assertSame( 0, $def['sla_hours'] );
		self::assertSame( 0, $def['warning_hours'] );
	}

	/**
	 * Ujemne godziny to zero, nie ujemny termin (deadline przed utworzeniem
	 * sprawy = sprawa przeterminowana w chwili powstania).
	 */
	public function test_ujemne_godziny_schodza_do_zera(): void {
		$def = StatusDefs::sanitize_def(
			array(
				'label'         => 'Test',
				'sla_hours'     => -24,
				'warning_hours' => -1,
			)
		);

		self::assertSame( 0, $def['sla_hours'] );
		self::assertSame( 0, $def['warning_hours'] );
	}

	/**
	 * Godziny z formularza przychodza tekstem — maja wyjsc liczba.
	 */
	public function test_godziny_z_formularza_wychodza_liczba(): void {
		$def = StatusDefs::sanitize_def(
			array(
				'label'         => 'Test',
				'sla_hours'     => '72',
				'warning_hours' => '18',
			)
		);

		self::assertSame( 72, $def['sla_hours'] );
		self::assertSame( 18, $def['warning_hours'] );
	}

	/**
	 * Znaczniki z pola wyboru („1", „on", brak) wychodza wartoscia logiczna.
	 */
	public function test_znaczniki_z_pola_wyboru_wychodza_logiczne(): void {
		$wlaczone = StatusDefs::sanitize_def( array( 'active' => '1', 'terminal' => 'on' ) );
		$puste    = StatusDefs::sanitize_def( array( 'active' => '0', 'terminal' => '' ) );

		self::assertTrue( $wlaczone['active'] );
		self::assertTrue( $wlaczone['terminal'] );
		self::assertFalse( $puste['active'] );
		self::assertFalse( $puste['terminal'] );
	}

	/**
	 * Etykieta dluzsza niz limit kolumny jest UCINANA, a nie odrzucana przez
	 * baze — i liczona w ZNAKACH, nie w bajtach (polskie znaki zajmuja dwa).
	 */
	public function test_dluga_etykieta_jest_ucinana_po_znakach_nie_bajtach(): void {
		$def = StatusDefs::sanitize_def( array( 'label' => str_repeat( 'ą', 300 ) ) );

		self::assertSame( 190, mb_strlen( $def['label'] ), 'Limit etykiety liczy się w znakach.' );
		self::assertLessThanOrEqual( 190, mb_strlen( $def['label'] ) );
	}

	/**
	 * Etykieta miesci sie w limicie => zostaje w calosci (ucinanie nie moze
	 * dzialac „na wszelki wypadek").
	 */
	public function test_krotka_etykieta_zostaje_w_calosci(): void {
		$def = StatusDefs::sanitize_def( array( 'label' => 'Czeka na część' ) );

		self::assertSame( 'Czeka na część', $def['label'] );
	}
}
