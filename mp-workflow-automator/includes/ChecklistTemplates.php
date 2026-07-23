<?php
/**
 * Szablony checklist per RODZAJ sprawy (P3.5) — opcja-tresc konfigurowalna.
 *
 * Szablon = lista krokow {key, label} per rodzaj (reklamacja/naprawa/zapytanie/
 * zwrot). `template_id` = rodzaj sprawy (checklista dobierana do rodzaju). Stan
 * odhaczen zyje w `case_checklists` (klasa Checklists) — tu tylko DEFINICJA.
 * Konfiguracja = backend-handler-only (admin_post, capability system-admin +
 * nonce), BEZ menu — panel admina D podepnie przycisk pozniej.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Definicje i konfiguracja szablonow checklist.
 */
final class ChecklistTemplates {

	/**
	 * Opcja-tresc: rodzaj => lista {key, label}.
	 */
	public const OPTION = 'mp_automator_checklist_templates';

	/**
	 * Akcja admin-post konfiguracji szablonow (capability system-admin).
	 */
	public const ACTION_CONFIG = 'mp_automator_checklist_config';

	/**
	 * Rejestruje handler konfiguracji (priv I nopriv => jawne 403 dla nieuprawnionych).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
		add_action( 'admin_post_nopriv_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
	}

	/**
	 * Domyslne szablony checklist per rodzaj (seed pierwszej instalacji; admin
	 * moze nadpisac przez konfiguracje). Klucze = maszynowe (sanitize_key).
	 *
	 * @return array<string, array<int, array{key: string, label: string}>>
	 */
	public static function defaults(): array {
		return array(
			'reklamacja' => array(
				array(
					'key'   => 'zebranie_danych',
					'label' => 'Zebranie danych zgłoszenia',
				),
				array(
					'key'   => 'ocena_gwarancji',
					'label' => 'Ocena zasadności i gwarancji',
				),
				array(
					'key'   => 'kontakt_klient',
					'label' => 'Kontakt z klientem',
				),
				array(
					'key'   => 'decyzja',
					'label' => 'Decyzja i odpowiedź do klienta',
				),
			),
			'naprawa'    => array(
				array(
					'key'   => 'diagnoza',
					'label' => 'Diagnoza usterki',
				),
				array(
					'key'   => 'wycena',
					'label' => 'Wycena naprawy',
				),
				array(
					'key'   => 'akceptacja',
					'label' => 'Akceptacja kosztów przez klienta',
				),
				array(
					'key'   => 'realizacja',
					'label' => 'Realizacja naprawy',
				),
			),
			'zapytanie'  => array(
				array(
					'key'   => 'analiza',
					'label' => 'Analiza zapytania',
				),
				array(
					'key'   => 'odpowiedz',
					'label' => 'Przygotowanie i wysłanie odpowiedzi',
				),
			),
			'zwrot'      => array(
				array(
					'key'   => 'weryfikacja',
					'label' => 'Weryfikacja warunków zwrotu',
				),
				array(
					'key'   => 'odbior',
					'label' => 'Odbiór produktu',
				),
				array(
					'key'   => 'zwrot_srodkow',
					'label' => 'Zwrot środków',
				),
			),
		);
	}

	/**
	 * Wszystkie szablony (opcja nadpisuje domyslne per rodzaj).
	 *
	 * @return array<string, array<int, array{key: string, label: string}>>
	 */
	public static function all(): array {
		$stored = get_option( self::OPTION, array() );
		$out    = self::defaults();

		if ( is_array( $stored ) ) {
			foreach ( $stored as $kind => $steps ) {
				$clean = self::sanitize_steps( $steps );

				if ( array() !== $clean ) {
					$out[ (string) $kind ] = $clean;
				}
			}
		}

		return $out;
	}

