<?php
/**
 * Nazwy tabel wlasnych Automatora (D) — WYLACZNIE przez stale tej klasy.
 *
 * Zakaz dynamicznego skladania nazw w SQL; linter cudzych tabel pilnuje,
 * zeby inne pluginy tych nazw nie dotykaly (i zeby D nie dotykal cudzych).
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Rejestr nazw tabel D (4 wg DATABASE.md, wlasnosc D w OWNERSHIP.md).
 */
final class Tables {

	/**
	 * Reguly silnika automatora (trigger/warunek/akcja; kursor round-robin).
	 */
	public const WORKFLOW_RULES = 'mp_workflow_rules';

	/**
	 * Ksiegowosc SLA per sprawa (terminy + markery wysylek; idempotencja sweepa).
	 */
	public const CASE_SLA = 'mp_case_sla';

	/**
	 * Stan odhaczen checklist (wiersz per KROK, atomowy toggle; step_label zamrozony).
	 */
	public const CASE_CHECKLISTS = 'mp_case_checklists';

	/**
	 * Rejestr operacji D (APPEND-ONLY, strukturalny, NO-PII).
	 */
	public const WORKFLOW_EVENTS = 'mp_workflow_events';

	/**
	 * Pelna nazwa tabeli z prefiksem instalacji.
	 *
	 * @param string $table Stala z tej klasy.
	 * @return string
	 */
	public static function full( string $table ): string {
		global $wpdb;

		return $wpdb->prefix . $table;
	}
}
