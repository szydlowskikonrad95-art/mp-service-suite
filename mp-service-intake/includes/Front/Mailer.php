<?php
/**
 * Maile Intake: magic-link weryfikacji + potwierdzenie z numerem SRV.
 *
 * Szablony w C z kotwicami (C degraded bez D — nie zalezy od szablonow D).
 * Magic-link: token w URL, GET na endpoint weryfikacji. 2. mail (po weryfikacji)
 * niesie NUMER SRV (krok 6 specyfikacji) — SRV ujawniany dopiero po potwierdzeniu.
 *
 * @package MP\Intake
 */

namespace MP\Intake\Front;

use MP\Intake\CaseEvents;
use MP\Intake\CaseRepo;

/**
 * Wysylka maili zgloszenia.
 */
final class Mailer {

	/**
	 * Opcja alertu poczty (ostatnia nieudana wysylka) — czyta Stan witryny.
	 *
	 * @var string
	 */
	public const ALERT_OPTION = 'mp_intake_mail_alert';

	/**
	 * Wysyla magic-link potwierdzenia zgloszenia.
	 *
	 * @param string   $email   Adres odbiorcy.
	 * @param string   $token   Surowy token (do URL).
	 * @param int|null $case_id Sprawa, ktorej dotyczy mail (slad przy awarii wysylki).
	 * @return bool Wynik wp_mail.
	 */
	public static function send_magic_link( string $email, string $token, ?int $case_id = null ): bool {
		$url = add_query_arg(
			array(
				'action' => 'mp_intake_verify',
				'token'  => rawurlencode( $token ),
			),
			admin_url( 'admin-post.php' )
		);

		$subject = sprintf(
			/* translators: %s: nazwa firmy/strony. */
			__( 'Potwierdź swoje zgłoszenie serwisowe — %s', 'mp-service-intake' ),
			self::nazwa_firmy()
		);
		$body = sprintf(
			/* translators: 1: nazwa firmy/strony, 2: link potwierdzajacy, 3: liczba godzin waznosci linku. */
			__( "Dziękujemy za zgłoszenie serwisowe w %1\$s.\n\nAby je potwierdzić i uruchomić obsługę, kliknij w link poniżej (ważny %3\$d godz.):\n\n%2\$s\n\nJeśli to nie Ty wysłałeś to zgłoszenie, zignoruj tę wiadomość.", 'mp-service-intake' ),
			self::nazwa_firmy(),
			$url,
			CaseRepo::TOKEN_TTL_HOURS
		) . self::stopka();

		return self::deliver( $email, self::filtruj_temat( $subject, 'potwierdzenie' ), self::filtruj_tresc( $body, 'potwierdzenie' ), 'magic_link', $case_id );
	}

	/**
	 * Wysyla passwordless link logowania do panelu (krotki TTL, jednorazowy).
	 *
	 * Link prowadzi na strone z przyciskiem — zalogowanie DOPIERO przez POST
	 * (skanery poczty prefetchuja GET; sam GET NIE loguje).
	 *
	 * @param string $email    Adres odbiorcy.
	 * @param string $selector Publiczny selektor (lookup).
	 * @param string $token    Surowy walidator (do URL).
	 * @return bool Wynik wp_mail.
	 */
	public static function send_login_link( string $email, string $selector, string $token ): bool {
		$url = add_query_arg(
			array(
				'action' => 'mp_intake_login',
				'sel'    => rawurlencode( $selector ),
				'tok'    => rawurlencode( $token ),
			),
			admin_url( 'admin-post.php' )
		);

		$subject = sprintf(
			/* translators: %s: nazwa firmy/strony. */
			__( 'Logowanie do panelu zgłoszeń — %s', 'mp-service-intake' ),
			self::nazwa_firmy()
		);
		$body = sprintf(
			/* translators: 1: link logowania, 2: liczba minut waznosci linku, 3: adres panelu zgloszen. */
			__( "Aby zalogować się do panelu swoich zgłoszeń, otwórz link poniżej i kliknij przycisk logowania (link ważny %2\$d minut, jednorazowy):\n\n%1\$s\n\nLink wygasł? Poproś o nowy, podając swój adres e-mail na stronie: %3\$s\n\nJeśli to nie Ty prosiłeś o logowanie, zignoruj tę wiadomość — nikt nie uzyskał dostępu do konta.", 'mp-service-intake' ),
			$url,
			Login::ttl_minutes(),
			self::adres_panelu()
		) . self::stopka();

		return self::deliver( $email, self::filtruj_temat( $subject, 'logowanie' ), self::filtruj_tresc( $body, 'logowanie' ), 'logowanie', null );
	}

