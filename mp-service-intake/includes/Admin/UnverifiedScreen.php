<?php
/**
 * Admin intake: zarzadzanie zgloszeniami NIEpotwierdzonymi (personel).
 *
 * Lista spraw `pending` + akcja „popraw e-mail + wyslij ponownie" (resend).
 * Resend: KAZDY = swiezy token (stary uniewazniony), throttle 1/5min per sprawa,
 * audit-log operacji (NIE eventy — unverified nie pisze eventow).
 *
 * BEZPIECZENSTWO (security-sweep): KAZDY endpoint = capability `mp_agent`
 * W PARZE z nonce; brak uprawnien => 403 (macierz rol negatywna: subscriber/anon).
 *
 * @package MP\Intake\Admin
 */

namespace MP\Intake\Admin;

use MP\Intake\Audit;
use MP\Intake\CaseRepo;
use MP\Intake\Front\Mailer;

/**
 * Ekran admina spraw niepotwierdzonych + resend.
 */
final class UnverifiedScreen {

	/**
	 * Slug strony admina.
	 */
	public const PAGE_SLUG = 'mp-intake-unverified';

	/**
	 * Capability wymagana do ekranu i akcji (personel serwisu).
	 */
	public const CAP = 'mp_agent';

	/**
	 * Okno throttle resendu w sekundach (1/5min per sprawa).
	 */
	private const THROTTLE_SECONDS = 300;

	/**
	 * Prefiks transientu throttle resendu.
	 */
	private const THROTTLE_PREFIX = 'mp_resend_throttle_';

	/**
	 * Rejestruje menu i endpoint resendu.
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_menu', array( self::class, 'add_menu' ) );
		// Priv I nopriv -> ten sam handler: capability sprawdzana PIERWSZA, wiec
		// personel przechodzi, a subscriber/anon dostaja JAWNE 403 (nie 400 z braku handlera).
		add_action( 'admin_post_mp_intake_resend', array( self::class, 'handle_resend' ) );
		add_action( 'admin_post_nopriv_mp_intake_resend', array( self::class, 'handle_resend' ) );
	}

	/**
	 * Menu: Zgloszenia niepotwierdzone (za capability personelu).
	 *
	 * @return void
	 */
	public static function add_menu(): void {
		add_menu_page(
			__( 'Zgłoszenia niepotwierdzone', 'mp-service-intake' ),
			__( 'MP: Niepotwierdzone', 'mp-service-intake' ),
			self::CAP,
			self::PAGE_SLUG,
			array( self::class, 'render_page' ),
			'dashicons-email-alt',
			58
		);
	}

	/**
	 * Render listy spraw niepotwierdzonych + formularze resendu.
	 *
	 * @return void
	 */
	public static function render_page(): void {
		if ( ! current_user_can( self::CAP ) ) {
			wp_die( esc_html__( 'Brak uprawnień.', 'mp-service-intake' ), '', array( 'response' => 403 ) );
		}

		$cases = CaseRepo::unverified_cases();

		echo '<div class="wrap"><h1>' . esc_html__( 'Zgłoszenia niepotwierdzone', 'mp-service-intake' ) . '</h1>';

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- tylko wyswietlenie komunikatu PRG, tresc escapowana.
		$notice = isset( $_GET['mp_notice'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['mp_notice'] ) ) : '';

		if ( '' !== $notice ) {
			echo '<div class="notice notice-info is-dismissible"><p>' . esc_html( $notice ) . '</p></div>';
		}

		if ( array() === $cases ) {
			echo '<p>' . esc_html__( 'Brak zgłoszeń oczekujących na potwierdzenie.', 'mp-service-intake' ) . '</p></div>';

			return;
		}

		echo '<table class="wp-list-table widefat fixed striped"><thead><tr>';
		echo '<th>' . esc_html__( 'Numer', 'mp-service-intake' ) . '</th>';
		echo '<th>' . esc_html__( 'Rodzaj', 'mp-service-intake' ) . '</th>';
		echo '<th>' . esc_html__( 'Utworzono', 'mp-service-intake' ) . '</th>';
		echo '<th>' . esc_html__( 'Link ważny do', 'mp-service-intake' ) . '</th>';
		echo '<th>' . esc_html__( 'Popraw e-mail i wyślij ponownie', 'mp-service-intake' ) . '</th>';
		echo '</tr></thead><tbody>';

		foreach ( $cases as $row ) {
			$case_id = (int) ( $row['id'] ?? 0 );
			$email   = CaseRepo::pending_email( $case_id );
			$created = get_date_from_gmt( (string) ( $row['created_at'] ?? '' ), 'Y-m-d H:i' );
			$expires = get_date_from_gmt( (string) ( $row['verify_token_expires_at'] ?? '' ), 'Y-m-d H:i' );

			echo '<tr>';
			echo '<td>' . esc_html( (string) ( $row['case_number'] ?? '' ) ) . '</td>';
			echo '<td>' . esc_html( (string) ( $row['kind'] ?? '' ) ) . '</td>';
			echo '<td>' . esc_html( $created ) . '</td>';
			echo '<td>' . esc_html( $expires ) . '</td>';
			echo '<td><form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '" style="display:flex;gap:.4rem;align-items:center">';
			echo '<input type="hidden" name="action" value="mp_intake_resend" />';
			echo '<input type="hidden" name="case_id" value="' . esc_attr( (string) $case_id ) . '" />';
			wp_nonce_field( 'mp_intake_resend_' . $case_id );
			echo '<input type="email" name="email" value="' . esc_attr( $email ) . '" style="min-width:16rem" />';
			echo '<button type="submit" class="button">' . esc_html__( 'Wyślij ponownie', 'mp-service-intake' ) . '</button>';
			echo '</form></td>';
			echo '</tr>';
		}

		echo '</tbody></table></div>';
	}

