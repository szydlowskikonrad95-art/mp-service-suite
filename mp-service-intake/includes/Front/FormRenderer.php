<?php
/**
 * Render formularza zgloszenia (front) — WCAG-lite + antyspam-pola.
 *
 * WCAG-lite (EAA): <label> spiete z KAZDYM polem, bledy w role=alert spiete
 * przez aria-describedby, potwierdzenia w role=status. Antyspam: honeypot
 * (ukryte pole `mp_hp` — bot je wypelni) + znacznik czasu startu `mp_ts`
 * (formularz wyslany <2s = bot, cichy odrzut). Pola z FormConfig per rodzaj.
 *
 * @package MP\Intake
 */

namespace MP\Intake\Front;

use MP\Intake\Assets;
use MP\Intake\FormConfig;
use MP\Intake\Validator;

/**
 * Budowa HTML formularza zgloszenia.
 */
final class FormRenderer {

	/**
	 * Renderuje formularz (blok/shortcode).
	 *
	 * @param array<string, mixed> $ctx Kontekst: errors (kody per pole), values, notice.
	 * @return string HTML.
	 */
	public static function render( array $ctx = array() ): string {
		$errors = isset( $ctx['errors'] ) && is_array( $ctx['errors'] ) ? $ctx['errors'] : array();
		$values = isset( $ctx['values'] ) && is_array( $ctx['values'] ) ? $ctx['values'] : array();
		$notice = (string) ( $ctx['notice'] ?? '' );
		$kind   = in_array( (string) ( $values['kind'] ?? '' ), FormConfig::KINDS, true )
			? (string) $values['kind']
			: 'reklamacja';

		$category = FormConfig::is_valid_category( (string) ( $values['category'] ?? '' ) )
			? (string) ( $values['category'] ?? '' )
			: '';

		// Warstwa kliencka: skrypt dynamicznego formularza + config pol per rodzaj/kategoria.
		self::enqueue_assets();

		// Klucze WYMAGANE dla wybranego rodzaju + kategorii (reszta unii renderowana bez
		// `required` — JS ukrywa je i toggluje `required` przy zmianie rodzaju/kategorii).
		$required_keys = array();
		foreach ( FormConfig::fields_for( $kind, $category ) as $field ) {
			if ( $field['required'] ) {
				$required_keys[] = $field['key'];
			}
		}

		// 2.57: etykiety z JEDNEGO zrodla — podsumowanie bledow odsyla do pol po nazwie.
		$etykiety = self::field_labels();

		$out  = '<div class="mp-intake">';
		$out .= '<h2>' . esc_html__( 'Zgłoszenie serwisowe', 'mp-service-intake' ) . '</h2>';

		if ( '' !== $notice ) {
			$out .= '<p class="mp-intake-notice" role="status">' . esc_html( $notice ) . '</p>';
		}

		$out .= self::error_summary( $errors );

		$out .= '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '" class="mp-intake-form" enctype="multipart/form-data" novalidate>';
		$out .= '<input type="hidden" name="action" value="mp_intake_submit" />';
		$out .= wp_nonce_field( 'mp_intake_submit', '_mp_nonce', true, false );

		// Antyspam: honeypot (ukryty wizualnie i dla czytnikow) + czas startu.
		$out .= '<div class="mp-hp-wrap" aria-hidden="true" style="position:absolute;left:-9999px;top:-9999px;">';
		$out .= '<label>' . esc_html__( 'Zostaw to pole puste', 'mp-service-intake' )
			. '<input type="text" name="mp_hp" value="" tabindex="-1" autocomplete="off" /></label>';
		$out .= '</div>';
		$out .= '<input type="hidden" name="mp_ts" value="' . esc_attr( (string) time() ) . '" />';

		// Rodzaj sprawy.
		$out .= self::field_wrap(
			'kind',
			esc_html( $etykiety['kind'] ),
			self::kind_select( $kind ),
			$errors
		);

		// Kategoria produktu (P1.2 — pola zaleza od wyboru; brak wyboru = pola bazowe).
		$out .= self::field_wrap(
			'category',
			esc_html( $etykiety['category'] ),
			self::category_select( $category ),
			$errors
		);

		// Imie i nazwisko (zawsze). Bez tego pola nazwa konta WP schodzila do
		// e-maila (WP publikuje ja na stronie autora), a ochrona przed sklejeniem
		// dwoch osob pod wspolna skrzynka nie miala jak zadzialac — obie wady
		// mialy TEN SAM korzen: formularz nie pytal o osobe.
		$out .= self::field_wrap(
			'customer_name',
			esc_html( $etykiety['customer_name'] ),
			'<input type="text" id="mp-f-customer_name" name="customer_name" value="' . esc_attr( (string) ( $values['customer_name'] ?? '' ) ) . '" required maxlength="190" autocomplete="name" aria-describedby="' . self::err_id( 'customer_name' ) . '" />',
			$errors
		);

		// E-mail kontaktowy (zawsze).
		$out .= self::field_wrap(
			'email',
			esc_html( $etykiety['email'] ),
			'<input type="email" id="mp-f-email" name="email" value="' . esc_attr( (string) ( $values['email'] ?? '' ) ) . '" required aria-describedby="' . self::err_id( 'email' ) . '" />',
			$errors
		);

		// UNIA pol wszystkich rodzajow — kazde pole raz. `required` tylko dla pol
		// wybranego rodzaju; JS pokazuje wlasciwe i toggluje `required` na zmianie.
		// Serwer waliduje fields_for(kind) na submit (JS = progressive enhancement).
		foreach ( FormConfig::union_fields() as $field ) {
			$out .= self::render_field( $field, $values, $errors, $required_keys );
		}

		// Zalaczniki (JPG/PNG/WebP/PDF, do 5 plikow) — etykieta I wymagalnosc
		// zaleza od KATEGORII produktu (P1.2 ze specyfikacji). JS przelacza jedno
		// i drugie przy zmianie kategorii; serwer waliduje niezaleznie
		// (SubmissionHandler: bramka przed utworzeniem sprawy).
		$attachments = FormConfig::attachments_for( $category );

		$out .= self::field_wrap(
			'mp_files',
			esc_html( $attachments['label'] ),
			'<input type="file" id="mp-f-mp_files" name="mp_files[]" multiple accept=".jpg,.jpeg,.png,.webp,.pdf"'
				. ( $attachments['required'] ? ' required' : '' )
				. ' aria-describedby="' . self::err_id( 'mp_files' ) . '" />',
			$errors,
			'mp-f-mp_files'
		);

		// Zgoda RODO (wymagana) — pelny tekst zamrazany przy zapisie.
		$consent_err = isset( $errors['mp_consent'] )
			? '<span class="mp-intake-error" id="' . self::err_id( 'mp_consent' ) . '" role="alert">' . esc_html__( 'Zgoda jest wymagana, aby przyjąć zgłoszenie.', 'mp-service-intake' ) . '</span>'
			: '';
		$out        .= '<p class="mp-intake-field mp-intake-consent">';
		// 2.57: zgoda renderuje sie POZA `field_wrap` (ma inny uklad), wiec
		// `aria-invalid` trzeba tu dolozyc osobno. To wlasnie ONA jest polem, ktore
		// przy pustym formularzu zglasza sie jako jedyne — czyli najczestszy blad
		// tego formularza nie mowil czytnikowi ekranu nic przy samym polu.
		$consent_invalid = isset( $errors['mp_consent'] ) ? ' aria-invalid="true"' : '';
		// ⛔ Identyfikator MUSI byc ten sam, ktory wylicza `ctrl_id('mp_consent')` —
		// inaczej odsylacz z podsumowania prowadzi donikad, a to gorsze niz jego brak.
		$consent_id = self::ctrl_id( 'mp_consent' );
		$out       .= '<label for="' . esc_attr( $consent_id ) . '"><input type="checkbox" id="' . esc_attr( $consent_id ) . '" name="mp_consent" value="1" required' . $consent_invalid . ' aria-describedby="' . self::err_id( 'mp_consent' ) . '" /> '
			. esc_html( \MP\Intake\Consents::processing_text() ) . '</label>' . $consent_err;
		$out       .= '</p>';

		$out .= '<p class="mp-intake-hint">' . esc_html__( 'Wskazówka: nie podawaj w opisie danych osobowych innych osób.', 'mp-service-intake' ) . '</p>';
		$out .= '<button type="submit" class="mp-intake-submit">' . esc_html__( 'Wyślij zgłoszenie', 'mp-service-intake' ) . '</button>';
		$out .= '</form></div>';

		return $out;
	}

