<?php
/**
 * Szablony maili powiadomien (P3.3) — opcja-tresc (warstwa ii uninstalla).
 *
 * Szablon = {subject, body} z MARKERAMI `{{numer_sprawy}}` itd. Markery
 * podmieniane wartosciami z kontekstu sprawy; kazda wartosc przechodzi
 * strip_crlf (Mailer) — marker w TEMACIE nie wstrzyknie naglowka. Renderowana
 * tresc NIGDY nie trafia do logow (NO-PII — patrz WorkflowEvents).
 *
 * Reguly i ich szablony PRZEZYWAJA RAZEM (warstwa ii): regula bez szablonu po
 * reinstalacji = sierota — dlatego seed obu pod jedna bramka SEED_VERSION.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Przechowywanie, seed i render szablonow maili.
 */
final class MailTemplates {

	/**
	 * Opcja-tresc z szablonami maili (warstwa ii). Ksztalt: key => {subject, body}.
	 */
	public const OPTION = 'mp_automator_mail_templates';

	/**
	 * Szablony domyslne (seed pierwszej instalacji). Klucz = template_key uzywany
	 * w action_config reguly notify.
	 *
	 * @return array<string, array{subject: string, body: string}>
	 */
	public static function defaults(): array {
		return array(
			'status_changed_client' => array(
				'subject' => 'Zgłoszenie {{numer_sprawy}} — zmiana statusu',
				'body'    => "Dzień dobry,\n\nStatus Twojego zgłoszenia {{numer_sprawy}} zmienił się na: {{status}}.\n\nSzczegóły sprawdzisz po zalogowaniu na swoje konto.\n\nData zmiany: {{data}}",
			),
		);
	}

	/**
	 * Wszystkie szablony (opcja nadpisuje domyslne per klucz).
	 *
	 * @return array<string, array{subject: string, body: string}>
	 */
	public static function all(): array {
		$stored = get_option( self::OPTION, array() );
		$out    = self::defaults();

		if ( is_array( $stored ) ) {
			foreach ( $stored as $key => $tpl ) {
				if ( is_string( $key ) && is_array( $tpl ) && isset( $tpl['subject'], $tpl['body'] ) ) {
					$out[ $key ] = array(
						'subject' => (string) $tpl['subject'],
						'body'    => (string) $tpl['body'],
					);
				}
			}
		}

		return $out;
	}

	/**
	 * Jeden szablon (opcja > domyslny). Null gdy nieznany klucz.
	 *
	 * @param string $key template_key.
	 * @return array{subject: string, body: string}|null
	 */
	public static function get( string $key ): ?array {
		$all = self::all();

		return isset( $all[ $key ] ) ? $all[ $key ] : null;
	}

	/**
	 * Renderuje szablon: podmienia markery wartosciami z kontekstu. Null gdy
	 * szablonu nie ma. Wartosci markerow BEZ CR/LF (anty header-injection w temacie).
	 *
	 * @param string               $key template_key.
	 * @param array<string, mixed> $ctx Kontekst sprawy (mp_case_get_context).
	 * @return array{subject: string, body: string}|null
	 */
	public static function render( string $key, array $ctx ): ?array {
		$tpl = self::get( $key );

		if ( null === $tpl ) {
			return null;
		}

		$map = self::markers( $ctx );

		return array(
			'subject' => strtr( $tpl['subject'], $map ),
			'body'    => strtr( $tpl['body'], $map ),
		);
	}

	/**
	 * Mapa marker => wartosc. Data w strefie WITRYNY przez wp_date (baza=UTC).
	 *
	 * @param array<string, mixed> $ctx Kontekst sprawy.
	 * @return array<string, string>
	 */
	private static function markers( array $ctx ): array {
		return array(
			'{{numer_sprawy}}' => Mailer::strip_crlf( (string) ( $ctx['case_number'] ?? '' ) ),
			'{{status}}'       => Mailer::strip_crlf( (string) ( $ctx['status'] ?? '' ) ),
			'{{rodzaj}}'       => Mailer::strip_crlf( (string) ( $ctx['rodzaj'] ?? '' ) ),
			'{{data}}'         => Mailer::strip_crlf( (string) wp_date( 'Y-m-d H:i' ) ),
		);
	}

	/**
	 * Sieje szablony domyslne do opcji (warstwa ii) — TYLKO brakujace klucze
	 * (skasowanego szablonu NIE odtwarzamy; bramka SEED_VERSION w Rules pilnuje
	 * jednorazowosci). Dzieki temu admin moze je edytowac.
	 *
	 * @return void
	 */
	public static function seed_defaults(): void {
		$current = get_option( self::OPTION, array() );

		if ( ! is_array( $current ) ) {
			$current = array();
		}

		$changed = false;

		foreach ( self::defaults() as $key => $tpl ) {
			if ( ! isset( $current[ $key ] ) ) {
				$current[ $key ] = $tpl;
				$changed         = true;
			}
		}

		if ( $changed ) {
			update_option( self::OPTION, $current, false );
		}
	}
}
