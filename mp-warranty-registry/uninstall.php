<?php
/**
 * Odinstalowanie MP Warranty & Serial Registry.
 *
 * Warstwa (i): opcje techniczne + wspolna mechanika rol (Common\Uninstall).
 * Warstwa (ii): dane biznesowe — domyslnie ZOSTAJA (default OFF); kasowanie
 * tabel dochodzi wraz z migracjami (D2) pod jawna lista tabel wlasnych.
 *
 * @package MP\Registry
 */

if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}

require_once __DIR__ . '/includes/Autoloader.php';

MP\Registry\Autoloader::register();

MP\Registry\Common\Uninstall::run(
	'mp_module_registry',
	array( 'mp_registry_schema_version' ),
	array()
);
