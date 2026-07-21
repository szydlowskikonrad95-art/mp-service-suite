<?php
/**
 * Komendy WP-CLI Intake (napedzaja tez testy E2E/DoD rdzenia C).
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * `wp mp case-create` / `case-verify` — rdzen narodzin sprawy bez frontu.
 */
final class Cli {

	/**
	 * Rejestruje komendy (wolane tylko pod WP-CLI).
	 *
	 * @return void
	 */
	public static function register(): void {
		\WP_CLI::add_command( 'mp case-create', array( self::class, 'case_create' ) );
		\WP_CLI::add_command( 'mp case-verify', array( self::class, 'case_verify' ) );
	}

	/**
	 * Tworzy sprawe niepotwierdzona i wypisuje token (do magic-linka).
	 *
	 * ## OPTIONS
	 *
	 * --kind=<rodzaj>
	 * : reklamacja|naprawa|zapytanie|zwrot.
	 *
	 * --email=<email>
	 * : E-mail zglaszajacego.
	 *
	 * [--serial=<serial>]
	 * : Numer seryjny produktu (snapshot gwarancji; bez tego sprawa bez produktu).
	 *
	 * [--name=<name>]
	 * : Imie/nazwa zglaszajacego.
	 *
	 * [--desc=<opis>]
	 * : Opis usterki (trafia do form_data jako pole pii_sensitive).
	 *
	 * @param string[]              $args       Pozycyjne (nieuzywane).
	 * @param array<string, string> $assoc_args Flagi.
	 * @return void
	 */
	public static function case_create( array $args, array $assoc_args ): void {
		unset( $args );

		$form_data = array();

		if ( isset( $assoc_args['desc'] ) ) {
			$form_data['issue_description'] = array(
				'label'         => 'Opis usterki',
				'value'         => (string) $assoc_args['desc'],
				'pii_sensitive' => true,
			);
		}

		$result = CaseRepo::create(
			array(
				'kind'      => (string) ( $assoc_args['kind'] ?? '' ),
				'email'     => (string) ( $assoc_args['email'] ?? '' ),
				'name'      => (string) ( $assoc_args['name'] ?? '' ),
				'serial'    => (string) ( $assoc_args['serial'] ?? '' ),
				'form_data' => $form_data,
			)
		);

		if ( isset( $result['error'] ) ) {
			\WP_CLI::error( (string) $result['error'] );
		}

		\WP_CLI::log( 'case_id=' . $result['case_id'] );
		\WP_CLI::log( 'case_number=' . $result['case_number'] );
		\WP_CLI::log( 'token=' . $result['token'] );
		\WP_CLI::success( 'Sprawa niepotwierdzona utworzona.' );
	}

	/**
	 * Potwierdza sprawe tokenem (symuluje klik magic-linka).
	 *
	 * ## OPTIONS
	 *
	 * <token>
	 * : Surowy token weryfikacji.
	 *
	 * @param string[] $args Pozycyjne: [0] token.
	 * @return void
	 */
	public static function case_verify( array $args ): void {
		$result = CaseRepo::verify( (string) ( $args[0] ?? '' ) );

		if ( isset( $result['error'] ) ) {
			\WP_CLI::error( (string) $result['error'] );
		}

		\WP_CLI::success( sprintf( 'Sprawa %s potwierdzona (case_id=%d).', $result['case_number'], $result['case_id'] ) );
	}
}
