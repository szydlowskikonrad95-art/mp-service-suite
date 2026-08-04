<?php
/**
 * Konto WP klienta — tworzenie/laczenie przy weryfikacji sprawy.
 *
 * Panel „moje zgloszenia" wymaga konta WP (rola `mp_client`); wlascicielstwo
 * spraw idzie przez `customers.wp_user_id`. Konto powstaje DOPIERO przy
 * weryfikacji (plan C: sieroty nie maja konta). EDGE (plan C, przeglad wlasny
 * 22.07): jesli e-mail nalezy do ISTNIEJACEGO uzytkownika (personel/admin),
 * podpinamy sprawe po jego user_id BEZ ruszania rol — nie robimy z admina klienta.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Zapewnia konto WP klienta i spina je z rekordem klienta.
 */
final class Accounts {

	/**
	 * Rola konta zakladanego dla nowego klienta.
	 */
	public const CLIENT_ROLE = 'mp_client';

	/**
	 * Czy uzytkownik ma WYLACZNIE role klienta (mp_client) — bez uprawnien
	 * personelu ani admina. Baza decyzji "ukryj pasek admina WP klientowi":
	 * pasek chowamy TYLKO czystemu klientowi; personel/admin widza go dalej.
	 *
	 * @param \WP_User $user Uzytkownik.
	 * @return bool
	 */
	public static function is_client_only( \WP_User $user ): bool {
		if ( user_can( $user, 'manage_options' ) ) {
			return false;
		}

		foreach ( Common\Roles::STAFF_CAPS as $staff_cap ) {
			if ( user_can( $user, $staff_cap ) ) {
				return false;
			}
		}

		return user_can( $user, self::CLIENT_ROLE );
	}

	/**
	 * Zapewnia konto WP dla klienta i ustawia `customers.wp_user_id`.
	 *
	 * Idempotentne: gdy klient ma juz `wp_user_id`, zwraca je bez zmian.
	 * Nowy user dostaje losowe haslo (logowanie passwordless — link mailem).
	 *
	 * ⛔ KONTO WP NIE NOSI DANYCH OSOBOWYCH. Ani nazwa wyswietlana, ani login,
	 * ani czlon adresu strony autora nie moga pochodzic z e-maila lub nazwiska:
	 * WordPress publikuje `display_name` i `user_nicename` na stronie autora,
	 * ktora jest jawna i indeksowalna (panel klienta ma `noindex`, ta strona nie
	 * miala nic). Wczesniej `display_name` schodzila do e-maila, gdy formularz
	 * nie zbieral nazwiska — czyli w NORMALNYM torze zgloszenia.
	 * Imie i nazwisko zyje wylacznie w tabeli klientow wtyczki, gdzie obsluguje
	 * je eraser RODO.
	 *
	 * @param int    $customer_id ID rekordu klienta.
	 * @param string $email       E-mail (klucz logiczny konta WP).
	 * @return int ID uzytkownika WP (0 = nie udalo sie zalozyc/podpiac).
	 */
	public static function ensure_for_customer( int $customer_id, string $email ): int {
		$email = sanitize_email( $email );

		// 2.4 (b): dlugosc tak samo jak ksztalt. Kolumna `customers.email` to
		// VARCHAR(190) — konto zalozone na dluzszym adresie i tak by sie nie
		// zapisalo, a blad wyszedlby z bazy, nie z walidacji.
		if ( '' === $email || null !== Validator::validate_email( $email ) ) {
			return 0;
		}

		$existing = Customers::wp_user_id( $customer_id );

		if ( null !== $existing && $existing > 0 ) {
			return $existing;
		}

		$user = get_user_by( 'email', $email );

		if ( $user instanceof \WP_User ) {
			// EDGE: e-mail istniejacego uzytkownika (np. personel/admin) —
			// podpinamy po user_id, ZERO ingerencji w role/capabilities.
			Customers::set_wp_user( $customer_id, (int) $user->ID );

			return (int) $user->ID;
		}

		$handle = self::unique_login( self::neutral_handle( $customer_id ) );

		$user_id = wp_insert_user(
			array(
				'user_login'    => $handle,
				'user_nicename' => $handle,
				'user_email'    => $email,
				'user_pass'     => wp_generate_password( 24, true, true ),
				'display_name'  => self::neutral_display_name( $customer_id ),
				'role'          => self::CLIENT_ROLE,
			)
		);

		if ( is_wp_error( $user_id ) ) {
			return 0;
		}

		Customers::set_wp_user( $customer_id, (int) $user_id );

		return (int) $user_id;
	}

