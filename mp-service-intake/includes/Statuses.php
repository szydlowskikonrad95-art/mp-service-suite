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
	// phpcs:disable WordPress.Arrays.MultipleStatementAlignment.DoubleArrowNotAligned -- klucze z diakrytykami (ą/ę) mylą liczenie kolumn sniffa (bajty vs znaki); wyrownanie i tak nieosiagalne mb-poprawnie.
	private const CORE = array(
		'nowe'            => false,
		'do uzupełnienia' => false,
		'w analizie'      => false,
		'zaakceptowane'   => false,
		'w naprawie'      => false,
		'odrzucone'       => true,
		'zamknięte'       => true,
	);
	// phpcs:enable WordPress.Arrays.MultipleStatementAlignment.DoubleArrowNotAligned

	/**
	 * Kolor tla plakietki statusu na liscie spraw (tekst zawsze bialy).
	 *
	 * DOBOR NIE JEST DOWOLNY: klient koncowy to instytucja publiczna, wiec
	 * plakietka musi spelniac WCAG 2.1 AA dla MALEGO tekstu (kontrast >= 4.5:1
	 * bialego na tym tle) — plakietka ma `font-size:.82em`, wiec nie lapie sie
	 * na luzniejszy prog tekstu duzego. Pilnuje tego test jednostkowy
	 * `StatusBadgeContrastTest`, zeby „ladniejszy" odcien nie wszedl przypadkiem.
	 *
	 * Kolor jest DODATKIEM do etykiety, nigdy jedynym nosnikiem znaczenia
	 * (WCAG 1.4.1) — w plakietce zawsze stoi nazwa statusu.
	 *
	 * @var array<string, string>
	 */
	// phpcs:disable WordPress.Arrays.MultipleStatementAlignment.DoubleArrowNotAligned -- jak wyzej: diakrytyki mylą liczenie kolumn sniffa.
	public const BADGE_COLORS = array(
		'nowe'            => '#2563eb',
		'do uzupełnienia' => '#a16207',
		'w analizie'      => '#7c3aed',
		'zaakceptowane'   => '#0e7490',
		'w naprawie'      => '#c2410c',
		'odrzucone'       => '#dc2626',
		'zamknięte'       => '#4b5563',
	);
	// phpcs:enable WordPress.Arrays.MultipleStatementAlignment.DoubleArrowNotAligned

	/**
	 * Neutralne tlo dla statusu spoza rdzenia (wlasny status z filtra D).
	 */
	public const BADGE_COLOR_FALLBACK = '#4b5563';

	/**
	 * Kolor plakietki dla statusu; status wlasny => neutralny szary.
	 *
	 * @param string $slug Slug statusu.
	 * @return string Kolor HEX.
	 */
	public static function badge_color( string $slug ): string {
		return self::BADGE_COLORS[ $slug ] ?? self::BADGE_COLOR_FALLBACK;
	}

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
	 * Etykieta statusu (rdzen: label = slug; wlasny: z filtra). Slug gdy nieznany.
	 *
	 * @param string $slug Status.
	 * @return string
	 */
	public static function label( string $slug ): string {
		$all = self::all();

		return isset( $all[ $slug ]['label'] ) ? (string) $all[ $slug ]['label'] : $slug;
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
