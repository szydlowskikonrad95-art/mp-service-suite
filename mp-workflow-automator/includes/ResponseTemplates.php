<?php
/**
 * Szablony odpowiedzi per RODZAJ sprawy (P3.5) — personel wybiera szablon
 * odpowiadajac klientowi. Opcja-tresc konfigurowalna (admin_post, capability
 * system-admin + nonce, BEZ menu). Markery podmieniane z kontekstu sprawy;
 * WHITELIST markerow jest WIDOCZNA (markers_whitelist) — admin wie co wstawic,
 * nie wpisze martwego `{{klient}}`.
 *
 * ⚠️ BEZPIECZENSTWO: render zwraca PLAIN-TEXT; wartosci markerow BEZ CR/LF.
 * JESLI kiedys tresc pojdzie jako HTML — wartosci MUSZA przejsc esc_html() w
 * `markers()`, inaczej marker z danych klienta = XSS.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Definicje, konfiguracja i render szablonow odpowiedzi.
 */
final class ResponseTemplates {

	/**
	 * Opcja-tresc: rodzaj => lista {key, label, body}.
	 */
	public const OPTION = 'mp_automator_response_templates';

	/**
	 * Akcja admin-post konfiguracji (capability system-admin).
	 */
	public const ACTION_CONFIG = 'mp_automator_response_config';

	/**
	 * Dozwolone rodzaje spraw (rdzen FormConfig::KINDS z C — kopia stala).
	 *
	 * @var array<int, string>
	 */
	private const KINDS_ALLOWED = array( 'reklamacja', 'naprawa', 'zapytanie', 'zwrot' );

	/**
	 * Rejestruje handler konfiguracji (priv I nopriv => jawne 403).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
		add_action( 'admin_post_nopriv_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
	}

	/**
	 * WHITELIST markerow WIDOCZNA adminowi: marker => opis. Tylko te sa
	 * podmieniane w render(); inne zostaja doslownie (admin widzi liste).
	 *
	 * @return array<string, string>
	 */
	public static function markers_whitelist(): array {
		return array(
			'{{numer_sprawy}}' => __( 'Numer sprawy (SRV/RRRR/NNNN)', 'mp-workflow-automator' ),
			'{{status}}'       => __( 'Aktualny status sprawy', 'mp-workflow-automator' ),
			'{{rodzaj}}'       => __( 'Rodzaj sprawy', 'mp-workflow-automator' ),
			'{{data}}'         => __( 'Bieżąca data', 'mp-workflow-automator' ),
		);
	}

	/**
	 * Domyslne szablony odpowiedzi per rodzaj (admin moze nadpisac).
	 *
	 * @return array<string, array<int, array{key: string, label: string, body: string}>>
	 */
	public static function defaults(): array {
		return array(
			'reklamacja' => array(
				array(
					'key'   => 'przyjecie',
					'label' => 'Potwierdzenie przyjęcia reklamacji',
					'body'  => "Dzień dobry,\n\nPotwierdzamy przyjęcie reklamacji {{numer_sprawy}}. Status: {{status}}. Poinformujemy o decyzji.\n\nData: {{data}}",
				),
				array(
					'key'   => 'decyzja_odmowna',
					'label' => 'Reklamacja nieuznana',
					'body'  => "Dzień dobry,\n\nPo analizie reklamacji {{numer_sprawy}} informujemy, że nie może zostać uznana. Szczegóły w panelu sprawy.\n\nData: {{data}}",
				),
			),
			'naprawa'    => array(
				array(
					'key'   => 'wycena',
					'label' => 'Wycena naprawy do akceptacji',
					'body'  => "Dzień dobry,\n\nPrzygotowaliśmy wycenę naprawy dla zgłoszenia {{numer_sprawy}}. Prosimy o akceptację, aby przejść do realizacji.\n\nData: {{data}}",
				),
				array(
					'key'   => 'gotowe',
					'label' => 'Naprawa zakończona',
					'body'  => "Dzień dobry,\n\nNaprawa w zgłoszeniu {{numer_sprawy}} została zakończona (status: {{status}}).\n\nData: {{data}}",
				),
			),
			'zapytanie'  => array(
				array(
					'key'   => 'odpowiedz',
					'label' => 'Odpowiedź na zapytanie',
					'body'  => "Dzień dobry,\n\nW odpowiedzi na zapytanie {{numer_sprawy}} przesyłamy informacje. Szczegóły w panelu sprawy.\n\nData: {{data}}",
				),
			),
			'zwrot'      => array(
				array(
					'key'   => 'zaakceptowany',
					'label' => 'Zwrot zaakceptowany',
					'body'  => "Dzień dobry,\n\nZwrot {{numer_sprawy}} został zaakceptowany. Środki zwrócimy zgodnie z regulaminem.\n\nData: {{data}}",
				),
			),
		);
	}

	/**
	 * Wszystkie szablony (opcja nadpisuje domyslne per rodzaj).
	 *
	 * @return array<string, array<int, array{key: string, label: string, body: string}>>
	 */
	public static function all(): array {
		$stored = get_option( self::OPTION, array() );
		$out    = self::defaults();

		if ( is_array( $stored ) ) {
			foreach ( $stored as $kind => $tpls ) {
				$clean = self::sanitize_templates( $tpls );

				if ( array() !== $clean ) {
					$out[ (string) $kind ] = $clean;
				}
			}
		}

		return $out;
	}

