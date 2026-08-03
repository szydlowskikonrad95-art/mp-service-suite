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

use MP\Intake\Statuses;

use MP\Intake\FormConfig;

use MP\Intake\CaseEvents;
use MP\Intake\CaseRepo;
use MP\Intake\Consents;
use MP\Intake\Customers;
use MP\Intake\Messages;
use MP\Intake\Privacy;

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
		// Wysylka wiadomosci + edycja danych wymagaja zalogowania (tylko priv — klient).
		add_action( 'admin_post_mp_intake_message', array( self::class, 'handle_send_message' ) );
		add_action( 'admin_post_mp_intake_update_contact', array( self::class, 'handle_update_contact' ) );
		add_action( 'admin_post_mp_intake_withdraw', array( self::class, 'handle_withdraw' ) );
		add_action( 'admin_post_mp_intake_withdraw_confirm', array( self::class, 'handle_withdraw_confirm' ) );
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

		if ( ! PageDetect::is_plugin_page( $page_id, 'mp_account' ) ) {
			return;
		}

		PageDetect::send(
			array(
				// Panel pokazuje DANE OSOBOWE: nic nie ma prawa zostac w cache
				// (takze przy „wstecz") ani trafic do wyszukiwarki.
				'Cache-Control'           => 'no-store, max-age=0',
				'X-Robots-Tag'            => 'noindex, nofollow',
				'Referrer-Policy'         => 'no-referrer',
				'X-Content-Type-Options'  => 'nosniff',
				'X-Frame-Options'         => 'SAMEORIGIN',
				'Content-Security-Policy' => "frame-ancestors 'self';",
			),
			'account'
		);

		// Pas zapasowy: czesc hostingow filtruje naglowki, meta zostaje w HTML.
		add_action(
			'wp_head',
			static function (): void {
				echo '<meta name="robots" content="noindex, nofollow" />' . "\n";
			},
			1
		);
	}

	/**
	 * Render panelu (shortcode): logowanie albo lista spraw.
	 *
	 * @return string HTML.
	 */
	public static function render(): string {
		// Wspolny arkusz stylu frontu (formularz + panel) — polerka #16.
		FormRenderer::enqueue_style();

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
		$out = '<div class="mp-account mp-account--login">';

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
		$out .= '<p class="mp-account__field"><label for="mp-account-email">' . esc_html__( 'Adres e-mail', 'mp-service-intake' ) . '</label>';
		$out .= '<input type="email" id="mp-account-email" name="email" required autocomplete="email" /></p>';
		$out .= '<p class="mp-account__actions"><button type="submit">' . esc_html__( 'Wyślij link logowania', 'mp-service-intake' ) . '</button></p>';
		// Waznosc linku POWIEDZIANA Z GORY: bez tego klient otwiera maila po
		// godzinie, widzi „link nieaktualny" i dzwoni do serwisu. Liczba minut
		// z Login::TTL_SECONDS, zeby ekran i mail nie mogly sie rozjechac.
		$out .= '<p class="mp-account__meta">' . esc_html(
			sprintf(
				/* translators: %d: liczba minut waznosci linku logowania. */
				_n(
					'Link będzie ważny %d minutę i zadziała tylko raz. Po tym czasie po prostu poproś o nowy.',
					'Link będzie ważny %d minut i zadziała tylko raz. Po tym czasie po prostu poproś o nowy.',
					Login::ttl_minutes(),
					'mp-service-intake'
				),
				Login::ttl_minutes()
			)
		) . '</p>';
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

		// Wspolna skrzynka wielu osob: samoobsluga danych wylaczona (#10).
		$shared = count( Customers::ids_by_wp_user( $wp_user_id ) ) > 1;

		$out  = '<div class="mp-account mp-account--panel">';
		$out .= '<h2>' . esc_html__( 'Moje zgłoszenia', 'mp-service-intake' ) . '</h2>';
		$out .= '<p><a href="' . esc_url( wp_logout_url( self::url() ) ) . '">' . esc_html__( 'Wyloguj', 'mp-service-intake' ) . '</a></p>';

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- tylko wyswietlenie komunikatu PRG (bez skutkow), tresc escapowana.
		$notice = isset( $_GET['mp_notice'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['mp_notice'] ) ) : '';

		if ( '' !== $notice ) {
			$out .= '<p class="mp-account__notice" role="status">' . esc_html( $notice ) . '</p>';
		}

		$out .= self::render_contact_form( $wp_user_id, $shared );

		// Blok RODO CELOWO pod lista spraw: klient wchodzi tu po status naprawy,
		// a nie po kasowanie konta. Wczesniej czerwony przycisk usuwania danych
		// rozdzielal profil od zgloszen i sasiadowal z „Zapisz dane" — na telefonie
		// pudlo kciukiem konczylo sie nieodwracalna akcja (przeglad UI 27.07).
		if ( array() === $cases ) {
			$out .= '<p>' . esc_html__( 'Nie znaleźliśmy zgłoszeń przypisanych do tego konta.', 'mp-service-intake' ) . '</p>';
			$out .= self::render_privacy_form( $shared ) . '</div>';

			return $out;
		}

		$out .= '<h3>' . esc_html__( 'Twoje zgłoszenia', 'mp-service-intake' ) . '</h3>';

		foreach ( $cases as $case ) {
			$out .= self::render_case_block( $case );
		}

		$out .= self::render_privacy_form( $shared );
		$out .= '</div>';

		return $out;
	}

	/**
	 * Formularz edycji danych kontaktowych (art. 16 — sprostowanie).
	 *
	 * E-mail pokazany tylko do odczytu (klucz tozsamosci). Prefill z rekordu klienta.
	 * Konto wspoldzielone (wspolny e-mail wielu osob): bez formularza i bez
	 * prefillu — nie pokazujemy jednej osobie danych kontaktowych drugiej (#10).
	 *
	 * @param int  $wp_user_id ID biezacego uzytkownika.
	 * @param bool $shared     Czy konto obsluguje wiecej niz jedna osobe.
	 * @return string HTML.
	 */
	private static function render_contact_form( int $wp_user_id, bool $shared ): string {
		$customer = self::primary_customer( $wp_user_id );

		if ( null === $customer ) {
			return '';
		}

		$name  = (string) ( $customer['name'] ?? '' );
		$phone = (string) ( $customer['phone'] ?? '' );
		$email = (string) ( $customer['email'] ?? '' );

		$out  = '<section class="mp-account__contact">';
		$out .= '<h3>' . esc_html__( 'Twoje dane kontaktowe', 'mp-service-intake' ) . '</h3>';
		$out .= '<p class="mp-account__meta">' . esc_html__( 'E-mail:', 'mp-service-intake' ) . ' ' . esc_html( $email ) . '</p>';

		if ( $shared ) {
			$out .= '<p class="mp-account__meta">' . esc_html( self::shared_mailbox_notice() ) . '</p></section>';

			return $out;
		}
		$out .= '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '" class="mp-account__contact-form">';
		$out .= '<input type="hidden" name="action" value="mp_intake_update_contact" />';
		$out .= wp_nonce_field( 'mp_intake_update_contact', '_mp_nonce', true, false );
		$out .= '<p class="mp-account__field"><label for="mp-name">' . esc_html__( 'Imię i nazwisko', 'mp-service-intake' ) . '</label>';
		$out .= '<input type="text" id="mp-name" name="name" value="' . esc_attr( $name ) . '" /></p>';
		$out .= '<p class="mp-account__field"><label for="mp-phone">' . esc_html__( 'Telefon', 'mp-service-intake' ) . '</label>';
		$out .= '<input type="text" id="mp-phone" name="phone" value="' . esc_attr( $phone ) . '" /></p>';
		$out .= '<p class="mp-account__actions"><button type="submit">' . esc_html__( 'Zapisz dane', 'mp-service-intake' ) . '</button></p>';
		$out .= '</form></section>';

		return $out;
	}

	/**
	 * Obsluga zapisu danych kontaktowych (POST) — art. 16.
	 *
	 * @return void
	 */
	public static function handle_update_contact(): void {
		$user_id = get_current_user_id();

		if ( 0 === $user_id
			|| ! isset( $_POST['_mp_nonce'] )
			|| ! wp_verify_nonce( sanitize_text_field( wp_unslash( (string) $_POST['_mp_nonce'] ) ), 'mp_intake_update_contact' )
		) {
			self::redirect_notice( __( 'Sesja wygasła — spróbuj ponownie.', 'mp-service-intake' ) );
		}

		$customer_ids = Customers::ids_by_wp_user( $user_id );

		// Wspolna skrzynka (znalezisko #10): edycja hurtem nadpisalaby dane
		// INNYCH osob korzystajacych z tego adresu — sprostowanie przez serwis.
		if ( count( $customer_ids ) > 1 ) {
			self::redirect_notice( self::shared_mailbox_notice() );
		}

		$name  = isset( $_POST['name'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['name'] ) ) : '';
		$phone = isset( $_POST['phone'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['phone'] ) ) : '';

		foreach ( $customer_ids as $customer_id ) {
			Customers::update_contact( $customer_id, $name, $phone );
		}

		self::redirect_notice( __( 'Dane kontaktowe zostały zapisane.', 'mp-service-intake' ) );
	}

	/**
	 * Komunikat dla konta wspoldzielonego (wspolny e-mail wielu osob).
	 *
	 * @return string
	 */
	private static function shared_mailbox_notice(): string {
		return __( 'Z tego adresu e-mail korzysta więcej niż jedna osoba, więc samodzielna edycja i usuwanie danych są wyłączone. Napisz wiadomość w swojej sprawie — pracownik serwisu zaktualizuje lub usunie Twoje dane po potwierdzeniu tożsamości.', 'mp-service-intake' );
	}

	/**
	 * Podstawowy (najstarszy) rekord klienta biezacego uzytkownika — do prefillu.
	 *
	 * @param int $wp_user_id ID uzytkownika WP.
	 * @return array<string, mixed>|null
	 */
	private static function primary_customer( int $wp_user_id ): ?array {
		$ids = Customers::ids_by_wp_user( $wp_user_id );

		if ( array() === $ids ) {
			return null;
		}

		return Customers::get( (int) $ids[0] );
	}

	/**
	 * Sekcja RODO: wycofanie zgody + usuniecie danych (art. 7(3) + art. 17).
	 * Konto wspoldzielone: zamiast przycisku wyjasnienie (POST i tak odmowi).
	 *
	 * @param bool $shared Czy konto obsluguje wiecej niz jedna osobe.
	 * @return string HTML.
	 */
	private static function render_privacy_form( bool $shared ): string {
		$out  = '<section class="mp-account__privacy">';
		$out .= '<h3>' . esc_html__( 'Prywatność (RODO)', 'mp-service-intake' ) . '</h3>';

		if ( $shared ) {
			$out .= '<p class="mp-account__meta">' . esc_html( self::shared_mailbox_notice() ) . '</p></section>';

			return $out;
		}

		$out .= '<p class="mp-account__meta">' . esc_html__( 'Możesz wycofać zgodę na przetwarzanie danych i poprosić o ich usunięcie. Jeśli masz aktywne zgłoszenie lub trwa okres roszczeń (gwarancja/rękojmia), dane usuniemy dopiero po jego zakończeniu.', 'mp-service-intake' ) . '</p>';

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- wybor WIDOKU (krok 1 vs ekran potwierdzenia); sama operacja ma wlasny nonce nizej.
		$krok_potwierdzenia = isset( $_GET['mp_withdraw'] ) && 'potwierdz' === sanitize_text_field( wp_unslash( (string) $_GET['mp_withdraw'] ) );

		if ( $krok_potwierdzenia ) {
			// Drugi, swiadomy klik. Mowimy wprost, co zniknie, a co zostaje —
			// klient ma podjac decyzje z pelna informacja, nie w ciemno.
			$out .= '<div class="mp-account__privacy-confirm" role="alert">';
			$out .= '<p><strong>' . esc_html__( 'Ta operacja jest nieodwracalna — nie można jej cofnąć.', 'mp-service-intake' ) . '</strong></p>';
			$out .= '<p>' . esc_html__( 'Usuniemy Twoje dane osobowe: imię i nazwisko, telefon, adres e-mail oraz treści, które je zawierają.', 'mp-service-intake' ) . '</p>';
			$out .= '<p>' . esc_html__( 'Zostaje historia zdarzeń zgłoszeń i statystyki serwisu — bez danych pozwalających Cię zidentyfikować. Wymaga tego rozliczalność obsługi reklamacji.', 'mp-service-intake' ) . '</p>';
			$out .= '<p>' . esc_html__( 'Po usunięciu danych stracisz dostęp do tego panelu.', 'mp-service-intake' ) . '</p>';
			$out .= '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '" class="mp-account__privacy-form">';
			$out .= '<input type="hidden" name="action" value="mp_intake_withdraw_confirm" />';
			$out .= wp_nonce_field( 'mp_intake_withdraw_confirm', '_mp_nonce', true, false );
			$out .= '<p class="mp-account__actions">';
			$out .= '<button type="submit">' . esc_html__( 'Tak, wycofuję zgodę i usuwam dane', 'mp-service-intake' ) . '</button> ';
			$out .= '<a href="' . esc_url( self::url() ) . '">' . esc_html__( 'Anuluj', 'mp-service-intake' ) . '</a>';
			$out .= '</p></form></div></section>';

			return $out;
		}

		$out .= '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '" class="mp-account__privacy-form">';
		$out .= '<input type="hidden" name="action" value="mp_intake_withdraw" />';
		$out .= wp_nonce_field( 'mp_intake_withdraw', '_mp_nonce', true, false );
		$out .= '<p class="mp-account__actions"><button type="submit">' . esc_html__( 'Wycofaj zgodę i usuń moje dane', 'mp-service-intake' ) . '</button></p>';
		$out .= '</form></section>';

		return $out;
	}

	/**
	 * KROK 1 — klikniecie „Wycofaj zgodę i usuń moje dane" NIC nie zmienia.
	 *
	 * Prowadzi na ekran potwierdzenia (ten sam wzorzec, co magic-link: klikniecie
	 * pokazuje strone z przyciskiem). Wczesniej jeden POST kasowal dane, a przycisk
	 * sasiadowal z „Zapisz dane" — pudlo kciukiem na telefonie bylo nieodwracalne.
	 * Konto wspoldzielone odbija sie juz tutaj, zeby nie prowadzic donikad.
	 *
	 * @return void
	 */
	public static function handle_withdraw(): void {
		$user_id = get_current_user_id();

		if ( 0 === $user_id
			|| ! isset( $_POST['_mp_nonce'] )
			|| ! wp_verify_nonce( sanitize_text_field( wp_unslash( (string) $_POST['_mp_nonce'] ) ), 'mp_intake_withdraw' )
		) {
			self::redirect_notice( __( 'Sesja wygasła — spróbuj ponownie.', 'mp-service-intake' ) );
		}

		if ( count( Customers::ids_by_wp_user( $user_id ) ) > 1 ) {
			self::redirect_notice( self::shared_mailbox_notice() );
		}

		wp_safe_redirect( add_query_arg( 'mp_withdraw', 'potwierdz', self::url() ) );
		exit;
	}

	/**
	 * KROK 2 — potwierdzone wycofanie zgody + kanal do erasera (POST).
	 *
	 * Wycofanie zgody (art. 7(3)) jest NATYCHMIASTOWE i emituje CONSENT_WITHDRAWN
	 * na sprawach klienta — niezaleznie od tego, czy eraser od razu usunie dane
	 * (aktywna sprawa => odroczenie EN BLOC w Privacy::erase).
	 *
	 * @return void
	 */
	public static function handle_withdraw_confirm(): void {
		$user_id = get_current_user_id();

		if ( 0 === $user_id
			|| ! isset( $_POST['_mp_nonce'] )
			|| ! wp_verify_nonce( sanitize_text_field( wp_unslash( (string) $_POST['_mp_nonce'] ) ), 'mp_intake_withdraw_confirm' )
		) {
			self::redirect_notice( __( 'Sesja wygasła — spróbuj ponownie.', 'mp-service-intake' ) );
		}

		$customer_ids = Customers::ids_by_wp_user( $user_id );

		// Wspolna skrzynka (znalezisko #10): konto obslugujace WIECEJ NIZ JEDNA
		// osobe nie moze jednym klikiem wycofac zgod i skasowac danych CUDZYCH.
		// Wniosek przechodzi wtedy przez czlowieka (wiadomosc w sprawie /
		// wbudowany eraser WP uruchamiany przez administratora per osoba).
		if ( count( $customer_ids ) > 1 ) {
			self::redirect_notice( self::shared_mailbox_notice() );
		}

		$emails = array();

		foreach ( $customer_ids as $customer_id ) {
			Consents::withdraw( $customer_id, Consents::KEY_PROCESSING );

			// CONSENT_WITHDRAWN na KAZDEJ sprawie klienta (audit-trail art. 7).
			foreach ( CaseRepo::for_customer( $customer_id ) as $case ) {
				CaseEvents::log(
					(int) ( $case['id'] ?? 0 ),
					CaseEvents::CONSENT_WITHDRAWN,
					array( 'consent_key' => Consents::KEY_PROCESSING ),
					$user_id
				);
			}

			$customer = Customers::get( $customer_id );

			if ( null !== $customer && '' !== (string) ( $customer['email'] ?? '' ) ) {
				$emails[ (string) $customer['email'] ] = true;
			}
		}

		$retained = false;
		$removed  = false;

		foreach ( array_keys( $emails ) as $email ) {
			$result   = Privacy::erase( $email );
			$retained = $retained || (bool) $result['items_retained'];
			$removed  = $removed || (bool) $result['items_removed'];
		}

		if ( $removed ) {
			$notice = __( 'Zgoda została wycofana, a Twoje dane osobowe zostały usunięte.', 'mp-service-intake' );
		} elseif ( $retained ) {
			$notice = __( 'Zgoda została wycofana. Masz aktywne zgłoszenie — dane usuniemy po jego zakończeniu.', 'mp-service-intake' );
		} else {
			$notice = __( 'Zgoda została wycofana.', 'mp-service-intake' );
		}

		self::redirect_notice( $notice );
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

		$out  = '<section class="mp-account__case">';
		$out .= '<h3>' . esc_html( (string) ( $row['case_number'] ?? '' ) ) . '</h3>';
		// Klient widzi NAZWY, nie wartosci techniczne: funkcje tlumaczace stoja
		// w tym samym produkcie i po prostu nie byly tu uzyte.
		$out .= '<p class="mp-account__meta">'
			. esc_html( FormConfig::kind_label( (string) ( $row['kind'] ?? '' ) ) ) . ' · '
			. esc_html__( 'Status:', 'mp-service-intake' ) . ' <strong>' . esc_html( '' !== $status ? Statuses::label( $status ) : '—' ) . '</strong> · '
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
			return '<p class="mp-account__empty">' . esc_html__( 'Brak wiadomości.', 'mp-service-intake' ) . '</p>';
		}

		$labels = array(
			'client' => __( 'Ty', 'mp-service-intake' ),
			'staff'  => __( 'Serwis', 'mp-service-intake' ),
			'system' => __( 'System', 'mp-service-intake' ),
		);

		$out = '<ul class="mp-account__messages">';

		foreach ( $messages as $msg ) {
			$author = (string) ( $msg['author_type'] ?? 'system' );
			$label  = $labels[ $author ] ?? $labels['system'];
			$when   = get_date_from_gmt( (string) ( $msg['created_at'] ?? '' ), 'Y-m-d H:i' );

			$out .= '<li class="mp-account__message">';
			$out .= '<span class="mp-account__message-author">' . esc_html( $label ) . '</span> ';
			$out .= '<span class="mp-account__message-when">' . esc_html( $when ) . '</span><br />';
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
			$out .= '<p class="mp-account__note-closed">' . esc_html__( 'Sprawa jest zamknięta — wiadomość trafi do serwisu, ale nie zmienia statusu sprawy.', 'mp-service-intake' ) . '</p>';
		}

		$out .= '<p class="mp-account__field"><label for="mp-msg-' . esc_attr( (string) $case_id ) . '">' . esc_html__( 'Napisz wiadomość do serwisu', 'mp-service-intake' ) . '</label>';
		$out .= '<textarea id="mp-msg-' . esc_attr( (string) $case_id ) . '" name="body" rows="3" required></textarea></p>';
		$out .= '<p class="mp-account__actions"><button type="submit">' . esc_html__( 'Wyślij', 'mp-service-intake' ) . '</button></p>';
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
