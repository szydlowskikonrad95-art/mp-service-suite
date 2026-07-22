<?php
/**
 * Konfiguracja formularza — PLASKI schemat per RODZAJ sprawy (kontrakt C).
 *
 * ZERO logiki warunkowej pole-od-pola (ostrzezenie przed „wlasnym form-builderem"):
 * kazdy rodzaj to lista pol {key, label, type, required, pii_sensitive}. Admin
 * edytuje wymagalnosc bez zmiany kodu (opcja autoload=no, warstwa TRESCI uninstalla);
 * bez zapisanej konfiguracji dziala domyslna mapa z tej klasy.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Definicje pol formularza per rodzaj zgloszenia.
 */
final class FormConfig {

	/**
	 * Opcja z nadpisana konfiguracja (autoload=no — warstwa TRESCI).
	 */
	public const OPTION = 'mp_intake_form_config';

	/**
	 * Dozwolone rodzaje spraw (zamknieta lista).
	 */
	public const KINDS = array( 'reklamacja', 'naprawa', 'zapytanie', 'zwrot' );

	/**
	 * Dozwolone typy pol (zamknieta lista — walidator zna kazdy).
	 */
	public const FIELD_TYPES = array( 'text', 'textarea', 'serial', 'document', 'date', 'email', 'tel' );

	/**
	 * Domyslna mapa pol per rodzaj (uzywana gdy brak nadpisania w opcji).
	 *
	 * @return array<string, array<int, array{key: string, label: string, type: string, required: bool, pii_sensitive: bool}>>
	 */
	public static function defaults(): array {
		$serial   = array(
			'key'           => 'serial',
			'label'         => __( 'Numer seryjny produktu', 'mp-service-intake' ),
			'type'          => 'serial',
			'required'      => true,
			'pii_sensitive' => false,
		);
		$document = array(
			'key'           => 'purchase_document',
			'label'         => __( 'Dokument zakupu (nr faktury/paragonu)', 'mp-service-intake' ),
			'type'          => 'document',
			'required'      => true,
			'pii_sensitive' => true,
		);
		$date     = array(
			'key'           => 'purchase_date',
			'label'         => __( 'Data zakupu', 'mp-service-intake' ),
			'type'          => 'date',
			'required'      => true,
			'pii_sensitive' => false,
		);
		$issue    = array(
			'key'           => 'issue_description',
			'label'         => __( 'Opis usterki / sprawy', 'mp-service-intake' ),
			'type'          => 'textarea',
			'required'      => true,
			'pii_sensitive' => true,
		);

		return array(
			'reklamacja' => array( $serial, $document, $date, $issue ),
			'naprawa'    => array( $serial, $issue ),
			'zapytanie'  => array( $issue ),
			'zwrot'      => array(
				$serial,
				$document,
				$date,
				array(
					'key'           => 'return_reason',
					'label'         => __( 'Powód zwrotu', 'mp-service-intake' ),
					'type'          => 'textarea',
					'required'      => true,
					'pii_sensitive' => false,
				),
			),
		);
	}

	/**
	 * Zwraca liste pol dla rodzaju (z nadpisania w opcji albo domyslna).
	 *
	 * @param string $kind Rodzaj sprawy.
	 * @return array<int, array{key: string, label: string, type: string, required: bool, pii_sensitive: bool}>
	 */
	public static function fields_for( string $kind ): array {
		$config = get_option( self::OPTION, array() );

		if ( is_array( $config ) && isset( $config[ $kind ] ) && is_array( $config[ $kind ] ) ) {
			return self::sanitize_kind_fields( $config[ $kind ] );
		}

		$defaults = self::defaults();

		return $defaults[ $kind ] ?? array();
	}

	/**
	 * Czy rodzaj jest dozwolony.
	 *
	 * @param string $kind Rodzaj.
	 * @return bool
	 */
	public static function is_valid_kind( string $kind ): bool {
		return in_array( $kind, self::KINDS, true );
	}

	/**
	 * Mapa rodzaj => lista {key, required} dla WSZYSTKICH rodzajow.
	 *
	 * Config dla warstwy klienckiej (JS): mowi ktore pola nalezą do rodzaju i
	 * ktore sa wymagane. JS pokazuje/ukrywa pola i toggluje `required` wg tej
	 * mapy; serwer NIEZALEZNIE waliduje fields_for(kind) na submit (JS = tylko UX).
	 *
	 * @return array<string, array<int, array{key: string, required: bool}>>
	 */
	public static function kind_field_map(): array {
		$map = array();

		foreach ( self::KINDS as $kind ) {
			$fields = array();

			foreach ( self::fields_for( $kind ) as $field ) {
				$fields[] = array(
					'key'      => $field['key'],
					'required' => $field['required'],
				);
			}

			$map[ $kind ] = $fields;
		}

		return $map;
	}

	/**
	 * Unia definicji pol po WSZYSTKICH rodzajach (dedup po kluczu — pierwsza
	 * definicja wygrywa). Formularz renderuje KAZDE mozliwe pole raz; JS
	 * pokazuje wlasciwe dla wybranego rodzaju. Dzieki temu np. `return_reason`
	 * (tylko zwrot) istnieje w DOM od poczatku — brak dwuetapowego "wyslij->blad".
	 *
	 * @return array<int, array{key: string, label: string, type: string, required: bool, pii_sensitive: bool}>
	 */
	public static function union_fields(): array {
		$seen = array();
		$out  = array();

		foreach ( self::KINDS as $kind ) {
			foreach ( self::fields_for( $kind ) as $field ) {
				if ( isset( $seen[ $field['key'] ] ) ) {
					continue;
				}

				$seen[ $field['key'] ] = true;
				$out[]                 = $field;
			}
		}

		return $out;
	}

	/**
	 * Czysci wiersz pol z opcji (obrona przed smieciem/zmiana schematu).
	 *
	 * @param array<int, mixed> $fields Surowe pola z opcji.
	 * @return array<int, array{key: string, label: string, type: string, required: bool, pii_sensitive: bool}>
	 */
	private static function sanitize_kind_fields( array $fields ): array {
		$out = array();

		foreach ( $fields as $field ) {
			if ( ! is_array( $field ) || '' === (string) ( $field['key'] ?? '' ) ) {
				continue;
			}

			$type = (string) ( $field['type'] ?? 'text' );

			$out[] = array(
				'key'           => (string) $field['key'],
				'label'         => (string) ( $field['label'] ?? $field['key'] ),
				'type'          => in_array( $type, self::FIELD_TYPES, true ) ? $type : 'text',
				'required'      => ! empty( $field['required'] ),
				'pii_sensitive' => ! empty( $field['pii_sensitive'] ),
			);
		}

		return $out;
	}
}