	/**
	 * Rejestruje i wpina skrypt dynamicznego formularza (raz na render).
	 *
	 * Config pol per rodzaj idzie czysto przez wp_localize_script (JSON w
	 * `window.mpIntakeForm`); JS TYLKO pokazuje/ukrywa pola i toggluje
	 * `required` — zero oslabienia walidacji serwerowej (fields_for(kind)
	 * waliduje na submit niezaleznie). Wersjonowanie przez `Assets::ver()` —
	 * wersja wtyczki PLUS znacznik czasu pliku, wiec poprawka samego skryptu
	 * dociera do przegladarek nawet bez podbicia wersji wtyczki (2.41).
	 *
	 * @return void
	 */
	private static function enqueue_assets(): void {
		static $done = false;

		if ( $done ) {
			return;
		}

		$done = true;

		self::enqueue_style();

		wp_enqueue_script(
			'mp-intake-form',
			plugin_dir_url( MP_INTAKE_FILE ) . 'assets/js/intake-form.js',
			array(),
			Assets::ver( 'assets/js/intake-form.js' ),
			true
		);

		wp_localize_script(
			'mp-intake-form',
			'mpIntakeForm',
			array(
				'kinds'              => FormConfig::kind_field_map(),
				'categories'         => FormConfig::category_field_map(),
				// P1.2: reguly zalacznika per kategoria + wariant „bez kategorii"
				// (JS musi umiec wrocic do stanu opcjonalnego, gdy klient cofnie
				// wybor na „— wybierz —").
				'attachments'        => FormConfig::category_attachment_map(),
				'attachmentsDefault' => FormConfig::attachments_for( '' ),
				'allFields'          => array_map(
					static function ( array $field ): string {
						return $field['key'];
					},
					FormConfig::union_fields()
				),
				// 2.57: napis stanu „trwa" idzie STAD, nie z kodu skryptu — reszta
				// tekstow tego modulu przechodzi przez tlumaczenie i ten nie moze byc
				// wyjatkiem, bo pokazuje sie klientowi.
				'sendingLabel'       => __( 'Wysyłanie…', 'mp-service-intake' ),
			)
		);
	}