	/**
	 * Szablony dla rodzaju (pusta lista gdy nieznany).
	 *
	 * @param string $kind Rodzaj sprawy.
	 * @return array<int, array{key: string, label: string, body: string}>
	 */
	public static function for_kind( string $kind ): array {
		$all = self::all();

		return isset( $all[ $kind ] ) ? $all[ $kind ] : array();
	}

	/**
	 * Jeden szablon (rodzaj + klucz). Null gdy nieznany.
	 *
	 * @param string $kind Rodzaj sprawy.
	 * @param string $key  Klucz szablonu.
	 * @return array{key: string, label: string, body: string}|null
	 */
	public static function get( string $kind, string $key ): ?array {
		foreach ( self::for_kind( $kind ) as $tpl ) {
			if ( $tpl['key'] === $key ) {
				return $tpl;
			}
		}

		return null;
	}

	/**
	 * Renderuje szablon: podmienia WYLACZNIE markery z whitelist wartosciami z
	 * kontekstu sprawy (mp_case_get_context). Null gdy szablonu nie ma.
	 *
	 * @param string               $kind Rodzaj sprawy.
	 * @param string               $key  Klucz szablonu.
	 * @param array<string, mixed> $ctx  Kontekst sprawy.
	 * @return string|null
	 */
	public static function render( string $kind, string $key, array $ctx ): ?string {
		$tpl = self::get( $kind, $key );

		if ( null === $tpl ) {
			return null;
		}

		return strtr( $tpl['body'], self::markers( $ctx ) );
	}

	/**
	 * Mapa marker => wartosc (plain-text, bez CR/LF). Data w strefie witryny.
	 *
	 * @param array<string, mixed> $ctx Kontekst sprawy.
	 * @return array<string, string>
	 */
	private static function markers( array $ctx ): array {
		$strip = static function ( $value ): string {
			return trim( (string) preg_replace( '/[\r\n]+/', ' ', (string) $value ) );
		};

		return array(
			'{{numer_sprawy}}' => $strip( $ctx['case_number'] ?? '' ),
			'{{status}}'       => $strip( $ctx['status'] ?? '' ),
			'{{rodzaj}}'       => $strip( $ctx['rodzaj'] ?? '' ),
			'{{data}}'         => $strip( wp_date( 'Y-m-d H:i' ) ),
		);
	}

	/**
	 * Sanityzuje liste szablonow (key maszynowy, label+body tekstowe; dedup key).
	 *
	 * @param mixed $tpls Surowa lista.
	 * @return array<int, array{key: string, label: string, body: string}>
	 */
	private static function sanitize_templates( $tpls ): array {
		if ( ! is_array( $tpls ) ) {
			return array();
		}

		$out  = array();
		$seen = array();

		foreach ( $tpls as $tpl ) {
			if ( ! is_array( $tpl ) || ! isset( $tpl['key'], $tpl['label'], $tpl['body'] ) ) {
				continue;
			}

			$key   = sanitize_key( (string) $tpl['key'] );
			$label = sanitize_text_field( (string) $tpl['label'] );
			$body  = sanitize_textarea_field( (string) $tpl['body'] );

			if ( '' === $key || '' === $label || '' === $body || isset( $seen[ $key ] ) ) {
				continue;
			}

			$seen[ $key ] = true;
			$out[]        = array(
				'key'   => $key,
				'label' => $label,
				'body'  => $body,
			);
		}

		return $out;
	}

	/**
	 * Handler konfiguracji: capability system-admin PIERWSZA => 403; nonce;
	 * payload JSON {rodzaj: [{key,label,body}, ...]} => walidacja + sanityzacja =>
	 * zapis. Audyt CONFIG_CHANGED.
	 *
	 * @return void
	 */
	public static function handle_config(): void {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die(
				esc_html__( 'Brak uprawnień do konfiguracji szablonów.', 'mp-workflow-automator' ),
				'',
				array( 'response' => 403 )
			);
		}

		check_admin_referer( self::ACTION_CONFIG );

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$raw     = isset( $_POST['payload'] ) ? sanitize_textarea_field( wp_unslash( $_POST['payload'] ) ) : '';
		$decoded = json_decode( $raw, true );
		$out     = array();

		if ( is_array( $decoded ) ) {
			foreach ( $decoded as $kind => $tpls ) {
				$kind = sanitize_key( (string) $kind );

				if ( ! in_array( $kind, self::KINDS_ALLOWED, true ) ) {
					continue;
				}

				$clean = self::sanitize_templates( $tpls );

				if ( array() !== $clean ) {
					$out[ $kind ] = $clean;
				}
			}
		}

		update_option( self::OPTION, $out, false );

		WorkflowEvents::log(
			WorkflowEvents::CONFIG_CHANGED,
			array(
				'object' => 'response_templates',
				'kinds'  => array_keys( $out ),
			),
			null,
			get_current_user_id()
		);

		$back = wp_get_referer();
		wp_safe_redirect( false !== $back ? $back : admin_url() );
		exit;
	}
}
