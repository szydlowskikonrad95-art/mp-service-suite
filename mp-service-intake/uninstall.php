<?php
/**
 * Odinstalowanie MP Service Intake.
 *
 * Warstwa (i): opcje techniczne + wspolna mechanika rol (Common\Uninstall).
 * Warstwa (ii): dane biznesowe — domyslnie ZOSTAJA (default OFF); kasowanie
 * tabel dochodzi wraz z migracjami (D2) pod jawna lista tabel wlasnych.
 *
 * @package MP\Intake
 */

if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}

require_once __DIR__ . '/includes/Autoloader.php';

MP\Intake\Autoloader::register();

// Warstwa (ii) — dane biznesowe C — kasowane WYLACZNIE za jawna zgoda admina.
// srv_counters czyszczone RAZEM ze sprawami: skasowanie licznika przy zostawionych
// sprawach => duplikaty SRV po reinstalacji w tym samym roku (DATABASE.md sekcja 4).
$mp_intake_delete_data = ( '1' === get_option( 'mp_intake_delete_data', '0' ) );

if ( $mp_intake_delete_data ) {
	global $wpdb;

	$mp_intake_tables = array(
		MP\Intake\Tables::CASE_EVENTS,
		MP\Intake\Tables::MESSAGES,
		MP\Intake\Tables::ATTACHMENTS,
		MP\Intake\Tables::CONSENTS,
		MP\Intake\Tables::CASES,
		MP\Intake\Tables::CUSTOMERS,
		MP\Intake\Tables::SRV_COUNTERS,
	);

	foreach ( $mp_intake_tables as $mp_intake_table ) {
		$mp_intake_full = MP\Intake\Tables::full( $mp_intake_table );
		// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.DirectDatabaseQuery.SchemaChange, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- uninstall sciezka ON: kasowanie WLASNYCH tabel (nazwa ze stalych, nie z inputu).
		$wpdb->query( "DROP TABLE IF EXISTS {$mp_intake_full}" );
	}

	delete_option( MP\Intake\Schema::VERSION_OPTION );
}

MP\Intake\Common\Uninstall::run(
	'mp_module_intake',
	array( 'mp_intake_schema_version', 'mp_intake_delete_data' ),
	array()
);
