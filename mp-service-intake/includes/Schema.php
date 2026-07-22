<?php
/**
 * Migracje schematu Intake (v1: 7 tabel z kontraktu DATABASE.md).
 *
 * Rygor dbDelta: dwie spacje po PRIMARY KEY, KEY nie INDEX, bez FOREIGN KEY
 * (relacje logiczne w kodzie), LONGTEXT z walidacja JSON w PHP, utf8mb4
 * z get_charset_collate(). Dziala przy DOMYSLNYM (strict) SQL_MODE.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

use MP\Intake\Common\Migrations;

/**
 * Definicje i uruchamianie migracji Intake.
 */
final class Schema {

	/**
	 * Opcja wersji schematu (kontrakt: mp_intake_schema_version).
	 */
	public const VERSION_OPTION = 'mp_intake_schema_version';

	/**
	 * Najwyzsza wersja migracji (docelowy schemat). Gate dla maybe_upgrade.
	 */
	public const LATEST = 1;

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
			)
		);
	}

	/**
	 * V1: customers / service_cases / case_events / messages / attachments /
	 * consents / srv_counters.
	 *
	 * @return void
	 */
	public static function migration_1_tables(): void {
		global $wpdb;

		$charset     = $wpdb->get_charset_collate();
		$customers   = Tables::full( Tables::CUSTOMERS );
		$cases       = Tables::full( Tables::CASES );
		$events      = Tables::full( Tables::CASE_EVENTS );
		$messages    = Tables::full( Tables::MESSAGES );
		$attachments = Tables::full( Tables::ATTACHMENTS );
		$consents    = Tables::full( Tables::CONSENTS );
		$counters    = Tables::full( Tables::SRV_COUNTERS );

		Migrations::db_delta(
			"CREATE TABLE {$customers} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				email VARCHAR(190) NOT NULL DEFAULT '',
				name VARCHAR(190) NOT NULL DEFAULT '',
				phone VARCHAR(40) NOT NULL DEFAULT '',
				wp_user_id BIGINT UNSIGNED NULL,
				anonymized_at DATETIME NULL,
				created_at DATETIME NOT NULL,
				updated_at DATETIME NOT NULL,
				PRIMARY KEY  (id),
				KEY email (email),
				KEY wp_user_id (wp_user_id)
			) {$charset};"
		);

		Migrations::db_delta(
			"CREATE TABLE {$cases} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				case_number VARCHAR(20) NOT NULL,
				customer_id BIGINT UNSIGNED NULL,
				product_registry_id BIGINT UNSIGNED NULL,
				kind VARCHAR(20) NOT NULL DEFAULT '',
				status VARCHAR(20) NULL,
				identity_status VARCHAR(10) NOT NULL DEFAULT 'pending',
				verify_token_hash CHAR(64) NULL,
				verify_token_expires_at DATETIME NULL,
				verify_token_used_at DATETIME NULL,
				rejection_reason_code VARCHAR(64) NULL,
				possible_duplicate TINYINT(1) NOT NULL DEFAULT 0,
				form_data LONGTEXT NULL,
				form_schema_version INT UNSIGNED NOT NULL DEFAULT 1,
				warranty_snapshot LONGTEXT NULL,
				warranty_snapshot_schema_version INT UNSIGNED NULL,
				priority VARCHAR(10) NOT NULL DEFAULT 'normal',
				assigned_to BIGINT UNSIGNED NULL,
				country VARCHAR(2) NOT NULL DEFAULT '',
				lang VARCHAR(10) NOT NULL DEFAULT '',
				created_at DATETIME NOT NULL,
				verified_at DATETIME NULL,
				status_changed_at DATETIME NULL,
				updated_at DATETIME NOT NULL,
				PRIMARY KEY  (id),
				UNIQUE KEY case_number (case_number),
				UNIQUE KEY verify_token_hash (verify_token_hash),
				KEY customer_id (customer_id),
				KEY product_registry_id (product_registry_id),
				KEY status (status),
				KEY identity_status (identity_status),
				KEY created_at (created_at)
			) {$charset};"
		);

		Migrations::db_delta(
			"CREATE TABLE {$events} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				case_id BIGINT UNSIGNED NOT NULL,
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

		Migrations::db_delta(
			"CREATE TABLE {$messages} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				case_id BIGINT UNSIGNED NOT NULL,
				author_type VARCHAR(10) NOT NULL DEFAULT 'client',
				author_id BIGINT UNSIGNED NULL,
				body LONGTEXT NOT NULL,
				created_at DATETIME NOT NULL,
				PRIMARY KEY  (id),
				KEY case_id (case_id),
				KEY created_at (created_at)
			) {$charset};"
		);

		Migrations::db_delta(
			"CREATE TABLE {$attachments} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				case_id BIGINT UNSIGNED NOT NULL,
				path VARCHAR(255) NOT NULL,
				mime VARCHAR(100) NOT NULL DEFAULT '',
				size_bytes BIGINT UNSIGNED NOT NULL DEFAULT 0,
				original_name VARCHAR(255) NOT NULL DEFAULT '',
				retention_until DATETIME NULL,
				deleted_at DATETIME NULL,
				created_at DATETIME NOT NULL,
				PRIMARY KEY  (id),
				KEY case_id (case_id),
				KEY retention_until (retention_until)
			) {$charset};"
		);

		Migrations::db_delta(
			"CREATE TABLE {$consents} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				customer_id BIGINT UNSIGNED NULL,
				email VARCHAR(190) NOT NULL DEFAULT '',
				case_id BIGINT UNSIGNED NULL,
				consent_key VARCHAR(64) NOT NULL DEFAULT '',
				consent_version VARCHAR(20) NOT NULL DEFAULT '',
				consent_text LONGTEXT NOT NULL,
				withdrawn_at DATETIME NULL,
				consented_at DATETIME NOT NULL,
				PRIMARY KEY  (id),
				KEY customer_id (customer_id),
				KEY email (email),
				KEY case_id (case_id),
				KEY consent_key (consent_key)
			) {$charset};"
		);

		Migrations::db_delta(
			"CREATE TABLE {$counters} (
				year SMALLINT UNSIGNED NOT NULL,
				value BIGINT UNSIGNED NOT NULL DEFAULT 0,
				PRIMARY KEY  (year)
			) {$charset};"
		);
	}
}
