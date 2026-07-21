<?php
/**
 * Os czasu sprawy — wp_mp_case_events (APPEND-ONLY BEZ WYJATKOW).
 *
 * ZELAZNA ZASADA NO-PII-IN-LOG: payload jest W 100% STRUKTURALNY (referencje,
 * fakty, kody) — ZERO pol wolnotekstowych. Tresc rozmowy zyje w messages,
 * event trzyma tylko wskaznik. Klasa nie ma metod UPDATE/DELETE z zalozenia.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Zapis zdarzen osi czasu sprawy.
 */
final class CaseEvents {

	/**
	 * Wersja ksztaltu payloadu.
	 */
	public const SCHEMA_VERSION = 1;

	/**
	 * Narodziny sprawy (dopiero po weryfikacji mailowej).
	 */
	public const CASE_CREATED = 'CASE_CREATED';

	/**
	 * Zarejestrowanie zgody RODO.
	 */
	public const CONSENT_RECORDED = 'CONSENT_RECORDED';

	/**
	 * Wycofanie zgody RODO.
	 */
	public const CONSENT_WITHDRAWN = 'CONSENT_WITHDRAWN';

	/**
	 * Redakcja danych osobowych (payload: target_id + lista pol, bez wartosci).
	 */
	public const PII_REDACTION = 'PII_REDACTION';

	/**
	 * Dopisuje zdarzenie do osi czasu sprawy (append-only).
	 *
	 * @param int                  $case_id    ID sprawy.
	 * @param string               $event_type Typ (stala z tej klasy).
	 * @param array<string, mixed> $payload    Dane STRUKTURALNE (bez wolnego tekstu).
	 * @param int|null             $actor_id   Kto (null = system/klient).
	 * @return void
	 */
	public static function log( int $case_id, string $event_type, array $payload, ?int $actor_id ): void {
		global $wpdb;

		$table = Tables::full( Tables::CASE_EVENTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna append-only.
		$wpdb->insert(
			$table,
			array(
				'case_id'        => $case_id,
				'event_type'     => $event_type,
				'payload'        => (string) wp_json_encode( $payload ),
				'schema_version' => self::SCHEMA_VERSION,
				'actor_id'       => $actor_id,
				'created_at'     => gmdate( 'Y-m-d H:i:s' ),
			)
		);
		// phpcs:enable
	}
}
