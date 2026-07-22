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

		if ( array() === $cases ) {
			$out .= '<p>' . esc_html__( 'Nie znaleźliśmy zgłoszeń przypisanych do tego konta.', 'mp-service-intake' ) . '</p></div>';

			return $out;
		}

		$out .= '<table class="mp-account__cases" style="width:100%;border-collapse:collapse">';
		$out .= '<thead><tr>';
		$out .= '<th style="text-align:left;padding:.4rem;border-bottom:1px solid #ccc">' . esc_html__( 'Numer sprawy', 'mp-service-intake' ) . '</th>';
		$out .= '<th style="text-align:left;padding:.4rem;border-bottom:1px solid #ccc">' . esc_html__( 'Rodzaj', 'mp-service-intake' ) . '</th>';
		$out .= '<th style="text-align:left;padding:.4rem;border-bottom:1px solid #ccc">' . esc_html__( 'Status', 'mp-service-intake' ) . '</th>';
		$out .= '<th style="text-align:left;padding:.4rem;border-bottom:1px solid #ccc">' . esc_html__( 'Data zgłoszenia', 'mp-service-intake' ) . '</th>';
		$out .= '</tr></thead><tbody>';

		foreach ( $cases as $case ) {
			$status  = (string) ( $case['status'] ?? '' );
			$created = (string) ( $case['created_at'] ?? '' );
			$date    = '' !== $created ? get_date_from_gmt( $created, 'Y-m-d H:i' ) : '';

			$out .= '<tr>';
			$out .= '<td style="padding:.4rem;border-bottom:1px solid #eee">' . esc_html( (string) ( $case['case_number'] ?? '' ) ) . '</td>';
			$out .= '<td style="padding:.4rem;border-bottom:1px solid #eee">' . esc_html( (string) ( $case['kind'] ?? '' ) ) . '</td>';
			$out .= '<td style="padding:.4rem;border-bottom:1px solid #eee">' . esc_html( '' !== $status ? $status : '—' ) . '</td>';
			$out .= '<td style="padding:.4rem;border-bottom:1px solid #eee">' . esc_html( $date ) . '</td>';
			$out .= '</tr>';
		}

		$out .= '</tbody></table></div>';

		return $out;
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
