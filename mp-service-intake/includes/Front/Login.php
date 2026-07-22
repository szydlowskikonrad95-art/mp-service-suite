<?php
/**
 * Passwordless logowanie klienta do panelu „moje zgloszenia".
 *
 * Caly intake jest bezhasłowy (weryfikacja mailem) — logowanie tez: klient
 * podaje e-mail, dostaje jednorazowy link (TTL 20 min). Link prowadzi na
 * strone z przyciskiem — zalogowanie DOPIERO przez POST (sam GET NIE loguje;
 * skanery poczty prefetchuja linki). Wzorzec split-token: publiczny `selector`
 * (lookup) + tajny `validator` (porownanie staloczasowe). Jednorazowosc =
 * kasacja meta po sukcesie. Passwordless WYLACZNIE dla `mp_client` bez
 * uprawnien personelu/admina (personel loguje sie natywnie hasłem).
 *
 * @package MP\Intake
 */

namespace MP\Intake\Front;

/**
 * Handlery logowania passwordless (admin-post) + wystawianie tokenow.
 */
final class Login {

	/**
	 * Meta z publicznym selektorem aktywnego linku logowania.
	 */
	private const META_SELECTOR = '_mp_login_sel';

	/**
	 * Meta z hashem walidatora (nigdy surowy token w bazie).
	 */
	private const META_VALIDATOR = '_mp_login_val';

	/**
	 * Meta z czasem wygasniecia linku (UNIX ts).
	 */
	private const META_EXPIRES = '_mp_login_exp';

	/**
	 * Zywotnosc linku logowania w sekundach (link sesyjny — krotki TTL).
	 */
	private const TTL_SECONDS = 1200;

	/**
	 * Rejestruje handlery admin-post (goscie i zalogowani).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_nopriv_mp_intake_login_request', array( self::class, 'handle_request' ) );
		add_action( 'admin_post_mp_intake_login_request', array( self::class, 'handle_request' ) );
		add_action( 'admin_post_nopriv_mp_intake_login', array( self::class, 'handle_landing' ) );
		add_action( 'admin_post_mp_intake_login', array( self::class, 'handle_landing' ) );
		add_action( 'admin_post_nopriv_mp_intake_login_confirm', array( self::class, 'handle_confirm' ) );
		add_action( 'admin_post_mp_intake_login_confirm', array( self::class, 'handle_confirm' ) );
	}

	/**
	 * Czy uzytkownik moze logowac sie passwordless (klient, NIE personel/admin).
	 *
	 * @param \WP_User $user Uzytkownik.
	 * @return bool
	 */
	private static function is_client( \WP_User $user ): bool {
		return \MP\Intake\Accounts::is_client_only( $user );
	}

	/**
	 * Obsluga zadania linku logowania (POST e-mail) — komunikat NEUTRALNY.
	 *
	 * @return void
	 */
	public static function handle_request(): void {
		if ( ! isset( $_POST['_mp_nonce'] ) || ! wp_verify_nonce( sanitize_text_field( wp_unslash( (string) $_POST['_mp_nonce'] ) ), 'mp_intake_login_request' ) ) {
			self::back_with_notice( __( 'Sesja wygasła — spróbuj ponownie.', 'mp-service-intake' ) );
		}

		$email = isset( $_POST['email'] ) ? sanitize_email( wp_unslash( (string) $_POST['email'] ) ) : '';

		$issued = self::issue_for_email( $email );

		if ( null !== $issued ) {
			Mailer::send_login_link( $email, $issued['selector'], $issued['token'] );
		}

		// Zawsze ten sam komunikat — zero enumeracji kont.
		self::back_with_notice( __( 'Jeśli konto istnieje, wysłaliśmy link do logowania na podany adres e-mail.', 'mp-service-intake' ) );
	}

