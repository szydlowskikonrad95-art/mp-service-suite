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
use MP\Intake\Common\Str;
use MP\Intake\Consents;
use MP\Intake\FormConfig;
use MP\Intake\RateLimit;
use MP\Intake\Validator;

/**
 * Handlery admin-post frontu Intake.
 */
final class SubmissionHandler {

	/**
	 * Minimalny czas wypelnienia formularza w sekundach (ponizej = bot).
	 */
	public const MIN_FILL_SECONDS = 2;

	/**
	 * Maksymalny wiek znacznika czasu formularza w sekundach (powyzej =
	 * replay/sfalszowany). 10800 = 3 h — hojnie ponad realny czas wypelniania;
	 * nonce i tak wygasa wczesniej. Literal (spojnie z DEDUP_WINDOW — brak
	 * zaleznosci od kolejnosci ladowania stalych WP).
	 */
	public const MAX_FILL_SECONDS = 10800;

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

		// S4 #1: zaladunek wiekszy niz post_max_size => PHP wyrzuca $_POST i $_FILES,
		// wiec 'action' ginie i admin-post.php odpala hook BEZ akcji, ktorego nikt
		// nie obsluguje => biala pusta strona (handle_submit nawet nie startuje).
		// Lapiemy TEN jeden przypadek i wracamy na formularz z komunikatem o limicie.
		add_action( 'admin_post_nopriv', array( self::class, 'guard_oversized_post' ) );
		add_action( 'admin_post', array( self::class, 'guard_oversized_post' ) );
	}

	/**
	 * Strażnik zaladunku przekraczajacego post_max_size (S4 #1).
	 *
	 * Wpiety w admin-post.php BEZ akcji (jedyny hook, ktory wtedy leci). Reaguje
	 * WYLACZNIE gdy: POST, $_POST i $_FILES puste, Content-Length > post_max_size,
	 * a zrodlem jest nasza strona formularza. Wtedy zamiast bialej pustki wraca na
	 * formularz z komunikatem, do ilu megabajtow serwer przyjmuje pliki. Kazdy inny
	 * bezakcyjny POST zostawiamy nietkniety (return) — nie przejmujemy cudzego ruchu.
	 *
	 * @return void
	 */
	public static function guard_oversized_post(): void {
		$method = isset( $_SERVER['REQUEST_METHOD'] ) ? sanitize_text_field( wp_unslash( (string) $_SERVER['REQUEST_METHOD'] ) ) : '';

		if ( 'POST' !== $method ) {
			return;
		}

		// Oversized-POST: PHP zostawia $_POST i $_FILES puste mimo niezerowego ciala.
		$content_length = isset( $_SERVER['CONTENT_LENGTH'] ) ? (int) $_SERVER['CONTENT_LENGTH'] : 0;

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- oversized-POST: cialo (w tym nonce) PHP juz wyrzucil; sprawdzamy WYLACZNIE pustosc $_POST/$_FILES, nie przetwarzamy zadnej wartosci.
		if ( array() !== $_POST || array() !== $_FILES || $content_length <= 0 ) {
			return;
		}

		$post_max = wp_convert_hr_to_bytes( (string) ini_get( 'post_max_size' ) );

		if ( $post_max <= 0 || $content_length <= $post_max ) {
			return;
		}

		// Tylko dla NASZEGO formularza — inaczej przechwycilibysmy cudzy bezakcyjny
		// POST. Referer jest jedynym tropem (body przepadlo razem z 'action').
		// Porownujemy caly adres BEZ schematu (odpornosc na http/https), zeby dzialalo
		// i przy ladnych permalinkach (/zgloszenie-serwisowe/), i przy zwyklych (?page_id=N),
		// gdzie sama sciezka to „/" i nie odroznilaby stron.
		$strip    = static fn( string $u ): string => (string) preg_replace( '#^https?://#i', '', $u );
		$referer  = $strip( (string) wp_get_referer() );
		$form_url = $strip( self::form_page_url() );

		if ( '' === $referer || '' === $form_url || 0 !== strpos( $referer, $form_url ) ) {
			return;
		}

		// Komunikat podaje limit REALNIE egzekwowany na pliki (min(upload,post)).
		self::redirect_back(
			array(
				'notice' => sprintf(
					/* translators: %s: rozmiar z jednostka, np. „2 MB". */
					__( 'Załącznik jest za duży — ten serwer przyjmuje pliki do %s. Zmniejsz zdjęcie (np. w telefonie) i wyślij zgłoszenie ponownie; wpisane dane wpisz jeszcze raz.', 'mp-service-intake' ),
					size_format( wp_max_upload_size() )
				),
			)
		);
	}

	/**
	 * Adres strony formularza zgloszenia (permalink auto-strony) albo ''.
	 *
	 * @return string
	 */
	private static function form_page_url(): string {
		$page_id = (int) get_option( 'mp_intake_form_page_id', 0 );

		if ( $page_id <= 0 ) {
			return '';
		}

		$url = get_permalink( $page_id );

		return false === $url ? '' : (string) $url;
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

		// Antyspam: honeypot wypelniony ALBO podejrzany znacznik czasu => cichy
		// sukces (bot nie wie). D11: BRAK mp_ts tez = bot — wczesniej pominiecie pola
		// omijalo pulapke (warunek `$started > 0`); teraz missing/za szybko/za stary
		// wpada w blokade. Prawdziwy formularz zawsze wysyla swiezy mp_ts.
		$honeypot = isset( $_POST['mp_hp'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['mp_hp'] ) ) : '';
		$started  = isset( $_POST['mp_ts'] ) ? (int) $_POST['mp_ts'] : 0;
		$elapsed  = time() - $started;
		$bad_ts   = $started <= 0 || $elapsed < self::MIN_FILL_SECONDS || $elapsed > self::MAX_FILL_SECONDS;

		if ( '' !== $honeypot || $bad_ts ) {
			self::redirect_back( array( 'notice' => self::neutral_message() ) );
		}

		$kind     = isset( $_POST['kind'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['kind'] ) ) : '';
		$category = isset( $_POST['category'] ) ? sanitize_key( wp_unslash( (string) $_POST['category'] ) ) : '';

		if ( ! FormConfig::is_valid_category( $category ) ) {
			$category = '';
		}

		$email    = isset( $_POST['email'] ) ? sanitize_email( wp_unslash( (string) $_POST['email'] ) ) : '';
		$customer = isset( $_POST['customer_name'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['customer_name'] ) ) : '';
		$customer = trim( $customer );
		$consent  = isset( $_POST['mp_consent'] ) && '1' === sanitize_text_field( wp_unslash( (string) $_POST['mp_consent'] ) );
		$values   = self::collect_values( $kind, $category );

		// Ochrona zgloszen: rate-limit warstwowy + dedup twardy. Po honeypocie,
		// przed tworzeniem sprawy. Marker dedup dopiero po sukcesie (mark_submitted).
		// IP klienta z RateLimit::client_ip() (filtr mp_intake_client_ip; domyslnie
		// REMOTE_ADDR) — za reverse-proxy wszyscy = 1 IP proxy = blok wszystkich (flaga #10).
		$serial  = (string) ( $values['serial'] ?? '' );
		$ip      = RateLimit::client_ip();
		$blocked = RateLimit::check( $ip, $email, $serial, $kind );

		if ( null !== $blocked ) {
			// S4 #3: odmowa NIE czysci formularza — wpisane dane wracaja w PRG
			// (echo_values), zeby czlowiek nie przepisywal opisu usterki od nowa.
			// Przy limicie (nie dedup) komunikat mowi KIEDY znow mozna i ze nie
			// trzeba czekac: wiadomosc w istniejacej sprawie idzie od razu i nie
			// podlega temu limitowi (tak samo mowi instrukcja klienta).
			$notice = RateLimit::BLOCK_DUPLICATE === $blocked
				? self::duplicate_message()
				: self::rate_limited_message(
					RateLimit::retry_after( $ip, $email, $serial ),
					RateLimit::blocked_scope( $ip, $email, $serial )
				);
			self::redirect_back(
				array(
					'notice' => $notice,
					'values' => self::echo_values( $values, $kind, $category, $email, $customer ),
				)
			);
		}

		// Zgoda RODO i imie zglaszajacego — JEDNA bramka, nie dwie. Bramki
		// sekwencyjne kaza czlowiekowi krazyc (poz. 2.57): poprawia jedno,
		// wysyla, dostaje nastepne. Oba braki sa znane w tym samym momencie,
		// wiec wracaja razem.
		$gate_errors = array();

		if ( ! $consent ) {
			$gate_errors['mp_consent'] = 'REQUIRED';
		}

		$name_error = Validator::validate_customer_name( $customer );

		if ( null !== $name_error ) {
			$gate_errors['customer_name'] = $name_error;
		}

		// (specyfikacja: „wymagane pola I ZALACZNIKI zalezne od wybranej kategorii
		// produktu"). Bramka PRZED utworzeniem sprawy i PRZED rezerwacja dedup:
		// sprawa nie moze powstac bez obowiazkowego zdjecia, bo klient dostalby
		// wtedy tylko notke „czesc zalacznikow nie zostala dolaczona", a serwis
		// sprawe bez tabliczki znamionowej.
		// ⛔ 2.57: to byla OSOBNA bramka z wlasnym powrotem — czlowiek poprawial
		// zgode, wysylal, i dopiero WTEDY dowiadywal sie o brakujacym zdjeciu.
		$files = self::collect_files();

		if ( FormConfig::attachments_for( $category )['required'] && ! self::has_usable_attachment( $files ) ) {
			$gate_errors['mp_files'] = 'ATTACHMENT_REQUIRED';
		}

		// ⛔ 2.57: WSZYSTKIE braki wracaja RAZEM, w jednym przebiegu. Bramki byly
		// sekwencyjne, wiec przy pustym formularzu klient krazyl co najmniej TRZY
		// razy (zgoda → zalacznik → pola), choc wszystkie braki byly znane juz
		// przy pierwszym wyslaniu.
		// ⚠️ Wolamy TE SAMA funkcje, ktorej uzywa `CaseRepo::create` — nie wlasna
		// kopie regul. Gdyby reguly rozjechaly sie na dwie, formularz zaczalby
		// odrzucac co innego niz zapis i nikt by tego nie zauwazyl. `create`
		// waliduje dalej po swojemu — to zostaje jako druga warstwa.
		$bledy_pol = self::flatten_errors(
			CaseRepo::collect_validation_errors( $kind, $email, $values, gmdate( 'Y-m-d' ), $category )
		);

		// Braki z bramek WYGRYWAJA nad walidacja pol: mowia konkretniej (o imieniu
		// decyduje `validate_customer_name`, nie ogolna regula pola).
		$gate_errors = array_merge( $bledy_pol, $gate_errors );

		if ( array() !== $gate_errors ) {
			self::redirect_back(
				array(
					'errors' => $gate_errors,
					'values' => self::echo_values( $values, $kind, $category, $email, $customer ),
				)
			);
		}

		// Atomowa REZERWACJA dedup PRZED utworzeniem sprawy (znalezisko #4):
		// dwa rownolegle POST-y tego samego zgloszenia (podwojny klik, retry
		// proxy) — pierwszy zajmuje klucz, drugi odpada jako duplikat. Dawny
		// check-then-set (marker dopiero po sukcesie) przepuszczal oba: dwie
		// sprawy w bazie, dwa maile do klienta.
		if ( ! RateLimit::claim_submission( $email, $serial, $kind ) ) {
			self::redirect_back( array( 'notice' => self::duplicate_message() ) );
		}

		$result = CaseRepo::create(
			array(
				'kind'     => $kind,
				'category' => $category,
				'email'    => $email,
				'name'     => $customer,
				'values'   => $values,
			)
		);

		if ( isset( $result['error'] ) ) {
			// D5: odrzucone zgloszenie zwalnia rezerwacje — poprawiony retry
			// nie jest duplikatem i nie czeka 15 min.
			RateLimit::release_claim( $email, $serial, $kind );

			self::redirect_back(
				array(
					'errors' => self::flatten_errors( $result['validation'] ?? array() ),
					'values' => self::echo_values( $values, $kind, $category, $email, $customer ),
				)
			);
		}

		// Audyt #2: zgoda RODO zapisywana PRZED zalacznikami — zgoda to wymog
		// prawny przetwarzania, zalacznik to dodatek. Pad w srodku (np. pelny
		// dysk przy zapisie plikow) nie moze zostawic sprawy z danymi bez
		// utrwalonej zgody.
		// Zgoda RODO: pelny tekst zamrozony, spieta ze sprawa (podpiecie do klienta przy weryfikacji).
		$zgoda_id = Consents::record(
			$email,
			(int) $result['case_id'],
			Consents::KEY_PROCESSING,
			Consents::VERSION,
			Consents::processing_text()
		);

		// ⛔ Wynik zapisu ZGODY sprawdzamy — wczesniej metoda byla wolana jak
		// instrukcja, a zwracana wartosc nie byla ani przypisywana, ani badana.
		// Komentarz trzy linie wyzej nazywa te awarie po imieniu: „pad w srodku
		// nie moze zostawic sprawy z danymi bez utrwalonej zgody". Kolejnosc
		// chronila przed padem PO zapisie zgody — nie chronila przed nieudanym
		// zapisem samej zgody. Sprawa bez zgody = przetwarzanie bez mozliwosci
		// wykazania podstawy prawnej (RODO art. 7 ust. 1), wiec jej nie
		// zostawiamy: kasujemy zgloszenie i prosimy czlowieka o ponowienie.
		if ( 0 === $zgoda_id ) {
			CaseRepo::purge_pending_cases( array( (int) $result['case_id'] ) );
			RateLimit::release_claim( $email, $serial, $kind );

			self::redirect_back(
				array(
					'notice' => __( 'Nie udało się zapisać Twojej zgody, więc zgłoszenie nie zostało przyjęte. Spróbuj ponownie za chwilę.', 'mp-service-intake' ),
				)
			);
		}

		// Zalaczniki na sprawe niepotwierdzona (CAP pending chroni dysk; sieroty
		// sprzatane cronem sierot razem ze sprawa). `$files` zebrane wyzej przy
		// bramce — jedno czytanie $_FILES na zgloszenie.
		$att_errors = array();

		if ( array() !== $files ) {
			// D4: wynik NIE jest ignorowany — pominiete pliki musza trafic do klienta
			// (inaczej reklamacja bez dowodu). Teksty bledow gotowe w store_for_case.
			$att        = Attachments::store_for_case( (int) $result['case_id'], $kind, $files );
			$att_errors = $att['errors'];
		}

		// D5: liczniki e-mail/serial + marker dedup DOPIERO teraz (udane zgloszenie) —
		// literowka/blad walidacji nie zjada limitu dobowego; retry nie jest duplikatem.
		RateLimit::record_submission( $email, $serial, $kind );

		$mail_ok = Mailer::send_magic_link( $email, (string) $result['token'], (int) $result['case_id'] );

		// Komunikat NEUTRALNY — zero enumeracji, SRV dopiero w mailu/panelu.
		// 2.1b: ...ale TYLKO gdy mail naprawde wyszedl. Wynik wysylki byl wczesniej
		// ignorowany, wiec przy padnietej poczcie klient dostawal zdanie brzmiace
		// jak potwierdzenie i czekal na link, ktory nie mial prawa przyjsc.
		// D4: dokladamy info o pominietych plikach (nie zdradza istnienia konta —
		// dotyczy plikow ktore klient sam wgral, wiec anty-enumeracja zachowana).
		$notice = $mail_ok ? self::neutral_message() : self::mail_failed_message();

		if ( array() !== $att_errors ) {
			$notice .= ' ' . __( 'Uwaga: część załączników nie została dołączona do zgłoszenia:', 'mp-service-intake' )
				. ' ' . implode( ' ', $att_errors );
		}

		self::redirect_back( array( 'notice' => $notice ) );
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

			// 2.1b: ten sam wzorzec co przy zgloszeniu — wynik wysylki byl ignorowany.
			// Tu bolalo najbardziej: numer sprawy klient poznaje WYLACZNIE z tego maila
			// (krok 6 specyfikacji), wiec przy padnietej poczcie zostawal z niczym, slyszac,
			// ze numer zostal wyslany. Brak adresu = mail nie poszedl tak samo.
			$mail_ok = '' !== $email
				&& Mailer::send_confirmation( $email, (string) $result['case_number'], (int) $result['case_id'] );

			if ( $mail_ok ) {
				self::render_landing(
					__( 'Zgłoszenie potwierdzone', 'mp-service-intake' ),
					__( 'Dziękujemy. Twoje zgłoszenie zostało potwierdzone — szczegóły i numer sprawy wysłaliśmy na Twój adres e-mail.', 'mp-service-intake' ),
					200,
					true
				);
			}

			// ⛔ NUMERU SPRAWY TU NIE POKAZUJEMY, choc klient wlasnie udowodnil, ze ma
			// dostep do skrzynki. Reguła produktu jest starsza i szersza: SRV wychodzi
			// WYLACZNIE mailem albo panelem (naglowek tego pliku, krok 6 specyfikacji), a
			// pilnuje jej test C3 („strona POST nie zdradza numeru SRV"). Pierwsza
			// wersja tej poprawki numer pokazywala i C3 od razu ja zlapal — zmiana
			// tamtej reguly to decyzja wlasciciela produktu, nie skutek uboczny
			// naprawy komunikatu. Klient dostaje prawde i droge dalej, nie numer.
			self::render_landing(
				__( 'Zgłoszenie potwierdzone — wiadomość nie wyszła', 'mp-service-intake' ),
				__( 'Twoje zgłoszenie zostało potwierdzone i przyjęte do obsługi — obsługa już je widzi. Nie udało się jednak wysłać wiadomości z potwierdzeniem, bo nasza poczta odmówiła jej przyjęcia. Skontaktuj się z serwisem po numer sprawy.', 'mp-service-intake' ),
				200,
				true
			);
		}

		$already = empty( $result['expired'] );

		self::render_landing(
			$already ? __( 'Zgłoszenie już potwierdzone', 'mp-service-intake' ) : __( 'Link nieaktualny', 'mp-service-intake' ),
			(string) $result['error'],
			$already ? 200 : 410,
			$already
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
		$title = __( 'Potwierdź zgłoszenie', 'mp-service-intake' );

		Landing::open( $title );
		echo '<h1>' . esc_html( $title ) . '</h1>';
		echo '<p>' . esc_html__( 'Aby potwierdzić swoje zgłoszenie serwisowe i uruchomić obsługę, kliknij przycisk poniżej.', 'mp-service-intake' ) . '</p>';
		echo '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '">';
		echo '<input type="hidden" name="action" value="mp_intake_verify_confirm" />';
		echo '<input type="hidden" name="token" value="' . esc_attr( $token ) . '" />';
		wp_nonce_field( 'mp_intake_verify_confirm', '_mp_nonce' );
		echo '<button type="submit">' . esc_html__( 'Potwierdzam', 'mp-service-intake' ) . '</button>';
		echo '</form>';
		Landing::close();
		exit;
	}

	/**
	 * Zbiera wartosci pol wg schematu rodzaju + kategorii (tylko znane pola — anty-smiec).
	 *
	 * @param string $kind     Rodzaj sprawy.
	 * @param string $category Slug kategorii (pusty = tylko pola rodzaju).
	 * @return array<string, string>
	 */
	private static function collect_values( string $kind, string $category = '' ): array {
		$values = array();

		if ( ! FormConfig::is_valid_kind( $kind ) ) {
			return $values;
		}

		foreach ( FormConfig::fields_for( $kind, $category ) as $field ) {
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
	 * Wartosci do PRZEPISANIA w formularzu po odbiciu z bledem.
	 *
	 * Czysta funkcja (testowana jednostkowo — `SubmissionGateTest`).
	 *
	 * Po co osobno: `collect_values()` zwraca tylko pola z `fields_for()`,
	 * a rodzaj, kategoria i e-mail polami nie sa. Kategoria wypadala z odbicia
	 * — po bledzie walidacji lista wracala do „— wybierz —", razem z nia znikaly
	 * pola kategorii i oznaczenie wymaganego zalacznika. Klient poprawial
	 * jedno pole i dostawal formularz o innym ksztalcie niz wyslal.
	 *
	 * @param array<string, mixed> $values   Wartosci pol z formularza.
	 * @param string               $kind     Rodzaj sprawy.
	 * @param string               $category Slug kategorii (moze byc pusty).
	 * @param string               $email    E-mail kontaktowy.
	 * @param string               $customer Imie i nazwisko zglaszajacego.
	 * @return array<string, mixed>
	 */
	public static function echo_values( array $values, string $kind, string $category, string $email, string $customer = '' ): array {
		return array_merge(
			$values,
			array(
				'kind'          => $kind,
				'category'      => $category,
				'email'         => $email,
				'customer_name' => $customer,
			)
		);
	}

	/**
	 * Czy wsrod przeslanych plikow jest CHOC JEDEN nadajacy sie do przyjecia.
	 *
	 * Czysta funkcja (testowana jednostkowo — `SubmissionGateTest`).
	 *
	 * Liczy sie plik, ktory PRZEJDZIE walidacje (`Attachments::validate_upload`),
	 * a nie sam fakt wyboru pliku w przegladarce. Inaczej zdjecie 12 MB albo
	 * plik .exe „spelnialoby" wymog kategorii, sprawa powstawalaby bez tabliczki
	 * znamionowej, a klient dowiadywalby sie o tym z notki po fakcie.
	 *
	 * @param array<int, array<string, mixed>> $files Znormalizowane pliki.
	 * @return bool
	 */
	public static function has_usable_attachment( array $files ): bool {
		foreach ( $files as $file ) {
			// Puste pole pliku: `validate_upload` zwraca dla niego null („brak
			// zalacznika, nie blad") — bez tego warunku pusty wpis liczylby sie
			// jako spelniony wymog. `collect_files()` takich nie przepuszcza,
			// ale metoda jest publiczna i musi bronic sie sama.
			if ( UPLOAD_ERR_NO_FILE === (int) ( $file['error'] ?? UPLOAD_ERR_NO_FILE ) ) {
				continue;
			}

			if ( null === Attachments::validate_upload( $file ) ) {
				return true;
			}
		}

		return false;
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
	 * Komunikat po ODRZUCENIU zgloszenia jako duplikat (audyt 2.1 — czesc (b)).
	 *
	 * PO CO: oba miejsca odrzucenia (odczyt przed praca i przegrana rezerwacja
	 * atomowa) mowily „To zgloszenie wlasnie przyjelismy — sprawdz skrzynke".
	 * Przy podwojnym kliknieciu bylo to nieszkodliwe, ale klucz duplikatu to
	 * `e-mail + numer seryjny + rodzaj`, wiec klient zglaszajacy w tym samym oknie
	 * INNA usterke tego samego sprzetu dostawal zdanie brzmiace jak potwierdzenie.
	 * Sprawa nie powstawala, a on byl pewien, ze powstala.
	 *
	 * JEDNO ZRODLO dla obu miejsc — inaczej za tydzien rozjada sie slowo w slowo.
	 * Liczba minut z `RateLimit::DEDUP_WINDOW`, nie wpisana slownie.
	 *
	 * @return string
	 */
	private static function duplicate_message(): string {
		$minuty = RateLimit::dedup_minutes();

		return sprintf(
			/* translators: %s: okno dedup w minutach z odmiana, np. „15 minut". */
			__( 'Tego zgłoszenia NIE przyjęliśmy — takie samo (ten sam sprzęt i ten sam rodzaj sprawy) przyjęliśmy chwilę wcześniej i to nim się zajmujemy. Sprawdź swoją skrzynkę e-mail. Jeśli zgłaszasz INNĄ usterkę tego samego sprzętu, odczekaj %s albo skontaktuj się z serwisem.', 'mp-service-intake' ),
			sprintf(
				Str::odmiana(
					$minuty,
					/* translators: forma dla 1. */
					__( '%d minutę', 'mp-service-intake' ),
					/* translators: forma dla 2-4. */
					__( '%d minuty', 'mp-service-intake' ),
					/* translators: forma dla 0 i 5+. */
					__( '%d minut', 'mp-service-intake' )
				),
				$minuty
			)
		);
	}

	/**
	 * Komunikat odmowy przy przekroczeniu limitu zgloszen (S4 #3 + Z8).
	 *
	 * Mowi KIEDY znow mozna (moment z RateLimit::retry_after, w strefie witryny)
	 * oraz ze nie trzeba czekac — wiadomosc w istniejacej sprawie idzie od razu.
	 * Zastepuje dawne „Spróbuj ponownie za jakiś czas", ktore nie mowilo ani
	 * kiedy, ani co zrobic zamiast. Gdy momentu nie da sie ustalic (okno tuz
	 * wygaslo) — pomijamy zdanie o godzinie, reszta zostaje.
	 *
	 * Z8 (polowanie 2026-08-05): jeden wspolny tekst „Z TEGO ADRESU wysłano…"
	 * obwinial niewinny adres, gdy odbicie poszlo z limitu NUMERU SERYJNEGO albo
	 * LACZA — klient ze swiezym adresem zmienial go (nic nie dawalo) albo uznawal
	 * system za zepsuty. Kazdy zakres blokady mowi teraz wlasnym zdaniem; gdy
	 * zakresu nie da sie ustalic — zdanie neutralne bez wskazywania winnego.
	 *
	 * @param int|null    $retry_ts Unix ts konca blokady albo null.
	 * @param string|null $scope    Zakres blokady (RateLimit::SCOPE_*) albo null.
	 * @return string
	 */
	private static function rate_limited_message( ?int $retry_ts, ?string $scope ): string {
		switch ( $scope ) {
			case RateLimit::SCOPE_SERIAL:
				$powod = __( 'Dla tego numeru seryjnego wysłano zbyt wiele zgłoszeń w krótkim czasie.', 'mp-service-intake' );
				/* translators: %s: data i godzina, od ktorej znow mozna wyslac, np. „5.08, 14:30". */
				$kiedy_wzor = __( ' Kolejne zgłoszenie z tym numerem seryjnym wyślesz po %s.', 'mp-service-intake' );
				break;
			case RateLimit::SCOPE_IP:
				$powod = __( 'Z tego łącza internetowego wysłano zbyt wiele zgłoszeń w krótkim czasie.', 'mp-service-intake' );
				/* translators: %s: data i godzina, od ktorej znow mozna wyslac, np. „5.08, 14:30". */
				$kiedy_wzor = __( ' Kolejne zgłoszenie wyślesz po %s.', 'mp-service-intake' );
				break;
			case RateLimit::SCOPE_EMAIL:
				$powod = __( 'Z tego adresu e-mail wysłano zbyt wiele zgłoszeń w krótkim czasie.', 'mp-service-intake' );
				/* translators: %s: data i godzina, od ktorej znow mozna wyslac, np. „5.08, 14:30". */
				$kiedy_wzor = __( ' Kolejne zgłoszenie z tego adresu wyślesz po %s.', 'mp-service-intake' );
				break;
			default:
				$powod = __( 'Wysłano zbyt wiele zgłoszeń w krótkim czasie.', 'mp-service-intake' );
				/* translators: %s: data i godzina, od ktorej znow mozna wyslac, np. „5.08, 14:30". */
				$kiedy_wzor = __( ' Kolejne zgłoszenie wyślesz po %s.', 'mp-service-intake' );
		}

		$kiedy = null !== $retry_ts
			? sprintf( $kiedy_wzor, wp_date( 'j.m, H:i', $retry_ts ) )
			: '';

		return $powod . $kiedy . ' '
			. __( 'Nie musisz czekać — jeśli masz już założoną sprawę, napisz wiadomość przy niej w panelu zgłoszeń: trafia do serwisu od razu i nie podlega temu limitowi.', 'mp-service-intake' );
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
	 * Komunikat, gdy WYSYLKA MAILA PADLA (audyt 2.1b).
	 *
	 * PO CO: `wp_mail()` zwraca falsz przy odmowie serwera poczty, a klient
	 * slyszal DOKLADNIE to samo co przy sukcesie — czekal na link, ktory nie mial
	 * prawa przyjsc, a zgloszenie umieralo jako niepotwierdzone po wygasnieciu tokenu.
	 *
	 * ANTY-ENUMERACJA ZACHOWANA: zdanie nie mowi NIC o tym, czy podane dane pasuja
	 * do czegokolwiek w bazie — mowi wylacznie o awarii serwera poczty, ktora jest
	 * niezalezna od tresci zgloszenia. Zgloszenie powstaje ZAWSZE, wiec fakt jego
	 * zapisania nie jest wyciekiem (inaczej niz przy logowaniu, gdzie maila
	 * wysylamy TYLKO dla istniejacego konta — patrz `Front\Login::handle_request`).
	 *
	 * @return string
	 */
	private static function mail_failed_message(): string {
		return __( 'Zgłoszenie zapisaliśmy, ale nie udało się wysłać wiadomości e-mail z linkiem potwierdzającym — to awaria naszej poczty, nie błąd po Twojej stronie. Skontaktuj się z serwisem, żeby dokończyć zgłoszenie; ponowne wysłanie formularza nic nie da.', 'mp-service-intake' );
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
	 * @param string $title          Tytul.
	 * @param string $message        Tresc.
	 * @param int    $status         Kod HTTP.
	 * @param bool   $with_panel_cta Czy dolaczyc CTA "Przejdz do panelu zgloszen" (tylko po sukcesie).
	 * @return never
	 */
	private static function render_landing( string $title, string $message, int $status = 200, bool $with_panel_cta = false ): void {
		Landing::open( $title, $status );
		echo '<h1>' . esc_html( $title ) . '</h1><p>' . esc_html( $message ) . '</p>';

		// CTA: droga dalej do panelu zgloszen (tylko po sukcesie potwierdzenia).
		if ( $with_panel_cta ) {
			echo '<p><a class="mp-cta" href="' . esc_url( AccountPage::url() ) . '">'
				. esc_html__( 'Przejdź do panelu zgłoszeń', 'mp-service-intake' ) . '</a></p>';
		}

		Landing::close();
		exit;
	}
}
