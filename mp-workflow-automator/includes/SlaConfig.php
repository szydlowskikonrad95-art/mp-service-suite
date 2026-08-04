<?php
/**
 * Konfiguracja SLA per status (P3.4): godziny + okno ostrzegawcze + terminalnosc,
 * oraz wyliczenie deadline z modyfikatorem priorytetu.
 *
 * Zrodla godzin:
 *  - rdzen 7: defaulty ze STATE_MACHINE (opcja `mp_automator_sla_core` nadpisuje;
 *    warstwa ii — punkt rozszerzenia dla wdrozeniowca, BEZ ekranu w panelu:
 *    godziny 7 statusow rdzenia zmienia sie kodem/WP-CLI, nie z panelu.
 *    Godziny statusow WLASNYCH sa edytowalne w panelu przez `StatusDefs`),
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
	 * Akcja admin-post ekranu ustawien (= akcja nonce). Do 1.3.12 ta klasa miala
	 * wylacznie ODCZYT konfiguracji (`get_option`) i ANI JEDNEJ funkcji zapisu —
	 * godzin terminow nie dalo sie zmienic z panelu, choc dokumentacja techniczna
	 * twierdzila, ze „wszystko konfigurowalne w adminie".
	 */
	public const ACTION_CONFIG = 'mp_automator_sla_config';

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
	 * Rejestruje handler zapisu z ekranu ustawien (nopriv swiadomie — jawne 403
	 * z bramki capability zamiast cichego „0" z admin-post.php).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
		add_action( 'admin_post_nopriv_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
	}

	/**
	 * Statusy rdzenia, ktore MAJA pilnowany termin — zrodlo dla ekranu ustawien.
	 * Terminalnych (odrzucone/zamkniete) nie ma tu z zalozenia: nie maja SLA.
	 *
	 * @return array<string, int> slug => domyslne godziny.
	 */
	public static function core_defaults(): array {
		return self::CORE_HOURS;
	}

	/**
	 * Biezace (efektywne) godziny rdzenia = defaulty nadpisane opcja.
	 *
	 * @return array<string, array{sla_hours: int, warning_hours: int, nadpisane: bool}>
	 */
	public static function core_effective(): array {
		$overrides = get_option( self::CORE_OPTION, array() );
		$overrides = is_array( $overrides ) ? $overrides : array();
		$out       = array();

		foreach ( self::CORE_HOURS as $slug => $default_hours ) {
			$nadpisane = isset( $overrides[ $slug ] ) && is_array( $overrides[ $slug ] );
			$hours     = $nadpisane && isset( $overrides[ $slug ]['sla_hours'] )
				? max( 0, (int) $overrides[ $slug ]['sla_hours'] )
				: (int) $default_hours;

			$warn = $nadpisane && isset( $overrides[ $slug ]['warning_hours'] )
				? max( 0, (int) $overrides[ $slug ]['warning_hours'] )
				: self::default_warning( $hours );

			$out[ $slug ] = array(
				'sla_hours'     => $hours,
				'warning_hours' => $warn,
				'nadpisane'     => $nadpisane,
			);
		}

		return $out;
	}

	/**
	 * Odcisk biezacej konfiguracji rdzenia (blokada optymistyczna formularza).
	 *
	 * @return string
	 */
	public static function config_rev(): string {
		return md5( (string) wp_json_encode( get_option( self::CORE_OPTION, array() ) ) );
	}

	/**
	 * Zapisuje nadpisania godzin rdzenia i PODBIJA WERSJE POLITYKI.
	 *
	 * ⚠️ Podbicie wersji jest czescia zapisu, nie ozdobnikiem: wiersze SLA istniejacych
	 * spraw niosa `sla_policy_version` z chwili wyliczenia, wiec po zmianie godzin
	 * TERMINY JUZ WYLICZONE SA STARE dopoki ktos nie uruchomi „Przelicz SLA".
	 * Bez podbicia nie da sie odroznic wiersza policzonego na nowych godzinach od
	 * starego — a numer wersji byl stemplowany od poczatku i NIKT go nigdy nie zmienial
	 * (zawsze 1), wiec kolumna niosla informacje pozorna.
	 *
	 * @param array<string, array<string, mixed>> $godziny slug => {sla_hours, warning_hours}.
	 * @return int Liczba zapisanych nadpisan.
	 */
	public static function save_core( array $godziny ): int {
		$out = array();

		foreach ( $godziny as $slug => $wartosci ) {
			$slug = (string) $slug;

			// Rdzenia nie da sie rozszerzyc z ekranu — nadpisujemy WYLACZNIE statusy,
			// ktore rdzen zna. Inaczej ekran cicho tworzylby statusy-widma.
			if ( ! isset( self::CORE_HOURS[ $slug ] ) || ! is_array( $wartosci ) ) {
				continue;
			}

			$hours = max( 0, (int) ( $wartosci['sla_hours'] ?? 0 ) );
			$warn  = max( 0, (int) ( $wartosci['warning_hours'] ?? 0 ) );

			$out[ $slug ] = array(
				'sla_hours'     => $hours,
				'warning_hours' => $warn,
			);
		}

		update_option( self::CORE_OPTION, $out, false );
		update_option( self::POLICY_OPTION, self::policy_version() + 1, false );

		WorkflowEvents::log(
			WorkflowEvents::CONFIG_CHANGED,
			array(
				'object'         => 'sla_core',
				'statuses'       => array_keys( $out ),
				'policy_version' => self::policy_version(),
			),
			null,
			get_current_user_id()
		);

		return count( $out );
	}

	/**
	 * Handler ekranu ustawien: capability => nonce => blokada optymistyczna => zapis.
	 *
	 * @return void
	 */
	public static function handle_config(): void {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die(
				esc_html__( 'Brak uprawnień do konfiguracji terminów.', 'mp-workflow-automator' ),
				'',
				array( 'response' => 403 )
			);
		}

		check_admin_referer( self::ACTION_CONFIG );

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$rev = isset( $_POST['mp_config_rev'] ) ? sanitize_text_field( wp_unslash( $_POST['mp_config_rev'] ) ) : '';
		$ref = wp_get_referer();
		$cel = false !== $ref ? $ref : admin_url();

		if ( self::config_rev() !== $rev ) {
			wp_safe_redirect( add_query_arg( 'mp_settings_error', 'konflikt-terminy', $cel ) );
			exit;
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$rows = isset( $_POST['mp_sla'] ) && is_array( $_POST['mp_sla'] )
			// phpcs:ignore WordPress.Security.NonceVerification.Missing, WordPress.Security.ValidatedSanitizedInput.InputNotSanitized -- kazde pole rzutowane na int w save_core().
			? (array) wp_unslash( $_POST['mp_sla'] )
			: array();

		self::save_core( $rows );

		wp_safe_redirect( add_query_arg( 'mp_settings_ok', 'terminy', $cel ) );
		exit;
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
