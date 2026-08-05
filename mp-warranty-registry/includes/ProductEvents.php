<?php
/**
 * Historia produktu — wp_mp_product_events (APPEND-ONLY, zero UPDATE/DELETE).
 *
 * Zasady kontraktu (EVENT_MODEL.md §4):
 * - zmiany danych produktu: diff before/after; pola pii_sensitive w diffie
 *   TYLKO jako {field, changed: true} (bez wartosci),
 * - EXCEPTION_CREATED / EXCEPTION_REVOKED: {exception_id, typ, actor_id} —
 *   NIGDY kopia tekstu `reason` (NO-PII-IN-LOG).
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * Zapis zdarzen historii produktu.
 */
final class ProductEvents {

	/**
	 * Typ zdarzenia: przyznanie wyjatku gwarancyjnego.
	 */
	public const EXCEPTION_CREATED = 'EXCEPTION_CREATED';

	/**
	 * Typ zdarzenia: cofniecie wyjatku gwarancyjnego.
	 */
	public const EXCEPTION_REVOKED = 'EXCEPTION_REVOKED';

	/**
	 * Wersja ksztaltu payloadu — wspolny kontrakt wszystkich trzech dziennikow
	 * (`EVENT_MODEL.md` sekcja 2: „wersja ksztaltu payloadu (w payloadzie)").
	 *
	 * ⛔ Dziennik rejestru jako JEDYNY z trzech tego pola nie zapisywal. Dziennik
	 * jest append-only, wiec przy pierwszej zmianie ksztaltu wpisu nie dalo by sie
	 * odroznic starych zapisow od nowych — a mowa o wpisach, ktore specyfikacja wymienia
	 * wprost: „historia zmian danych produktu i decyzji gwarancyjnych".
	 */
	public const SCHEMA_VERSION = 1;

	/**
	 * Klucz techniczny w payloadzie. NIE jest polem produktu — czytelnicy dziennika
	 * musza go pomijac przy wyliczaniu, co sie zmienilo.
	 */
	public const META_KEY = 'schema_version';

	/**
	 * Pola produktu traktowane jako wrazliwe (diff bez wartosci).
	 * Dokument zakupu bywa numerem faktury imiennej (MAPA-PII w DATABASE.md).
	 */
	public const PII_FIELDS = array( 'purchase_document' );

	/**
	 * Dopisuje zdarzenie do historii produktu (append-only).
	 *
	 * Payload przechodzi przez sanitize_payload() — pas bezpieczenstwa
	 * NO-PII-IN-LOG (klucz `reason` nigdy nie wchodzi do logu).
	 *
	 * @param int                  $product_registry_id ID produktu.
	 * @param string               $event_type          Typ zdarzenia.
	 * @param array<string, mixed> $payload             Dane zdarzenia (skalary/tablice).
	 * @param int|null             $actor_id            Kto (null = system).
	 * @return bool True gdy wpis powstal (wczesniej `: void` — nieudany zapis
	 *              przechodzil niezauwazony i decyzja gwarancyjna zostawala
	 *              w bazie bez sladu, kto ja podjal).
	 */
	public static function log( int $product_registry_id, string $event_type, array $payload, ?int $actor_id ): bool {
		$table = Tables::full( Tables::PRODUCT_EVENTS );

		return Common\EventWrite::insert(
			$table,
			array(
				'product_registry_id' => $product_registry_id,
				'event_type'          => $event_type,
				// Wersja ksztaltu idzie W PAYLOADZIE — tak stanowi wspolny kontrakt.
				// Dokladana PO oczyszczeniu, zeby zadne pole z pliku klienta nie moglo
				// jej podmienic.
				'payload'             => (string) wp_json_encode( self::z_wersja( self::sanitize_payload( $payload ) ) ),
				'actor_id'            => $actor_id,
				'created_at'          => gmdate( 'Y-m-d H:i:s' ),
			)
		);
	}

	/**
	 * Dokleja wersje ksztaltu do payloadu.
	 *
	 * @param array<string, mixed> $payload Payload po oczyszczeniu.
	 * @return array<string, mixed>
	 */
	private static function z_wersja( array $payload ): array {
		$payload[ self::META_KEY ] = self::SCHEMA_VERSION;

		return $payload;
	}

