<?php
/**
 * Slownik POWODOW ODRZUCENIA sprawy (cz. 1 pkt 5 audytu).
 *
 * ⛔ PO CO TO ISTNIEJE. Kartka klienta zada SIEDMIU statusow sprawy, ale jednego
 * z nich — „odrzucone" — nie dalo sie ustawic w interfejsie. Slepy zaulek dzialal
 * tak: karta sprawy pokazuje pole powodu odrzucenia WYLACZNIE wtedy, gdy lista
 * powodow nie jest pusta (`Admin\CaseCard::section_actions`), lista pochodzi
 * z zaczepu `mp_rejection_reasons`, a tego zaczepu w calym produkcie NIKT NIE
 * REJESTROWAL — istnialy tylko DWA ODCZYTY (karta sprawy i eksport CSV modulu
 * automatyzacji). Bez powodu zapis konczy sie bledem REJECTION_REASON_REQUIRED
 * (`CaseRepo::change_status`). Pracownik wybieral wiec status z listy, klikal
 * „Zmien status" i dostawal odmowe, ktorej nie mial jak spelnic.
 *
 * Rozwiazanie idzie WZORCEM PRODUKTU, nie nowym pomyslem: opcja z konfiguracja
 * + sekcja na ekranie ustawien + handler admin-post z nonce i capability — tak
 * samo, jak trzymane sa statusy wlasne, szablony maili i pula pracownikow.
 *
 * DOMYSLNY SLOWNIK JEST NIEPUSTY. Gdyby powody trzeba bylo najpierw wpisac,
 * swiezo postawiona witryna dalej mialaby ten sam slepy zaulek — tyle ze ukryty
 * o jeden ekran dalej.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

defined( 'ABSPATH' ) || exit;

/**
 * Konfigurowalny slownik powodow odrzucenia (kod => etykieta).
 */
final class RejectionReasons {

	/**
	 * Opcja z konfiguracja (kod => etykieta).
	 */
	public const OPTION = 'mp_intake_rejection_reasons';

	/**
	 * Akcja admin-post zapisu (= akcja nonce).
	 */
	public const ACTION_CONFIG = 'mp_intake_rejection_reasons_config';

	/**
	 * Capability zapisu — konfiguracja to poziom system-config.
	 */
	public const CAP = 'mp_system_admin';

	/**
	 * Limit dlugosci etykiety (kolumna slownika i czytelnosc listy).
	 */
	private const LABEL_MAX = 190;

	/**
	 * Limit liczby powodow (lista rozwijana, nie katalog).
	 */
	private const MAX_REASONS = 50;

	/**
	 * Domyslny slownik — zeby „odrzucone" bylo zapisywalne OD RAZU po instalacji.
	 *
	 * @return array<string, string>
	 */
	public static function defaults(): array {
		return array(
			'brak_dowodu'       => __( 'Brak dowodu zakupu', 'mp-service-intake' ),
			'poza_gwarancja'    => __( 'Sprzęt poza okresem gwarancji', 'mp-service-intake' ),
			'uszkodzenie_winy'  => __( 'Uszkodzenie z winy użytkownika', 'mp-service-intake' ),
			'brak_usterki'      => __( 'Nie stwierdzono usterki', 'mp-service-intake' ),
			'nie_nasz_produkt'  => __( 'Produkt spoza naszej oferty', 'mp-service-intake' ),
			'zgloszenie_dublet' => __( 'Zgłoszenie powielone', 'mp-service-intake' ),
		);
	}

