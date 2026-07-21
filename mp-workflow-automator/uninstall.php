<?php
/**
 * Odinstalowanie MP Workflow Automator.
 *
 * Warstwa (i): opcje techniczne + wspolna mechanika rol (Common\Uninstall).
 * Warstwa (ii): dane biznesowe — domyslnie ZOSTAJA (default OFF); kasowanie
 * tabel dochodzi wraz z migracjami (D2) pod jawna lista tabel wlasnych.
 *
 * @package MP\Automator
 */

if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}

require_once __DIR__ . '/includes/Autoloader.php';

MP\Automator\Autoloader::register();

MP\Automator\Common\Uninstall::run(
	'mp_module_automator',
	array( 'mp_automator_schema_version' ),
	array()
);
