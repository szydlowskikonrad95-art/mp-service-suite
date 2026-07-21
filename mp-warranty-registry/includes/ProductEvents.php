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
	 * @return void
	 */
	public static function log( int $product_registry_id, string $event_type, array $payload, ?int $actor_id ): void {
		global $wpdb;

		$table = Tables::full( Tables::PRODUCT_EVENTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna append-only.
		$wpdb->insert(
			$table,
			array(
				'product_registry_id' => $product_registry_id,
				'event_type'          => $event_type,
				'payload'             => (string) wp_json_encode( self::sanitize_payload( $payload ) ),
				'actor_id'            => $actor_id,
				'created_at'          => gmdate( 'Y-m-d H:i:s' ),
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
