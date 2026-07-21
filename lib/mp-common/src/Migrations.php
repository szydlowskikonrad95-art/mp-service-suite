<?php
/**
 * Helper migracji schematu (wspolny dla 3 pluginow).
 *
 * Wzorzec kontraktu (MIGRATION_POLICY.md): wersja schematu w opcji per plugin,
 * ponumerowane migracje uruchamiane rosnaco; kazda zapisana wersja OD RAZU po
 * udanym kroku (przerwanie w polowie -> ponowny przebieg dokancza od miejsca).
 * Zmiany nieaddytywne (poza dbDelta) wolno robic WYLACZNIE pod .maintenance
 * lub LOCK TABLES ... WRITE — to egzekwuje tresc konkretnej migracji.
 *
 * @package MP\Common
 */

namespace MP\Common;

/**
 * Uruchamianie ponumerowanych migracji schematu.
 */
final class Migrations {

	/**
	 * Wykonuje zalegle migracje (idempotentnie).
	 *
	 * @param string                      $version_option Nazwa opcji z biezaca wersja schematu.
	 * @param array<int, callable():void> $migrations  Mapa wersja => migracja (rosnaco).
	 * @return int Wersja schematu po przebiegu.
	 */
	public static function run( string $version_option, array $migrations ): int {
		$current = (int) get_option( $version_option, 0 );

		ksort( $migrations );

		foreach ( $migrations as $version => $migration ) {
			if ( $version <= $current ) {
				continue;
			}

			$migration();
			update_option( $version_option, (string) $version, false );
			$current = $version;
		}

		return $current;
	}

	/**
	 * Laduje dbDelta (wp-admin/includes/upgrade.php) i wykonuje CREATE TABLE.
	 *
	 * Rygor DATABASE.md pilnowany w TRESCI schematu (dwie spacje po PRIMARY KEY,
	 * KEY nie INDEX, bez FOREIGN KEY, LONGTEXT nie JSON).
	 *
	 * @param string $sql Pelna instrukcja CREATE TABLE.
	 * @return void
	 */
	public static function db_delta( string $sql ): void {
		require_once ABSPATH . 'wp-admin/includes/upgrade.php';
		dbDelta( $sql );
	}
}
