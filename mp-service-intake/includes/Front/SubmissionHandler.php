<?php
/**
 * Obsluga zgloszenia z frontu (POST) i potwierdzenia magic-linkiem (GET).
 *
 * POST: nonce + honeypot + pulapka czasu (<2s = bot) -> CaseRepo::create ->
 * mail z magic-linkiem -> komunikat NEUTRALNY (bez enumeracji). GET verify:
 * CaseRepo::verify -> 2. mail z SRV -> neutralna strona (no-store, no-referrer).
 *
 * @package MP\Intake
 */

namespace MP\Intake\Front;

use MP\Intake\Attachments;
use MP\Intake\CaseRepo;
use MP\Intake\Consents;
use MP\Intake\FormConfig;
use MP\Intake\RateLimit;

/**
 * Handlery admin-post frontu Intake.
 */
final class SubmissionHandler {

	/**
	 * Minimalny czas wypelnienia formularza w sekundach (ponizej = bot).
	 */
	public const MIN_FILL_SECONDS = 2;

	/**
	 * Transient z kontekstem bledow formularza (PRG — per sesja/ciasteczko).
	 */
	public const CTX_TRANSIENT = 'mp_intake_ctx_';

	/**
	 * Rejestruje handlery (zalogowani i niezalogowani goscie).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_nopriv_mp_intake_submit', array( self::class, 'handle_submit' ) );
		add_action( 'admin_post_mp_intake_submit', array( self::class, 'handle_submit' ) );
		add_action( 'admin_post_nopriv_mp_intake_verify', array( self::class, 'handle_verify' ) );
		add_action( 'admin_post_mp_intake_verify', array( self::class, 'handle_verify' ) );
		add_action( 'admin_post_nopriv_mp_intake_verify_confirm', array( self::class, 'handle_verify_confirm' ) );
		add_action( 'admin_post_mp_intake_verify_confirm', array( self::class, 'handle_verify_confirm' ) );
		add_action( 'admin_post_mp_intake_attachment', array( self::class, 'handle_attachment' ) );
	}

	/**
	 * Serwuje zalacznik przez PHP (endpoint z bramka dostepu + nonce).
	 *
	 * @return void
	 */
	public static function handle_attachment(): void {
		$id = isset( $_GET['id'] ) ? absint( $_GET['id'] ) : 0;

		check_admin_referer( 'mp_intake_attachment_' . $id );

		Attachments::serve( $id );
	}

