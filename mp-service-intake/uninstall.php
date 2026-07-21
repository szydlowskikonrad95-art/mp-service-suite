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

MP\Intake\Common\Uninstall::run(
	'mp_module_intake',
	array( 'mp_intake_schema_version' ),
	array()
);
