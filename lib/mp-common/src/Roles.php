<?php
/**
 * Wspolne role systemu MP (4 role ze specyfikacji).
 *
 * Role sa WSPOLDZIELONE przez 3 pluginy: kazdy plugin przy aktywacji
 * odtwarza je idempotentnie; zdejmuje je dopiero OSTATNI odinstalowywany
 * (patrz Uninstall).
 *
 * @package MP\Common
 */

namespace MP\Common;

/**
 * Definicja i utrzymanie 4 dedykowanych rol mp_*.
 */
final class Roles {

	/**
	 * Slug => etykieta. Pelna macierz capabilities: SECURITY.md (kontrakt D2).
	 */
	public const ROLES = array(
		'mp_system_admin' => 'Administrator systemu MP',
		'mp_coordinator'  => 'Koordynator serwisu MP',
		'mp_agent'        => 'Pracownik serwisu MP',
		'mp_client'       => 'Klient MP',
	);

	/**
	 * Capabilities personelu — te dostaje TAKZE wbudowany administrator WP
	 * (bez nich nie widzialby ekranow mp_*); mp_client swiadomie poza lista.
	 */
	public const STAFF_CAPS = array( 'mp_system_admin', 'mp_coordinator', 'mp_agent' );

	/**
	 * Uprawnienia, ktore WPUSZCZAJA do rejestru produktow — JEDNO zrodlo prawdy.
	 *
	 * ⛔ PO CO OSOBNA LISTA, SKORO JEST `STAFF_CAPS`: bo do rejestru wchodzi WEZSZY
	 * krag niz „personel". Menu rejestru bralo cap z `menu_cap_for_current_user()`,
	 * ktory zwraca PIERWSZE uprawnienie z calego personelu — koordynatorowi zwracal
	 * jego wlasne, wiec pozycja w menu byla widoczna. Ekran dwadziescia linii nizej
	 * sprawdzal CO INNEGO (`mp_agent` albo `mp_system_admin`) i konczyl `wp_die()`.
	 * Koordynator widzial drzwi, otwieral je i dostawal odmowe — nie wiedzac, czy to
	 * awaria, czy tak ma byc. Dwa warunki na jedne drzwi, w jednym pliku.
	 *
	 * ⚠️ Ta lista NIE zmienia tego, KTO ma dostep — jest przepisana z warunku, ktory
	 * juz stal w `ProductsScreen::render()`. Zawezanie dostepu ponad to, co obiecuje
	 * dokumentacja klienta, byloby wada tej samej klasy, tylko w druga strone.
	 */
	public const REGISTRY_CAPS = array( 'mp_agent', 'mp_system_admin' );

	/**
	 * Czy biezacy uzytkownik ma prawo wejsc do rejestru produktow.
	 *
	 * @return bool
	 */
	public static function can_current_user_see_registry(): bool {
		foreach ( self::REGISTRY_CAPS as $cap ) {
			if ( current_user_can( $cap ) ) {
				return true;
			}
		}

		return false;
	}

	/**
	 * Cap dla `add_menu_page()` rejestru — z TEJ SAMEJ listy co bramka ekranu.
	 *
	 * `add_menu_page()` przyjmuje JEDEN cap, a role MP nie dziedzicza po sobie,
	 * wiec podajemy to, ktore biezacy uzytkownik faktycznie ma. Gdy nie ma zadnego,
	 * zwracamy cap spoza jego zasiegu — pozycja w menu sie NIE POKAZUJE, zamiast
	 * wpuszczac i odsylac z kwitkiem.
	 *
	 * @return string
	 */
	public static function registry_menu_cap(): string {
		foreach ( self::REGISTRY_CAPS as $cap ) {
			if ( current_user_can( $cap ) ) {
				return $cap;
			}
		}

		return 'mp_system_admin';
	}

	/**
	 * Tworzy brakujace role (idempotentnie — wolane przy KAZDEJ aktywacji,
	 * takze po awaryjnym zdjeciu rol; runda W: aktywacja zawsze odtwarza).
	 *
	 * Kazda rola niesie wlasna cap-marke (kod sprawdza WYLACZNIE capability,
	 * nigdy nazwe roli). To minimalny zestaw pod moduł B; pelna macierz
	 * uprawnien doprecyzuje SECURITY.md (D2) — rozszerzenie, nie przebudowa.
	 *
	 * @return void
	 */
	public static function ensure(): void {
		foreach ( self::ROLES as $slug => $label ) {
			if ( null === get_role( $slug ) ) {
				add_role( $slug, $label, array( 'read' => true ) );
			}

			$role = get_role( $slug );

			if ( null !== $role && ! $role->has_cap( $slug ) ) {
				$role->add_cap( $slug );
			}
		}

		$admin = get_role( 'administrator' );

		if ( null !== $admin ) {
			foreach ( self::STAFF_CAPS as $cap ) {
				if ( ! $admin->has_cap( $cap ) ) {
					$admin->add_cap( $cap );
				}
			}
		}
	}

	/**
	 * Czy biezacy uzytkownik to personel serwisu (dowolna z trzech rol).
	 *
	 * ⛔ Role MP NIE MAJA HIERARCHII — i to jest projekt, nie usterka: kod
	 * sprawdza wylacznie capability, nigdy nazwe roli. Konsekwencja jest jednak
	 * taka, ze `current_user_can( 'mp_agent' )` odbija koordynatora, choc ten
	 * nadzoruje ludzi pracujacych na danym ekranie. Dlatego bramka personelu ma
	 * byc JEDNA funkcja, a nie kopia warunku w kazdym ekranie z osobna.
	 *
	 * @return bool
	 */
	public static function current_user_is_staff(): bool {
		foreach ( self::STAFF_CAPS as $cap ) {
			if ( current_user_can( $cap ) ) {
				return true;
			}
		}

		return false;
	}

	/**
	 * Capability do `add_menu_page()` dla BIEZACEGO uzytkownika.
	 *
	 * `add_menu_page` przyjmuje JEDEN cap, a role nie dziedzicza po sobie —
	 * wiec wpisanie tam `mp_agent` na sztywno chowa ekran przed koordynatorem,
	 * czyli przelozonym osoby, ktora na nim pracuje. Zwracamy cap, ktory
	 * uzytkownik FAKTYCZNIE ma; klient i gosc nie maja zadnego, wiec pozycja
	 * menu im sie nie pokaze, a render sprawdza personel osobno (obrona
	 * warstwowa).
	 *
	 * @return string
	 */
	public static function menu_cap_for_current_user(): string {
		foreach ( self::STAFF_CAPS as $cap ) {
			if ( current_user_can( $cap ) ) {
				return $cap;
			}
		}

		// Nikt z personelu — cap, ktorego taki uzytkownik nie ma (menu ukryte).
		return 'mp_system_admin';
	}
}
