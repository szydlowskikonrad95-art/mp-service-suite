<?php
/**
 * Odczyty rejestru (tabele wlasne B — wylacznie tu, przez Tables::full()).
 *
 * @package MP\Registry
 */

namespace MP\Registry;

use MP\Registry\Common\Str;

/**
 * Repozytorium odczytow Registry.
 */
final class Repo {

	/**
	 * Znajduje produkt po numerze seryjnym (postac dowolna — normalizacja tu).
	 *
	 * @param string $serial Surowy numer seryjny.
	 * @return array<string, mixed>|null Wiersz rejestru lub null.
	 */
	public static function find_by_serial( string $serial ): ?array {
		global $wpdb;

		$normalized = Str::normalize_serial( $serial );

		if ( '' === $normalized ) {
			return null;
		}

		$table = Tables::full( Tables::REGISTRY );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna przez Tables::full(), zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT * FROM {$table} WHERE serial_normalized = %s", $normalized ),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $row ) ? $row : null;
	}

	/**
	 * Aktywny wyjatek gwarancyjny dla produktu (PRECEDENS z kontraktu).
	 *
	 * Odczyt deterministyczny: per-sprawa > globalny (case-first), potem
	 * valid_until DESC, id DESC, LIMIT 1. Aktywnosc Z DATY:
	 * status='active' AND (valid_until IS NULL OR valid_until >= NOW).
	 * Wyjatek z case_id honorowany TYLKO gdy $case_id sie zgadza;
	 * case_id NULL = globalny na produkt.
	 *
	 * @param int      $product_registry_id ID produktu.
	 * @param int|null $case_id             Sprawa pytajaca (lub null).
	 * @return array<string, mixed>|null Wiersz wyjatku lub null.
	 */
	public static function get_active_exception( int $product_registry_id, ?int $case_id ): ?array {
		global $wpdb;

		$table = Tables::full( Tables::EXCEPTIONS );
		$now   = gmdate( 'Y-m-d H:i:s' );

		if ( null === $case_id ) {
			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
			$row = $wpdb->get_row(
				$wpdb->prepare(
					"SELECT * FROM {$table}
					WHERE product_registry_id = %d AND status = 'active' AND case_id IS NULL
					AND ( valid_until IS NULL OR valid_until >= %s )
					ORDER BY valid_until DESC, id DESC LIMIT 1",
					$product_registry_id,
					$now
				),
				ARRAY_A
			);
			// phpcs:enable
		} else {
			// Case-first: wyjatek tej sprawy wygrywa z globalnym.
			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
			$row = $wpdb->get_row(
				$wpdb->prepare(
					"SELECT * FROM {$table}
					WHERE product_registry_id = %d AND status = 'active'
					AND ( case_id = %d OR case_id IS NULL )
					AND ( valid_until IS NULL OR valid_until >= %s )
					ORDER BY ( case_id IS NOT NULL ) DESC, valid_until DESC, id DESC LIMIT 1",
					$product_registry_id,
					$case_id,
					$now
				),
				ARRAY_A
			);
			// phpcs:enable
		}

		return is_array( $row ) ? $row : null;
	}

	/**
	 * Kategoria produktu po ID — dla haka kontraktowego `mp_product_category`
	 * (Intake `get_context.kategoria` => os przydzialu w Automatorze).
	 *
	 * Read-only. Brak produktu / brak kategorii => zwraca przekazany $default_value
	 * (kontrakt „brak danej = default, nie blad").
	 *
	 * @param mixed $default_value             Wartosc domyslna (zwykle null).
	 * @param int   $product_registry_id ID produktu.
	 * @return mixed Slug kategorii (string) albo $default_value.
	 */
	public static function category_for( $default_value, int $product_registry_id ) {
		global $wpdb;

		if ( $product_registry_id <= 0 ) {
			return $default_value;
		}

		$table = Tables::full( Tables::REGISTRY );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna przez Tables::full(), zapytanie przygotowane.
		$category = $wpdb->get_var(
			$wpdb->prepare( "SELECT category FROM {$table} WHERE id = %d", $product_registry_id )
		);
		// phpcs:enable

		return ( is_string( $category ) && '' !== $category ) ? $category : $default_value;
	}

