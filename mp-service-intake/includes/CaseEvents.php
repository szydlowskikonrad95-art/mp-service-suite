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
	 * Nieudana wysylka maila do klienta (magic-link / potwierdzenie z numerem SRV).
	 * Payload: {kind, error_code} — STRUKTURALNY, bez tresci maila. Bez tego zdarzenia
	 * awaria poczty byla niewidoczna: klient nie dostawal linku, a w bazie nie zostawal
	 * zaden slad (audyt 27.07). Wzorzec zgodny z MAIL_FAILED w Automatorze.
	 */
	public const MAIL_FAILED = 'MAIL_FAILED';

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
	 * @return bool True gdy wpis powstal. ⛔ Wczesniej `: void` — nieudany zapis
	 *              przechodzil niezauwazony, bo `$wpdb->insert()` przy bledzie
	 *              zwraca wartosc falszywa, a nie przerywa wykonania.
	 */
	public static function log( int $case_id, string $event_type, array $payload, ?int $actor_id ): bool {
		$table = Tables::full( Tables::CASE_EVENTS );

		return Common\EventWrite::insert(
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
	}

	/**
	 * Sprawy, ktorym NIE WYSZEDL ostatnio wyslany link potwierdzajacy (audyt 2.1b).
	 *
	 * PO CO: awaria poczty byla zapisywana na osi sprawy i podnosila alarm globalny
	 * („poczta nie dziala"), ale personel obslugujacy kolejke potrzebuje odpowiedzi
	 * na pytanie o POJEDYNCZA sprawe — „ktoremu klientowi nie doszedl link".
	 * Ekran „Niepotwierdzone" pokazywal takie sprawy nieodroznialnie od udanych.
	 *
	 * KTORE liczymy: tylko awarie NOWSZE niz wydanie aktualnego tokenu. Kazda ponowna
	 * wysylka wydaje swiezy token (`CaseRepo::regenerate_token`), wiec udana ponowka
	 * gasi oznaczenie sama, bez kasowania czegokolwiek (os czasu jest append-only).
	 * Moment wydania liczymy z `verify_token_expires_at` minus TTL — obie wartosci
	 * sa w GMT, tak samo jak `created_at` zdarzen.
	 *
	 * JEDNO zapytanie na caly ekran, nie jedno na wiersz (lista ma do 100 spraw).
	 *
	 * @param array<int, int> $case_ids Sprawy z listy.
	 * @return array<int, true> Mapa case_id => true (tylko sprawy z nieudana wysylka).
	 */
	public static function cases_with_failed_mail( array $case_ids ): array {
		global $wpdb;

		$ids = array_values( array_unique( array_filter( array_map( 'intval', $case_ids ) ) ) );

		if ( array() === $ids ) {
			return array();
		}

		$events       = Tables::full( Tables::CASE_EVENTS );
		$cases        = Tables::full( Tables::CASES );
		$placeholders = implode( ', ', array_fill( 0, count( $ids ), '%d' ) );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared, WordPress.DB.PreparedSQLPlaceholders.ReplacementsWrongNumber -- tabele wlasne, zapytanie przygotowane; liczba placeholderow jest ZMIENNA (tyle, ile id), wiec sniff nie policzy jej statycznie — argumenty ida jedna tablica przez array_merge.
		$rows = $wpdb->get_col(
			$wpdb->prepare(
				"SELECT DISTINCT e.case_id
				FROM {$events} e
				INNER JOIN {$cases} c ON c.id = e.case_id
				WHERE e.case_id IN ( {$placeholders} )
				AND e.event_type = %s
				AND c.verify_token_expires_at IS NOT NULL
				AND e.created_at >= DATE_SUB( c.verify_token_expires_at, INTERVAL %d HOUR )",
				array_merge( $ids, array( self::MAIL_FAILED, CaseRepo::TOKEN_TTL_HOURS ) )
			)
		);
		// phpcs:enable

		$out = array();

		foreach ( (array) $rows as $id ) {
			$out[ (int) $id ] = true;
		}

		return $out;
	}
}
