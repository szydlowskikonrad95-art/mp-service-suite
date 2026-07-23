<?php
/**
 * Slownik kategorii produktu (kartka P1.2/P3.1 — os przydzialu + pola formularza).
 *
 * Whitelist 4 kategorii (klepniete 21.07). Konfigurowalny przez filtr
 * `mp_product_categories` (slug => etykieta PL). Walidacja wejscia:
 * wartosc spoza listy => FALLBACK ('inne'), nigdy blad (kontrakt „brak danej
 * = bezpieczny default, nie wyjatek").
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * Kanoniczny slownik kategorii produktu.
 */
final class Categories {

	/**
	 * Domyslny slownik slug => etykieta PL (klepniete Dzidek 21.07).
	 */
	private const DEFAULTS = array(
		'audio'            => 'Elektronika audio',
		'agd'              => 'AGD drobne',
		'elektronarzedzia' => 'Elektronarzędzia',
		'inne'             => 'Inne',
	);

	/**
	 * Kategoria zapasowa (gdy brak / nieznana).
	 */
	public const FALLBACK = 'inne';

	/**
	 * Pelny slownik (z filtrem konfiguracyjnym). Zawsze niepusty.
	 *
	 * @return array<string, string> slug => etykieta.
	 */
	public static function all(): array {
		$cats = apply_filters( 'mp_product_categories', self::DEFAULTS );

		return ( is_array( $cats ) && array() !== $cats ) ? $cats : self::DEFAULTS;
	}

	/**
	 * Dozwolone slugi.
	 *
	 * @return string[]
	 */
	public static function slugs(): array {
		return array_keys( self::all() );
	}

	/**
	 * Waliduje wartosc do dozwolonego sluga. Przyjmuje slug LUB etykiete
	 * (case-insensitive). Spoza listy / puste => FALLBACK.
	 *
	 * @param string $value Surowa wartosc (z CSV / formularza).
	 * @return string Dozwolony slug.
	 */
	public static function sanitize( string $value ): string {
		$value = trim( $value );

		if ( '' === $value ) {
			return self::FALLBACK;
		}

		$slug = sanitize_key( $value );

		if ( in_array( $slug, self::slugs(), true ) ) {
			return $slug;
		}

		// Dopasowanie po etykiecie (np. CSV z „Elektronika audio" zamiast sluga).
		$lower = function_exists( 'mb_strtolower' ) ? mb_strtolower( $value ) : strtolower( $value );

		foreach ( self::all() as $candidate_slug => $label ) {
			$label_lower = function_exists( 'mb_strtolower' ) ? mb_strtolower( $label ) : strtolower( $label );

			if ( $label_lower === $lower ) {
				return (string) $candidate_slug;
			}
		}

		return self::FALLBACK;
	}

	/**
	 * Etykieta PL dla sluga (fallback: etykieta „Inne", potem sam slug).
	 *
	 * @param string $slug Slug kategorii.
	 * @return string Etykieta do wyswietlenia.
	 */
	public static function label( string $slug ): string {
		$all = self::all();

		return $all[ $slug ] ?? ( $all[ self::FALLBACK ] ?? $slug );
	}
}
