<?php
/**
 * Panel klienta „moje zgłoszenia" (P1.5) + strona logowania passwordless.
 *
 * Jedna strona `[mp_account]`: niezalogowany widzi formularz „wyślij link
 * logowania", zalogowany widzi WŁASNE sprawy (status na żywo). Wlascicielstwo
 * przez `customers.wp_user_id` = biezacy user — klient widzi TYLKO swoje
 * (IDOR-safe: nie ma parametru case_id z URL, lista budowana z konta).
 *
 * C6a = wersja bazowa (lista spraw + status). Historia wiadomosci, wysylka,
 * edycja danych (art. 16) i wycofanie zgody dochodza w C6b.
 *
 * @package MP\Intake
 */

namespace MP\Intake\Front;

use MP\Intake\CaseRepo;
use MP\Intake\Customers;
use MP\Intake\Messages;

/**
 * Rejestracja strony panelu/logowania i jej render.
 */
final class AccountPage {

	/**
	 * Opcja z ID auto-strony panelu.
	 */
	public const PAGE_OPTION = 'mp_account_page_id';

	/**
	 * Opcja z odciskiem palca tresci auto-strony (kasacja tylko gdy nietknieta).
	 */
	public const FINGERPRINT_OPTION = 'mp_account_page_fingerprint';

	/**
	 * Znacznik shortcode w tresci auto-strony.
	 */
	private const CONTENT = '[mp_account]';

	/**
	 * Rejestruje shortcode + naglowki bezpieczenstwa panelu.
	 *
	 * @return void
	 */
	public static function register(): void {
		add_shortcode( 'mp_account', array( self::class, 'render' ) );
		add_action( 'template_redirect', array( self::class, 'maybe_headers' ) );
		// Wysylka wiadomosci wymaga zalogowania (tylko priv — klient).
		add_action( 'admin_post_mp_intake_message', array( self::class, 'handle_send_message' ) );
	}

	/**
	 * Odcisk palca oryginalnej tresci auto-strony (uninstall: kasuj tylko gdy nietknieta).
	 *
	 * @return string
	 */
	public static function original_fingerprint(): string {
		return md5( self::CONTENT );
	}

	/**
	 * URL strony panelu (fallback: strona glowna).
	 *
	 * @return string
	 */
	public static function url(): string {
		$page_id = (int) get_option( self::PAGE_OPTION, 0 );
		$link    = $page_id > 0 ? get_permalink( $page_id ) : '';

		return is_string( $link ) && '' !== $link ? $link : home_url( '/' );
	}

	/**
	 * Dokłada naglowki no-store na stronie panelu (dane spraw nie do cache).
	 *
	 * @return void
	 */
	public static function maybe_headers(): void {
		$page_id = (int) get_option( self::PAGE_OPTION, 0 );

		if ( 0 === $page_id || ! is_page( $page_id ) || headers_sent() ) {
			return;
		}

		header( 'Cache-Control: no-store, max-age=0' );
		header( 'X-Content-Type-Options: nosniff' );
		header( 'X-Frame-Options: SAMEORIGIN' );
	}

	/**
	 * Render panelu (shortcode): logowanie albo lista spraw.
	 *
	 * @return string HTML.
	 */
	public static function render(): string {
		if ( ! is_user_logged_in() ) {
			return self::render_login_form();
		}

		return self::render_panel( get_current_user_id() );
	}

	/**
	 * Formularz „wyślij link logowania" (komunikat neutralny nad formularzem).
	 *
	 * @return string HTML.
	 */
	private static function render_login_form(): string {
		$out = '<div class="mp-account mp-account--login" style="max-width:30rem;margin:0 auto">';

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- tylko wyswietlenie komunikatu PRG (bez skutkow), tresc escapowana.
		$notice = isset( $_GET['mp_notice'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['mp_notice'] ) ) : '';

		if ( '' !== $notice ) {
			$out .= '<p class="mp-account__notice" role="status">' . esc_html( $notice ) . '</p>';
		}

		$out .= '<h2>' . esc_html__( 'Panel zgłoszeń serwisowych', 'mp-service-intake' ) . '</h2>';
		$out .= '<p>' . esc_html__( 'Podaj adres e-mail użyty w zgłoszeniu — wyślemy link do zalogowania.', 'mp-service-intake' ) . '</p>';
		$out .= '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '" class="mp-account__form">';
		$out .= '<input type="hidden" name="action" value="mp_intake_login_request" />';
		$out .= wp_nonce_field( 'mp_intake_login_request', '_mp_nonce', true, false );
		$out .= '<p><label for="mp-account-email">' . esc_html__( 'Adres e-mail', 'mp-service-intake' ) . '</label><br />';
		$out .= '<input type="email" id="mp-account-email" name="email" required autocomplete="email" style="width:100%;box-sizing:border-box;padding:.5rem" /></p>';
		$out .= '<p><button type="submit" style="padding:.6rem 1.2rem;cursor:pointer">' . esc_html__( 'Wyślij link logowania', 'mp-service-intake' ) . '</button></p>';
		$out .= '</form></div>';

		return $out;
	}