	/**
	 * Wpina arkusz stylu frontu Intake (formularz + panel klienta).
	 *
	 * Wspoldzielony przez FormRenderer (formularz) i AccountPage (panel) —
	 * jeden handle, wp_enqueue_style idempotentne. Wersjonowanie przez
	 * `Assets::ver()` (wersja wtyczki + znacznik czasu pliku, 2.41) — korzysta
	 * z tego takze panel klienta, ktory wola te metode. Sam wyglad, zero logiki.
	 *
	 * @return void
	 */
	public static function enqueue_style(): void {
		wp_enqueue_style(
			'mp-intake',
			plugin_dir_url( MP_INTAKE_FILE ) . 'assets/css/intake.css',
			array(),
			Assets::ver( 'assets/css/intake.css' )
		);
	}

	/**
	 * Render pojedynczego pola wg definicji FormConfig.
	 *
	 * @param array{key: string, label: string, type: string, required: bool, pii_sensitive: bool} $field         Definicja.
	 * @param array<string, mixed>                                                                 $values        Wartosci.
	 * @param array<string, string>                                                                $errors        Kody bledow per pole.
	 * @param array<int, string>                                                                   $required_keys Klucze wymagane dla WYBRANEGO rodzaju (reszta bez `required`).
	 * @return string
	 */
	private static function render_field( array $field, array $values, array $errors, array $required_keys ): string {
		$key      = $field['key'];
		$id       = 'mp-f-' . preg_replace( '/[^a-z0-9_]/', '', $key );
		$value    = (string) ( $values[ $key ] ?? '' );
		$required = in_array( $key, $required_keys, true ) ? ' required' : '';
		$descr    = ' aria-describedby="' . self::err_id( $key ) . '"';

		// `maxlength` = ta sama granica co w Validatorze, tylko podana od razu
		// w przegladarce: klient widzi limit PISZAC, zamiast stracic dlugi tekst
		// przy wysylce. Serwer i tak sprawdza po swojemu (to jest tylko wygoda).
		$limit  = Validator::limit_znakow( (string) $field['type'] );
		$maxlen = $limit > 0 ? ' maxlength="' . esc_attr( (string) $limit ) . '"' : '';

		if ( 'textarea' === $field['type'] ) {
			$control = '<textarea id="' . esc_attr( $id ) . '" name="' . esc_attr( $key ) . '" rows="4"' . $maxlen . $required . $descr . '>' . esc_textarea( $value ) . '</textarea>';
		} else {
			$html_type = self::html_input_type( $field['type'] );
			$control   = '<input type="' . esc_attr( $html_type ) . '" id="' . esc_attr( $id ) . '" name="' . esc_attr( $key ) . '" value="' . esc_attr( $value ) . '"' . $maxlen . $required . $descr . ' />';
		}

		return self::field_wrap( $key, esc_html( $field['label'] ), $control, $errors, $id );
	}

