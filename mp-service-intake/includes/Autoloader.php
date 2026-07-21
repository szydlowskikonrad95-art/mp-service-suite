<?php
/**
 * Natywny autoloader pluginu (PSR-4-style, bez Composera w runtime).
 *
 * MP\Intake\Plugin        => includes/Plugin.php
 * MP\Intake\Common\Str    => includes/Common/Str.php (kopia generowana przez build)
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Rejestracja autoloadera przestrzeni MP\Intake.
 */
final class Autoloader {

	/**
	 * Prefiks przestrzeni nazw pluginu.
	 */
	private const PREFIX = 'MP\\Intake\\';

	/**
	 * Rejestruje autoloader w SPL (idempotentnie).
	 *
	 * @return void
	 */
	public static function register(): void {
		spl_autoload_register( array( self::class, 'load' ) );
	}

	/**
	 * Laduje plik klasy z katalogu includes/.
	 *
	 * @param string $class_name W pelni kwalifikowana nazwa klasy.
	 * @return void
	 */
	public static function load( string $class_name ): void {
		if ( 0 !== strpos( $class_name, self::PREFIX ) ) {
			return;
		}

		$relative = substr( $class_name, strlen( self::PREFIX ) );
		$path     = __DIR__ . '/' . str_replace( '\\', '/', $relative ) . '.php';

		if ( is_file( $path ) ) {
			require $path;
		}
	}
}
