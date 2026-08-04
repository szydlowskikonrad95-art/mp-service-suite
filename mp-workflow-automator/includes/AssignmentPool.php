<?php
/**
 * Pula pracownikow reguly przydzialu — edycja z panelu.
 *
 * DLACZEGO TO ISTNIEJE (audyt 29.07): silnik przydzialu dzialal od poczatku, ale
 * pula jechala z aktywacji PUSTA (`Rules::seed_if_absent` -> `{"pool":[]}`), a nie
 * bylo ZADNEGO sposobu, zeby ja wypelnic — ani ekranu, ani komendy WP-CLI. Panel
 * i Stan witryny uczciwie krzyczaly „lista pracownikow jest pusta", tylko czlowiek
 * nie mial czym tego naprawic poza recznym SQL-em. Instrukcja klienta kazala przy tym
 * „wskazac pracownikow w regule" jako PIERWSZY krok wdrozenia. Efekt u klienta: zadne
 * zgloszenie nie trafia do nikogo, a droga naprawy opisana w instrukcji nie istnieje.
 *
 * Zapis idzie do `action_config_json` reguly (klucz `pool`) — NIE do osobnej opcji,
 * bo silnik czyta wlasnie stamtad (`RuleEngine::run_assignment`). Pozostale klucze
 * konfiguracji sa zachowywane: nadpisujemy wylacznie `pool`.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

defined( 'ABSPATH' ) || exit;

/**
 * Konfiguracja puli pracownikow dla regul typu `assign`.
 */
final class AssignmentPool {

	/**
	 * Akcja admin-post konfiguracji (capability system-admin).
	 */
	public const ACTION_CONFIG = 'mp_automator_pool_config';

	/**
	 * Rejestruje handler konfiguracji (priv I nopriv => jawne 403 zamiast 400).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
		add_action( 'admin_post_nopriv_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
	}

	/**
	 * Pracownicy serwisu, ktorych mozna wskazac do puli.
	 *
	 * Kryterium to CAPABILITY, nie nazwa roli — administrator systemu tez ma
	 * `mp_agent`, a klient nie ma. Ten sam warunek stosuje silnik w runtime
	 * (`RuleEngine::run_assignment`), wiec lista w panelu nie klamie: kazdy
	 * pokazany user realnie moze dostac sprawe.
	 *
	 * @return array<int, \WP_User>
	 */
	public static function agents(): array {
		/*
		 * ODSIEW WCHODZI DO ZAPYTANIA, nie do PHP po fakcie (2.51). Dotad bylo:
		 * pobierz DWIESCIE PIERWSZYCH kont CALEJ witryny wg nazwy, potem odsiej
		 * po uprawnieniu — a `number` WordPress zamienia na LIMIT, wiec obciecie
		 * szlo PRZED odsianiem. Konta klientow przybywaja SAME (modul zgloszen
		 * zaklada je przy potwierdzeniu zgloszenia), wiec przy dwustu klientach
		 * o nazwach wczesniejszych alfabetycznie ekran wyboru puli przestawal
		 * pokazywac pracownikow — bez jednego komunikatu, po prostu pusta lista.
		 *
		 * `capability` (WordPress 5.9+) obejmuje jedno i drugie zrodlo uprawnienia:
		 * role, ktore je maja, ORAZ uprawnienie nadane pojedynczemu kontu — wiec
		 * kryterium zostaje takie samo jak dotad (CAPABILITY, nie nazwa roli)
		 * i takie samo, jakiego uzywa silnik w runtime.
		 */
		$users = get_users(
			array(
				'capability' => 'mp_agent',
				'orderby'    => 'display_name',
				'order'      => 'ASC',
				'number'     => 200,
			)
		);

		return array_values(
			array_filter(
				$users,
				static function ( $user ): bool {
					return $user instanceof \WP_User && user_can( $user->ID, 'mp_agent' );
				}
			)
		);
	}