	/**
	 * Obsluga wyslania formularza (POST).
	 *
	 * @return void
	 */
	public static function handle_submit(): void {
		if ( ! isset( $_POST['_mp_nonce'] ) || ! wp_verify_nonce( sanitize_text_field( wp_unslash( (string) $_POST['_mp_nonce'] ) ), 'mp_intake_submit' ) ) {
			self::redirect_back( array( 'notice' => __( 'Sesja formularza wygasła — spróbuj ponownie.', 'mp-service-intake' ) ) );
		}

		// Antyspam: honeypot wypelniony ALBO za szybko => cichy sukces (bot nie wie).
		$honeypot = isset( $_POST['mp_hp'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['mp_hp'] ) ) : '';
		$started  = isset( $_POST['mp_ts'] ) ? (int) $_POST['mp_ts'] : 0;

		if ( '' !== $honeypot || ( $started > 0 && ( time() - $started ) < self::MIN_FILL_SECONDS ) ) {
			self::redirect_back( array( 'notice' => self::neutral_message() ) );
		}

		$kind    = isset( $_POST['kind'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['kind'] ) ) : '';
		$email   = isset( $_POST['email'] ) ? sanitize_email( wp_unslash( (string) $_POST['email'] ) ) : '';
		$consent = isset( $_POST['mp_consent'] ) && '1' === sanitize_text_field( wp_unslash( (string) $_POST['mp_consent'] ) );
		$values  = self::collect_values( $kind );

		// Ochrona zgloszen (P1.6): rate-limit warstwowy + dedup twardy. Po honeypocie,
		// przed tworzeniem sprawy. Marker dedup dopiero po sukcesie (mark_submitted).
		$serial  = (string) ( $values['serial'] ?? '' );
		$ip      = isset( $_SERVER['REMOTE_ADDR'] ) ? sanitize_text_field( wp_unslash( (string) $_SERVER['REMOTE_ADDR'] ) ) : '';
		$blocked = RateLimit::check( $ip, $email, $serial, $kind );

		if ( null !== $blocked ) {
			$notice = RateLimit::BLOCK_DUPLICATE === $blocked
				? __( 'To zgłoszenie właśnie przyjęliśmy — sprawdź swoją skrzynkę e-mail.', 'mp-service-intake' )
				: __( 'Zbyt wiele zgłoszeń w krótkim czasie. Spróbuj ponownie za jakiś czas.', 'mp-service-intake' );
			self::redirect_back( array( 'notice' => $notice ) );
		}

		// Zgoda RODO wymagana PRZED przyjeciem zgloszenia.
		if ( ! $consent ) {
			self::redirect_back(
				array(
					'errors' => array( 'mp_consent' => 'REQUIRED' ),
					'values' => array_merge(
						$values,
						array(
							'kind'  => $kind,
							'email' => $email,
						)
					),
				)
			);
		}

		$result = CaseRepo::create(
			array(
				'kind'   => $kind,
				'email'  => $email,
				'values' => $values,
			)
		);

		if ( isset( $result['error'] ) ) {
			self::redirect_back(
				array(
					'errors' => self::flatten_errors( $result['validation'] ?? array() ),
					'values' => array_merge(
						$values,
						array(
							'kind'  => $kind,
							'email' => $email,
						)
					),
				)
			);
		}

		// Zalaczniki na sprawe niepotwierdzona (CAP pending chroni dysk; sieroty
		// sprzatane cronem sierot razem ze sprawa).
		$files = self::collect_files();

		if ( array() !== $files ) {
			Attachments::store_for_case( (int) $result['case_id'], $kind, $files );
		}

		// Zgoda RODO: pelny tekst zamrozony, spieta ze sprawa (podpiecie do klienta przy weryfikacji).
		Consents::record(
			$email,
			(int) $result['case_id'],
			Consents::KEY_PROCESSING,
			Consents::VERSION,
			Consents::processing_text()
		);

		// Dedup: dopiero teraz (udane zgloszenie) — retry po odrzuceniu nie jest duplikatem.
		RateLimit::mark_submitted( $email, $serial, $kind );

		Mailer::send_magic_link( $email, (string) $result['token'] );

		// Komunikat NEUTRALNY — zero enumeracji, SRV dopiero w mailu/panelu.
		self::redirect_back( array( 'notice' => self::neutral_message() ) );
	}

	/**
	 * Krok 1 potwierdzenia (GET): strona z przyciskiem POST „Potwierdzam".
	 *
	 * GET NIE potwierdza sprawy — skanery poczty prefetchuja linki (robia tylko
	 * GET, nie POST), wiec sam GET nie moze mutowac (FLAGA #7). Weryfikacja =
	 * POST przez handle_verify_confirm. Strona neutralna (zero danych/SRV).
	 *
	 * @return void
	 */
	public static function handle_verify(): void {
		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- GET z linka mailowego nie moze niesc nonce; renderujemy TYLKO formularz POST, nic nie mutuje.
		$token = isset( $_GET['token'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['token'] ) ) : '';

		self::render_verify_form( $token );
	}