	/**
	 * Wystawia jednorazowy link dla e-maila (jesli to konto `mp_client`).
	 *
	 * Sam zapisuje selector + hash walidatora + TTL w meta i zwraca surowe
	 * dane do linku; wysylke maila robi wolajacy (handler / CLI E2E). Zwraca
	 * null gdy e-mail nieprawidlowy albo konto nie jest klientem (bez enumeracji).
	 *
	 * @param string $email E-mail.
	 * @return array{selector: string, token: string}|null
	 */
	public static function issue_for_email( string $email ): ?array {
		$email = sanitize_email( $email );

		if ( '' === $email || ! is_email( $email ) ) {
			return null;
		}

		$user = get_user_by( 'email', $email );

		if ( ! $user instanceof \WP_User || ! self::is_client( $user ) ) {
			return null;
		}

		$selector  = bin2hex( random_bytes( 16 ) );
		$validator = wp_generate_password( 32, false, false );

		update_user_meta( $user->ID, self::META_SELECTOR, $selector );
		update_user_meta( $user->ID, self::META_VALIDATOR, hash( 'sha256', $validator ) );
		update_user_meta( $user->ID, self::META_EXPIRES, (string) ( time() + self::TTL_SECONDS ) );

		return array(
			'selector' => $selector,
			'token'    => $validator,
		);
	}

	/**
	 * Strona lądowania linku (GET) — przycisk POST. GET NICZEGO nie loguje.
	 *
	 * @return void
	 */
	public static function handle_landing(): void {
		// phpcs:disable WordPress.Security.NonceVerification.Recommended -- GET z linka mailowego nie moze niesc nonce; nic nie mutuje, tylko render formularza POST.
		$selector = isset( $_GET['sel'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['sel'] ) ) : '';
		$token    = isset( $_GET['tok'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['tok'] ) ) : '';
		// phpcs:enable

		self::render_login_button( $selector, $token );
	}

	/**
	 * Potwierdzenie logowania (POST) — walidacja + ustawienie ciasteczka sesji.
	 *
	 * @return void
	 */
	public static function handle_confirm(): void {
		if ( ! isset( $_POST['_mp_nonce'] ) || ! wp_verify_nonce( sanitize_text_field( wp_unslash( (string) $_POST['_mp_nonce'] ) ), 'mp_intake_login_confirm' ) ) {
			self::render_landing_fail();
		}

		$selector = isset( $_POST['sel'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['sel'] ) ) : '';
		$token    = isset( $_POST['tok'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['tok'] ) ) : '';

		$user_id = self::consume( $selector, $token );

		if ( 0 === $user_id ) {
			self::render_landing_fail();
		}

		wp_set_auth_cookie( $user_id, false );

		if ( ! headers_sent() ) {
			header( 'Referrer-Policy: no-referrer' );
		}

		wp_safe_redirect( AccountPage::url() );
		exit;
	}

	/**
	 * Waliduje link i (przy sukcesie) go zuzywa. Zwraca user_id albo 0.
	 *
	 * NIE ustawia ciasteczka sesji — to robi handler POST (albo CLI E2E czyta
	 * sam wynik). Jednorazowosc: selector kasowany zawsze gdy trafil.
	 *
	 * @param string $selector Selektor z formularza.
	 * @param string $token     Surowy walidator z formularza.
	 * @return int ID uzytkownika albo 0.
	 */
	public static function consume( string $selector, string $token ): int {
		if ( 1 !== preg_match( '/^[a-f0-9]{32}$/', $selector ) || '' === $token ) {
			return 0;
		}

		$users = get_users(
			array(
				'meta_key'   => self::META_SELECTOR, // phpcs:ignore WordPress.DB.SlowDBQuery.slow_db_query_meta_key -- lookup po jednorazowym selektorze; wolumen klientow maly, brak alternatywy bez wlasnej tabeli.
				'meta_value' => $selector,           // phpcs:ignore WordPress.DB.SlowDBQuery.slow_db_query_meta_value
				'number'     => 1,
				'fields'     => array( 'ID' ),
			)
		);

		if ( array() === $users ) {
			return 0;
		}

		$user_id = (int) $users[0]->ID;
		$expires = (int) get_user_meta( $user_id, self::META_EXPIRES, true );
		$stored  = (string) get_user_meta( $user_id, self::META_VALIDATOR, true );

		$valid = time() <= $expires && '' !== $stored && hash_equals( $stored, hash( 'sha256', $token ) );

		// Jednorazowosc: kasujemy link ZAWSZE gdy selektor trafil (sukces i porazka).
		delete_user_meta( $user_id, self::META_SELECTOR );
		delete_user_meta( $user_id, self::META_VALIDATOR );
		delete_user_meta( $user_id, self::META_EXPIRES );

		if ( ! $valid ) {
			return 0;
		}

		$user = get_user_by( 'id', $user_id );

		if ( ! $user instanceof \WP_User || ! self::is_client( $user ) ) {
			return 0;
		}

		return $user_id;
	}