	/**
	 * Wysyla potwierdzenie z numerem SRV (po weryfikacji).
	 *
	 * @param string   $email       Adres odbiorcy.
	 * @param string   $case_number Numer SRV.
	 * @param int|null $case_id     Sprawa, ktorej dotyczy mail (slad przy awarii wysylki).
	 * @return bool Wynik wp_mail.
	 */
	public static function send_confirmation( string $email, string $case_number, ?int $case_id = null ): bool {
		$subject = sprintf(
			/* translators: %s: numer sprawy SRV. */
			__( 'Zgłoszenie %s zostało przyjęte', 'mp-service-intake' ),
			$case_number
		);
		$body = sprintf(
			/* translators: 1: nazwa firmy/strony, 2: numer sprawy SRV, 3: adres panelu zgloszen. */
			__( "Twoje zgłoszenie zostało potwierdzone i przyjęte do obsługi w %1\$s.\n\nNumer sprawy: %2\$s\n\nPodawaj ten numer w kontakcie z serwisem. Status sprawy możesz śledzić po zalogowaniu na swoje konto: %3\$s", 'mp-service-intake' ),
			self::nazwa_firmy(),
			$case_number,
			self::adres_panelu()
		) . self::stopka();

		return self::deliver( $email, self::filtruj_temat( $subject, 'przyjecie' ), self::filtruj_tresc( $body, 'przyjecie' ), 'potwierdzenie', $case_id );
	}

	/**
	 * JEDNO GARDLO WYSYLKI (audyt 27.07 — soczewki „obserwowalnosc" i „awarie").
	 *
	 * Funkcja wp_mail() zwraca false przy odmowie serwera poczty i NIE rzuca wyjatku. Bez
	 * tego gardla awaria byla niewidoczna: klient nie dostawal linku, formularz i tak
	 * mowil „sprawdz skrzynke", a w bazie nie zostawal zaden slad. Wzorzec przeniesiony
	 * z Automatora (Sla::notify — log + alert), zeby obie wtyczki reagowaly tak samo.
	 *
	 * @param string   $email   Adres odbiorcy.
	 * @param string   $subject Temat.
	 * @param string   $body    Tresc.
	 * @param string   $kind    Rodzaj maila (magic_link|logowanie|potwierdzenie).
	 * @param int|null $case_id Sprawa (gdy znana) — slad ladue na jej osi.
	 * @return bool Wynik wp_mail.
	 */
	private static function deliver( string $email, string $subject, string $body, string $kind, ?int $case_id ): bool {
		$ok = wp_mail( $email, $subject, $body );

		if ( $ok ) {
			// Udana wysylka gasi alert — inaczej komunikat w Stanie witryny wisialby
			// wiecznie po jednej chwilowej odmowie serwera (i przestalby cokolwiek znaczyc).
			if ( array() !== (array) get_option( self::ALERT_OPTION, array() ) ) {
				delete_option( self::ALERT_OPTION );
			}

			// Alarm globalny gasnie powyzej, ale oznaczenie POJEDYNCZEJ sprawy na
			// ekranie „Niepotwierdzone" musi zgasnac osobno — inaczej personel
			// wiecznie widzi „link nie doszedl" przy sprawie, ktorej link wlasnie
			// doszedl. Wpis dokladamy TYLKO gdy jest co odwolywac, wiec zwykla
			// wysylka nie puchnie osi sprawy ani o jeden wiersz.
			if ( null !== $case_id && $case_id > 0 && self::ma_nieudana_wysylke( $case_id ) ) {
				CaseEvents::log(
					$case_id,
					CaseEvents::MAIL_SENT,
					array( 'kind' => $kind ),
					null
				);
			}

			return true;
		}

		// Slad na osi sprawy — obsluga widzi, ktory mail nie wyszedl i kiedy.
		if ( null !== $case_id && $case_id > 0 ) {
			CaseEvents::log(
				$case_id,
				CaseEvents::MAIL_FAILED,
				array(
					'kind'       => $kind,
					'error_code' => 'smtp_failed',
				),
				null
			);
		}

		// Alert globalny — widoczny w Narzedzia -> Stan witryny takze dla maili
		// bez sprawy (link logowania), bo tam awaria poczty tez blokuje klienta.
		update_option(
			self::ALERT_OPTION,
			array(
				'kind' => $kind,
				'time' => gmdate( 'Y-m-d H:i:s' ),
			),
			false
		);

		return false;
	}