	/**
	 * Krok 2 potwierdzenia (POST): weryfikacja ATOMOWA + 2. mail + neutralna strona.
	 *
	 * Podwojny POST bezpieczny: CaseRepo::verify jest warunkowy (rows=1 albo
	 * „juz potwierdzone" / „wygaslo") — W1.
	 *
	 * @return void
	 */
	public static function handle_verify_confirm(): void {
		if ( ! isset( $_POST['_mp_nonce'] ) || ! wp_verify_nonce( sanitize_text_field( wp_unslash( (string) $_POST['_mp_nonce'] ) ), 'mp_intake_verify_confirm' ) ) {
			self::render_landing(
				__( 'Sesja wygasła', 'mp-service-intake' ),
				__( 'Sesja potwierdzenia wygasła. Otwórz link z e-maila ponownie i kliknij „Potwierdzam".', 'mp-service-intake' ),
				403
			);
		}

		$token  = isset( $_POST['token'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['token'] ) ) : '';
		$result = CaseRepo::verify( $token );

		if ( isset( $result['case_id'] ) ) {
			$email = self::email_for_case( (int) $result['case_id'] );

			if ( '' !== $email ) {
				Mailer::send_confirmation( $email, (string) $result['case_number'] );
			}

			self::render_landing(
				__( 'Zgłoszenie potwierdzone', 'mp-service-intake' ),
				__( 'Dziękujemy. Twoje zgłoszenie zostało potwierdzone — szczegóły i numer sprawy wysłaliśmy na Twój adres e-mail.', 'mp-service-intake' )
			);
		}

		$already = empty( $result['expired'] );

		self::render_landing(
			$already ? __( 'Zgłoszenie już potwierdzone', 'mp-service-intake' ) : __( 'Link nieaktualny', 'mp-service-intake' ),
			(string) $result['error'],
			$already ? 200 : 410
		);
	}

	/**
	 * Renderuje neutralna strone z przyciskiem POST „Potwierdzam" (krok 1 GET).
	 *
	 * Naglowki jak render_landing (no-store/no-referrer/nosniff); ZERO danych
	 * sprawy i ZERO numeru SRV (wszystko idzie mailem).
	 *
	 * @param string $token Surowy token (ukryte pole formularza; kto ma URL, ma token).
	 * @return never
	 */
	private static function render_verify_form( string $token ): void {
		if ( ! headers_sent() ) {
			status_header( 200 );
			header( 'Cache-Control: no-store, max-age=0' );
			header( 'Referrer-Policy: no-referrer' );
			header( 'X-Content-Type-Options: nosniff' );
			header( 'X-Frame-Options: SAMEORIGIN' );
			header( 'Content-Type: text/html; charset=utf-8' );
		}

		$title = __( 'Potwierdź zgłoszenie', 'mp-service-intake' );

		echo '<!doctype html><html lang="pl"><head><meta charset="utf-8" />';
		echo '<meta name="viewport" content="width=device-width, initial-scale=1" />';
		echo '<meta name="robots" content="noindex, nofollow" />';
		echo '<title>' . esc_html( $title ) . '</title>';
		echo '<style>body{font-family:system-ui,sans-serif;max-width:34rem;margin:4rem auto;padding:0 1rem;line-height:1.6;color:#1a1a1a}button{font-size:1rem;padding:.7rem 1.4rem;cursor:pointer}</style>';
		echo '</head><body>';
		echo '<h1>' . esc_html( $title ) . '</h1>';
		echo '<p>' . esc_html__( 'Aby potwierdzić swoje zgłoszenie serwisowe i uruchomić obsługę, kliknij przycisk poniżej.', 'mp-service-intake' ) . '</p>';
		echo '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '">';
		echo '<input type="hidden" name="action" value="mp_intake_verify_confirm" />';
		echo '<input type="hidden" name="token" value="' . esc_attr( $token ) . '" />';
		wp_nonce_field( 'mp_intake_verify_confirm', '_mp_nonce' );
		echo '<button type="submit">' . esc_html__( 'Potwierdzam', 'mp-service-intake' ) . '</button>';
		echo '</form></body></html>';
		exit;
	}

