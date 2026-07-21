<?php
/**
 * Wspolna mechanika odinstalowania pluginu MP (warstwa i + wspolne role).
 *
 * Zasady (kontrakt + runda W):
 * - markery braci czytane BEZPOSREDNIO z bazy ($wpdb), nie przez get_option
 *   (dwa rownolegle uninstalle widza nieswiezy cache i nikt nie zdjalby rol),
 * - remap uzytkownikow PARTIAMI po 100 PRZED zdjeciem roli (przerwany proces
 *   dokancza przy ponownym uruchomieniu — uninstall jest idempotentny),
 * - WLASNY marker kasowany na SAMYM KONCU (fatal wczesniej => marker zostaje
 *   => role zostaja; kierunek bledu bezpieczny, opisany w README),
 * - warstwa (ii) — dane biznesowe — jest opcjonalna i NIE przechodzi tedy;
 *   kazdy plugin obsluguje ja we wlasnym uninstall.php (lista jawna tabel).
 *
 * @package MP\Common
 */

namespace MP\Common;

/**
 * Sprzatanie warstwy (i) oraz zdjecie wspolnych rol przez ostatni zyjacy plugin.
 */
final class Uninstall {

	/**
	 * Markery obecnosci modulow (kazdy plugin pisze WYLACZNIE swoj).
	 */
	public const MODULE_MARKERS = array(
		'mp_module_intake',
		'mp_module_registry',
		'mp_module_automator',
	);

	/**
	 * Sprzata warstwe (i) pluginu i — gdy to ostatni modul MP — wspolne role.
	 *
	 * @param string   $own_marker  Marker wolajacego pluginu (z MODULE_MARKERS).
	 * @param string[] $own_options Opcje techniczne pluginu do skasowania.
	 * @param string[] $cron_hooks  Haki cron pluginu do wyczyszczenia.
	 * @return void
	 */
	public static function run( string $own_marker, array $own_options, array $cron_hooks = array() ): void {
		foreach ( $cron_hooks as $hook ) {
			wp_clear_scheduled_hook( $hook );
		}

		foreach ( $own_options as $option ) {
			delete_option( $option );
		}

		if ( self::is_last_module( $own_marker ) ) {
			self::remove_roles();
		}

		delete_option( $own_marker );
	}

	/**
	 * Czy wolajacy plugin jest ostatnim zyjacym modulem MP.
	 *
	 * Odczyt markerow braci wprost z tabeli opcji (z pominieciem cache).
	 *
	 * @param string $own_marker Marker wolajacego pluginu.
	 * @return bool True gdy zaden inny marker nie istnieje.
	 */
	private static function is_last_module( string $own_marker ): bool {
		global $wpdb;

		$others = array_values( array_diff( self::MODULE_MARKERS, array( $own_marker ) ) );

		if ( 2 !== count( $others ) ) {
			return false;
		}

		// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- Uninstall: swiadomy odczyt z pominieciem cache opcji (runda W).
		$alive = (int) $wpdb->get_var(
			$wpdb->prepare(
				"SELECT COUNT(*) FROM {$wpdb->options} WHERE option_name IN (%s, %s)",
				$others[0],
				$others[1]
			)
		);

		return 0 === $alive;
	}

	/**
	 * Remapuje uzytkownikow rol mp_* i zdejmuje role.
	 *
	 * Kolejnosc odporna na przerwanie: najpierw remap partiami, rola znika
	 * dopiero przy pustym wyniku. Uzytkownik bez zadnej innej roli dostaje
	 * "subscriber" (konto bez roli = gorsze niz subscriber).
	 *
	 * @return void
	 */
	private static function remove_roles(): void {
		foreach ( array_keys( Roles::ROLES ) as $role_slug ) {
			do {
				$user_ids   = get_users(
					array(
						'role'   => $role_slug,
						'number' => 100,
						'fields' => 'ID',
					)
				);
				$batch_size = count( $user_ids );

				foreach ( $user_ids as $user_id ) {
					$user = new \WP_User( (int) $user_id );
					$user->remove_role( $role_slug );

					if ( empty( $user->roles ) ) {
						$user->set_role( 'subscriber' );
					}
				}
			} while ( 100 === $batch_size );

			remove_role( $role_slug );
		}

		$admin = get_role( 'administrator' );

		if ( null !== $admin ) {
			foreach ( Roles::STAFF_CAPS as $cap ) {
				if ( $admin->has_cap( $cap ) ) {
					$admin->remove_cap( $cap );
				}
			}
		}
	}
}
