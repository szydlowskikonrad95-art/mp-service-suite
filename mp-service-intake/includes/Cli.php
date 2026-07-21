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
	 * [--document=<dokument>]
	 * : Dokument zakupu (nr faktury/paragonu).
	 *
	 * [--date=<data>]
	 * : Data zakupu (Y-m-d).
	 *
	 * [--desc=<opis>]
	 * : Opis usterki (pole issue_description, pii_sensitive).
	 *
	 * [--return-reason=<powod>]
	 * : Powod zwrotu (pole return_reason dla rodzaju „zwrot").
	 *
	 * @param string[]              $args       Pozycyjne (nieuzywane).
	 * @param array<string, string> $assoc_args Flagi.
	 * @return void
	 */
	public static function case_create( array $args, array $assoc_args ): void {
		unset( $args );

		$values = array(
			'serial'            => (string) ( $assoc_args['serial'] ?? '' ),
			'purchase_document' => (string) ( $assoc_args['document'] ?? '' ),
			'purchase_date'     => (string) ( $assoc_args['date'] ?? '' ),
			'issue_description' => (string) ( $assoc_args['desc'] ?? '' ),
			'return_reason'     => (string) ( $assoc_args['return-reason'] ?? '' ),
		);

		$result = CaseRepo::create(
			array(
				'kind'   => (string) ( $assoc_args['kind'] ?? '' ),
				'email'  => (string) ( $assoc_args['email'] ?? '' ),
				'name'   => (string) ( $assoc_args['name'] ?? '' ),
				'values' => array_filter( $values, static fn( $v ) => '' !== $v ),
			)
		);

		if ( isset( $result['error'] ) ) {
			if ( isset( $result['validation'] ) ) {
				foreach ( $result['validation'] as $err ) {
					\WP_CLI::log( sprintf( '  - %s: %s', $err['field'], $err['reason_code'] ) );
				}
			}

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
