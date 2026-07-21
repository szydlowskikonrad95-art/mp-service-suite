<?php
/**
 * Smoke-testy szkieletow: autoloadery znajduja klasy, kontrakt markerow spojny.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use PHPUnit\Framework\TestCase;

/**
 * Szkielet kazdego pluginu laduje sie przez wlasny autoloader.
 */
final class SmokeTest extends TestCase {

	/**
	 * Klasy rdzenia kazdego pluginu istnieja (parsowanie + sciezki autoloadera).
	 */
	public function test_plugin_classes_exist(): void {
		$classes = array(
			MP\Intake\Plugin::class,
			MP\Intake\Lifecycle::class,
			MP\Registry\Plugin::class,
			MP\Registry\Lifecycle::class,
			MP\Automator\Plugin::class,
			MP\Automator\Lifecycle::class,
			MP\Common\Common::class,
			MP\Common\Str::class,
			MP\Common\Roles::class,
			MP\Common\Contract::class,
			MP\Common\Uninstall::class,
		);

		foreach ( $classes as $class_name ) {
			self::assertTrue( class_exists( $class_name ), "Brak klasy: {$class_name}" );
		}
	}

	/**
	 * Markery modulow: 3 rozne, zgodne z lista wspolnej mechaniki uninstall.
	 */
	public function test_module_markers_match_contract(): void {
		$markers = array(
			MP\Intake\Lifecycle::MODULE_MARKER,
			MP\Registry\Lifecycle::MODULE_MARKER,
			MP\Automator\Lifecycle::MODULE_MARKER,
		);

		self::assertCount( 3, array_unique( $markers ), 'Markery modulow musza byc unikalne.' );
		self::assertEqualsCanonicalizing( MP\Common\Uninstall::MODULE_MARKERS, $markers );
	}

	/**
	 * Kontrakt rol: dokladnie 4 role ze specyfikacji.
	 */
	public function test_roles_contract(): void {
		self::assertSame(
			array( 'mp_system_admin', 'mp_coordinator', 'mp_agent', 'mp_client' ),
			array_keys( MP\Common\Roles::ROLES )
		);
	}
}
