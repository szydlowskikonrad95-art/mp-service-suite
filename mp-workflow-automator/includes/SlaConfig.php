<?php
/**
 * Konfiguracja SLA per status (P3.4): godziny + okno ostrzegawcze + terminalnosc,
 * oraz wyliczenie deadline z modyfikatorem priorytetu.
 *
 * Zrodla godzin:
 *  - rdzen 7: defaulty ze STATE_MACHINE (opcja `mp_automator_sla_core` nadpisuje;
 *    warstwa ii, admin-edytowalne w panelu),
 *  - statusy wlasne: `StatusDefs` (ma sla_hours + warning_hours).
 * warning_hours: gdy nie ustawione => round(sla_hours × 0.25) (ostrzegaj przy 25%
 * pozostalego okna — NIE stale 24h, bo dla 24h-statusu warning odpalalby w t=0 = spam).
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Polityka czasow SLA + deadline.
 */
final class SlaConfig {

	/**
	 * Opcja-tresc z nadpisaniami rdzenia (warstwa ii). {slug => {sla_hours, warning_hours}}.
	 */
	public const CORE_OPTION = 'mp_automator_sla_core';

	/**
	 * Wersja polityki SLA (stemplowana w wierszu; bump = „Przelicz SLA" w SLA-4).
	 */
	public const POLICY_OPTION = 'mp_automator_sla_policy_version';

	/**
	 * Domyslne godziny SLA rdzenia 7 (STATE_MACHINE §1). Terminalne (odrzucone/
	 * zamkniete) NIE maja SLA — nie ma ich tu (deadline NULL).
	 */
	// phpcs:disable WordPress.Arrays.MultipleStatementAlignment.DoubleArrowNotAligned -- klucze z diakrytykami (ą/ę) mylą sniff (bajty vs znaki).
	private const CORE_HOURS = array(
		'nowe'            => 24,
		'do uzupełnienia' => 72,
		'w analizie'      => 48,
		'zaakceptowane'   => 24,
		'w naprawie'      => 120,
	);
	// phpcs:enable WordPress.Arrays.MultipleStatementAlignment.DoubleArrowNotAligned

	/**
	 * Modyfikator deadline per priorytet (STATE_MACHINE §1). Nieznany => normal (×1).
	 *
	 * @var array<string, float>
	 */
	private const PRIORITY_MODIFIER = array(
		'high'   => 0.5,
		'normal' => 1.0,
		'low'    => 2.0,
	);

	/**
	 * Ulamek okna SLA na ostrzezenie, gdy warning_hours nie ustawione jawnie.
	 */
	private const WARNING_FRACTION = 0.25;

	/**
	 * Konfiguracja SLA dla statusu: {sla_hours, warning_hours, terminal}.
	 * sla_hours=0 lub terminal => brak pilnowania (deadline NULL).
	 *
	 * @param string $slug Status.
	 * @return array{sla_hours: int, warning_hours: int, terminal: bool}
	 */
	public static function for_status( string $slug ): array {
		// Statusy wlasne: definicja od D (StatusDefs).
		$custom = StatusDefs::all();

		if ( isset( $custom[ $slug ] ) ) {
			$def   = $custom[ $slug ];
			$hours = (int) $def['sla_hours'];

			return array(
				'sla_hours'     => $hours,
				'warning_hours' => $def['warning_hours'] > 0 ? (int) $def['warning_hours'] : self::default_warning( $hours ),
				'terminal'      => (bool) $def['terminal'],
			);
		}

		// Rdzen 7: nadpisania z opcji > defaulty; poza CORE_HOURS => terminal (brak SLA).
		$overrides = get_option( self::CORE_OPTION, array() );
		$overrides = is_array( $overrides ) ? $overrides : array();

		if ( isset( self::CORE_HOURS[ $slug ] ) || isset( $overrides[ $slug ] ) ) {
			$hours = isset( $overrides[ $slug ]['sla_hours'] )
				? max( 0, (int) $overrides[ $slug ]['sla_hours'] )
				: (int) ( self::CORE_HOURS[ $slug ] ?? 0 );

			$warn = isset( $overrides[ $slug ]['warning_hours'] )
				? max( 0, (int) $overrides[ $slug ]['warning_hours'] )
				: self::default_warning( $hours );

			return array(
				'sla_hours'     => $hours,
				'warning_hours' => $warn,
				'terminal'      => false,
			);
		}

		// Nieznany / terminalny rdzen (odrzucone/zamkniete) => brak SLA.
		return array(
			'sla_hours'     => 0,
			'warning_hours' => 0,
			'terminal'      => true,
		);
	}

	/**
	 * Wylicza deadline (UTC 'Y-m-d H:i:s') albo NULL (terminal / sla_hours=0 / brak base).
	 *
	 * @param string      $slug      Status.
	 * @param string|null $base_time Baza (status_changed_at, UTC). NULL => brak deadline.
	 * @param string      $priority  Priorytet (high/normal/low).
	 * @return string|null
	 */
	public static function deadline_for( string $slug, ?string $base_time, string $priority ): ?string {
		$cfg = self::for_status( $slug );

		if ( $cfg['terminal'] || $cfg['sla_hours'] <= 0 || null === $base_time || '' === $base_time ) {
			return null;
		}

		$modifier = self::PRIORITY_MODIFIER[ $priority ] ?? 1.0;
		$hours    = (int) round( $cfg['sla_hours'] * $modifier );
		$base_ts  = strtotime( $base_time . ' UTC' );

		if ( false === $base_ts || $hours <= 0 ) {
			return null;
		}

		return gmdate( 'Y-m-d H:i:s', $base_ts + $hours * HOUR_IN_SECONDS );
	}

	/**
	 * Domyslne okno ostrzegawcze = 25% okna SLA (min. 1h gdy sla_hours>0).
	 *
	 * @param int $sla_hours Godziny SLA.
	 * @return int
	 */
	private static function default_warning( int $sla_hours ): int {
		if ( $sla_hours <= 0 ) {
			return 0;
		}

		return max( 1, (int) round( $sla_hours * self::WARNING_FRACTION ) );
	}

	/**
	 * Biezaca wersja polityki (stemplowana w wierszu case_sla).
	 *
	 * @return int
	 */
	public static function policy_version(): int {
		return max( 1, (int) get_option( self::POLICY_OPTION, 1 ) );
	}
}