	/**
	 * Panel zalogowanego: WŁASNE sprawy + status na żywo (IDOR-safe).
	 *
	 * @param int $wp_user_id ID biezacego uzytkownika.
	 * @return string HTML.
	 */
	private static function render_panel( int $wp_user_id ): string {
		$cases = self::own_cases( $wp_user_id );

		$out  = '<div class="mp-account mp-account--panel">';
		$out .= '<h2>' . esc_html__( 'Moje zgłoszenia', 'mp-service-intake' ) . '</h2>';
		$out .= '<p><a href="' . esc_url( wp_logout_url( self::url() ) ) . '">' . esc_html__( 'Wyloguj', 'mp-service-intake' ) . '</a></p>';

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- tylko wyswietlenie komunikatu PRG (bez skutkow), tresc escapowana.
		$notice = isset( $_GET['mp_notice'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['mp_notice'] ) ) : '';

		if ( '' !== $notice ) {
			$out .= '<p class="mp-account__notice" role="status">' . esc_html( $notice ) . '</p>';
		}

		if ( array() === $cases ) {
			$out .= '<p>' . esc_html__( 'Nie znaleźliśmy zgłoszeń przypisanych do tego konta.', 'mp-service-intake' ) . '</p></div>';

			return $out;
		}

		foreach ( $cases as $case ) {
			$out .= self::render_case_block( $case );
		}

		$out .= '</div>';

		return $out;
	}

	/**
	 * Blok jednej sprawy: nagłówek + historia wiadomości + formularz wysyłki.
	 *
	 * @param array<string, mixed> $row Wiersz sprawy (z for_customer).
	 * @return string HTML.
	 */
	private static function render_case_block( array $row ): string {
		$case_id = (int) ( $row['id'] ?? 0 );
		$status  = (string) ( $row['status'] ?? '' );
		$created = (string) ( $row['created_at'] ?? '' );
		$date    = '' !== $created ? get_date_from_gmt( $created, 'Y-m-d H:i' ) : '';
		$closed  = in_array( $status, CaseRepo::TERMINAL_STATUSES, true );

		$out  = '<section class="mp-account__case" style="margin:1.2rem 0;padding:1rem;border:1px solid #ddd;border-radius:6px">';
		$out .= '<h3 style="margin:.2rem 0">' . esc_html( (string) ( $row['case_number'] ?? '' ) ) . '</h3>';
		$out .= '<p style="margin:.2rem 0;color:#555">'
			. esc_html( (string) ( $row['kind'] ?? '' ) ) . ' · '
			. esc_html__( 'Status:', 'mp-service-intake' ) . ' <strong>' . esc_html( '' !== $status ? $status : '—' ) . '</strong> · '
			. esc_html( $date ) . '</p>';

		$out .= self::render_messages( $case_id );
		$out .= self::render_send_form( $case_id, $closed );

		$out .= '</section>';

		return $out;
	}

	/**
	 * Historia wiadomości sprawy (chronologicznie). Autor: Ty / Serwis / System.
	 *
	 * @param int $case_id ID sprawy (własnej — ownership sprawdzony wyżej).
	 * @return string HTML.
	 */
	private static function render_messages( int $case_id ): string {
		$messages = Messages::for_case( $case_id );

		if ( array() === $messages ) {
			return '<p class="mp-account__empty" style="color:#777">' . esc_html__( 'Brak wiadomości.', 'mp-service-intake' ) . '</p>';
		}

		$labels = array(
			'client' => __( 'Ty', 'mp-service-intake' ),
			'staff'  => __( 'Serwis', 'mp-service-intake' ),
			'system' => __( 'System', 'mp-service-intake' ),
		);

		$out = '<ul class="mp-account__messages" style="list-style:none;padding:0;margin:.5rem 0">';

		foreach ( $messages as $msg ) {
			$author = (string) ( $msg['author_type'] ?? 'system' );
			$label  = $labels[ $author ] ?? $labels['system'];
			$when   = get_date_from_gmt( (string) ( $msg['created_at'] ?? '' ), 'Y-m-d H:i' );

			$out .= '<li style="margin:.4rem 0;padding:.5rem .7rem;background:#f6f6f6;border-radius:4px">';
			$out .= '<span style="font-weight:600">' . esc_html( $label ) . '</span> ';
			$out .= '<span style="color:#888;font-size:.85em">' . esc_html( $when ) . '</span><br />';
			$out .= nl2br( esc_html( (string) ( $msg['body'] ?? '' ) ) );
			$out .= '</li>';
		}

		$out .= '</ul>';

		return $out;
	}