	/**
	 * Renderuje minimalna strone z przyciskiem logowania (POST).
	 *
	 * @param string $selector Selektor.
	 * @param string $token    Walidator.
	 * @return never
	 */
	private static function render_login_button( string $selector, string $token ): void {
		self::landing_headers( 200 );

		$action = admin_url( 'admin-post.php' );

		echo '<!doctype html><html lang="pl"><head><meta charset="utf-8" />';
		echo '<meta name="viewport" content="width=device-width, initial-scale=1" />';
		echo '<meta name="robots" content="noindex, nofollow" />';
		echo '<title>' . esc_html__( 'Logowanie do panelu', 'mp-service-intake' ) . '</title>';
		echo '<style>body{font-family:system-ui,sans-serif;max-width:30rem;margin:4rem auto;padding:0 1rem;line-height:1.6;color:#1a1a1a}button{font-size:1rem;padding:.7rem 1.4rem;cursor:pointer}</style>';
		echo '</head><body>';
		echo '<h1>' . esc_html__( 'Logowanie do panelu zgłoszeń', 'mp-service-intake' ) . '</h1>';
		echo '<p>' . esc_html__( 'Kliknij przycisk, aby zalogować się do panelu swoich zgłoszeń.', 'mp-service-intake' ) . '</p>';
		echo '<form method="post" action="' . esc_url( $action ) . '">';
		echo '<input type="hidden" name="action" value="mp_intake_login_confirm" />';
		echo '<input type="hidden" name="sel" value="' . esc_attr( $selector ) . '" />';
		echo '<input type="hidden" name="tok" value="' . esc_attr( $token ) . '" />';
		wp_nonce_field( 'mp_intake_login_confirm', '_mp_nonce' );
		echo '<button type="submit">' . esc_html__( 'Zaloguj się', 'mp-service-intake' ) . '</button>';
		echo '</form></body></html>';
		exit;
	}

	/**
	 * Neutralna strona bledu logowania (link nieaktualny/zuzyty).
	 *
	 * @return never
	 */
	private static function render_landing_fail(): void {
		self::landing_headers( 410 );

		echo '<!doctype html><html lang="pl"><head><meta charset="utf-8" />';
		echo '<meta name="viewport" content="width=device-width, initial-scale=1" />';
		echo '<meta name="robots" content="noindex, nofollow" />';
		echo '<title>' . esc_html__( 'Link nieaktualny', 'mp-service-intake' ) . '</title>';
		echo '<style>body{font-family:system-ui,sans-serif;max-width:30rem;margin:4rem auto;padding:0 1rem;line-height:1.6;color:#1a1a1a}</style>';
		echo '</head><body><h1>' . esc_html__( 'Link nieaktualny', 'mp-service-intake' ) . '</h1>';
		echo '<p>' . esc_html__( 'Link logowania wygasł lub został już użyty. Poproś o nowy link ze strony logowania.', 'mp-service-intake' ) . '</p>';
		echo '</body></html>';
		exit;
	}

	/**
	 * Naglowki bezpieczenstwa stron z tokenem (no-store, no-referrer).
	 *
	 * @param int $status Kod HTTP.
	 * @return void
	 */
	private static function landing_headers( int $status ): void {
		if ( headers_sent() ) {
			return;
		}

		status_header( $status );
		header( 'Cache-Control: no-store, max-age=0' );
		header( 'Referrer-Policy: no-referrer' );
		header( 'X-Content-Type-Options: nosniff' );
		header( 'X-Frame-Options: SAMEORIGIN' );
		header( 'Content-Type: text/html; charset=utf-8' );
	}

	/**
	 * Powrot na strone panelu z komunikatem (PRG bez PII w URL).
	 *
	 * @param string $notice Komunikat.
	 * @return never
	 */
	private static function back_with_notice( string $notice ): void {
		$url = add_query_arg( 'mp_notice', rawurlencode( $notice ), AccountPage::url() );

		wp_safe_redirect( $url );
		exit;
	}
}