	/**
	 * Obsluga resendu (POST): capability + nonce + throttle + swiezy token + audit.
	 *
	 * @return void
	 */
	public static function handle_resend(): void {
		if ( ! current_user_can( self::CAP ) ) {
			wp_die( esc_html__( 'Brak uprawnień do tej operacji.', 'mp-service-intake' ), '', array( 'response' => 403 ) );
		}

		$case_id = isset( $_POST['case_id'] ) ? absint( $_POST['case_id'] ) : 0;

		check_admin_referer( 'mp_intake_resend_' . $case_id );

		if ( 0 === $case_id ) {
			self::back( __( 'Brak sprawy.', 'mp-service-intake' ) );
		}

		// Throttle 1/5min per sprawa.
		$throttle_key = self::THROTTLE_PREFIX . $case_id;

		if ( false !== get_transient( $throttle_key ) ) {
			self::back( __( 'Ponowną wysyłkę można wykonać najwyżej raz na 5 minut dla danej sprawy.', 'mp-service-intake' ) );
		}

		// Popraw e-mail (opcjonalnie) PRZED wyslaniem.
		$email = isset( $_POST['email'] ) ? sanitize_email( wp_unslash( (string) $_POST['email'] ) ) : '';

		if ( '' !== $email && is_email( $email ) ) {
			CaseRepo::set_pending_email( $case_id, $email );
		}

		$token = CaseRepo::regenerate_token( $case_id );

		if ( null === $token ) {
			self::back( __( 'Tej sprawy nie można ponowić (nie jest niepotwierdzona).', 'mp-service-intake' ) );
		}

		$to = CaseRepo::pending_email( $case_id );

		if ( '' === $to || ! is_email( $to ) ) {
			self::back( __( 'Brak poprawnego adresu e-mail dla tej sprawy.', 'mp-service-intake' ) );
		}

		set_transient( $throttle_key, 1, self::THROTTLE_SECONDS );
		Mailer::send_magic_link( $to, $token );
		Audit::log( 'resend', $case_id, get_current_user_id() );

		self::back( __( 'Link weryfikacyjny wysłany ponownie (świeży token).', 'mp-service-intake' ) );
	}

	/**
	 * Powrot na ekran z komunikatem (PRG).
	 *
	 * @param string $notice Komunikat.
	 * @return never
	 */
	private static function back( string $notice ): void {
		$url = add_query_arg(
			array(
				'page'      => self::PAGE_SLUG,
				'mp_notice' => rawurlencode( $notice ),
			),
			admin_url( 'admin.php' )
		);

		wp_safe_redirect( $url );
		exit;
	}
}
