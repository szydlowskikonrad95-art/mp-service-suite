<?php
/**
 * Plugin Name: MP Workflow Automator
 * Description: Silnik regul serwisu: automatyczny przydzial spraw, statusy, powiadomienia e-mail, terminy SLA z eskalacja, checklisty i eksport raportow.
 * Version: 0.5.0
 * Requires at least: 6.0
 * Requires PHP: 8.1
 * Author: MP Service Suite
 * License: GPLv2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: mp-workflow-automator
 * Domain Path: /languages
 *
 * @package MP\Automator
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'MP_AUTOMATOR_FILE', __FILE__ );
define( 'MP_AUTOMATOR_VERSION', '0.5.0' );

if ( ! defined( 'MP_CONTRACT_VERSION' ) ) {
	define( 'MP_CONTRACT_VERSION', 1 );
}

require_once __DIR__ . '/includes/Autoloader.php';

MP\Automator\Autoloader::register();

register_activation_hook( __FILE__, array( MP\Automator\Lifecycle::class, 'activate' ) );
register_deactivation_hook( __FILE__, array( MP\Automator\Lifecycle::class, 'deactivate' ) );

add_action(
	'plugins_loaded',
	static function (): void {
		MP\Automator\Plugin::instance()->boot();
	}
);
