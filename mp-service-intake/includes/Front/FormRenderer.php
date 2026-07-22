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

use MP\Intake\FormConfig;

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

		// Warstwa kliencka: skrypt dynamicznego formularza + config pol per rodzaj.
		self::enqueue_assets();

		// Klucze WYMAGANE dla wybranego rodzaju (reszta unii pol renderowana bez
		// `required` — JS ukrywa je i toggluje `required` przy zmianie rodzaju).
		$required_keys = array();
		foreach ( FormConfig::fields_for( $kind ) as $field ) {
			if ( $field['required'] ) {
				$required_keys[] = $field['key'];
			}
		}

		$out  = '<div class="mp-intake">';
		$out .= '<h2>' . esc_html__( 'Zgłoszenie serwisowe', 'mp-service-intake' ) . '</h2>';

		if ( '' !== $notice ) {
			$out .= '<p class="mp-intake-notice" role="status">' . esc_html( $notice ) . '</p>';
		}

		if ( array() !== $errors ) {
			$out .= '<p class="mp-intake-error-summary" role="alert">'
				. esc_html__( 'Formularz zawiera błędy — popraw zaznaczone pola.', 'mp-service-intake' )
				. '</p>';
		}

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
			esc_html__( 'Rodzaj zgłoszenia', 'mp-service-intake' ),
			self::kind_select( $kind ),
			$errors
		);

		// E-mail kontaktowy (zawsze).
		$out .= self::field_wrap(
			'email',
			esc_html__( 'Twój e-mail', 'mp-service-intake' ),
			'<input type="email" id="mp-f-email" name="email" value="' . esc_attr( (string) ( $values['email'] ?? '' ) ) . '" required aria-describedby="' . self::err_id( 'email' ) . '" />',
			$errors
		);

		// UNIA pol wszystkich rodzajow — kazde pole raz. `required` tylko dla pol
		// wybranego rodzaju; JS pokazuje wlasciwe i toggluje `required` na zmianie.
		// Serwer waliduje fields_for(kind) na submit (JS = progressive enhancement).
		foreach ( FormConfig::union_fields() as $field ) {
			$out .= self::render_field( $field, $values, $errors, $required_keys );
		}

		// Zalaczniki (opcjonalne): JPG/PNG/WebP/PDF, do 5 plikow.
		$out .= self::field_wrap(
			'mp_files',
			esc_html__( 'Załączniki (opcjonalnie: zdjęcia, PDF — do 5 plików)', 'mp-service-intake' ),
			'<input type="file" id="mp-f-mp_files" name="mp_files[]" multiple accept=".jpg,.jpeg,.png,.webp,.pdf" />',
			$errors,
			'mp-f-mp_files'
		);

		// Zgoda RODO (wymagana) — pelny tekst zamrazany przy zapisie.
		$consent_err = isset( $errors['mp_consent'] )
			? '<span class="mp-intake-error" id="' . self::err_id( 'mp_consent' ) . '" role="alert">' . esc_html__( 'Zgoda jest wymagana, aby przyjąć zgłoszenie.', 'mp-service-intake' ) . '</span>'
			: '';
		$out        .= '<p class="mp-intake-field mp-intake-consent">';
		$out        .= '<label for="mp-f-consent"><input type="checkbox" id="mp-f-consent" name="mp_consent" value="1" required aria-describedby="' . self::err_id( 'mp_consent' ) . '" /> '
			. esc_html( \MP\Intake\Consents::processing_text() ) . '</label>' . $consent_err;
		$out        .= '</p>';

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
	 * waliduje na submit niezaleznie). Wersjonowanie po MP_INTAKE_VERSION
	 * (bump wersji = nowy ?ver — uniknij starego cache).
	 *
	 * @return void
	 */
	private static function enqueue_assets(): void {
		static $done = false;

		if ( $done ) {
			return;
		}

		$done = true;

		wp_enqueue_script(
			'mp-intake-form',
			plugin_dir_url( MP_INTAKE_FILE ) . 'assets/js/intake-form.js',
			array(),
			MP_INTAKE_VERSION,
			true
		);

		wp_localize_script(
			'mp-intake-form',
			'mpIntakeForm',
			array(
				'kinds'     => FormConfig::kind_field_map(),
				'allFields' => array_map(
					static function ( array $field ): string {
						return $field['key'];
					},
					FormConfig::union_fields()
				),
			)
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

		if ( 'textarea' === $field['type'] ) {
			$control = '<textarea id="' . esc_attr( $id ) . '" name="' . esc_attr( $key ) . '" rows="4"' . $required . $descr . '>' . esc_textarea( $value ) . '</textarea>';
		} else {
			$html_type = self::html_input_type( $field['type'] );
			$control   = '<input type="' . esc_attr( $html_type ) . '" id="' . esc_attr( $id ) . '" name="' . esc_attr( $key ) . '" value="' . esc_attr( $value ) . '"' . $required . $descr . ' />';
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
		$for_id = '' === $for_id ? 'mp-f-' . preg_replace( '/[^a-z0-9_]/', '', $key ) : $for_id;
		$out    = '<p class="mp-intake-field mp-intake-field-' . esc_attr( $key ) . '" data-mp-field="' . esc_attr( $key ) . '">';
		$out   .= '<label for="' . esc_attr( $for_id ) . '">' . $label . '</label>';
		$out   .= $control;

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
		$labels = array(
			'reklamacja' => __( 'Reklamacja', 'mp-service-intake' ),
			'naprawa'    => __( 'Naprawa', 'mp-service-intake' ),
			'zapytanie'  => __( 'Zapytanie', 'mp-service-intake' ),
			'zwrot'      => __( 'Zwrot', 'mp-service-intake' ),
		);

		$out = '<select id="mp-f-kind" name="kind">';

		foreach ( FormConfig::KINDS as $kind ) {
			$out .= '<option value="' . esc_attr( $kind ) . '"' . selected( $selected, $kind, false ) . '>'
				. esc_html( $labels[ $kind ] ) . '</option>';
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
	 * Tlumaczy kod bledu na komunikat PL (czysta funkcja).
	 *
	 * @param string $code Kod z Validatora.
	 * @return string
	 */
	public static function error_text( string $code ): string {
		$map = array(
			'REQUIRED'         => __( 'To pole jest wymagane.', 'mp-service-intake' ),
			'INVALID_EMAIL'    => __( 'Podaj poprawny adres e-mail.', 'mp-service-intake' ),
			'DATE_INVALID'     => __( 'Podaj datę w formacie RRRR-MM-DD.', 'mp-service-intake' ),
			'DATE_FUTURE'      => __( 'Data zakupu nie może być z przyszłości.', 'mp-service-intake' ),
			'DATE_TOO_OLD'     => __( 'Data zakupu jest zbyt odległa — sprawdź ją.', 'mp-service-intake' ),
			'SERIAL_INVALID'   => __( 'Numer seryjny wygląda nieprawidłowo.', 'mp-service-intake' ),
			'DOCUMENT_INVALID' => __( 'Numer dokumentu wygląda nieprawidłowo.', 'mp-service-intake' ),
			'INVALID_TEL'      => __( 'Podaj poprawny numer telefonu.', 'mp-service-intake' ),
			'KIND_INVALID'     => __( 'Wybierz poprawny rodzaj zgłoszenia.', 'mp-service-intake' ),
		);

		return $map[ $code ] ?? __( 'Popraw to pole.', 'mp-service-intake' );
	}
}
