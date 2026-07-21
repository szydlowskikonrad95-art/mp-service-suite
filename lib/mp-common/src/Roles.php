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
	 * Tworzy brakujace role (idempotentnie — wolane przy KAZDEJ aktywacji,
	 * takze po awaryjnym zdjeciu rol; runda W: aktywacja zawsze odtwarza).
	 *
	 * @return void
	 */
	public static function ensure(): void {
		foreach ( self::ROLES as $slug => $label ) {
			if ( null === get_role( $slug ) ) {
				add_role( $slug, $label, array( 'read' => true ) );
			}
		}
	}
}
