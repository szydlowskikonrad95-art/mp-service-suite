<?php
/**
 * Definicje stalych MP_* dla analizy statycznej (PHPStan nie laduje plikow glownych pluginow).
 *
 * @package MP
 */

define( 'MP_CONTRACT_VERSION', 1 );

define( 'MP_INTAKE_FILE', __DIR__ . '/mp-service-intake/mp-service-intake.php' );
define( 'MP_INTAKE_VERSION', '0.1.0' );

define( 'MP_REGISTRY_FILE', __DIR__ . '/mp-warranty-registry/mp-warranty-registry.php' );
define( 'MP_REGISTRY_VERSION', '0.1.0' );

define( 'MP_AUTOMATOR_FILE', __DIR__ . '/mp-workflow-automator/mp-workflow-automator.php' );
define( 'MP_AUTOMATOR_VERSION', '0.1.0' );
