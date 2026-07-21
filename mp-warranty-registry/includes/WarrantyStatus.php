<?php
/**
 * Silnik statusu gwarancji (czysta logika, testowalna jednostkowo).
 *
 * 4 statusy ze spec P2.2: aktywna | wygasla | brak_danych | weryfikacja.
 * Wyjatek gwarancyjny i archiwizacja to NIE statusy (osobne pola zwrotki).
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * Wyliczanie statusu gwarancji z danych rejestru.
 */
final class WarrantyStatus {

	public const ACTIVE       = 'aktywna';
	public const EXPIRED      = 'wygasla';
	public const NO_DATA      = 'brak_danych';
	public const VERIFICATION = 'weryfikacja';

	/**
	 * Status gwarancji dla danych produktu.
	 *
	 * Regula kontraktu (karta B + spec P2.2):
	 * - produkt nieznaleziony lub bez daty gwarancji -> brak_danych,
	 * - niezgodnosc danych zakupu (ktorykolwiek match === false) -> weryfikacja
	 *   (niezgodnosc NIE blokuje zgloszenia — snapshot dostaje ten status),
	 * - poza tym: warranty_until >= dzis (UTC, wlacznie) -> aktywna, inaczej wygasla.
	 *
	 * @param bool        $found               Czy serial istnieje w rejestrze.
	 * @param string|null $warranty_until      Data konca gwarancji (Y-m-d) lub null.
	 * @param bool|null   $purchase_doc_match  Wynik porownania dokumentu (null = nie weryfikowano/brak danych).
	 * @param bool|null   $purchase_date_match Wynik porownania daty zakupu.
	 * @param string|null $today               Dzis (Y-m-d, UTC) — wstrzykiwane w testach.
	 * @return string Jeden z 4 statusow.
	 */
	public static function compute(
		bool $found,
		?string $warranty_until,
		?bool $purchase_doc_match = null,
		?bool $purchase_date_match = null,
		?string $today = null
	): string {
		if ( ! $found ) {
			return self::NO_DATA;
		}

		if ( false === $purchase_doc_match || false === $purchase_date_match ) {
			return self::VERIFICATION;
		}

		if ( null === $warranty_until || '' === $warranty_until ) {
			return self::NO_DATA;
		}

		if ( null === $today ) {
			$today = gmdate( 'Y-m-d' );
		}

		return ( $warranty_until >= $today ) ? self::ACTIVE : self::EXPIRED;
	}
}