	/**
	 * Opakowuje pole w <label> + komunikat bledu (WCAG-lite).
	 *
	 * @param string                $key     Klucz pola.
	 * @param string                $label   Etykieta (juz zescapowana).
	 * @param string                $control HTML kontrolki.
	 * @param array<string, string> $errors  Kody bledow per pole.
	 * @param string                $for_id  Id kontrolki dla atrybutu for.
	 * @return string
	 */
	private static function field_wrap( string $key, string $label, string $control, array $errors, string $for_id = '' ): string {
		$for_id = '' === $for_id ? self::ctrl_id( $key ) : $for_id;
		$out    = '<p class="mp-intake-field mp-intake-field-' . esc_attr( $key ) . '" data-mp-field="' . esc_attr( $key ) . '">';
		$out   .= '<label for="' . esc_attr( $for_id ) . '">' . $label . '</label>';

		// 2.57: pole z bledem MUSI byc oznaczone dla czytnika ekranu, nie tylko
		// wizualnie. Jedno miejsce dla wszystkich pol — patrz `mark_invalid`.
		$out .= isset( $errors[ $key ] ) ? self::mark_invalid( $control ) : $control;

		if ( isset( $errors[ $key ] ) ) {
			$out .= '<span class="mp-intake-error" id="' . self::err_id( $key ) . '" role="alert">'
				. esc_html( self::error_text( (string) $errors[ $key ] ) ) . '</span>';
		}

		$out .= '</p>';

		return $out;
	}

	/**
	 * Select rodzaju sprawy.
	 *
	 * @param string $selected Wybrany rodzaj.
	 * @return string
	 */
	private static function kind_select( string $selected ): string {
		$labels = FormConfig::kind_labels();

		$out = '<select id="mp-f-kind" name="kind">';

		foreach ( FormConfig::KINDS as $kind ) {
			$out .= '<option value="' . esc_attr( $kind ) . '"' . selected( $selected, $kind, false ) . '>'
				. esc_html( $labels[ $kind ] ?? $kind ) . '</option>';
		}

		return $out . '</select>';
	}

	/**
	 * Select kategorii produktu (P1.2). Pusty wybor = pola bazowe (fallback).
	 *
	 * @param string $selected Wybrana kategoria (slug).
	 * @return string
	 */
	private static function category_select( string $selected ): string {
		$out  = '<select id="mp-f-category" name="category">';
		$out .= '<option value="">' . esc_html__( '— wybierz kategorię —', 'mp-service-intake' ) . '</option>';

		foreach ( FormConfig::categories() as $slug => $label ) {
			$out .= '<option value="' . esc_attr( (string) $slug ) . '"' . selected( $selected, $slug, false ) . '>'
				. esc_html( (string) $label ) . '</option>';
		}

		return $out . '</select>';
	}

