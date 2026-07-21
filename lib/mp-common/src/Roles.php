<?php
/**
 * Wspolne role systemu MP (4 role ze specyfikacji).
 *
 * Role sa WSPOLDZIELONE przez 3 pluginy: kazdy plugin przy aktywacji
 * odtwarza je idempotentnie; zdejmuje je dopiero OSTATNI odinstalowywany
 * (patrz Uninstall).
 *
 * @package MP\Common
 */

namespace MP\Common;

/**
 * Definicja i utrzymanie 4 dedykowanych rol mp_*.
 */
final class Roles {

	/**
	 * Slug => etykieta. Pelna macierz capabilities: SECURITY.md (kontrakt D2).
	 */
	public const ROLES = array(
		'mp_system_admin' => 'Administrator systemu MP',
		'mp_coordinator'  => 'Koordynator serwisu MP',
		'mp_agent'        => 'Pracownik serwisu MP',
		'mp_client'       => 'Klient MP',
	);

	/**
	 * Capabilities personelu — te dostaje TAKZE wbudowany administrator WP
	 * (bez nich nie widzialby ekranow mp_*); mp_client swiadomie poza lista.
	 */
	public const STAFF_CAPS = array( 'mp_system_admin', 'mp_coordinator', 'mp_agent' );

	/**
	 * Tworzy brakujace role (idempotentnie — wolane przy KAZDEJ aktywacji,
	 * takze po awaryjnym zdjeciu rol; runda W: aktywacja zawsze odtwarza).
	 *
	 * Kazda rola niesie wlasna cap-marke (kod sprawdza WYLACZNIE capability,
	 * nigdy nazwe roli). To minimalny zestaw pod klocek B; pelna macierz
	 * uprawnien doprecyzuje SECURITY.md (D2) — rozszerzenie, nie przebudowa.
	 *
	 * @return void
	 */
	public static function ensure(): void {
		foreach ( self::ROLES as $slug => $label ) {
			if ( null === get_role( $slug ) ) {
				add_role( $slug, $label, array( 'read' => true ) );
			}

			$role = get_role( $slug );

			if ( null !== $role && ! $role->has_cap( $slug ) ) {
				$role->add_cap( $slug );
			}
		}

		$admin = get_role( 'administrator' );

		if ( null !== $admin ) {
			foreach ( self::STAFF_CAPS as $cap ) {
				if ( ! $admin->has_cap( $cap ) ) {
					$admin->add_cap( $cap );
				}
			}
		}
	}
}
