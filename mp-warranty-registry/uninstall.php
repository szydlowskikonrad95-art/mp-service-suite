<?php
/**
 * Odinstalowanie MP Warranty & Serial Registry.
 *
 * Warstwa (i): opcje techniczne + wspolna mechanika rol (Common\Uninstall).
 * Warstwa (ii) — dane biznesowe — default OFF (zostaja): kasowane WYLACZNIE
 * gdy admin swiadomie wlaczyl opcje "usun dane przy odinstalowaniu".
 * Opcja wersji schematu zyje/umiera RAZEM z tabelami (przy zostawionych
 * tabelach skasowana wersja = ryzyko niechcianych ALTER-ow po reinstalacji).
 *
 * @package MP\Registry
 */

if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}

require_once __DIR__ . '/includes/Autoloader.php';

MP\Registry\Autoloader::register();

$mp_registry_delete_data = ( '1' === get_option( 'mp_registry_delete_data', '0' ) );

if ( $mp_registry_delete_data ) {
	global $wpdb;

	$mp_registry_tables = array(
		MP\Registry\Tables::IMPORT_JOBS,
		MP\Registry\Tables::EXCEPTIONS,
		MP\Registry\Tables::PRODUCT_EVENTS,
		MP\Registry\Tables::REGISTRY,
	);

	foreach ( $mp_registry_tables as $mp_registry_table ) {
		$mp_registry_full = MP\Registry\Tables::full( $mp_registry_table );
		// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.DirectDatabaseQuery.SchemaChange, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- uninstall sciezka ON: kasowanie WLASNYCH tabel (nazwa ze stalych, nie z inputu).
		$wpdb->query( "DROP TABLE IF EXISTS {$mp_registry_full}" );
	}

	delete_option( MP\Registry\Schema::VERSION_OPTION );
}

MP\Registry\Common\Uninstall::run(
	'mp_module_registry',
	array( 'mp_registry_delete_data' ),
	array()
);