	/**
	 * Czy sprawa ma na osi nieodwolana nieudana wysylke (2.1b).
	 *
	 * Pytamy o OSTATNI wpis pocztowy, nie o „czy kiedykolwiek padlo": po udanej
	 * ponowce jest juz odwolany i drugiego `MAIL_SENT` dokladac nie ma po co.
	 * Jedno zapytanie po indeksowanej kolumnie, tylko przy UDANEJ wysylce ze
	 * znana sprawa — czyli rzadziej niz sama wysylka maila.
	 *
	 * @param int $case_id ID sprawy.
	 * @return bool
	 */
	private static function ma_nieudana_wysylke( int $case_id ): bool {
		global $wpdb;

		$table = \MP\Intake\Tables::full( \MP\Intake\Tables::CASE_EVENTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna append-only, zapytanie przygotowane.
		$ostatni = $wpdb->get_var(
			$wpdb->prepare(
				"SELECT event_type FROM {$table}
				WHERE case_id = %d AND event_type IN ( %s, %s )
				ORDER BY id DESC LIMIT 1",
				$case_id,
				CaseEvents::MAIL_FAILED,
				CaseEvents::MAIL_SENT
			)
		);
		// phpcs:enable

		return CaseEvents::MAIL_FAILED === $ostatni;
	}

	/**
	 * Nazwa firmy z ustawien WordPressa (Ustawienia -> Ogolne -> Tytul witryny).
	 *
	 * PO CO: maile bez nazwy nadawcy w TRESCI wygladaja na spam. Klient dostaje
	 * „Dziekujemy za zgloszenie" i nie wie, od kogo. Bierzemy to z ustawien
	 * strony, wiec dziala od razu, bez zadnej konfiguracji wtyczki.
	 *
	 * @return string
	 */
	private static function nazwa_firmy(): string {
		$nazwa = trim( (string) get_bloginfo( 'name' ) );

		return '' !== $nazwa ? $nazwa : __( 'serwisie', 'mp-service-intake' );
	}

	/**
	 * Adres strony z panelem zgloszen (fallback: strona glowna).
	 *
	 * @return string
	 */
	private static function adres_panelu(): string {
		$page_id = (int) get_option( AccountPage::PAGE_OPTION, 0 );
		$url     = $page_id > 0 ? (string) get_permalink( $page_id ) : '';

		return '' !== $url ? $url : (string) home_url( '/' );
	}

	/**
	 * Stopka maila: nazwa firmy + kontakt zwrotny.
	 *
	 * Telefon/adres bierzemy z filtra `mp_intake_mail_kontakt` — strona moze
	 * podac swoje dane bez dotykania kodu wtyczki. Bez filtra zostaje sama
	 * nazwa i adres strony (i tak lepiej niz nic).
	 *
	 * @return string
	 */
	private static function stopka(): string {
		/**
		 * Filtruje linie kontaktowa w stopce maili systemowych.
		 *
		 * @param string $kontakt Dodatkowa linia (np. telefon, godziny pracy).
		 */
		$kontakt = (string) apply_filters( 'mp_intake_mail_kontakt', '' );

		$stopka = "\n\n---\n" . self::nazwa_firmy() . "\n" . home_url( '/' );

		return '' !== trim( $kontakt ) ? $stopka . "\n" . trim( $kontakt ) : $stopka;
	}

	/**
	 * Filtr tematu maila systemowego (dla programisty strony).
	 *
	 * Tresci NIE wystawiamy w panelu admina swiadomie: te trzy maile nios
	 * jednorazowe linki bezpieczenstwa i wyciecie placeholdera przez pomylke
	 * zepsuloby logowanie. Programista moze je nadpisac filtrem.
	 *
	 * @param string $temat    Temat.
	 * @param string $rodzaj   `potwierdzenie`, `logowanie` albo `przyjecie`.
	 * @return string
	 */
	private static function filtruj_temat( string $temat, string $rodzaj ): string {
		/**
		 * Filtruje temat maila systemowego Intake.
		 *
		 * @param string $temat  Temat.
		 * @param string $rodzaj Rodzaj maila.
		 */
		return (string) apply_filters( 'mp_intake_mail_temat', $temat, $rodzaj );
	}

	/**
	 * Filtr tresci maila systemowego (dla programisty strony).
	 *
	 * @param string $tresc  Tresc.
	 * @param string $rodzaj `potwierdzenie`, `logowanie` albo `przyjecie`.
	 * @return string
	 */
	private static function filtruj_tresc( string $tresc, string $rodzaj ): string {
		/**
		 * Filtruje tresc maila systemowego Intake.
		 *
		 * UWAGA: tresc zawiera jednorazowy link. Nadpisujac ja, zachowaj adres
		 * z oryginalu, inaczej klient nie potwierdzi zgloszenia ani sie nie zaloguje.
		 *
		 * @param string $tresc  Tresc.
		 * @param string $rodzaj Rodzaj maila.
		 */
		return (string) apply_filters( 'mp_intake_mail_tresc', $tresc, $rodzaj );
	}
}
