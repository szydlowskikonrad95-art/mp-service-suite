<?php
/**
 * Akcje personelu na karcie sprawy (kartka krok 7 — „kazda decyzja zapisuje sie
 * w historii"): zmiana statusu · odpowiedz do klienta · przydzial. Handlery
 * admin-post; KAZDY sam egzekwuje capability + nonce (metody repo NIE autoryzuja).
 *
 * Model B: zmiana statusu / odpowiedz — dowolny personel; PRZYDZIAL — tylko
 * koordynator / administrator (pracownik nie przydziela innym). Wszystkie akcje
 * ida przez metody repo/hooki => audyt w case_events + maile P3.3 (RuleEngine
 * slucha mp_case_status_changed / mp_case_message_added). PRG na karte z notka.
 *
 * @package MP\Intake\Admin
 */

namespace MP\Intake\Admin;

use MP\Intake\CaseRepo;
use MP\Intake\Messages;

/**
 * Handlery admin-post akcji karty sprawy.
 */
final class CaseActions {

	/**
	 * Rejestruje handlery (priv I nopriv => jawne 403 dla nieuprawnionych).
	 *
	 * @return void
	 */
	public static function register(): void {
		foreach ( array( 'status', 'reply', 'assign' ) as $act ) {
			$hook = 'mp_intake_case_' . $act;
			add_action( 'admin_post_' . $hook, array( self::class, 'handle_' . $act ) );
			add_action( 'admin_post_nopriv_' . $hook, array( self::class, 'handle_' . $act ) );
		}
	}

	/**
	 * Czy personel serwisu (dowolna z 3 rol; NIE hierarchiczne).
	 *
	 * @return bool
	 */
	private static function is_staff(): bool {
		return current_user_can( 'mp_agent' )
			|| current_user_can( 'mp_coordinator' )
			|| current_user_can( 'mp_system_admin' );
	}

	/**
	 * Czy moze przydzielac (koordynator / administrator systemu).
	 *
	 * @return bool
	 */
	private static function can_assign(): bool {
		return current_user_can( 'mp_coordinator' ) || current_user_can( 'mp_system_admin' );
	}

	/**
	 * Zmiana statusu: cap personelu + nonce; optimistic-lock (expected_status);
	 * powod przy „odrzucone". change_status loguje event + emituje maile P3.3.
	 *
	 * @return void
	 */
	public static function handle_status(): void {
		if ( ! self::is_staff() ) {
			self::deny();
		}

		check_admin_referer( 'mp_intake_case_status' );

		// phpcs:disable WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$case_id  = isset( $_POST['case_id'] ) ? absint( $_POST['case_id'] ) : 0;
		$new      = isset( $_POST['new_status'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['new_status'] ) ) : '';
		$expected = isset( $_POST['expected_status'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['expected_status'] ) ) : '';
		$reason   = isset( $_POST['rejection_reason_code'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['rejection_reason_code'] ) ) : '';
		// phpcs:enable

		if ( 0 === $case_id || '' === $new ) {
			self::back( $case_id, __( 'Brak danych zmiany statusu.', 'mp-service-intake' ) );
		}

		$result = CaseRepo::change_status( $case_id, $new, $expected, get_current_user_id(), '' !== $reason ? $reason : null );

		self::back( $case_id, self::status_notice( $result ) );
	}

	/**
	 * Mapuje wynik change_status na komunikat dla personelu.
	 *
	 * @param array<string, mixed> $result Wynik CaseRepo::change_status.
	 * @return string
	 */
	private static function status_notice( array $result ): string {
		if ( ! empty( $result['success'] ) ) {
			return __( 'Status zmieniony (klient i pracownik powiadomieni).', 'mp-service-intake' );
		}

		$code = isset( $result['error_code'] ) ? (string) $result['error_code'] : '';

		switch ( $code ) {
			case 'STATUS_CONFLICT':
				return __( 'Ktoś zmienił status w międzyczasie — odśwież stronę i spróbuj ponownie.', 'mp-service-intake' );
			case 'REJECTION_REASON_REQUIRED':
				return __( 'Odrzucenie wymaga podania powodu.', 'mp-service-intake' );
			case 'INVALID_TRANSITION':
				return __( 'Niedozwolone przejście statusu (sprawę zamkniętą można tylko wznowić do „w analizie").', 'mp-service-intake' );
			case 'CASE_NOT_FOUND':
				return __( 'Sprawa nie istnieje lub niepotwierdzona.', 'mp-service-intake' );
			default:
				return __( 'Nie udało się zmienić statusu.', 'mp-service-intake' );
		}
	}

