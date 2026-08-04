<?php
/**
 * Walidacja zgloszenia — SYNCHRONICZNIE PRZED insertem (P1.4).
 *
 * Odmowa = zwrot bledow do warstwy HTTP (NIE event — unverified sprawa nie
 * pisze do osi czasu). Bledy jako kody {field, reason_code}, nigdy surowe
 * stringi z danymi (EVENT_MODEL: VALIDATION_FAILED {field, reason_code}).
 * Czyste funkcje — testowane jednostkowo bez WP.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Walidator pol formularza wg schematu rodzaju.
 */
final class Validator {

	/**
	 * Najstarsza akceptowalna data zakupu (ochrona przed literowka/atakiem).
	 */
	public const MIN_PURCHASE_YEAR = 1990;

	/**
	 * Waliduje zgloszenie wg pol rodzaju.
	 *
	 * @param string                $kind   Rodzaj sprawy.
	 * @param array<string, string> $values Wartosci pol (klucz => surowa wartosc).
	 * @param string                $today    Dzis w 'Y-m-d' (UTC) — wstrzykiwane dla testow.
	 * @param string                $category Slug kategorii (pusty = tylko pola rodzaju).
	 * @return array<int, array{field: string, reason_code: string}> Lista bledow (pusta = OK).
	 */
	public static function validate( string $kind, array $values, string $today, string $category = '' ): array {
		$errors = array();

		if ( ! FormConfig::is_valid_kind( $kind ) ) {
			return array(
				array(
					'field'       => 'kind',
					'reason_code' => 'KIND_INVALID',
				),
			);
		}

		foreach ( FormConfig::fields_for( $kind, $category ) as $field ) {
			$key   = $field['key'];
			$value = trim( (string) ( $values[ $key ] ?? '' ) );

			if ( '' === $value ) {
				if ( $field['required'] ) {
					$errors[] = array(
						'field'       => $key,
						'reason_code' => 'REQUIRED',
					);
				}

				continue;
			}

			$reason = self::validate_value( $field['type'], $value, $today );

			if ( null !== $reason ) {
				$errors[] = array(
					'field'       => $key,
					'reason_code' => $reason,
				);
			}
		}

		return $errors;
	}

	/**
	 * Waliduje pojedyncza wartosc wg typu pola (czysta funkcja).
	 *
	 * @param string $type  Typ pola (FormConfig::FIELD_TYPES).
	 * @param string $value Niepusta wartosc.
	 * @param string $today Dzis w 'Y-m-d' (UTC).
	 * @return string|null Kod bledu albo null gdy OK.
	 */
	public static function validate_value( string $type, string $value, string $today ): ?string {
		// Twardy sufit dlugosci PRZED walidacja typu. Bez niego pola `text`
		// i `textarea` wpadaly w `default: null`, czyli mialy limit... zaden:
		// zgloszenie ze 100 tys. znakow opisu wchodzilo do bazy w calosci
		// (sprawdzone atakiem na zywym WP). Skutki: puchnaca baza i kopie
		// zapasowe klienta, karta sprawy renderujaca kilometr tekstu, taki sam
		// kilometr w mailu do pracownika. Limity z zapasem — normalny opis
		// usterki miesci sie w 300-800 znakach.
		$limit = self::limit_znakow( $type );

		if ( $limit > 0 && Common\Str::len( $value ) > $limit ) {
			return 'TOO_LONG';
		}

		switch ( $type ) {
			case 'email':
				return self::validate_email( $value );
			case 'date':
				return self::validate_purchase_date( $value, $today );
			case 'serial':
				return self::validate_serial( $value );
			case 'document':
				return self::validate_document( $value );
			case 'tel':
				return 1 === preg_match( '/[0-9]{6,}/', preg_replace( '/[\s()+-]/', '', $value ) ?? '' ) ? null : 'INVALID_TEL';
			default:
				return null;
		}
	}

	/**
	 * Data zakupu: format Y-m-d, realna, nie z przyszlosci, nie sprzed 1990.
	 *
	 * @param string $value Wartosc.
	 * @param string $today Dzis w 'Y-m-d' (UTC).
	 * @return string|null Kod bledu albo null.
	 */
	public static function validate_purchase_date( string $value, string $today ): ?string {
		$parsed = \DateTime::createFromFormat( '!Y-m-d', $value, new \DateTimeZone( 'UTC' ) );

		if ( false === $parsed || $parsed->format( 'Y-m-d' ) !== $value ) {
			return 'DATE_INVALID';
		}

		if ( $value > $today ) {
			return 'DATE_FUTURE';
		}

		if ( (int) $parsed->format( 'Y' ) < self::MIN_PURCHASE_YEAR ) {
			return 'DATE_TOO_OLD';
		}

		return null;
	}

