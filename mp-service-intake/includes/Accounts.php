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
	 * @param int    $customer_id ID rekordu klienta.
	 * @param string $email       E-mail (klucz logiczny; login = e-mail).
	 * @param string $name        Nazwa do wyswietlenia.
	 * @return int ID uzytkownika WP (0 = nie udalo sie zalozyc/podpiac).
	 */
	public static function ensure_for_customer( int $customer_id, string $email, string $name ): int {
		$email = sanitize_email( $email );

		if ( '' === $email || ! is_email( $email ) ) {
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

		$user_id = wp_insert_user(
			array(
				'user_login'   => self::unique_login( $email ),
				'user_email'   => $email,
				'user_pass'    => wp_generate_password( 24, true, true ),
				'display_name' => '' !== $name ? $name : $email,
				'role'         => self::CLIENT_ROLE,
			)
		);

		if ( is_wp_error( $user_id ) ) {
			return 0;
		}

		Customers::set_wp_user( $customer_id, (int) $user_id );

		return (int) $user_id;
	}

	/**
	 * Buduje unikalny `user_login` z e-maila (WP wymaga unikalnego loginu).
	 *
	 * @param string $email E-mail.
	 * @return string
	 */
	private static function unique_login( string $email ): string {
		$base = sanitize_user( $email, true );

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