	/**
	 * Reguly przydzialu (typ `assign`) — tylko te maja pule.
	 *
	 * @return array<int, array<string, mixed>>
	 */
	public static function assign_rules(): array {
		global $wpdb;

		$table = Tables::full( Tables::WORKFLOW_RULES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna D, zapytanie przygotowane.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT id, action_config_json FROM {$table} WHERE action_type = %s ORDER BY priority ASC, id ASC",
				Rules::ACTION_ASSIGN
			),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * Pula zapisana w regule (surowa, bez filtrowania po uprawnieniach).
	 *
	 * @param string $config_json JSON konfiguracji akcji.
	 * @return array<int, int>
	 */
	public static function pool_from_config( string $config_json ): array {
		$dane = json_decode( $config_json, true );

		if ( ! is_array( $dane ) || ! isset( $dane['pool'] ) || ! is_array( $dane['pool'] ) ) {
			return array();
		}

		return array_values( array_unique( array_map( 'intval', $dane['pool'] ) ) );
	}

	/**
	 * Odcisk biezacej konfiguracji puli (blokada optymistyczna formularza).
	 *
	 * Ten sam wzorzec, co przy szablonach i checklistach: formularz niesie odcisk
	 * z chwili otwarcia, wiec drugi admin nie nadpisze cudzej zmiany po cichu.
	 *
	 * @return string
	 */
	public static function config_rev(): string {
		$stan = array();

		foreach ( self::assign_rules() as $rule ) {
			$stan[ (int) $rule['id'] ] = self::pool_from_config( (string) $rule['action_config_json'] );
		}

		return md5( (string) wp_json_encode( $stan ) );
	}

	/**
	 * Zapisuje pule do reguly, zachowujac pozostale klucze konfiguracji.
	 *
	 * @param int             $rule_id ID reguly.
	 * @param array<int, int> $pool    Identyfikatory pracownikow (juz zwalidowane).
	 * @return bool Czy zapis sie powiodl.
	 */
	public static function save_pool( int $rule_id, array $pool ): bool {
		global $wpdb;

		$table = Tables::full( Tables::WORKFLOW_RULES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna D, zapytanie przygotowane.
		$current = $wpdb->get_var(
			$wpdb->prepare(
				"SELECT action_config_json FROM {$table} WHERE id = %d AND action_type = %s",
				$rule_id,
				Rules::ACTION_ASSIGN
			)
		);
		// phpcs:enable

		if ( null === $current ) {
			return false;
		}

		$dane = json_decode( (string) $current, true );
		$dane = is_array( $dane ) ? $dane : array();

		// NADPISUJEMY WYLACZNIE `pool` — reszta konfiguracji akcji zostaje nietknieta.
		$dane['pool'] = array_values( $pool );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna D.
		$ok = $wpdb->update(
			$table,
			array( 'action_config_json' => (string) wp_json_encode( $dane ) ),
			array( 'id' => $rule_id ),
			array( '%s' ),
			array( '%d' )
		);
		// phpcs:enable

		return false !== $ok;
	}

	/**
	 * Obsluga zapisu z panelu.
	 *
	 * Bramki w kolejnosci: uprawnienie -> nonce -> blokada optymistyczna ->
	 * walidacja wartosci -> zapis -> wpis w rejestrze zdarzen.
	 *
	 * @return void
	 */
	public static function handle_config(): void {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die(
				esc_html__( 'Brak uprawnień do konfiguracji puli pracowników.', 'mp-workflow-automator' ),
				'',
				array( 'response' => 403 )
			);
		}

		check_admin_referer( self::ACTION_CONFIG );

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$rev = isset( $_POST['mp_config_rev'] ) ? sanitize_text_field( wp_unslash( $_POST['mp_config_rev'] ) ) : '';

		if ( self::config_rev() !== $rev ) {
			$ref = wp_get_referer();
			wp_safe_redirect( add_query_arg( 'mp_config_error', 'konflikt-pula', false !== $ref ? $ref : admin_url() ) );
			exit;
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$rule_id = isset( $_POST['mp_rule_id'] ) ? absint( wp_unslash( $_POST['mp_rule_id'] ) ) : 0;

		if ( 0 === $rule_id ) {
			$ref = wp_get_referer();
			wp_safe_redirect( add_query_arg( 'mp_config_error', 'pula', false !== $ref ? $ref : admin_url() ) );
			exit;
		}

		// Sanityzacja W MIEJSCU ODCZYTU (absint na kazdym elemencie), nie dopiero w petli
		// nizej — inaczej surowa tablica z $_POST krazy po funkcji i pierwsza pomylka
		// przy refaktorze wpuszcza ja dalej.
		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$raw = isset( $_POST['mp_pool'] ) ? array_map( 'absint', (array) wp_unslash( $_POST['mp_pool'] ) ) : array();

		// WALIDACJA: tylko istniejacy user Z UPRAWNIENIEM agenta. Podstawienie cudzego
		// ID w POST (np. klienta albo nieistniejacego) jest odrzucane tutaj, a nie dopiero
		// w runtime — inaczej pula wygladalaby na niepusta, a przydzial i tak by nie dzialal.
		$pool = array();

		foreach ( $raw as $uid ) {
			if ( $uid > 0 && user_can( $uid, 'mp_agent' ) && ! in_array( $uid, $pool, true ) ) {
				$pool[] = $uid;
			}
		}

		if ( ! self::save_pool( $rule_id, $pool ) ) {
			$ref = wp_get_referer();
			wp_safe_redirect( add_query_arg( 'mp_config_error', 'pula', false !== $ref ? $ref : admin_url() ) );
			exit;
		}

		WorkflowEvents::log(
			WorkflowEvents::CONFIG_CHANGED,
			array(
				'object'  => 'assignment_pool',
				'rule_id' => $rule_id,
				'count'   => count( $pool ),
			),
			null,
			get_current_user_id()
		);

		$back = wp_get_referer();
		wp_safe_redirect( add_query_arg( 'mp_config_saved', 'pula', false !== $back ? $back : admin_url() ) );
		exit;
	}
}