	/**
	 * Usuwa konto WP klienta przy eraserze RODO (art. 17).
	 *
	 * Kasujemy TYLKO czyste konto klienta (`mp_client`, bez uprawnien personelu/
	 * admina) — w `wp_users` zostaje e-mail, a login jest nieusuwalny przez
	 * wp_update_user, wiec pelne usuniecie usera to jedyny sposob wyczyszczenia
	 * konta. (Login i nazwa wyswietlana sa neutralne od naprawy 2.54, ale
	 * `user_email` to nadal dana osobowa i musi zniknac.) Konta personelu/admina (EDGE z ensure_for_customer:
	 * podpiete po e-mailu bez zmiany rol) NIE tykamy. Nie usuwamy tez, gdy konto
	 * wciaz spiete z innym NIEanonimizowanym klientem (bezpieczenstwo). Wywolywac
	 * PO Customers::anonymize (ktore odpina wp_user_id) — id konta przekazujemy z
	 * gory, bo po anonimizacji nie odczytamy go juz z rekordu klienta.
	 *
	 * @param int $wp_user_id ID uzytkownika WP (zlapane przed anonimizacja).
	 * @return bool True gdy konto usuniete; false gdy pominiete (personel/admin/
	 *              wspoldzielone/brak).
	 */
	public static function purge_client_account( int $wp_user_id ): bool {
		if ( $wp_user_id <= 0 ) {
			return false;
		}

		$user = get_user_by( 'id', $wp_user_id );

		if ( ! $user instanceof \WP_User ) {
			return false;
		}

		// Personel/admin (podpiety po e-mailu) — ZERO ingerencji.
		if ( ! self::is_client_only( $user ) ) {
			return false;
		}

		// Konto wciaz przypisane do innego nieanonimizowanego klienta — nie kasuj.
		if ( array() !== Customers::ids_by_wp_user( $wp_user_id ) ) {
			return false;
		}

		// Uniewaznij wszystkie sesje, potem usun konto (email/login/nazwisko znikaja).
		$sessions = \WP_Session_Tokens::get_instance( $wp_user_id );
		$sessions->destroy_all();

		if ( ! function_exists( 'wp_delete_user' ) ) {
			require_once ABSPATH . 'wp-admin/includes/user.php';
		}

		return (bool) wp_delete_user( $wp_user_id );
	}

