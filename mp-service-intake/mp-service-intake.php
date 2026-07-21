<?php
/**
 * Plugin Name: MP Service Intake
 * Description: Przyjmowanie zgloszen serwisowych i reklamacyjnych: dynamiczny formularz, numer sprawy SRV, konto klienta, ochrona przed spamem.
 * Version: 0.1.0
 * Requires at least: 6.9
 * Requires PHP: 8.1
 * Author: MP Service Suite
 * License: GPLv2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: mp-service-intake
 * Domain Path: /languages
 *
 * @package MP\Intake
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'MP_INTAKE_FILE', __FILE__ );
define( 'MP_INTAKE_VERSION', '0.1.0' );

if ( ! defined( 'MP_CONTRACT_VERSION' ) ) {
	define( 'MP_CONTRACT_VERSION', 1 );
}

require_once __DIR__ . '/includes/Autoloader.php';

MP\Intake\Autoloader::register();

register_activation_hook( __FILE__, array( MP\Intake\Lifecycle::class, 'activate' ) );
register_deactivation_hook( __FILE__, array( MP\Intake\Lifecycle::class, 'deactivate' ) );

add_action(
	'plugins_loaded',
	static function (): void {
		MP\Intake\Plugin::instance()->boot();
	}
);