	/**
	 * Mapuje typ pola FormConfig na typ inputu HTML.
	 *
	 * @param string $type Typ pola.
	 * @return string
	 */
	private static function html_input_type( string $type ): string {
		switch ( $type ) {
			case 'date':
				return 'date';
			case 'email':
				return 'email';
			case 'tel':
				return 'tel';
			default:
				return 'text';
		}
	}

	/**
	 * Id komunikatu bledu pola (dla aria-describedby).
	 *
	 * @param string $key Klucz pola.
	 * @return string
	 */
	private static function err_id( string $key ): string {
		return 'mp-err-' . preg_replace( '/[^a-z0-9_]/', '', $key );
	}

	/**
	 * Identyfikator KONTROLKI pola — ten sam, ktorego uzywa `field_wrap` w `for`.
	 *
	 * Osobna metoda, bo do tego samego identyfikatora odsyla teraz takze
	 * podsumowanie bledow; dwie kopie tego wyrazenia rozjechalyby sie przy
	 * pierwszej zmianie i odsylacz prowadzilby donikad.
	 *
	 * @param string $key Klucz pola.
	 * @return string
	 */
	private static function ctrl_id( string $key ): string {
		return 'mp-f-' . preg_replace( '/[^a-z0-9_]/', '', $key );
	}

	/**
	 * Etykiety pol — JEDNO zrodlo dla formularza i dla podsumowania bledow.
	 *
	 * ⛔ Nie powielaj tych napisow w `render()`. Podsumowanie odsyla czlowieka do
	 * pola PO NAZWIE, wiec gdy nazwa w jednym miejscu sie zmieni, a w drugim nie,
	 * odsylacz zaczyna klamac — a to gorsze niz brak odsylacza.
	 *
	 * @return array<string, string>
	 */
	private static function field_labels(): array {
		$mapa = array(
			'kind'          => __( 'Rodzaj zgłoszenia', 'mp-service-intake' ),
			'category'      => __( 'Kategoria produktu', 'mp-service-intake' ),
			'customer_name' => __( 'Imię i nazwisko', 'mp-service-intake' ),
			'email'         => __( 'Twój e-mail', 'mp-service-intake' ),
			'mp_files'      => __( 'Załączniki', 'mp-service-intake' ),
			'mp_consent'    => __( 'Zgoda na przetwarzanie danych', 'mp-service-intake' ),
		);

		foreach ( FormConfig::union_fields() as $field ) {
			$mapa[ (string) $field['key'] ] = (string) $field['label'];
		}

		return $mapa;
	}

	/**
	 * Podsumowanie bledow z ODSYLACZAMI do pol (audyt 2.57).
	 *
	 * ⭐ CO PRODUKT ROBIL DOBRZE I ZOSTAJE NIETKNIETE: komunikat ma `role="alert"`,
	 * jest ogloszony, a skrypt `intake-form.js` PRZENOSI NA NIEGO FOKUS po powrocie
	 * strony — bo obszar `aria-live` nie oglasza tresci obecnej juz przy wczytaniu.
	 * Dzial audytu ten zarzut WYCOFAL i nazwal to mocna strona; nie ruszamy tego.
	 *
	 * Brakowalo drugiej polowy: podsumowanie bylo zwyklym akapitem BEZ listy
	 * i bez odsylaczy, wiec czlowiek slyszal „popraw zaznaczone pola" i musial
	 * sam znalezc, ktore. Teraz kazdy blad to odsylacz prowadzacy WPROST do pola.
	 *
	 * @param array<string, string> $errors Bledy: klucz pola => kod bledu.
	 * @return string
	 */
	private static function error_summary( array $errors ): string {
		if ( array() === $errors ) {
			return '';
		}

		$etykiety = self::field_labels();

		$out  = '<div class="mp-intake-error-summary" role="alert">';
		$out .= '<p>' . esc_html(
			_n(
				'Formularz zawiera błąd — popraw pole wskazane poniżej.',
				'Formularz zawiera błędy — popraw pola wskazane poniżej.',
				count( $errors ),
				'mp-service-intake'
			)
		) . '</p>';
		$out .= '<ul>';

		foreach ( $errors as $key => $kod ) {
			$key       = (string) $key;
			$etykieta  = $etykiety[ $key ] ?? $key;
			$komunikat = self::error_text( (string) $kod );

			$out .= '<li><a href="#' . esc_attr( self::ctrl_id( $key ) ) . '">'
				. esc_html( $etykieta ) . '</a>: ' . esc_html( $komunikat ) . '</li>';
		}

		$out .= '</ul></div>';

		return $out;
	}