	/**
	 * Rejestruje dostawce slownika i handler zapisu.
	 *
	 * Zaczep `mp_rejection_reasons` jest kontraktem miedzy modulami: czyta go
	 * karta sprawy (tu) i eksport CSV modulu automatyzacji. Dotad nie mial ZADNEGO
	 * dostawcy — teraz ma dokladnie jednego.
	 *
	 * @return void
	 */
	public static function register(): void {
		add_filter( 'mp_rejection_reasons', array( self::class, 'provide' ) );

		add_action( 'admin_post_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
		add_action( 'admin_post_nopriv_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
	}

	/**
	 * Biezacy slownik: konfiguracja z opcji, a gdy jej nie ma — domyslny.
	 *
	 * @param mixed $reasons Wartosc wejsciowa filtra (ignorowana — jestesmy zrodlem).
	 * @return array<string, string>
	 */
	public static function provide( $reasons = array() ): array {
		unset( $reasons );

		return self::all();
	}

	/**
	 * Slownik po sanityzacji (kod => etykieta). Pusta konfiguracja => domyslny.
	 *
	 * @return array<string, string>
	 */
	public static function all(): array {
		$zapisane = get_option( self::OPTION, null );

		if ( ! is_array( $zapisane ) ) {
			return self::defaults();
		}

		$czyste = self::sanitize( $zapisane );

		// Pusta lista = ten sam slepy zaulek, ktory naprawiamy. Nie pozwalamy
		// zapisac pustki (nizej), ale gdyby wpis w bazie zepsul sie inna droga,
		// karta sprawy dalej ma z czego wybrac.
		return array() === $czyste ? self::defaults() : $czyste;
	}

	/**
	 * Porzadkuje slownik: kod jako klucz techniczny, etykieta jako tekst.
	 *
	 * @param array<mixed, mixed> $reasons Slownik surowy.
	 * @return array<string, string>
	 */
	public static function sanitize( array $reasons ): array {
		$czyste = array();

		foreach ( $reasons as $code => $label ) {
			$kod = sanitize_key( (string) $code );

			if ( '' === $kod ) {
				continue;
			}

			$etykieta = sanitize_text_field( (string) $label );

			if ( '' === $etykieta ) {
				continue;
			}

			if ( mb_strlen( $etykieta ) > self::LABEL_MAX ) {
				$etykieta = mb_substr( $etykieta, 0, self::LABEL_MAX );
			}

			$czyste[ $kod ] = $etykieta;

			if ( count( $czyste ) >= self::MAX_REASONS ) {
				break;
			}
		}

		return $czyste;
	}

	/**
	 * Zamienia tresc pola tekstowego („kod|Etykieta" w kazdej linii) na slownik.
	 *
	 * Linia bez kreski = sama etykieta; kod powstaje wtedy z etykiety, zeby
	 * administrator nie musial wymyslac kluczy technicznych.
	 *
	 * @param string $tekst Tresc pola.
	 * @return array<string, string>
	 */
	public static function parse( string $tekst ): array {
		$slownik = array();

		$linie = preg_split( '/\r\n|\r|\n/', $tekst );
		$linie = is_array( $linie ) ? $linie : array();

		foreach ( $linie as $linia ) {
			$linia = trim( (string) $linia );

			if ( '' === $linia ) {
				continue;
			}

			if ( false !== strpos( $linia, '|' ) ) {
				list( $kod, $etykieta ) = array_pad( explode( '|', $linia, 2 ), 2, '' );
			} else {
				$kod      = $linia;
				$etykieta = $linia;
			}

			$kod = sanitize_key( self::slug( (string) $kod ) );

			if ( '' === $kod ) {
				continue;
			}

			$slownik[ $kod ] = trim( (string) $etykieta );
		}

		return self::sanitize( $slownik );
	}

	/**
	 * Slownik jako tresc pola tekstowego (odwrotnosc `parse`).
	 *
	 * @return string
	 */
	public static function to_text(): string {
		$linie = array();

		foreach ( self::all() as $kod => $etykieta ) {
			$linie[] = $kod . '|' . $etykieta;
		}

		return implode( "\n", $linie );
	}

	/**
	 * Zapis z ekranu ustawien: capability => nonce => walidacja => zapis.
	 *
	 * @return void
	 */
	public static function handle_config(): void {
		if ( ! current_user_can( self::CAP ) ) {
			wp_die(
				esc_html__( 'Brak uprawnień do konfiguracji powodów odrzucenia.', 'mp-service-intake' ),
				'',
				array( 'response' => 403 )
			);
		}

		check_admin_referer( self::ACTION_CONFIG );

		// Pole jest WIELOLINIOWE, wiec sanitize_text_field zjadlby znaki konca linii
		// i skleilby wszystkie powody w jeden. Sanityzacja idzie per wartosc w
		// `parse()`/`sanitize()`: kod przez sanitize_key, etykieta przez
		// sanitize_text_field — czyli na tym, co realnie trafia do bazy.
		// phpcs:ignore WordPress.Security.NonceVerification.Missing, WordPress.Security.ValidatedSanitizedInput.InputNotSanitized -- check_admin_referer() wyzej; sanityzacja per wartosc w parse().
		$raw = isset( $_POST['mp_rejection_reasons'] ) ? (string) wp_unslash( $_POST['mp_rejection_reasons'] ) : '';

		$slownik = self::parse( $raw );
		$ref     = wp_get_referer();
		$powrot  = false !== $ref ? $ref : admin_url();

		// PUSTA LISTA = przywrocenie slepego zaulka. Odmawiamy i mowimy czemu.
		if ( array() === $slownik ) {
			wp_safe_redirect( add_query_arg( 'mp_settings_error', 'powody-puste', $powrot ) );
			exit;
		}

		update_option( self::OPTION, $slownik, false );

		wp_safe_redirect( add_query_arg( 'mp_settings_ok', 'powody', $powrot ) );
		exit;
	}

	/**
	 * Kod techniczny z tekstu czlowieka (polskie znaki => laciriskie, spacje => _).
	 *
	 * @param string $tekst Tekst.
	 * @return string
	 */
	private static function slug( string $tekst ): string {
		$tekst = strtr(
			$tekst,
			array(
				'ą' => 'a',
				'ć' => 'c',
				'ę' => 'e',
				'ł' => 'l',
				'ń' => 'n',
				'ó' => 'o',
				'ś' => 's',
				'ź' => 'z',
				'ż' => 'z',
				'Ą' => 'a',
				'Ć' => 'c',
				'Ę' => 'e',
				'Ł' => 'l',
				'Ń' => 'n',
				'Ó' => 'o',
				'Ś' => 's',
				'Ź' => 'z',
				'Ż' => 'z',
			)
		);

		$tekst = (string) preg_replace( '/\s+/', '_', trim( $tekst ) );

		return strtolower( $tekst );
	}
}
