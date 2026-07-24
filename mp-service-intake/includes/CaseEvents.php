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
	 * Przydzial sprawy pracownikowi (auto round-robin D lub reczny koordynatora).
	 * Payload: {from, to, actor} — KAZDY przydzial tworzy wpis (EVENT_MODEL.md).
	 */
	public const CASE_ASSIGNED = 'CASE_ASSIGNED';

	/**
	 * Zmiana statusu sprawy (po narodzinach). Payload: {from, to, actor,
	 * rejection_reason_code?} — kod tylko przy wejsciu w 'odrzucone'.
	 */
	public const STATUS_CHANGED = 'STATUS_CHANGED';

	/**
	 * Zmiana priorytetu sprawy (silnik regul lub reczna). Payload: {from, to, actor}.
	 */
	public const PRIORITY_CHANGED = 'PRIORITY_CHANGED';

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
	 * Wyjatek gwarancyjny NADANY na sprawe (listener mp_warranty_exception_changed,
	 * stan 'active'). Payload: {exception_id} — NO-PII, bez reason (EVENT_MODEL.md).
	 */
	public const EXCEPTION_APPLIED = 'EXCEPTION_APPLIED';

	/**
	 * Wyjatek gwarancyjny COFNIETY na sprawie (listener mp_warranty_exception_changed,
	 * stan 'revoked'). Payload: {exception_id} — NO-PII (EVENT_MODEL.md).
	 */
	public const EXCEPTION_REVOKED = 'EXCEPTION_REVOKED';

	/**
	 * Przypomnienie SLA wyslane (listener mp_sla_notified od D, kind 'reminder').
	 * Payload: {kind, recipient_ref} — NO-PII, nigdy adres (EVENT_MODEL.md).
	 */
	public const SLA_REMINDER_SENT = 'SLA_REMINDER_SENT';

	/**
	 * Eskalacja SLA wyslana (listener mp_sla_notified od D, kind 'escalation').
	 * Payload: {kind, recipient_ref} — NO-PII (EVENT_MODEL.md).
	 */
	public const SLA_ESCALATED = 'SLA_ESCALATED';

	/**
	 * Odhaczenie/odznaczenie pozycji checklisty przez personel (funkcja
	 * kontraktowa `mp_case_checklist_authorize` — C waliduje wlasnosc/role,
	 * PO OK D zapisuje stan u siebie). Payload: {step_key, completed, actor_id}
	 * — STRUKTURALNY, bez tresci (EVENT_MODEL.md).
	 */
	public const CHECKLIST_ITEM_TOGGLED = 'CHECKLIST_ITEM_TOGGLED';

	/**
	 * Os czasu sprawy (append-only) — chronologicznie. Do karty sprawy personelu.
	 *
	 * @param int $case_id ID sprawy.
	 * @param int $limit   Max wierszy (1..500).
	 * @return array<int, array<string, mixed>>
	 */
	public static function for_case( int $case_id, int $limit = 200 ): array {
		global $wpdb;

		$table = Tables::full( Tables::CASE_EVENTS );
		$limit = max( 1, min( 500, $limit ) );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna append-only, zapytanie przygotowane.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT event_type, payload, actor_id, created_at
				FROM {$table} WHERE case_id = %d ORDER BY id ASC LIMIT %d",
				$case_id,
				$limit
			),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $rows ) ? $rows : array();
	}

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
