<?php
/**
 * Metryka wspolnej biblioteki mp-common.
 *
 * Zrodlo jedyne: lib/mp-common. Kopie w pluginach sa GENEROWANE przez build
 * (stempel namespace MP\{Plugin}\Common) i nie podlegaja edycji.
 *
 * @package MP\Common
 */

namespace MP\Common;

/**
 * Informacje o wersji wspolnego kodu.
 */
final class Common {

	/**
	 * Wersja zrodla mp-common (hash builda trafia do BUILD-INFO w ZIP).
	 */
	public const VERSION = '0.1.0';

	/**
	 * Zwraca wersje wspolnej biblioteki.
	 *
	 * @return string Wersja semver.
	 */
	public static function version(): string {
		return self::VERSION;
	}
}