	/**
	 * Odpowiedz do klienta: cap personelu + nonce; Messages::add('staff') emituje
	 * mp_case_message_added => regula powiadamia klienta (P3.3). Sprawa musi istniec.
	 *
	 * @return void
	 */
	public static function handle_reply(): void {
		if ( ! self::is_staff() ) {
			self::deny();
		}

		check_admin_referer( 'mp_intake_case_reply' );

		// phpcs:disable WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$case_id = isset( $_POST['case_id'] ) ? absint( $_POST['case_id'] ) : 0;
		$body    = isset( $_POST['body'] ) ? sanitize_textarea_field( wp_unslash( (string) $_POST['body'] ) ) : '';
		// phpcs:enable

		if ( 0 === $case_id ) {
			self::back( $case_id, __( 'Brak sprawy.', 'mp-service-intake' ) );
		}

		$ctx = apply_filters( 'mp_case_get_context', null, $case_id );

		if ( ! is_array( $ctx ) ) {
			self::back( $case_id, __( 'Sprawa nie istnieje lub niepotwierdzona.', 'mp-service-intake' ) );
		}

		if ( '' === trim( $body ) ) {
			self::back( $case_id, __( 'Wiadomość jest pusta.', 'mp-service-intake' ) );
		}

		Messages::add( $case_id, 'staff', get_current_user_id(), $body );

		self::back( $case_id, __( 'Odpowiedź wysłana do klienta.', 'mp-service-intake' ) );
	}

	/**
	 * Przydzial sprawy: cap koordynator/admin + nonce; CaseRepo::assign loguje
	 * event + emituje mp_case_assigned (mail agenta).
	 *
	 * @return void
	 */
	public static function handle_assign(): void {
		if ( ! self::can_assign() ) {
			self::deny();
		}

		check_admin_referer( 'mp_intake_case_assign' );

		// phpcs:disable WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$case_id  = isset( $_POST['case_id'] ) ? absint( $_POST['case_id'] ) : 0;
		$assignee = isset( $_POST['assignee'] ) ? absint( $_POST['assignee'] ) : 0;
		// phpcs:enable

		if ( 0 === $case_id || 0 === $assignee ) {
			self::back( $case_id, __( 'Wybierz pracownika do przydziału.', 'mp-service-intake' ) );
		}

		$result = CaseRepo::assign( $case_id, $assignee, get_current_user_id() );

		$notice = ! empty( $result['success'] )
			? __( 'Sprawa przydzielona (pracownik powiadomiony).', 'mp-service-intake' )
			: __( 'Nie udało się przydzielić sprawy.', 'mp-service-intake' );

		self::back( $case_id, $notice );
	}

	/**
	 * Odmowa dostepu (403) — jawne dla nieuprawnionych.
	 *
	 * @return never
	 */
	private static function deny(): void {
		wp_die(
			esc_html__( 'Brak uprawnień do tej operacji.', 'mp-service-intake' ),
			'',
			array( 'response' => 403 )
		);
	}

	/**
	 * PRG na karte sprawy z komunikatem.
	 *
	 * @param int    $case_id ID sprawy.
	 * @param string $notice  Komunikat.
	 * @return never
	 */
	private static function back( int $case_id, string $notice ): void {
		$url = add_query_arg(
			array(
				'page'      => CasesScreen::PAGE_SLUG,
				'case_id'   => $case_id,
				'mp_notice' => rawurlencode( $notice ),
			),
			admin_url( 'admin.php' )
		);

		wp_safe_redirect( $url );
		exit;
	}
}
