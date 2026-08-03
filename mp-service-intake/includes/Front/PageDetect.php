<?php
/**
 * Rozpoznanie „to jest strona wtyczki" — do naglowkow bezpieczenstwa.
 *
 * DLACZEGO ISTNIEJE: wczesniej naglowki leczaly TYLKO na stronie utworzonej
 * automatycznie przy aktywacji (ID w opcji). Ale dokumentowany sposob uzycia to
 * „wstaw shortcode na SWOJA podstrone" — takie strony zostawaly BEZ naglowkow
 * (zmierzone 2026-07-26 na demie: auto-strona miala `Cache-Control: no-store`,
 * recznie zalozona `/moje-sprawy/` nie miala nic). Teraz liczy sie JEDNO albo
 * DRUGIE: konfigurowana auto-strona LUB obecnosc shortcode'u w tresci.
 *
 * @package MP\Intake\Front
 */

namespace MP\Intake\Front;

/**
 * Wykrywanie stron frontu wtyczki.
 */
final class PageDetect {

	/**
	 * Czy biezace zadanie to strona wtyczki (auto-strona albo shortcode w tresci).
	 *
	 * ⛔ Rozpoznanie musi widziec OBIE drogi wstawienia. Produkt renderuje
	 * formularz **blokiem i skrotem**, przy czym blok jest droga GLOWNA (tak
	 * zaklada sie strona automatyczna, tak robia buildery). Sprawdzany byl sam
	 * skrot — a `has_shortcode()` zaczyna od warunku „jesli w tresci nie ma
	 * znaku `[` — zwroc falsz", zas blok zapisany jest jako komentarz
	 * `<!-- wp:mp/... /-->` i nawiasu kwadratowego NIE zawiera. Odpowiedz
	 * brzmiala wiec zawsze „to nie nasza strona", a klient, ktory przenosil
	 * formularz na wlasna podstrone blokiem, dostawal ja **bez naglowkow
	 * bezpieczenstwa** (mozna ja bylo osadzic w ramce na obcej stronie).
	 *
	 * @param int    $configured_page_id ID auto-strony z opcji (0 = brak).
	 * @param string $shortcode          Nazwa shortcode'u, np. `mp_intake_form`.
	 * @param string $block              Nazwa bloku, np. `mp/intake-form` (pusty = brak bloku).
	 * @return bool
	 */
	public static function is_plugin_page( int $configured_page_id, string $shortcode, string $block = '' ): bool {
		if ( $configured_page_id > 0 && is_page( $configured_page_id ) ) {
			return true;
		}

		if ( ! is_singular() ) {
			return false;
		}

		$post = get_post();

		if ( ! $post instanceof \WP_Post ) {
			return false;
		}

		if ( has_shortcode( (string) $post->post_content, $shortcode ) ) {
			return true;
		}

		return '' !== $block && function_exists( 'has_block' ) && has_block( $block, $post );
	}

	/**
	 * Wysyla naglowki, jesli jeszcze nic nie poszlo do przegladarki.
	 *
	 * Kazdy zestaw przechodzi przez filtr `mp_intake_security_headers` — strona
	 * klienta moze go dostosowac albo wylaczyc (np. gdy celowo osadza formularz
	 * w ramce z innej domeny). Zwrocenie pustej tablicy = brak naglowkow.
	 *
	 * @param array<string, string> $headers Naglowek => wartosc.
	 * @param string                $context `form` albo `account`.
	 * @return void
	 */
	public static function send( array $headers, string $context ): void {
		if ( headers_sent() ) {
			return;
		}

		/**
		 * Filtruje naglowki bezpieczenstwa stron frontu wtyczki.
		 *
		 * @param array<string, string> $headers Naglowek => wartosc.
		 * @param string                $context `form` albo `account`.
		 */
		$headers = (array) apply_filters( 'mp_intake_security_headers', $headers, $context );

		foreach ( $headers as $name => $value ) {
			if ( '' === (string) $name || '' === (string) $value ) {
				continue;
			}

			header( (string) $name . ': ' . (string) $value );
		}
	}
}
