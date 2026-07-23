<?php
/**
 * Stan checklist per sprawa (P3.5) — toggle pozycji + odczyt. Tabela wlasna D
 * `case_checklists`. KOLEJNOSC KONTRAKTU: najpierw hook `mp_case_checklist_authorize`
 * (C waliduje wlasnosc/role + emituje CHECKLIST_ITEM_TOGGLED), PO OK D zapisuje stan.
 *
 * Handler backend-only (admin_post, capability personelu + nonce, BEZ menu —
 * przycisk podepnie panel admina D). `template_id` = rodzaj sprawy (checklista
 * dobierana do rodzaju z ChecklistTemplates); `step_label` ZAMROZONY przy zapisie.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Toggle i odczyt stanu checklisty sprawy.
 */
final class Checklists {

	/**
	 * Akcja admin-post toggle pozycji checklisty (personel).
	 */
	public const ACTION_TOGGLE = 'mp_automator_checklist_toggle';

	/**
	 * Rejestruje handler toggle (priv I nopriv => jawne 403 dla nieuprawnionych).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_' . self::ACTION_TOGGLE, array( self::class, 'handle_toggle' ) );
		add_action( 'admin_post_nopriv_' . self::ACTION_TOGGLE, array( self::class, 'handle_toggle' ) );
	}

	/**
	 * Czy biezacy uzytkownik to personel serwisu (wstepna bramka D; WLASCIWA
	 * autoryzacja wlasnosci/roli robi C w mp_case_checklist_authorize).
	 *
	 * @return bool
	 */
	private static function is_staff(): bool {
		return current_user_can( 'mp_agent' )
			|| current_user_can( 'mp_coordinator' )
			|| current_user_can( 'mp_system_admin' );
	}

	/**
	 * Toggle pozycji: capability personelu PIERWSZA => 403; nonce; kontekst sprawy
	 * (rodzaj => szablon); walidacja kroku; AUTORYZACJA przez hook C; PO OK upsert.
	 *
	 * @return void
	 */
	public static function handle_toggle(): void {
		if ( ! self::is_staff() ) {
			wp_die(
				esc_html__( 'Brak uprawnień do checklisty.', 'mp-workflow-automator' ),
				'',
				array( 'response' => 403 )
			);
		}

		check_admin_referer( self::ACTION_TOGGLE );

		// phpcs:disable WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$case_id   = isset( $_POST['case_id'] ) ? absint( $_POST['case_id'] ) : 0;
		$step_key  = isset( $_POST['step_key'] ) ? sanitize_key( wp_unslash( $_POST['step_key'] ) ) : '';
		$completed = isset( $_POST['completed'] ) && '1' === sanitize_text_field( wp_unslash( $_POST['completed'] ) );
		// phpcs:enable

		if ( 0 === $case_id || '' === $step_key ) {
			self::fail( __( 'Brak sprawy lub kroku.', 'mp-workflow-automator' ) );
		}

		// Kontekst sprawy przez kontrakt C (D nie czyta tabel C literalem).
		$ctx = apply_filters( 'mp_case_get_context', null, $case_id );

		if ( ! is_array( $ctx ) ) {
			self::fail( __( 'Sprawa nie istnieje.', 'mp-workflow-automator' ) );
		}

		$kind  = (string) ( $ctx['rodzaj'] ?? '' );
		$label = ChecklistTemplates::step_label( $kind, $step_key );

		if ( '' === $label ) {
			self::fail( __( 'Krok spoza szablonu checklisty tego rodzaju sprawy.', 'mp-workflow-automator' ) );
		}

		// KONTRAKT: najpierw autoryzacja C (wlasnosc/rola + event), potem zapis D.
		$auth = apply_filters( 'mp_case_checklist_authorize', null, $case_id, $step_key, $completed, get_current_user_id() );

		if ( ! is_array( $auth ) || empty( $auth['success'] ) ) {
			$code = is_array( $auth ) && isset( $auth['error_code'] ) ? (string) $auth['error_code'] : 'FORBIDDEN';
			self::fail( sprintf( /* translators: %s: kod bledu autoryzacji. */ __( 'Brak autoryzacji (%s).', 'mp-workflow-automator' ), $code ) );
		}

		self::upsert_state( $case_id, $kind, $step_key, $label, $completed );

		self::ok( __( 'Zapisano stan checklisty.', 'mp-workflow-automator' ) );
	}