	/**
	 * Formularz wysyłki wiadomości do serwisu (POST; ownership sprawdzany w handlerze).
	 *
	 * Sprawa zamknięta: wysyłka DOZWOLONA (nie zmienia statusu) + nota (tabletop S5).
	 *
	 * @param int  $case_id ID sprawy.
	 * @param bool $closed  Czy sprawa terminalna (zamknięta/odrzucona).
	 * @return string HTML.
	 */
	private static function render_send_form( int $case_id, bool $closed ): string {
		$out  = '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '" class="mp-account__send">';
		$out .= '<input type="hidden" name="action" value="mp_intake_message" />';
		$out .= '<input type="hidden" name="case_id" value="' . esc_attr( (string) $case_id ) . '" />';
		$out .= wp_nonce_field( 'mp_intake_message', '_mp_nonce', true, false );

		if ( $closed ) {
			$out .= '<p style="color:#7a5;margin:.3rem 0">' . esc_html__( 'Sprawa jest zamknięta — wiadomość trafi do serwisu, ale nie zmienia statusu sprawy.', 'mp-service-intake' ) . '</p>';
		}

		$out .= '<p><label for="mp-msg-' . esc_attr( (string) $case_id ) . '">' . esc_html__( 'Napisz wiadomość do serwisu', 'mp-service-intake' ) . '</label><br />';
		$out .= '<textarea id="mp-msg-' . esc_attr( (string) $case_id ) . '" name="body" rows="3" required style="width:100%;box-sizing:border-box;padding:.5rem"></textarea></p>';
		$out .= '<p><button type="submit" style="padding:.5rem 1rem;cursor:pointer">' . esc_html__( 'Wyślij', 'mp-service-intake' ) . '</button></p>';
		$out .= '</form>';

		return $out;
	}

	/**
	 * Obsluga wysylki wiadomosci klienta (POST) — ownership + walidacja.
	 *
	 * @return void
	 */
	public static function handle_send_message(): void {
		$user_id = get_current_user_id();
		$case_id = isset( $_POST['case_id'] ) ? absint( $_POST['case_id'] ) : 0;

		if ( 0 === $user_id || 0 === $case_id
			|| ! isset( $_POST['_mp_nonce'] )
			|| ! wp_verify_nonce( sanitize_text_field( wp_unslash( (string) $_POST['_mp_nonce'] ) ), 'mp_intake_message' )
		) {
			self::redirect_notice( __( 'Sesja wygasła — spróbuj ponownie.', 'mp-service-intake' ) );
		}

		// Ownership: sprawa MUSI należeć do zalogowanego klienta (IDOR).
		if ( ! in_array( $case_id, self::own_case_ids( $user_id ), true ) ) {
			self::redirect_notice( __( 'Nie znaleziono zgłoszenia.', 'mp-service-intake' ) );
		}

		$body = isset( $_POST['body'] ) ? sanitize_textarea_field( wp_unslash( (string) $_POST['body'] ) ) : '';

		if ( '' === trim( $body ) ) {
			self::redirect_notice( __( 'Wiadomość jest pusta.', 'mp-service-intake' ) );
		}

		Messages::add( $case_id, 'client', $user_id, $body );

		self::redirect_notice( __( 'Wiadomość została wysłana do serwisu.', 'mp-service-intake' ) );
	}

	/**
	 * Redirect PRG na panel z komunikatem.
	 *
	 * @param string $notice Komunikat.
	 * @return never
	 */
	private static function redirect_notice( string $notice ): void {
		wp_safe_redirect( add_query_arg( 'mp_notice', rawurlencode( $notice ), self::url() ) );
		exit;
	}

	/**
	 * ID WŁASNYCH spraw biezacego uzytkownika (ownership do wysylki/IDOR).
	 *
	 * @param int $wp_user_id ID uzytkownika WP.
	 * @return array<int, int>
	 */
	private static function own_case_ids( int $wp_user_id ): array {
		$ids = array();

		foreach ( self::own_cases( $wp_user_id ) as $case ) {
			$ids[] = (int) ( $case['id'] ?? 0 );
		}

		return array_values( array_filter( $ids ) );
	}

	/**
	 * WŁASNE sprawy biezacego uzytkownika (przez customers.wp_user_id).
	 *
	 * @param int $wp_user_id ID uzytkownika WP.
	 * @return array<int, array<string, mixed>>
	 */
	private static function own_cases( int $wp_user_id ): array {
		$cases = array();

		foreach ( Customers::ids_by_wp_user( $wp_user_id ) as $customer_id ) {
			foreach ( CaseRepo::for_customer( $customer_id ) as $case ) {
				$cases[] = $case;
			}
		}

		return $cases;
	}

	/**
	 * Tworzy auto-strone panelu (idempotentnie) z odciskiem palca.
	 *
	 * @return void
	 */
	public static function ensure_page(): void {
		$existing = (int) get_option( self::PAGE_OPTION, 0 );

		if ( $existing > 0 && 'page' === get_post_type( $existing ) && 'trash' !== get_post_status( $existing ) ) {
			return;
		}

		$page_id = wp_insert_post(
			array(
				'post_title'   => __( 'Panel zgłoszeń', 'mp-service-intake' ),
				'post_content' => self::CONTENT,
				'post_status'  => 'publish',
				'post_type'    => 'page',
			)
		);

		if ( is_int( $page_id ) && $page_id > 0 ) {
			update_option( self::PAGE_OPTION, $page_id, false );
			update_option( self::FINGERPRINT_OPTION, self::original_fingerprint(), false );
		}
	}
}
