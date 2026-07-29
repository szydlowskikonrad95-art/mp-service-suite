<?php
/**
 * Odinstalowanie MP Warranty & Serial Registry.
 *
 * Warstwa (i): opcje techniczne, katalog roboczy importow (pliki) + wspolna
 * mechanika rol (Common\Uninstall).
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

// Warstwa (i) — katalog roboczy importow (PLIKI techniczne) sprzatany ZAWSZE.
//
// Audyt 29.07: tego bloku NIE BYLO, choc OWNERSHIP.md obiecuje „warstwa (i) ZAWSZE:
// opcje techniczne, transienty, crony, PLIKI techniczne". Importer sklada tu znormalizowane
// pliki wsadowe i raporty odrzuconych wierszy (numery seryjne, faktury, daty zakupu),
// a cron retencji `mp_registry_imports_sweep` ginie razem z wtyczka — wiec po odinstalowaniu
// nic juz tego nie sprzatalo i katalog zostawal na serwerze NA ZAWSZE.
// Uklad 1:1 jak w Intake (mp-service-intake/uninstall.php) — ten sam wzorzec katalogu z guardami.
$mp_registry_uploads     = wp_upload_dir();
$mp_registry_imports_dir = rtrim( (string) $mp_registry_uploads['basedir'], '/' ) . '/mp-imports';

if ( is_dir( $mp_registry_imports_dir ) ) {
	$mp_registry_files = glob( $mp_registry_imports_dir . '/*' );

	foreach ( ( false === $mp_registry_files ? array() : $mp_registry_files ) as $mp_registry_file ) {
		if ( is_file( $mp_registry_file ) ) {
			wp_delete_file( $mp_registry_file );
		}
	}

	// Zostaja tylko .htaccess/index.php (guardy z Importer::imports_dir) — skasuj i zdejmij katalog.
	foreach ( array( '/.htaccess', '/index.php' ) as $mp_registry_guard ) {
		if ( is_file( $mp_registry_imports_dir . $mp_registry_guard ) ) {
			wp_delete_file( $mp_registry_imports_dir . $mp_registry_guard );
		}
	}

	// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_rmdir -- uninstall: pusty katalog techniczny importow.
	rmdir( $mp_registry_imports_dir );
}

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
	MP\Registry\Lifecycle::CRON_HOOKS
);
