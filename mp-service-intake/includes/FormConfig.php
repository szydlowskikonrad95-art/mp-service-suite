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
	 * Dozwolone kategorie produktu (spojne z Registry\Categories — slownik klepniety 21.07).
	 * Formularz P1.2: pola zaleza od WYBRANEJ kategorii (kartka). Pusta = brak kategorii (fallback).
	 */
	public const CATEGORY_SLUGS = array( 'audio', 'agd', 'elektronarzedzia', 'inne' );

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
	 * Zwraca liste pol dla rodzaju (z nadpisania w opcji albo domyslna), plus
	 * dodatkowe pola kategorii gdy $category niepuste (P1.2).
	 *
	 * @param string $kind     Rodzaj sprawy.
	 * @param string $category Slug kategorii (pusty = tylko pola rodzaju).
	 * @return array<int, array{key: string, label: string, type: string, required: bool, pii_sensitive: bool}>
	 */
	public static function fields_for( string $kind, string $category = '' ): array {
		$config = get_option( self::OPTION, array() );

		if ( is_array( $config ) && isset( $config[ $kind ] ) && is_array( $config[ $kind ] ) ) {
			$base = self::sanitize_kind_fields( $config[ $kind ] );
		} else {
			$defaults = self::defaults();
			$base     = $defaults[ $kind ] ?? array();
		}

		if ( '' === $category ) {
			return $base;
		}

		// Pola kategorii dopisane PO polach rodzaju (dedup po kluczu — rodzaj wygrywa).
		$seen = array();
		foreach ( $base as $field ) {
			$seen[ $field['key'] ] = true;
		}

		foreach ( self::category_fields( $category ) as $field ) {
			if ( ! isset( $seen[ $field['key'] ] ) ) {
				$seen[ $field['key'] ] = true;
				$base[]                = $field;
			}
		}

		return $base;
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

		foreach ( self::CATEGORY_SLUGS as $category ) {
			foreach ( self::category_fields( $category ) as $field ) {
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
	 * Kategorie produktu (slug => etykieta PL). Spojne z Registry\Categories.
	 * Konfigurowalne filtrem `mp_intake_categories`.
	 *
	 * @return array<string, string>
	 */
	public static function categories(): array {
		$map = array(
			'audio'            => __( 'Elektronika audio', 'mp-service-intake' ),
			'agd'              => __( 'AGD drobne', 'mp-service-intake' ),
			'elektronarzedzia' => __( 'Elektronarzędzia', 'mp-service-intake' ),
			'inne'             => __( 'Inne', 'mp-service-intake' ),
		);

		$filtered = apply_filters( 'mp_intake_categories', $map );

		return ( is_array( $filtered ) && array() !== $filtered ) ? $filtered : $map;
	}

	/**
	 * Czy kategoria dozwolona (pusta = brak wyboru, dozwolona jako fallback).
	 *
	 * @param string $category Slug kategorii.
	 * @return bool
	 */
	public static function is_valid_category( string $category ): bool {
		return '' === $category || in_array( $category, self::CATEGORY_SLUGS, true );
	}

	/**
	 * Domyslne dodatkowe pola per kategoria (P1.2 — sensowne domyslne, konfigurowalne).
	 * PLASKI schemat jak pola rodzaju, ZERO logiki warunkowej.
	 *
	 * @return array<string, array<int, array<string, mixed>>>
	 */
	private static function category_fields_defaults(): array {
		return array(
			'audio'            => array(
				array(
					'key'           => 'cat_audio_objaw',
					'label'         => __( 'Objaw dźwięku (np. brak dźwięku, trzaski, jeden kanał)', 'mp-service-intake' ),
					'type'          => 'text',
					'required'      => false,
					'pii_sensitive' => false,
				),
			),
			'agd'              => array(
				array(
					'key'           => 'cat_agd_model',
					'label'         => __( 'Model / moc z tabliczki znamionowej', 'mp-service-intake' ),
					'type'          => 'text',
					'required'      => false,
					'pii_sensitive' => false,
				),
			),
			'elektronarzedzia' => array(
				array(
					'key'           => 'cat_et_partia',
					'label'         => __( 'Nr partii / seria produktu', 'mp-service-intake' ),
					'type'          => 'text',
					'required'      => false,
					'pii_sensitive' => false,
				),
			),
			'inne'             => array(),
		);
	}

	/**
	 * Dodatkowe pola dla kategorii (z filtra konfiguracyjnego + sanityzacja).
	 *
	 * @param string $category Slug kategorii.
	 * @return array<int, array{key: string, label: string, type: string, required: bool, pii_sensitive: bool}>
	 */
	public static function category_fields( string $category ): array {
		if ( '' === $category ) {
			return array();
		}

		$map = apply_filters( 'mp_intake_category_fields', self::category_fields_defaults() );

		$fields = ( is_array( $map ) && isset( $map[ $category ] ) && is_array( $map[ $category ] ) )
			? $map[ $category ]
			: array();

		return self::sanitize_kind_fields( $fields );
	}

	/**
	 * Mapa kategoria => lista {key, required} dla warstwy klienckiej (JS).
	 *
	 * @return array<string, array<int, array{key: string, required: bool}>>
	 */
	public static function category_field_map(): array {
		$map = array();

		foreach ( self::CATEGORY_SLUGS as $category ) {
			$fields = array();

			foreach ( self::category_fields( $category ) as $field ) {
				$fields[] = array(
					'key'      => $field['key'],
					'required' => $field['required'],
				);
			}

			$map[ $category ] = $fields;
		}

		return $map;
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
