<?php
/**
 * Plugin Name: MP Warranty & Serial Registry
 * Description: Rejestr produktow, numerow seryjnych, partii i okresow gwarancyjnych: import CSV, statusy gwarancji, wyjatki gwarancyjne, wyszukiwarka.
 * Version: 0.5.0
 * Requires at least: 6.9
 * Requires PHP: 8.1
 * Author: MP Service Suite
 * License: GPLv2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: mp-warranty-registry
 * Domain Path: /languages
 *
 * @package MP\Registry
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'MP_REGISTRY_FILE', __FILE__ );
define( 'MP_REGISTRY_VERSION', '0.5.0' );

if ( ! defined( 'MP_CONTRACT_VERSION' ) ) {
	define( 'MP_CONTRACT_VERSION', 1 );
}

require_once __DIR__ . '/includes/Autoloader.php';

MP\Registry\Autoloader::register();

register_activation_hook( __FILE__, array( MP\Registry\Lifecycle::class, 'activate' ) );
register_deactivation_hook( __FILE__, array( MP\Registry\Lifecycle::class, 'deactivate' ) );

add_action(
	'plugins_loaded',
	static function (): void {
		MP\Registry\Plugin::instance()->boot();
	}
);
