<?php
/**
 * Migracje schematu Automatora (v1: 4 tabele z kontraktu DATABASE.md / OWNERSHIP.md).
 *
 * Rygor dbDelta: dwie spacje po PRIMARY KEY, KEY nie INDEX, bez FOREIGN KEY
 * (relacje logiczne w kodzie), LONGTEXT z walidacja JSON w PHP, utf8mb4
 * z get_charset_collate(). Dziala przy DOMYSLNYM (strict) SQL_MODE.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

use MP\Automator\Common\Migrations;

/**
 * Definicje i uruchamianie migracji Automatora.
 */
final class Schema {

	/**
	 * Opcja wersji schematu (kontrakt: mp_automator_schema_version).
	 */
	public const VERSION_OPTION = Lifecycle::SCHEMA_OPTION;

	/**
	 * Najwyzsza wersja migracji (docelowy schemat). Gate dla maybe_upgrade.
	 */
	public const LATEST = 2;

	/**
	 * Uruchamia zalegle migracje.
	 *
	 * @return void
	 */
	public static function migrate(): void {
		Migrations::run(
			self::VERSION_OPTION,
			array(
				1 => array( self::class, 'migration_1_tables' ),
				2 => array( self::class, 'migration_2_warning_at' ),
			)
		);
	}

	/**
	 * V2 (SLA-2): kolumna `warning_at` w case_sla — moment progu przypomnienia
	 * (= deadline − warning_hours, liczony przy provisioningu). Indeks pozwala
	 * sweepowi wybrac wymagalne przypomnienia czystym SARGABLE WHERE bez per-status
	 * liczenia w SQL. dbDelta dokłada kolumne+indeks do istniejacej tabeli.
	 *
	 * @return void
	 */
	public static function migration_2_warning_at(): void {
		global $wpdb;

		$charset = $wpdb->get_charset_collate();
		$sla     = Tables::full( Tables::CASE_SLA );

		Migrations::db_delta(
			"CREATE TABLE {$sla} (
				case_id BIGINT UNSIGNED NOT NULL,
				status VARCHAR(20) NOT NULL DEFAULT '',
				sla_policy_version INT UNSIGNED NOT NULL DEFAULT 1,
				deadline_at DATETIME NULL,
				warning_at DATETIME NULL,
				reminder_sent_at DATETIME NULL,
				escalated_at DATETIME NULL,
				reminder_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
				escalation_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
				updated_at DATETIME NOT NULL,
				PRIMARY KEY  (case_id),
				KEY deadline_at (deadline_at),
				KEY warning_at (warning_at)
			) {$charset};"
		);
	}

	/**
	 * V1: workflow_rules / case_sla / case_checklists / workflow_events.
	 *
	 * @return void
	 */
	public static function migration_1_tables(): void {
		global $wpdb;

		$charset    = $wpdb->get_charset_collate();
		$rules      = Tables::full( Tables::WORKFLOW_RULES );
		$sla        = Tables::full( Tables::CASE_SLA );
		$checklists = Tables::full( Tables::CASE_CHECKLISTS );
		$events     = Tables::full( Tables::WORKFLOW_EVENTS );

		// Reguly: kolumny STRUKTURALNE — ZAKAZ eval; system_key UNIQUE NULL
		// (uzytkownicze reguly maja NULL — wiele NULL dozwolone w UNIQUE).
		Migrations::db_delta(
			"CREATE TABLE {$rules} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				trigger_type VARCHAR(40) NOT NULL DEFAULT '',
				condition_key VARCHAR(40) NOT NULL DEFAULT '',
				condition_operator VARCHAR(20) NOT NULL DEFAULT 'equals',
				condition_value VARCHAR(190) NOT NULL DEFAULT '',
				action_type VARCHAR(40) NOT NULL DEFAULT '',
				action_config_json LONGTEXT NULL,
				priority INT NOT NULL DEFAULT 10,
				enabled TINYINT(1) NOT NULL DEFAULT 1,
				rr_cursor BIGINT UNSIGNED NOT NULL DEFAULT 0,
				source VARCHAR(10) NOT NULL DEFAULT 'user',
				system_key VARCHAR(64) NULL,
				created_at DATETIME NOT NULL,
				updated_at DATETIME NOT NULL,
				PRIMARY KEY  (id),
				UNIQUE KEY system_key (system_key),
				KEY trigger_enabled_priority (trigger_type, enabled, priority)
			) {$charset};"
		);

		// Ksiegowosc SLA: case_id PK; terminalne -> deadline_at NULL (sweep pomija).
		Migrations::db_delta(
			"CREATE TABLE {$sla} (
				case_id BIGINT UNSIGNED NOT NULL,
				status VARCHAR(20) NOT NULL DEFAULT '',
				sla_policy_version INT UNSIGNED NOT NULL DEFAULT 1,
				deadline_at DATETIME NULL,
				reminder_sent_at DATETIME NULL,
				escalated_at DATETIME NULL,
				reminder_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
				escalation_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
				updated_at DATETIME NOT NULL,
				PRIMARY KEY  (case_id),
				KEY deadline_at (deadline_at)
			) {$charset};"
		);

		// Checklisty: wiersz per KROK (atomowy toggle); step_label zamrozony
		// z chwili odhaczenia (wzorzec form_data); ZERO pol wolnotekstowych PII.
		Migrations::db_delta(
			"CREATE TABLE {$checklists} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				case_id BIGINT UNSIGNED NOT NULL,
				template_id VARCHAR(64) NOT NULL DEFAULT '',
				step_key VARCHAR(64) NOT NULL DEFAULT '',
				step_label VARCHAR(190) NOT NULL DEFAULT '',
				completed TINYINT(1) NOT NULL DEFAULT 0,
				completed_by BIGINT UNSIGNED NULL,
				completed_at DATETIME NULL,
				created_at DATETIME NOT NULL,
				updated_at DATETIME NOT NULL,
				PRIMARY KEY  (id),
				UNIQUE KEY case_step (case_id, template_id, step_key),
				KEY case_id (case_id)
			) {$charset};"
		);

		// Rejestr operacji D: jak case_events (append-only, strukturalny, NO-PII).
		// case_id NULL dopuszczalne — EXPORT_GENERATED / CRUD konfiguracji / sweep-run
		// nie dotycza pojedynczej sprawy.
		Migrations::db_delta(
			"CREATE TABLE {$events} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				case_id BIGINT UNSIGNED NULL,
				event_type VARCHAR(64) NOT NULL,
				payload LONGTEXT NULL,
				schema_version INT UNSIGNED NOT NULL DEFAULT 1,
				actor_id BIGINT UNSIGNED NULL,
				created_at DATETIME NOT NULL,
				PRIMARY KEY  (id),
				KEY case_id (case_id),
				KEY event_type (event_type),
				KEY created_at (created_at)
			) {$charset};"
		);
	}
}
