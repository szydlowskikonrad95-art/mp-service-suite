<?php
/**
 * Nazwy tabel pluginu Registry — WYLACZNIE przez te stale/metode.
 *
 * Standard kodu (OWNERSHIP.md): zakaz dynamicznego skladania nazw tabel w SQL;
 * linter cudzych tabel pilnuje, by literaly tabel innych pluginow nie pojawily
 * sie w tym kodzie.
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * Tabele wlasne Registry (4 z kontraktu DATABASE.md).
 */
final class Tables {

	/**
	 * Rejestr produktow/seriali.
	 */
	public const REGISTRY = 'mp_product_registry';

	/**
	 * Historia zmian produktu i decyzji (append-only).
	 */
	public const PRODUCT_EVENTS = 'mp_product_events';

	/**
	 * Stan wyjatkow gwarancyjnych.
	 */
	public const EXCEPTIONS = 'mp_warranty_exceptions';

	/**
	 * Przebiegi importu CSV.
	 */
	public const IMPORT_JOBS = 'mp_import_jobs';

	/**
	 * Pelna nazwa tabeli z prefiksem instalacji.
	 *
	 * @param string $table Jedna ze stalych tej klasy.
	 * @return string Nazwa z prefiksem $wpdb.
	 */
	public static function full( string $table ): string {
		global $wpdb;

		return $wpdb->prefix . $table;
	}
}
