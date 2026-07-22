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
		\WP_CLI::add_command( 'mp login-link', array( self::class, 'login_link' ) );
		\WP_CLI::add_command( 'mp login-consume', array( self::class, 'login_consume' ) );
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

	/**
	 * Wystawia passwordless link logowania i wypisuje selector+token (E2E).
	 *
	 * Nie wysyla maila — zwraca surowe dane linku, zeby test mogl je „kliknac".
	 *
	 * ## OPTIONS
	 *
	 * <email>
	 * : E-mail konta klienta.
	 *
	 * @param string[] $args Pozycyjne: [0] email.
	 * @return void
	 */
	public static function login_link( array $args ): void {
		$issued = Front\Login::issue_for_email( (string) ( $args[0] ?? '' ) );

		if ( null === $issued ) {
			\WP_CLI::error( 'Brak konta klienta dla tego e-maila (albo e-mail nieprawidlowy).' );
		}

		\WP_CLI::log( 'selector=' . $issued['selector'] );
		\WP_CLI::log( 'token=' . $issued['token'] );
		\WP_CLI::success( 'Link logowania wystawiony.' );
	}

	/**
	 * Zuzywa link logowania (selector+token) i wypisuje user_id (E2E).
	 *
	 * ## OPTIONS
	 *
	 * <selector>
	 * : Publiczny selektor linku.
	 *
	 * <token>
	 * : Surowy walidator linku.
	 *
	 * @param string[] $args Pozycyjne: [0] selector, [1] token.
	 * @return void
	 */
	public static function login_consume( array $args ): void {
		$user_id = Front\Login::consume( (string) ( $args[0] ?? '' ), (string) ( $args[1] ?? '' ) );

		\WP_CLI::log( 'user_id=' . $user_id );
		\WP_CLI::success( 0 === $user_id ? 'Link odrzucony.' : 'Link zuzyty, uzytkownik uwierzytelniony.' );
	}
}
