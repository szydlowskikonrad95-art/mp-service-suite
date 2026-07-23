<?php
/**
 * Migracje schematu Registry (v1: 4 tabele z kontraktu DATABASE.md).
 *
 * Rygor dbDelta: dwie spacje po PRIMARY KEY, KEY nie INDEX, bez FOREIGN KEY
 * (relacje logiczne w kodzie), LONGTEXT z walidacja JSON w PHP, utf8mb4
 * z get_charset_collate(). Dziala przy DOMYSLNYM (strict) SQL_MODE.
 *
 * @package MP\Registry
 */

namespace MP\Registry;

use MP\Registry\Common\Migrations;

/**
 * Definicje i uruchamianie migracji Registry.
 */
final class Schema {

	/**
	 * Opcja wersji schematu (kontrakt: mp_registry_schema_version).
	 */
	public const VERSION_OPTION = 'mp_registry_schema_version';

	/**
	 * Najwyzsza wersja migracji (docelowy schemat). Gate dla maybe_upgrade —
	 * BUMP przy dodaniu nowej migracji do migrate().
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
				2 => array( self::class, 'migration_2_product_category' ),
			)
		);
	}

	/**
	 * V1: tabele registry / product_events / warranty_exceptions / import_jobs.
	 *
	 * @return void
	 */
	public static function migration_1_tables(): void {
		global $wpdb;

		$charset  = $wpdb->get_charset_collate();
		$registry = Tables::full( Tables::REGISTRY );
		$events   = Tables::full( Tables::PRODUCT_EVENTS );
		$except   = Tables::full( Tables::EXCEPTIONS );
		$jobs     = Tables::full( Tables::IMPORT_JOBS );

		Migrations::db_delta(
			"CREATE TABLE {$registry} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				serial_display VARCHAR(100) NOT NULL,
				serial_normalized VARCHAR(100) NOT NULL,
				model VARCHAR(190) NOT NULL DEFAULT '',
				batch VARCHAR(100) NOT NULL DEFAULT '',
				purchase_document VARCHAR(190) NOT NULL DEFAULT '',
				purchase_date DATE NULL,
				warranty_until DATE NULL,
				source VARCHAR(20) NOT NULL DEFAULT 'manual',
				import_job_id BIGINT UNSIGNED NULL,
				archived TINYINT(1) NOT NULL DEFAULT 0,
				deleted_at DATETIME NULL,
				deleted_by BIGINT UNSIGNED NULL,
				created_at DATETIME NOT NULL,
				updated_at DATETIME NOT NULL,
				PRIMARY KEY  (id),
				UNIQUE KEY serial_norm (serial_normalized),
				KEY warranty_until (warranty_until),
				KEY model (model),
				KEY invoice (purchase_document)
			) {$charset};"
		);

		Migrations::db_delta(
			"CREATE TABLE {$events} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				product_registry_id BIGINT UNSIGNED NOT NULL,
				event_type VARCHAR(64) NOT NULL,
				payload LONGTEXT NULL,
				actor_id BIGINT UNSIGNED NULL,
				created_at DATETIME NOT NULL,
				PRIMARY KEY  (id),
				KEY product_registry_id (product_registry_id),
				KEY event_type (event_type),
				KEY created_at (created_at)
			) {$charset};"
		);

		Migrations::db_delta(
			"CREATE TABLE {$except} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				product_registry_id BIGINT UNSIGNED NOT NULL,
				case_id BIGINT UNSIGNED NULL,
				status VARCHAR(10) NOT NULL DEFAULT 'active',
				valid_from DATETIME NOT NULL,
				valid_until DATETIME NULL,
				reason VARCHAR(500) NOT NULL DEFAULT '',
				created_by BIGINT UNSIGNED NOT NULL,
				created_at DATETIME NOT NULL,
				revoked_by BIGINT UNSIGNED NULL,
				revoked_at DATETIME NULL,
				PRIMARY KEY  (id),
				KEY exception_scope (product_registry_id, status, case_id, valid_until)
			) {$charset};"
		);

		Migrations::db_delta(
			"CREATE TABLE {$jobs} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				file_path VARCHAR(500) NOT NULL,
				status VARCHAR(20) NOT NULL DEFAULT 'pending',
				total_rows INT UNSIGNED NOT NULL DEFAULT 0,
				processed_rows INT UNSIGNED NOT NULL DEFAULT 0,
				success_rows INT UNSIGNED NOT NULL DEFAULT 0,
				error_rows INT UNSIGNED NOT NULL DEFAULT 0,
				error_report_path VARCHAR(500) NULL,
				lock_key VARCHAR(64) NULL,
				job_token VARCHAR(36) NULL,
				created_at DATETIME NOT NULL,
				updated_at DATETIME NOT NULL,
				finished_at DATETIME NULL,
				PRIMARY KEY  (id),
				UNIQUE KEY lock_key (lock_key)
			) {$charset};"
		);
	}

	/**
	 * V2: kolumna `category` w product_registry (kartka P1.2/P3.1 — os przydzialu).
	 *
	 * ADDYTYWNA. dbDelta na istniejacej tabeli dodaje TYLKO brakujaca kolumne
	 * (nie tyka danych/innych kolumn). Istniejace wiersze dostaja DEFAULT 'inne'.
	 *
	 * @return void
	 */
	public static function migration_2_product_category(): void {
		global $wpdb;

		$charset  = $wpdb->get_charset_collate();
		$registry = Tables::full( Tables::REGISTRY );

		Migrations::db_delta(
			"CREATE TABLE {$registry} (
				id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
				serial_display VARCHAR(100) NOT NULL,
				serial_normalized VARCHAR(100) NOT NULL,
				model VARCHAR(190) NOT NULL DEFAULT '',
				batch VARCHAR(100) NOT NULL DEFAULT '',
				category VARCHAR(32) NOT NULL DEFAULT 'inne',
				purchase_document VARCHAR(190) NOT NULL DEFAULT '',
				purchase_date DATE NULL,
				warranty_until DATE NULL,
				source VARCHAR(20) NOT NULL DEFAULT 'manual',
				import_job_id BIGINT UNSIGNED NULL,
				archived TINYINT(1) NOT NULL DEFAULT 0,
				deleted_at DATETIME NULL,
				deleted_by BIGINT UNSIGNED NULL,
				created_at DATETIME NOT NULL,
				updated_at DATETIME NOT NULL,
				PRIMARY KEY  (id),
				UNIQUE KEY serial_norm (serial_normalized),
				KEY warranty_until (warranty_until),
				KEY model (model),
				KEY invoice (purchase_document),
				KEY category (category)
			) {$charset};"
		);
	}
}