	/**
	 * Zbiera wartosci pol wg schematu rodzaju (tylko znane pola — anty-smiec).
	 *
	 * @param string $kind Rodzaj sprawy.
	 * @return array<string, string>
	 */
	private static function collect_values( string $kind ): array {
		$values = array();

		if ( ! FormConfig::is_valid_kind( $kind ) ) {
			return $values;
		}

		foreach ( FormConfig::fields_for( $kind ) as $field ) {
			$key = $field['key'];

			if ( ! isset( $_POST[ $key ] ) ) { // phpcs:ignore WordPress.Security.NonceVerification.Missing -- nonce zweryfikowany w handle_submit przed wywolaniem.
				continue;
			}

			// phpcs:ignore WordPress.Security.NonceVerification.Missing, WordPress.Security.ValidatedSanitizedInput.InputNotSanitized -- nonce zweryfikowany w handle_submit; sanityzacja wg typu pola w nastepnej instrukcji (sanitize_textarea_field/sanitize_text_field).
			$raw = wp_unslash( (string) $_POST[ $key ] );

			$values[ $key ] = 'textarea' === $field['type']
				? sanitize_textarea_field( $raw )
				: sanitize_text_field( $raw );
		}

		return $values;
	}

	/**
	 * Zbiera przeslane pliki z pola `mp_files[]` do znormalizowanej listy.
	 *
	 * @return array<int, array<string, mixed>>
	 */
	private static function collect_files(): array {
		if ( ! isset( $_FILES['mp_files'] ) || ! is_array( $_FILES['mp_files']['name'] ?? null ) ) { // phpcs:ignore WordPress.Security.NonceVerification.Missing -- nonce zweryfikowany w handle_submit.
			return array();
		}

		// phpcs:disable WordPress.Security.ValidatedSanitizedInput.MissingUnslash, WordPress.Security.ValidatedSanitizedInput.InputNotSanitized, WordPress.Security.NonceVerification.Missing -- $_FILES: error/size to liczby, tmp_name od PHP (is_uploaded_file w Attachments), name -> sanitize_file_name w Attachments; nonce zweryfikowany wyzej.
		$names = (array) $_FILES['mp_files']['name'];
		$files = array();

		foreach ( array_keys( $names ) as $i ) {
			$error = (int) ( $_FILES['mp_files']['error'][ $i ] ?? UPLOAD_ERR_NO_FILE );

			if ( UPLOAD_ERR_NO_FILE === $error ) {
				continue;
			}

			$files[] = array(
				'name'     => (string) ( $_FILES['mp_files']['name'][ $i ] ?? '' ),
				'type'     => (string) ( $_FILES['mp_files']['type'][ $i ] ?? '' ),
				'tmp_name' => (string) ( $_FILES['mp_files']['tmp_name'][ $i ] ?? '' ),
				'error'    => $error,
				'size'     => (int) ( $_FILES['mp_files']['size'][ $i ] ?? 0 ),
			);
		}
		// phpcs:enable

		return $files;
	}

	/**
	 * Splaszcza bledy walidacji do mapy pole => kod (pierwszy kod per pole).
	 *
	 * @param array<int, array{field: string, reason_code: string}> $validation Bledy.
	 * @return array<string, string>
	 */
	private static function flatten_errors( array $validation ): array {
		$out = array();

		foreach ( $validation as $err ) {
			if ( ! isset( $out[ $err['field'] ] ) ) {
				$out[ $err['field'] ] = $err['reason_code'];
			}
		}

		return $out;
	}

	/**
	 * Neutralny komunikat po wyslaniu (bez enumeracji istnienia danych).
	 *
	 * @return string
	 */
	private static function neutral_message(): string {
		return __( 'Jeśli dane są poprawne, wysłaliśmy na podany adres e-mail link potwierdzający zgłoszenie.', 'mp-service-intake' );
	}

