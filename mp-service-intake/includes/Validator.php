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
	 * @param string                $today  Dzis w 'Y-m-d' (UTC) — wstrzykiwane dla testow.
	 * @return array<int, array{field: string, reason_code: string}> Lista bledow (pusta = OK).
	 */
	public static function validate( string $kind, array $values, string $today ): array {
		$errors = array();

		if ( ! FormConfig::is_valid_kind( $kind ) ) {
			return array(
				array(
					'field'       => 'kind',
					'reason_code' => 'KIND_INVALID',
				),
			);
		}

		foreach ( FormConfig::fields_for( $kind ) as $field ) {
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
		switch ( $type ) {
			case 'email':
				return self::is_email( $value ) ? null : 'INVALID_EMAIL';
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
	 * Serial: format (istnienie sprawdza B przez snapshot; tu tylko ksztalt).
	 *
	 * @param string $value Wartosc.
	 * @return string|null Kod bledu albo null.
	 */
	public static function validate_serial( string $value ): ?string {
		if ( mb_strlen( $value ) < 2 || mb_strlen( $value ) > 100 ) {
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
		if ( mb_strlen( $value ) > 190 ) {
			return 'DOCUMENT_INVALID';
		}

		return 1 === preg_match( '/[A-Za-z0-9]/', $value ) ? null : 'DOCUMENT_INVALID';
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