	/**
	 * Kroki checklisty dla rodzaju (pusta lista gdy nieznany).
	 *
	 * @param string $kind Rodzaj sprawy.
	 * @return array<int, array{key: string, label: string}>
	 */
	public static function for_kind( string $kind ): array {
		$all = self::all();

		return isset( $all[ $kind ] ) ? $all[ $kind ] : array();
	}

	/**
	 * Etykieta kroku dla rodzaju (zamrazana przy odhaczeniu). '' gdy krok obcy.
	 *
	 * @param string $kind     Rodzaj sprawy.
	 * @param string $step_key Klucz kroku.
	 * @return string
	 */
	public static function step_label( string $kind, string $step_key ): string {
		foreach ( self::for_kind( $kind ) as $step ) {
			if ( $step['key'] === $step_key ) {
				return $step['label'];
			}
		}

		return '';
	}

	/**
	 * Sanityzuje liste krokow (klucz maszynowy + etykieta tekstowa; dedup kluczy).
	 *
	 * @param mixed $steps Surowa lista krokow.
	 * @return array<int, array{key: string, label: string}>
	 */
	private static function sanitize_steps( $steps ): array {
		if ( ! is_array( $steps ) ) {
			return array();
		}

		$out  = array();
		$seen = array();

		foreach ( $steps as $step ) {
			if ( ! is_array( $step ) || ! isset( $step['key'], $step['label'] ) ) {
				continue;
			}

			$key   = sanitize_key( (string) $step['key'] );
			$label = sanitize_text_field( (string) $step['label'] );

			if ( '' === $key || '' === $label || isset( $seen[ $key ] ) ) {
				continue;
			}

			$seen[ $key ] = true;
			$out[]        = array(
				'key'   => $key,
				'label' => $label,
			);
		}

		return $out;
	}

	/**
	 * Handler konfiguracji: capability system-admin PIERWSZA => jawne 403; nonce;
	 * payload JSON {rodzaj: [{key,label}, ...]} => walidacja rodzaju + sanityzacja
	 * krokow => zapis do opcji. Audyt CONFIG_CHANGED.
	 *
	 * @return void
	 */
	public static function handle_config(): void {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die(
				esc_html__( 'Brak uprawnień do konfiguracji checklist.', 'mp-workflow-automator' ),
				'',
				array( 'response' => 403 )
			);
		}

		check_admin_referer( self::ACTION_CONFIG );

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$raw     = isset( $_POST['payload'] ) ? sanitize_textarea_field( wp_unslash( $_POST['payload'] ) ) : '';
		$decoded = json_decode( $raw, true );
		$valid   = self::KINDS_ALLOWED;
		$out     = array();

		if ( is_array( $decoded ) ) {
			foreach ( $decoded as $kind => $steps ) {
				$kind = sanitize_key( (string) $kind );

				if ( ! in_array( $kind, $valid, true ) ) {
					continue;
				}

				$clean = self::sanitize_steps( $steps );

				if ( array() !== $clean ) {
					$out[ $kind ] = $clean;
				}
			}
		}

		update_option( self::OPTION, $out, false );

		WorkflowEvents::log(
			WorkflowEvents::CONFIG_CHANGED,
			array(
				'object' => 'checklist_templates',
				'kinds'  => array_keys( $out ),
			),
			null,
			get_current_user_id()
		);

		self::redirect_ok();
	}

	/**
	 * Dozwolone rodzaje spraw (rdzen FormConfig::KINDS z C — kopia stala, D nie
	 * czyta klasy C przez linter cudzych; zmiana rzadka).
	 *
	 * @var array<int, string>
	 */
	private const KINDS_ALLOWED = array( 'reklamacja', 'naprawa', 'zapytanie', 'zwrot' );

	/**
	 * Powrot po zapisie (PRG) — na referer albo panel admina.
	 *
	 * @return never
	 */
	private static function redirect_ok(): void {
		$back = wp_get_referer();
		wp_safe_redirect( false !== $back ? $back : admin_url() );
		exit;
	}
}