	/**
	 * JEDNORAZOWA naprawa kont ZALOZONYCH PRZED ta poprawka (migracja 4).
	 *
	 * ⛔ Bez tego kroku poprawka nie zdejmuje szkody, tylko przestaje ja
	 * powiekszac: nazwa wyswietlana zapisywana byla RAZ w zyciu konta i nic
	 * jej nigdy nie aktualizowalo, wiec ludzie juz ujawnieni pozostaliby
	 * ujawnieni. Poprawiamy dwie rzeczy, ktore WordPress publikuje na stronie
	 * autora: nazwe wyswietlana i czlon adresu (`user_nicename`).
	 *
	 * Czego NIE ruszamy i dlaczego:
	 * - `user_login` — nieusuwalny przez `wp_update_user`, a NIE jest publikowany
	 *   (adres strony autora bierze `user_nicename`); przy zadaniu RODO konto
	 *   znika w calosci (`purge_client_account`),
	 * - kont personelu i administratora — sprawdzane `is_client_only()`; konto
	 *   podpiete po e-mailu (EDGE z `ensure_for_customer`) zostaje nietkniete,
	 * - `user_email` — to klucz logowania klienta; usuwa go dopiero eraser.
	 *
	 * @return int Liczba poprawionych kont.
	 */
	public static function redact_public_identities(): int {
		$poprawione = 0;
		$offset     = 0;
		$partia     = 100;

		do {
			$users = get_users(
				array(
					'role'    => self::CLIENT_ROLE,
					'number'  => $partia,
					'offset'  => $offset,
					'orderby' => 'ID',
					'order'   => 'ASC',
				)
			);

			foreach ( $users as $user ) {
				if ( ! $user instanceof \WP_User || ! self::is_client_only( $user ) ) {
					continue;
				}

				$customer_ids = Customers::ids_by_wp_user( (int) $user->ID );
				$customer_id  = array() === $customer_ids ? 0 : (int) $customer_ids[0];

				$handle = $customer_id > 0
					? self::neutral_handle( $customer_id )
					: 'mp-klient-u' . (int) $user->ID;

				// Uchwyt zajety przez INNE konto (np. dwa konta tego samego
				// klienta) — dokladamy numer konta, zeby nie podmienic cudzego.
				$zajety = get_user_by( 'slug', $handle );

				if ( $zajety instanceof \WP_User && (int) $zajety->ID !== (int) $user->ID ) {
					$handle .= '-u' . (int) $user->ID;
				}

				$nowa_nazwa = $customer_id > 0
					? self::neutral_display_name( $customer_id )
					/* translators: %d: numer konta WordPress. */
					: sprintf( __( 'Klient serwisu (konto #%d)', 'mp-service-intake' ), (int) $user->ID );

				if ( $user->display_name === $nowa_nazwa && $user->user_nicename === $handle ) {
					continue;
				}

				$wynik = wp_update_user(
					array(
						'ID'            => (int) $user->ID,
						'display_name'  => $nowa_nazwa,
						'user_nicename' => $handle,
					)
				);

				if ( ! is_wp_error( $wynik ) ) {
					++$poprawione;
				}
			}

			$pobrano = count( $users );
			$offset += $partia;
		} while ( $pobrano === $partia );

		return $poprawione;
	}

	/**
	 * Neutralny uchwyt konta klienta (login i czlon adresu strony autora).
	 *
	 * Zbudowany z ID rekordu klienta — identyfikatora wewnetrznego, ktory
	 * o czlowieku nie mowi nic. NIE z e-maila: adres `/author/<nicename>/`
	 * jest jawny, wiec uchwyt zbudowany z adresu wycieka go samym odsylaczem,
	 * nawet gdy nazwa wyswietlana jest juz neutralna.
	 *
	 * @param int $customer_id ID rekordu klienta.
	 * @return string
	 */
	private static function neutral_handle( int $customer_id ): string {
		return 'mp-klient-' . max( 0, $customer_id );
	}

	/**
	 * Neutralna nazwa wyswietlana konta klienta (WP publikuje ja na stronie autora).
	 *
	 * Rozroznialna dla personelu przegladajacego uzytkownikow WP, a jednoczesnie
	 * pozbawiona danych osobowych. Prawdziwe imie i nazwisko trzyma tabela
	 * klientow wtyczki.
	 *
	 * @param int $customer_id ID rekordu klienta.
	 * @return string
	 */
	private static function neutral_display_name( int $customer_id ): string {
		/* translators: %d: wewnetrzny numer rekordu klienta. */
		return sprintf( __( 'Klient serwisu #%d', 'mp-service-intake' ), max( 0, $customer_id ) );
	}

	/**
	 * Buduje unikalny `user_login` z podanej podstawy (WP wymaga unikalnego loginu).
	 *
	 * @param string $base_handle Podstawa uchwytu (bez danych osobowych).
	 * @return string
	 */
	private static function unique_login( string $base_handle ): string {
		$base = sanitize_user( $base_handle, true );

		if ( '' === $base ) {
			$base = 'mp_client';
		}

		$login = $base;
		$i     = 1;

		while ( username_exists( $login ) ) {
			++$i;
			$login = $base . '-' . $i;
		}

		return $login;
	}
}
