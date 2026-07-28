<?php
/**
 * Testy: JAKI status gwarancji widzi pracownik na karcie sprawy.
 *
 * Kartka P2.2 wymaga czterech statusow, w tym „wymagana weryfikacja". Karta
 * sprawy pokazywala jednak status liczony NA ZYWO z samej daty gwarancji
 * (`Repo::details_for` wola `WarrantyStatus::compute( ..., null, null )`),
 * a nie decyzje zapisana przy zgloszeniu. Skutek na zywym systemie:
 * sprawa SRV/2026/0022 miala w bazie `weryfikacja` (klient podal fakture
 * FV/2026/0199, w rejestrze jest FV/2026/0155), a karta swiecila na zielono
 * „aktywna". Czwarty status byl niewidoczny DOKLADNIE tam, gdzie instrukcja
 * kaze pracownikowi na niego zareagowac.
 *
 * Zrodlem prawdy dla SPRAWY jest jej snapshot (decyzja z chwili zgloszenia),
 * a nie biezacy odczyt z rejestru. Rejestr moze sie zmienic po fakcie —
 * historia decyzji nie.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Intake\Admin\CaseCard;
use PHPUnit\Framework\TestCase;

/**
 * Wybor statusu i powodu pokazywanego na karcie sprawy (czysta funkcja).
 */
final class WarrantyViewTest extends TestCase {

	/**
	 * Snapshot sprawy WYGRYWA z biezacym odczytem rejestru.
	 */
	public function test_snapshot_wygrywa_z_rejestrem(): void {
		$widok = CaseCard::warranty_view(
			array(
				'status'              => 'weryfikacja',
				'purchase_doc_match'  => false,
				'purchase_date_match' => true,
			),
			array( 'warranty_status' => 'aktywna' )
		);

		self::assertSame( 'weryfikacja', $widok['status'] );
	}

	/**
	 * Przy niezgodnosci pracownik dostaje POWOD, a nie samą plakietkę —
	 * inaczej musi zgadywać, czego szukać.
	 */
	public function test_powod_wskazuje_niezgodny_dokument(): void {
		$widok = CaseCard::warranty_view(
			array(
				'status'              => 'weryfikacja',
				'purchase_doc_match'  => false,
				'purchase_date_match' => true,
			),
			null
		);

		self::assertStringContainsString( 'dokument', mb_strtolower( $widok['powod'] ) );
		self::assertStringNotContainsString( 'data zakupu', mb_strtolower( $widok['powod'] ) );
	}

	/**
	 * Niezgodna data zakupu — powod mowi o dacie.
	 */
	public function test_powod_wskazuje_niezgodna_date(): void {
		$widok = CaseCard::warranty_view(
			array(
				'status'              => 'weryfikacja',
				'purchase_doc_match'  => true,
				'purchase_date_match' => false,
			),
			null
		);

		self::assertStringContainsString( 'data', mb_strtolower( $widok['powod'] ) );
	}

	/**
	 * Oba pola niezgodne — powod wymienia oba.
	 */
	public function test_powod_wymienia_oba_pola(): void {
		$widok = CaseCard::warranty_view(
			array(
				'status'              => 'weryfikacja',
				'purchase_doc_match'  => false,
				'purchase_date_match' => false,
			),
			null
		);

		$powod = mb_strtolower( $widok['powod'] );

		self::assertStringContainsString( 'dokument', $powod );
		self::assertStringContainsString( 'data', $powod );
	}

	/**
	 * Status inny niz „weryfikacja" nie dorabia powodu (zero szumu na karcie).
	 */
	public function test_aktywna_bez_powodu(): void {
		$widok = CaseCard::warranty_view( array( 'status' => 'aktywna' ), array( 'warranty_status' => 'aktywna' ) );

		self::assertSame( 'aktywna', $widok['status'] );
		self::assertSame( '', $widok['powod'] );
	}

	/**
	 * Brak snapshotu (sprawy sprzed wdrozenia modulu gwarancji) = fallback na
	 * biezacy odczyt z rejestru. Stare sprawy nie moga zgubic statusu.
	 */
	public function test_brak_snapshotu_spada_na_rejestr(): void {
		$widok = CaseCard::warranty_view( null, array( 'warranty_status' => 'wygasla' ) );

		self::assertSame( 'wygasla', $widok['status'] );
	}

	/**
	 * Brak jednego i drugiego = „brak danych", nigdy pusty string.
	 */
	public function test_brak_wszystkiego_to_brak_danych(): void {
		self::assertSame( 'brak_danych', CaseCard::warranty_view( null, null )['status'] );
	}

	/**
	 * Wyjatek gwarancyjny (decyzja administratora) ma byc widoczny — inaczej
	 * pracownik nie wie, dlaczego sprawa jest na gwarancji mimo niezgodnosci.
	 */
	public function test_wyjatek_gwarancyjny_widoczny(): void {
		$widok = CaseCard::warranty_view(
			array(
				'status'        => 'aktywna',
				'is_overridden' => true,
			),
			null
		);

		self::assertStringContainsString( 'wyjąt', mb_strtolower( $widok['powod'] ) );
	}
}