	/**
	 * Dokleja `aria-invalid="true"` do kontrolki pola, ktore ma blad (audyt 2.57).
	 *
	 * ⛔ `aria-invalid` nie wystepowal w module ANI RAZU — sprawdzone z proba
	 * kontrolna (inne atrybuty `aria-` w tym pliku sa, wiec szukanie je widzi).
	 * Skutek: czytnik ekranu oglaszal podsumowanie, ale przy samym polu nie mowil
	 * nic — osoba przechodzaca tabulatorem musiala zgadywac, ktore poprawic.
	 *
	 * Robimy to w JEDNYM miejscu, przez ktore przechodza WSZYSTKIE pola, zamiast
	 * dopisywac atrybut przy kazdej kontrolce z osobna — inaczej pierwsze nowe
	 * pole znowu by go nie mialo.
	 *
	 * @param string $control Gotowy HTML kontrolki.
	 * @return string
	 */
	private static function mark_invalid( string $control ): string {
		return (string) preg_replace(
			'/^(\s*<(?:input|select|textarea)\b)/i',
			'$1 aria-invalid="true"',
			$control,
			1
		);
	}

	/**
	 * Tlumaczy kod bledu na komunikat PL (czysta funkcja).
	 *
	 * @param string $code Kod z Validatora.
	 * @return string
	 */
	public static function error_text( string $code ): string {
		$map = array(
			'REQUIRED'            => __( 'To pole jest wymagane.', 'mp-service-intake' ),
			'INVALID_EMAIL'       => __( 'Podaj poprawny adres e-mail.', 'mp-service-intake' ),
			'DATE_INVALID'        => __( 'Podaj datę w formacie RRRR-MM-DD.', 'mp-service-intake' ),
			'DATE_FUTURE'         => __( 'Data zakupu nie może być z przyszłości.', 'mp-service-intake' ),
			'DATE_TOO_OLD'        => __( 'Data zakupu jest zbyt odległa — sprawdź ją.', 'mp-service-intake' ),
			'SERIAL_INVALID'      => __( 'Numer seryjny wygląda nieprawidłowo.', 'mp-service-intake' ),
			'DOCUMENT_INVALID'    => __( 'Numer dokumentu wygląda nieprawidłowo.', 'mp-service-intake' ),
			'INVALID_TEL'         => __( 'Podaj poprawny numer telefonu.', 'mp-service-intake' ),
			'KIND_INVALID'        => __( 'Wybierz poprawny rodzaj zgłoszenia.', 'mp-service-intake' ),
			'TOO_LONG'            => __( 'Ten tekst jest za długi — skróć go i wyślij ponownie.', 'mp-service-intake' ),
			// P1.2: obejmuje OBA przypadki — brak pliku i plik odrzucony (za duży
			// albo w innym formacie). Klient nie zgaduje, dlaczego nie przeszło.
			'ATTACHMENT_REQUIRED' => __( 'Do wybranej kategorii trzeba dołączyć załącznik: JPG, PNG, WebP lub PDF. Plik w innym formacie albo za duży nie został przyjęty.', 'mp-service-intake' ),
		);

		return $map[ $code ] ?? __( 'Popraw to pole.', 'mp-service-intake' );
	}
}
