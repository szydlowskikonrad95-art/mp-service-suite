<?php
/**
 * Odinstalowanie MP Workflow Automator.
 *
 * Warstwa (i): opcje techniczne + wspolna mechanika rol (Common\Uninstall).
 * Warstwa (ii): dane biznesowe — domyslnie ZOSTAJA (default OFF); 4 tabele D
 * (workflow_rules, case_sla, case_checklists, workflow_events) + opcje-TRESCI
 * (szablony/definicje checklist/statusy wlasne — dochodza w P3.2/P3.3/P3.5)
 * kasowane WYLACZNIE za jawna zgoda admina (mp_automator_delete_data=1). Reguly
 * i ich szablony PRZEZYWAJA RAZEM (regula bez szablonu po reinstalacji = sierota).
 *
 * @package MP\Automator
 */

if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}

require_once __DIR__ . '/includes/Autoloader.php';

MP\Automator\Autoloader::register();

// Warstwa (ii) — dane biznesowe D — kasowane WYLACZNIE za jawna zgoda admina.
$mp_automator_delete_data = ( '1' === get_option( 'mp_automator_delete_data', '0' ) );

if ( $mp_automator_delete_data ) {
	global $wpdb;

	$mp_automator_tables = array(
		MP\Automator\Tables::WORKFLOW_EVENTS,
		MP\Automator\Tables::CASE_CHECKLISTS,
		MP\Automator\Tables::CASE_SLA,
		MP\Automator\Tables::WORKFLOW_RULES,
	);

	foreach ( $mp_automator_tables as $mp_automator_table ) {
		$mp_automator_full = MP\Automator\Tables::full( $mp_automator_table );
		// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.DirectDatabaseQuery.SchemaChange, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- uninstall sciezka ON: kasowanie WLASNYCH tabel (nazwa ze stalych, nie z inputu).
		$wpdb->query( "DROP TABLE IF EXISTS {$mp_automator_full}" );
	}

	delete_option( MP\Automator\Schema::VERSION_OPTION );
	// SEED_VERSION w warstwie (ii): pelny uninstall kasuje => reinstalacja sieje swiezo.
	delete_option( MP\Automator\Rules::SEED_VERSION_OPTION );
}

MP\Automator\Common\Uninstall::run(
	'mp_module_automator',
	array( 'mp_automator_schema_version', 'mp_automator_delete_data' ),
	array()
);
