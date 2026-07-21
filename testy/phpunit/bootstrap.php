<?php
/**
 * Bootstrap testow jednostkowych (bez ladowania WordPressa).
 *
 * Testy jednostkowe pracuja na czystych klasach: autoloadery 3 pluginow
 * + zrodlo lib/mp-common (namespace MP\Common). Testy z zywym WP = golden/E2E.
 *
 * @package MP\Testy
 */

declare(strict_types=1);

$mp_repo_root = dirname( __DIR__, 2 );

require_once $mp_repo_root . '/mp-service-intake/includes/Autoloader.php';
require_once $mp_repo_root . '/mp-warranty-registry/includes/Autoloader.php';
require_once $mp_repo_root . '/mp-workflow-automator/includes/Autoloader.php';

MP\Intake\Autoloader::register();
MP\Registry\Autoloader::register();
MP\Automator\Autoloader::register();

// Minimalne stuby WP dla czystych klas, ktore tlumacza komunikaty.
// Testy jednostkowe NIE laduja WordPressa (golden/E2E maja zywy WP).
if ( ! function_exists( '__' ) ) {
	/**
	 * Stub translacji: zwraca tekst bez zmian.
	 *
	 * @param string $text   Tekst.
	 * @param string $domain Domena (ignorowana).
	 * @return string
	 */
	function __( string $text, string $domain = 'default' ): string { // phpcs:ignore
		unset( $domain );

		return $text;
	}
}

if ( ! function_exists( 'get_option' ) ) {
	/**
	 * Stub opcji: zwraca wartosc domyslna (testy jednostkowe = brak nadpisan,
	 * FormConfig::fields_for spada na defaults() z tej klasy).
	 *
	 * @param string $name    Nazwa opcji (ignorowana).
	 * @param mixed  $default Wartosc domyslna.
	 * @return mixed
	 */
	function get_option( string $name, $default = false ) { // phpcs:ignore
		unset( $name );

		return $default;
	}
}

spl_autoload_register(
	static function ( string $class_name ) use ( $mp_repo_root ): void {
		$prefix = 'MP\\Common\\';

		if ( 0 !== strpos( $class_name, $prefix ) ) {
			return;
		}

		$relative = substr( $class_name, strlen( $prefix ) );
		$path     = $mp_repo_root . '/lib/mp-common/src/' . str_replace( '\\', '/', $relative ) . '.php';

		if ( is_file( $path ) ) {
			require $path;
		}
	}
);