	/**
	 * Pola payloadu BEZ klucza technicznego — do wyliczania, co sie zmienilo.
	 *
	 * Wpisy sprzed 1.3.12 wersji nie maja; brak klucza jest wiec normalnym stanem,
	 * a nie bledem (dziennika nie wolno poprawiac wstecz).
	 *
	 * @param array<string, mixed> $payload Payload z dziennika.
	 * @return array<string, mixed>
	 */
	public static function pola_zmian( array $payload ): array {
		unset( $payload[ self::META_KEY ] );

		return $payload;
	}

	/**
	 * Historia egzemplarza — WIERSZE, nie licznik.
	 *
	 * ⛔ Do 1.3.12 ta tabela byla zapisywana i NIGDY nieczytana: w calym produkcie
	 * nie bylo ani jednego SELECT-a z `wp_mp_product_events`. Ekran poprawiania
	 * danych obiecywal „zmiana zapisuje sie w historii produktu", a historii nie
	 * dalo sie nigdzie zobaczyc — dziennik istnial jako zapis, nie jako historia.
	 *
	 * @param int $product_registry_id ID produktu.
	 * @param int $limit               Gorny limit wpisow (1..500, domyslnie 100).
	 * @return array<int, array<string, mixed>> Wpisy od najnowszego; `payload`
	 *                                          zdekodowany do tablicy.
	 */
	public static function history( int $product_registry_id, int $limit = 100 ): array {
		global $wpdb;

		if ( $product_registry_id <= 0 ) {
			return array();
		}

		$limit = max( 1, min( 500, $limit ) );
		$table = Tables::full( Tables::PRODUCT_EVENTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT id, event_type, payload, actor_id, created_at
				FROM {$table}
				WHERE product_registry_id = %d
				ORDER BY id DESC
				LIMIT %d",
				$product_registry_id,
				$limit
			),
			ARRAY_A
		);
		// phpcs:enable

		if ( ! is_array( $rows ) ) {
			return array();
		}

		$out = array();

		foreach ( $rows as $row ) {
			$payload = json_decode( (string) $row['payload'], true );

			$payload = is_array( $payload ) ? $payload : array();

			$out[] = array(
				'id'             => (int) $row['id'],
				'event_type'     => (string) $row['event_type'],
				'payload'        => $payload,
				// 0 = wpis sprzed wprowadzenia wersji (dziennik jest append-only).
				'schema_version' => (int) ( $payload[ self::META_KEY ] ?? 0 ),
				'actor_id'       => null === $row['actor_id'] ? null : (int) $row['actor_id'],
				'created_at'     => (string) $row['created_at'],
			);
		}

		return $out;
	}

	/**
	 * Ile wpisow ma historia egzemplarza (do informacji „pokazujemy N z M").
	 *
	 * @param int $product_registry_id ID produktu.
	 * @return int
	 */
	public static function history_count( int $product_registry_id ): int {
		global $wpdb;

		if ( $product_registry_id <= 0 ) {
			return 0;
		}

		$table = Tables::full( Tables::PRODUCT_EVENTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		return (int) $wpdb->get_var(
			$wpdb->prepare(
				"SELECT COUNT(*) FROM {$table} WHERE product_registry_id = %d",
				$product_registry_id
			)
		);
		// phpcs:enable
	}

	/**
	 * Pas bezpieczenstwa payloadu: wycina `reason` i maskuje pola PII.
	 *
	 * Czysta funkcja (testowana jednostkowo). Klucze z PII_FIELDS w diffach
	 * zostaja sprowadzone do {field, changed: true}.
	 *
	 * @param array<string, mixed> $payload Payload wejsciowy.
	 * @return array<string, mixed> Payload bezpieczny do logu.
	 */
	public static function sanitize_payload( array $payload ): array {
		unset( $payload['reason'] );

		foreach ( self::PII_FIELDS as $field ) {
			if ( array_key_exists( $field, $payload ) ) {
				$payload[ $field ] = array(
					'field'   => $field,
					'changed' => true,
				);
			}
		}

		return $payload;
	}
}