	/**
	 * Detale produktu po ID — kontrakt B->C `mp_product_details` (karta sprawy w C).
	 * NIE weryfikuje dokumentu zakupu: status liczony z samej daty gwarancji
	 * (WarrantyStatus::compute z doc/date = null). $default_value gdy brak produktu.
	 *
	 * @param mixed $default_value       Wartosc domyslna (zwykle null).
	 * @param int   $product_registry_id ID produktu w rejestrze.
	 * @return array{id: int, serial: string, model: string, batch: string, purchase_document: string, purchase_date: string, warranty_until: string, warranty_status: string, archived: bool}|mixed
	 */
	public static function details_for( $default_value, int $product_registry_id ) {
		global $wpdb;

		if ( $product_registry_id <= 0 ) {
			return $default_value;
		}

		$table = Tables::full( Tables::REGISTRY );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna przez Tables::full(), zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT id, serial_display, model, batch, purchase_document, purchase_date, warranty_until, archived
				FROM {$table} WHERE id = %d",
				$product_registry_id
			),
			ARRAY_A
		);
		// phpcs:enable

		if ( ! is_array( $row ) ) {
			return $default_value;
		}

		$warranty_until = null !== $row['warranty_until'] ? (string) $row['warranty_until'] : '';

		return array(
			'id'                => (int) $row['id'],
			'serial'            => (string) $row['serial_display'],
			'model'             => (string) $row['model'],
			'batch'             => (string) $row['batch'],
			'purchase_document' => (string) $row['purchase_document'],
			'purchase_date'     => null !== $row['purchase_date'] ? (string) $row['purchase_date'] : '',
			'warranty_until'    => $warranty_until,
			'warranty_status'   => WarrantyStatus::compute( true, '' !== $warranty_until ? $warranty_until : null, null, null ),
			'archived'          => ! empty( $row['archived'] ),
		);
	}

	/**
	 * Pola, ktore wolno poprawic z panelu.
	 *
	 * ⛔ NIE MA TU `serial_display` ani `serial_normalized`. Numer seryjny jest kluczem,
	 * po ktorym sprawy trzymaja sie produktu (relacja z kartki:
	 * `wp_mp_product_registry.id -> wp_mp_service_cases.product_registry_id`).
	 * Podmiana numeru w istniejacym wierszu przepisalaby historie serwisowa na inny
	 * egzemplarz — poprawka literowki wygladalaby jak cicha zamiana produktu.
	 * Zly numer = archiwizacja wpisu i zaimportowanie poprawnego.
	 */
	public const EDITABLE_FIELDS = array( 'model', 'batch', 'category', 'purchase_document', 'purchase_date', 'warranty_until' );

	/**
	 * Pelny wiersz produktu po ID (na potrzeby ekranu poprawiania danych).
	 *
	 * @param int $product_registry_id ID produktu.
	 * @return array<string, mixed>|null Wiersz albo null.
	 */
	public static function find_by_id( int $product_registry_id ): ?array {
		global $wpdb;

		if ( $product_registry_id <= 0 ) {
			return null;
		}

		$table = Tables::full( Tables::REGISTRY );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna przez Tables::full(), zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT * FROM {$table} WHERE id = %d", $product_registry_id ),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $row ) ? $row : null;
	}

	/**
	 * Poprawia dane produktu w rejestrze i zapisuje zmiane w historii.
	 *
	 * Kartka, plugin 2: „historia zmian danych produktu i decyzji gwarancyjnych".
	 * Decyzje gwarancyjne zapisywal juz `WarrantyExceptions`; tu domykamy pierwsza
	 * polowe wymogu — bez ekranu poprawiania nie bylo CZEGO zapisywac, bo dane
	 * produktu wchodzily wylacznie importem i pozostawaly nietykalne.
	 *
	 * Daty przechodza przez ten sam normalizator co import (`CsvParser::normalize_date`),
	 * wiec panel przyjmuje `2026-03-01` i `1.03.2026` dokladnie tak samo jak plik CSV.
	 *
	 * @param int                   $product_registry_id ID produktu.
	 * @param array<string, string> $fields              Pola do zapisania (podzbior EDITABLE_FIELDS).
	 * @param int|null              $actor_id            Kto zmienia (null = system).
	 * @return array<string, mixed> ['changed' => int] albo ['error' => string, 'field' => string].
	 */
	public static function update( int $product_registry_id, array $fields, ?int $actor_id ): array {
		global $wpdb;

		$row = self::find_by_id( $product_registry_id );

		if ( null === $row ) {
			return array(
				'error' => __( 'Produkt nie istnieje w rejestrze.', 'mp-warranty-registry' ),
				'field' => '',
			);
		}

		if ( ! empty( $row['archived'] ) ) {
			return array(
				'error' => __( 'Produkt jest w archiwum — najpierw go przywróć, potem poprawiaj dane.', 'mp-warranty-registry' ),
				'field' => '',
			);
		}

		$dane = array();
		$diff = array();

		foreach ( self::EDITABLE_FIELDS as $field ) {
			if ( ! array_key_exists( $field, $fields ) ) {
				continue;
			}

			$raw = trim( (string) $fields[ $field ] );

			if ( in_array( $field, array( 'purchase_date', 'warranty_until' ), true ) ) {
				$normalized = CsvParser::normalize_date( $raw );

				if ( false === $normalized ) {
					return array(
						'error' => __( 'Niepoprawna data — użyj formatu RRRR-MM-DD albo DD.MM.RRRR.', 'mp-warranty-registry' ),
						'field' => $field,
					);
				}

				$nowa = $normalized;
			} elseif ( 'category' === $field ) {
				$nowa = Categories::sanitize( $raw );
			} else {
				$nowa = sanitize_text_field( $raw );
			}

			$stara              = null === $row[ $field ] ? null : (string) $row[ $field ];
			$nowa_do_porownania = null === $nowa ? null : (string) $nowa;

			if ( $stara === $nowa_do_porownania ) {
				continue;
			}

			$dane[ $field ] = $nowa;
			$diff[ $field ] = array(
				'before' => $stara,
				'after'  => $nowa_do_porownania,
			);
		}

		if ( array() === $dane ) {
			return array( 'changed' => 0 );
		}

		// Gwarancja konczaca sie przed zakupem to najczestsza literowka przy recznej
		// poprawce (rok z palca). Liczymy na WARTOSCIACH PO ZMIANIE, nie na samych
		// nadeslanych polach — inaczej poprawa jednej daty omijalaby kontrole.
		$zakup_po     = array_key_exists( 'purchase_date', $dane ) ? $dane['purchase_date'] : ( null === $row['purchase_date'] ? null : (string) $row['purchase_date'] );
		$gwarancja_po = array_key_exists( 'warranty_until', $dane ) ? $dane['warranty_until'] : ( null === $row['warranty_until'] ? null : (string) $row['warranty_until'] );

		if ( null !== $zakup_po && null !== $gwarancja_po && $gwarancja_po < $zakup_po ) {
			return array(
				'error' => __( 'Gwarancja nie może kończyć się przed datą zakupu — sprawdź obie daty.', 'mp-warranty-registry' ),
				'field' => 'warranty_until',
			);
		}

		$dane['updated_at'] = current_time( 'mysql', true );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna.
		$zapisane = $wpdb->update( Tables::full( Tables::REGISTRY ), $dane, array( 'id' => $product_registry_id ) );
		// phpcs:enable

		if ( false === $zapisane ) {
			return array(
				'error' => __( 'Nie udało się zapisać zmiany — spróbuj ponownie.', 'mp-warranty-registry' ),
				'field' => '',
			);
		}

		// Ten sam typ zdarzenia i ten sam ksztalt payloadu, ktorego uzywa archiwizacja
		// (`Archive`), wiec historia produktu czyta sie jednym wzorcem. Numer faktury
		// jest na liscie PII — `ProductEvents::sanitize_payload()` sam utnie wartosci.
		ProductEvents::log( $product_registry_id, 'PRODUCT_UPDATED', $diff, $actor_id );

		return array( 'changed' => count( $diff ) );
	}
}
