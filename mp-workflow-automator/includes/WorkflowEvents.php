<?php
/**
 * Rejestr operacji D — wp_mp_workflow_events (APPEND-ONLY BEZ WYJATKOW).
 *
 * ZELAZNA ZASADA NO-PII-IN-LOG: payload W 100% STRUKTURALNY (referencje, kody,
 * statystyki) — ZERO wolnego tekstu, NIGDY adresu ani wyrenderowanej tresci maila.
 * Maile logowane wylacznie jako {template_key, recipient_ref}. Klasa nie ma metod
 * UPDATE/DELETE z zalozenia. Przy uninstallu C (mp_cases_data_erased) ZOSTAJE —
 * rejestr historyczny, nie wskazuje "na zywo".
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Zapis zdarzen rejestru operacji automatora.
 */
final class WorkflowEvents {

	/**
	 * Wersja ksztaltu payloadu.
	 */
	public const SCHEMA_VERSION = 1;

	/**
	 * Wykonanie reguly ({rule_id, case_id, trigger, action, result, depth}).
	 */
	public const RULE_EXECUTED = 'RULE_EXECUTED';

	/**
	 * Mutacja reguly zablokowana przez guard petli (glebokosc >= 1).
	 */
	public const RULE_LOOP_BLOCKED = 'RULE_LOOP_BLOCKED';

	/**
	 * Przekroczony limit akcji na zdarzenie (pas bezpieczenstwa 100).
	 */
	public const RULE_LIMIT_HIT = 'RULE_LIMIT_HIT';

	/**
	 * Zadna regula/pusta pula — sprawa zostaje nieprzydzielona (swiadomy stan).
	 */
	public const ASSIGNMENT_UNMATCHED = 'ASSIGNMENT_UNMATCHED';

	/**
	 * Nieudana wysylka maila (wp_mail=false) — ponowienie nastepnym sweepem.
	 */
	public const MAIL_FAILED = 'MAIL_FAILED';

	/**
	 * Wysylka nieudana po 3 probach — marker ustawiony + alarm admina.
	 */
	public const MAIL_FAILED_FINAL = 'MAIL_FAILED_FINAL';

	/**
	 * Adresat-klient bez adresu (zanonimizowany po RODO) — legalne pominiecie.
	 */
	public const MAIL_SKIPPED_NO_RECIPIENT = 'MAIL_SKIPPED_NO_RECIPIENT';

	/**
	 * Identyczny mail (adresat+tresc) w oknie dedupu — pominiety (best-effort).
	 */
	public const MAIL_DEDUPED = 'MAIL_DEDUPED';

	/**
	 * Wygenerowano eksport CSV ({user_id, rows, filters_hash}).
	 */
	public const EXPORT_GENERATED = 'EXPORT_GENERATED';

	/**
	 * CRUD konfiguracji ({object, id, actor}) — reguly/szablony/statusy/SLA.
	 */
	public const CONFIG_CHANGED = 'CONFIG_CHANGED';

	/**
	 * Przebieg sweepa / resyncu ({statystyki przebiegu: reminders/escalations...}).
	 */
	public const SWEEP_RUN = 'SWEEP_RUN';

	/**
	 * „Przelicz SLA" (SLA-4): admin przeliczyl terminy otwartych spraw wg biezacego
	 * SlaConfig. Payload {cases_touched}; actor_id = kto, created_at = kiedy (audyt).
	 */
	public const SLA_RECALCULATED = 'SLA_RECALCULATED';

	/**
	 * Raport koncowy wygenerowany przy zamknieciu sprawy (przebieg krok 8).
	 * D sklada podsumowanie i wola mp_case_add_system_message (wpis systemowy w C).
	 * Payload {case_number}; NO-PII.
	 */
	public const CLOSING_REPORT_GENERATED = 'CLOSING_REPORT_GENERATED';

	/**
	 * Dopisuje zdarzenie do rejestru operacji D (append-only).
	 *
	 * @param string               $event_type Typ (stala z tej klasy).
	 * @param array<string, mixed> $payload    Dane STRUKTURALNE (bez wolnego tekstu/PII).
	 * @param int|null             $case_id    ID sprawy (null = zdarzenie nie-per-sprawa).
	 * @param int|null             $actor_id   Kto (null = system).
	 * @return void
	 */
	public static function log( string $event_type, array $payload, ?int $case_id = null, ?int $actor_id = null ): void {
		global $wpdb;

		$table = Tables::full( Tables::WORKFLOW_EVENTS );

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
