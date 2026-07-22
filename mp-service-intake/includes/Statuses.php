<?php
/**
 * Rejestr statusow sprawy: rdzen 7 ze spec (NIEUSUWALNY) + statusy wlasne z
 * filtra `mp_registered_statuses` (D = zrodlo definicji, C = walidator przejsc;
 * bez D => tylko rdzen 7 — degraded). Terminalnosc wg FLAGI, nie nazwy na sztywno.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Statusy sprawy i ich terminalnosc.
 */
final class Statuses {

	/**
	 * Status startowy (po weryfikacji).
	 */
	public const NOWE = 'nowe';

	/**
	 * Jedyny cel REOPEN z terminalnych (STATE_MACHINE sekcja 2).
	 */
	public const REOPEN_TARGET = 'w analizie';

	/**
	 * Rdzen 7 ze spec: slug => terminal? (SLA-godziny konfiguruje D, nie tu).
	 *
	 * @var array<string, bool>
	 */
	private const CORE = array(
		'nowe'             => false,
		'do uzupełnienia' => false,
		'w analizie'       => false,
		'zaakceptowane'    => false,
		'w naprawie'       => false,
		'odrzucone'        => true,
		'zamknięte'       => true,
	);

	/**
	 * Pelna mapa statusow: slug => array{label:string, terminal:bool}.
	 * Rdzen 7 + wlasne z filtra; rdzenia nie da sie nadpisac ani usunac.
	 *
	 * @return array<string, array{label: string, terminal: bool}>
	 */
	public static function all(): array {
		$map = array();

		foreach ( self::CORE as $slug => $terminal ) {
			$map[ $slug ] = array(
				'label'    => $slug,
				'terminal' => $terminal,
			);
		}

		$custom = apply_filters( 'mp_registered_statuses', array() );

		if ( is_array( $custom ) ) {
			foreach ( $custom as $slug => $def ) {
				$slug = (string) $slug;

				// Rdzen 7 NIEUSUWALNY / nienadpisywalny.
				if ( '' === $slug || isset( self::CORE[ $slug ] ) || ! is_array( $def ) ) {
					continue;
				}

				$map[ $slug ] = array(
					'label'    => isset( $def['label'] ) ? (string) $def['label'] : $slug,
					'terminal' => ! empty( $def['terminal'] ),
				);
			}
		}

		return $map;
	}

	/**
	 * Czy status istnieje (rdzen lub wlasny).
	 *
	 * @param string $slug Status.
	 * @return bool
	 */
	public static function exists( string $slug ): bool {
		return isset( self::all()[ $slug ] );
	}

	/**
	 * Czy status jest terminalny (wg flagi). Nieistniejacy => false.
	 *
	 * @param string $slug Status.
	 * @return bool
	 */
	public static function is_terminal( string $slug ): bool {
		$all = self::all();

		return isset( $all[ $slug ] ) && $all[ $slug ]['terminal'];
	}
}