	/**
	 * Zapisuje kontekst i wraca na stronę formularza (PRG).
	 *
	 * @param array<string, mixed> $ctx Kontekst (errors/values/notice).
	 * @return never
	 */
	private static function redirect_back( array $ctx ): void {
		$key = self::CTX_TRANSIENT . self::client_key();
		set_transient( $key, $ctx, 5 * MINUTE_IN_SECONDS );

		$back = wp_get_referer();
		wp_safe_redirect( false !== $back ? $back : home_url( '/' ) );
		exit;
	}

	/**
	 * Odczytuje i kasuje kontekst PRG (dla renderera strony formularza).
	 *
	 * @return array<string, mixed>
	 */
	public static function pull_context(): array {
		$key = self::CTX_TRANSIENT . self::client_key();
		$ctx = get_transient( $key );

		if ( false !== $ctx ) {
			delete_transient( $key );
		}

		return is_array( $ctx ) ? $ctx : array();
	}

	/**
	 * Klucz klienta do PRG (ciasteczko sesyjne — bez PII).
	 *
	 * @return string
	 */
	private static function client_key(): string {
		$cookie = 'mp_intake_sess';

		if ( isset( $_COOKIE[ $cookie ] ) ) {
			$existing = sanitize_text_field( wp_unslash( (string) $_COOKIE[ $cookie ] ) );

			if ( 1 === preg_match( '/^[a-f0-9]{32}$/', $existing ) ) {
				return $existing;
			}
		}

		$key = md5( wp_generate_password( 32, false, false ) );
		setcookie( $cookie, $key, time() + HOUR_IN_SECONDS, '/', '', is_ssl(), true );

		return $key;
	}

	/**
	 * E-mail sprawy z zapamietanych danych kontaktowych (po weryfikacji juz klient).
	 *
	 * @param int $case_id ID sprawy.
	 * @return string
	 */
	private static function email_for_case( int $case_id ): string {
		global $wpdb;

		$table = \MP\Intake\Tables::full( \MP\Intake\Tables::CUSTOMERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne, zapytanie przygotowane.
		$email = $wpdb->get_var(
			$wpdb->prepare(
				"SELECT c.email FROM {$table} c
				INNER JOIN {$wpdb->prefix}mp_service_cases s ON s.customer_id = c.id
				WHERE s.id = %d",
				$case_id
			)
		);
		// phpcs:enable

		return is_string( $email ) ? $email : '';
	}

	/**
	 * Renderuje minimalna, neutralna strone potwierdzenia (BEZ zasobow zewn.).
	 *
	 * Naglowki: no-store (token nie w cache), Referrer-Policy: no-referrer
	 * (token nie wycieka referer-em), nosniff + SAMEORIGIN.
	 *
	 * @param string $title   Tytul.
	 * @param string $message Tresc.
	 * @param int    $status  Kod HTTP.
	 * @return never
	 */
	private static function render_landing( string $title, string $message, int $status = 200 ): void {
		if ( ! headers_sent() ) {
			status_header( $status );
			header( 'Cache-Control: no-store, max-age=0' );
			header( 'Referrer-Policy: no-referrer' );
			header( 'X-Content-Type-Options: nosniff' );
			header( 'X-Frame-Options: SAMEORIGIN' );
			header( 'Content-Type: text/html; charset=utf-8' );
		}

		echo '<!doctype html><html lang="pl"><head><meta charset="utf-8" />';
		echo '<meta name="viewport" content="width=device-width, initial-scale=1" />';
		echo '<meta name="robots" content="noindex, nofollow" />';
		echo '<title>' . esc_html( $title ) . '</title>';
		echo '<style>body{font-family:system-ui,sans-serif;max-width:38rem;margin:4rem auto;padding:0 1rem;line-height:1.6;color:#1a1a1a}h1{font-size:1.4rem}</style>';
		echo '</head><body><h1>' . esc_html( $title ) . '</h1><p>' . esc_html( $message ) . '</p></body></html>';
		exit;
	}
}