	/**
	 * Zapis stanu kroku (INSERT ... ON DUPLICATE KEY — atomowy toggle per krok).
	 * completed=true => completed_by/at ustawione; false => wyzerowane.
	 *
	 * @param int    $case_id  ID sprawy.
	 * @param string $kind     Rodzaj (= template_id).
	 * @param string $step_key Klucz kroku.
	 * @param string $label    Etykieta ZAMROZONA.
	 * @param bool   $done     Stan odhaczenia.
	 * @return void
	 */
	private static function upsert_state( int $case_id, string $kind, string $step_key, string $label, bool $done ): void {
		global $wpdb;

		$table = Tables::full( Tables::CASE_CHECKLISTS );
		$now   = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared, WordPress.DB.PreparedSQLPlaceholders.ReplacementsWrongNumber -- tabela wlasna D; upsert przygotowany, NULL literalny dla odznaczonych.
		// completed_by/completed_at: konkretne wartosci gdy odhaczone, inaczej NULL
		// (prepare z %s dalby '0000-00-00' zamiast NULL — stad literalny NULL).
		$meta_sql = $done
			? $wpdb->prepare( '%d, %s', get_current_user_id(), $now )
			: 'NULL, NULL';

		$wpdb->query(
			$wpdb->prepare(
				"INSERT INTO {$table}
					(case_id, template_id, step_key, step_label, completed, completed_by, completed_at, created_at, updated_at)
				VALUES (%d, %s, %s, %s, %d, {$meta_sql}, %s, %s)
				ON DUPLICATE KEY UPDATE
					step_label = VALUES(step_label),
					completed = VALUES(completed),
					completed_by = VALUES(completed_by),
					completed_at = VALUES(completed_at),
					updated_at = VALUES(updated_at)",
				$case_id,
				$kind,
				$step_key,
				$label,
				$done ? 1 : 0,
				$now,
				$now
			)
		);
		// phpcs:enable
	}

	/**
	 * Stan checklisty sprawy: krok => {label, completed, completed_by, completed_at}.
	 * Tabela wlasna D — SELECT dozwolony. Uzywane przez panel/testy.
	 *
	 * @param int $case_id ID sprawy.
	 * @return array<string, array{label: string, completed: bool, completed_by: int|null, completed_at: string|null}>
	 */
	public static function get_state( int $case_id ): array {
		global $wpdb;

		$table = Tables::full( Tables::CASE_CHECKLISTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna D, zapytanie przygotowane.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT step_key, step_label, completed, completed_by, completed_at
				FROM {$table} WHERE case_id = %d ORDER BY id ASC",
				$case_id
			),
			ARRAY_A
		);
		// phpcs:enable

		$out = array();

		foreach ( (array) $rows as $row ) {
			$out[ (string) $row['step_key'] ] = array(
				'label'        => (string) $row['step_label'],
				'completed'    => (bool) (int) $row['completed'],
				'completed_by' => null !== $row['completed_by'] ? (int) $row['completed_by'] : null,
				'completed_at' => null !== $row['completed_at'] ? (string) $row['completed_at'] : null,
			);
		}

		return $out;
	}

	/**
	 * Powrot z komunikatem sukcesu (PRG).
	 *
	 * @param string $msg Komunikat.
	 * @return never
	 */
	private static function ok( string $msg ): void {
		self::redirect( 'ok', $msg );
	}

	/**
	 * Powrot z komunikatem bledu (PRG).
	 *
	 * @param string $msg Komunikat.
	 * @return never
	 */
	private static function fail( string $msg ): void {
		self::redirect( 'err', $msg );
	}

	/**
	 * PRG na referer z komunikatem.
	 *
	 * @param string $type Typ (ok|err).
	 * @param string $msg  Komunikat.
	 * @return never
	 */
	private static function redirect( string $type, string $msg ): void {
		$back = wp_get_referer();
		$url  = add_query_arg(
			array(
				'mp_chk'    => $type,
				'mp_notice' => rawurlencode( $msg ),
			),
			false !== $back ? $back : admin_url()
		);

		wp_safe_redirect( $url );
		exit;
	}
}