	/**
	 * Maksymalna dlugosc wartosci wg typu pola (0 = typ ma wlasna walidacje).
	 *
	 * Rozne sufity, bo pola sluza do czego innego: jednolinijkowe `text`
	 * (model, objaw, nr partii) nie potrzebuje wiecej niz zdanie, a `textarea`
	 * to opis usterki — dajemy zapas na spokojna relacje, ale nie na powiesc.
	 *
	 * @param string $type Typ pola.
	 * @return int Limit znakow (0 = brak limitu na tym poziomie).
	 */
	public static function limit_znakow( string $type ): int {
		switch ( $type ) {
			case 'textarea':
				return 5000;
			case 'text':
				return 500;
			default:
				// email/serial/document/date/tel maja wlasne, ciasniejsze reguly
				// (e-mail: `validate_email` — limit 190 = szerokosc kolumny).
				return 0;
		}
	}

	/**
	 * Serial: format (istnienie sprawdza B przez snapshot; tu tylko ksztalt).
	 *
	 * @param string $value Wartosc.
	 * @return string|null Kod bledu albo null.
	 */
	public static function validate_serial( string $value ): ?string {
		if ( Common\Str::len( $value ) < 2 || Common\Str::len( $value ) > 100 ) {
			return 'SERIAL_INVALID';
		}

		return 1 === preg_match( '/[A-Za-z0-9]/', $value ) ? null : 'SERIAL_INVALID';
	}

	/**
	 * Dokument zakupu: niepusty ciag z chocby jednym znakiem alfanumerycznym.
	 *
	 * @param string $value Wartosc.
	 * @return string|null Kod bledu albo null.
	 */
	public static function validate_document( string $value ): ?string {
		if ( Common\Str::len( $value ) > 190 ) {
			return 'DOCUMENT_INVALID';
		}

		return 1 === preg_match( '/[A-Za-z0-9]/', $value ) ? null : 'DOCUMENT_INVALID';
	}

	/**
	 * Imie i nazwisko zglaszajacego: niepuste, mieszczace sie w kolumnie.
	 *
	 * Limit 190 = szerokosc `customers.name` (VARCHAR(190)) — ta sama zasada
	 * co przy dokumencie zakupu: kod pilnuje tego, co uniesie baza, zamiast
	 * oddawac czlowiekowi „blad zapisu do bazy" (poz. 2.4).
	 * Ksztaltu nazwiska NIE narzucamy (jeden znak, znaki diakrytyczne, apostrof,
	 * lacznik — wszystko to sa prawdziwe nazwiska).
	 *
	 * @param string $value Wartosc z formularza.
	 * @return string|null Kod bledu albo null.
	 */
	public static function validate_customer_name( string $value ): ?string {
		$value = trim( $value );

		if ( '' === $value ) {
			return 'REQUIRED';
		}

		return Common\Str::len( $value ) > 190 ? 'TOO_LONG' : null;
	}

	/**
	 * E-mail: ksztalt ORAZ dlugosc mieszczaca sie w kolumnie (2.4 czesc b).
	 *
	 * ⛔ Reguly dlugosci dla adresu NIE BYLO NA ZADNEJ SCIEZCE — ani tutaj, ani
	 * przy zakladaniu konta, ani przy zmianie adresu — choc kolumny `customers.email`
	 * i `service_cases.contact_email` to VARCHAR(190), a komentarz obok twierdzil,
	 * ze e-mail ma „wlasna, ciasniejsza regule". Adres dluzszy niz 190 znakow
	 * przechodzil walidacje ksztaltu i rozbijal sie dopiero o baze, wiec czlowiek
	 * dostawal „blad zapisu do bazy" zamiast zdania o tym, co poprawic.
	 *
	 * Wzorzec ten sam, co przy dokumencie zakupu i imieniu (`validate_document`,
	 * `validate_customer_name`): kod pilnuje tego, co uniesie baza.
	 *
	 * @param string $email Adres z formularza.
	 * @return string|null Kod bledu albo null.
	 */
	public static function validate_email( string $email ): ?string {
		if ( Common\Str::len( $email ) > 190 ) {
			return 'TOO_LONG';
		}

		return self::is_email( $email ) ? null : 'INVALID_EMAIL';
	}

	/**
	 * Walidacja e-maila (czysta — bez zaleznosci od WP w testach).
	 *
	 * @param string $email E-mail.
	 * @return bool
	 */
	public static function is_email( string $email ): bool {
		return false !== filter_var( $email, FILTER_VALIDATE_EMAIL );
	}
}
