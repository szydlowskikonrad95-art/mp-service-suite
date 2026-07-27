<?php
/**
 * Testy „Stanu witryny" dla Intake (C) — diagnostyka wdrozenia u klienta.
 *
 * Zglaszamy tylko to, czego awaria REALNIE psuje funkcje i co klient moze
 * naprawic na swoim hostingu. Kazdy test ma powiedziec: co nie dziala,
 * dlaczego to boli i co z tym zrobic.
 *
 * @package MP\Intake\Admin
 */

namespace MP\Intake\Admin;

use MP\Intake\Common\SiteHealth;
use MP\Intake\Attachments;

/**
 * Rejestracja testow Intake w Narzedzia -> Stan witryny.
 */
final class SiteHealthTests {

	/**
	 * Wpina testy w natywny ekran WP.
	 *
	 * @return void
	 */
	public static function register(): void {
		SiteHealth::register(
			'mp_intake',
			array(
				'fileinfo'     => array( self::class, 'test_fileinfo' ),
				'obrazy'       => array( self::class, 'test_biblioteka_obrazow' ),
				'https'        => array( self::class, 'test_https' ),
				'nadawca'      => array( self::class, 'test_nadawca' ),
				'upload_limit' => array( self::class, 'test_limit_uploadu' ),
				'poczta_lokal' => array( self::class, 'test_srodowisko_lokalne' ),
				'sieroty'      => array( self::class, 'test_sieroty_weryfikacji' ),
			)
		);
	}

	/**
	 * Sieroty weryfikacji: sprawy potwierdzone, o ktorych automatyzacja nie wie.
	 *
	 * Awaria w trakcie potwierdzania (pad PHP/restart bazy) mogla urwac
	 * zdarzenie narodzin sprawy — SLA nie ruszy, nikt nie przydzieli, klient
	 * czeka, a na oko wszystko wyglada dobrze (audyt #1). Sweep SLA doszywa
	 * takie sprawy co 5 minut; ten test swieci, gdyby doszywanie nie dzialalo
	 * (np. Automator wylaczony) i zaleglosc rosla.
	 *
	 * @return array<string, mixed>
	 */
	public static function test_sieroty_weryfikacji(): array {
		$ile = count( \MP\Intake\CaseRepo::unlaunched_ids( 10, 20 ) );

		if ( 0 === $ile ) {
			return SiteHealth::wynik(
				'mp_intake_sieroty',
				'good',
				__( 'Zgłoszenia: każda potwierdzona sprawa trafiła do automatyzacji', 'mp-service-intake' ),
				__( 'Nie ma spraw potwierdzonych, które ominęły automatyczny przydział i pilnowanie terminów.', 'mp-service-intake' )
			);
		}

		return SiteHealth::wynik(
			'mp_intake_sieroty',
			'critical',
			sprintf(
				/* translators: %d: liczba spraw. */
				_n(
					'%d potwierdzona sprawa czeka poza automatyzacją',
					'%d potwierdzonych spraw czeka poza automatyzacją',
					$ile,
					'mp-service-intake'
				),
				$ile
			),
			__( 'Te sprawy zostały potwierdzone przez klientów, ale automatyzacja o nich nie wie: nikt ich nie przydzieli i nie pilnuje ich terminów. Zwykle znaczy to, że wtyczka MP Workflow Automator jest wyłączona albo jej zadanie cykliczne (WP-Cron) nie chodzi.', 'mp-service-intake' ),
			__( 'Włącz wtyczkę MP Workflow Automator i sprawdź w tym ekranie test „cykliczne sprawdzanie terminów". Po najbliższym przebiegu (do 5 minut) sprawy zostaną doszyte automatycznie.', 'mp-service-intake' )
		);
	}

	/**
	 * Rozszerzenie ext-fileinfo: bez niego ZADEN zalacznik nie przejdzie.
	 *
	 * Rozpoznajemy typ pliku po TRESCI (nie po rozszerzeniu). Bez `finfo_open`
	 * wykrywanie zwraca pusty typ, ktorego nie ma na bialej liscie — czyli
	 * fail-closed: bezpiecznie, ale klient dostaje „Niedozwolony typ pliku"
	 * przy POPRAWNYM zdjeciu i nie ma jak zgadnac przyczyny.
	 *
	 * @return array<string, mixed>
	 */
	public static function test_fileinfo(): array {
		if ( function_exists( 'finfo_open' ) ) {
			return SiteHealth::wynik(
				'mp_intake_fileinfo',
				'good',
				__( 'Załączniki: rozpoznawanie typu plików działa', 'mp-service-intake' ),
				__( 'Rozszerzenie PHP „fileinfo" jest dostępne, więc typ pliku sprawdzamy po jego zawartości, a nie po nazwie.', 'mp-service-intake' )
			);
		}

		return SiteHealth::wynik(
			'mp_intake_fileinfo',
			'critical',
			__( 'Załączniki NIE DZIAŁAJĄ — brak rozszerzenia PHP „fileinfo"', 'mp-service-intake' ),
			__( 'Typ pliku sprawdzamy po zawartości. Bez rozszerzenia „fileinfo" system nie potrafi tego zrobić i dla bezpieczeństwa odrzuca KAŻDY załącznik — klient zobaczy komunikat „Niedozwolony typ pliku" nawet przy poprawnym zdjęciu.', 'mp-service-intake' ),
			__( 'Poproś hosting o włączenie rozszerzenia PHP „fileinfo" (zwykle jedno kliknięcie w panelu albo linia w php.ini).', 'mp-service-intake' )
		);
	}

	/**
	 * Imagick albo GD: bez nich EXIF/GPS zostaje w zdjeciach (RODO).
	 *
	 * @return array<string, mixed>
	 */
	public static function test_biblioteka_obrazow(): array {
		if ( Attachments::has_image_library() ) {
			return SiteHealth::wynik(
				'mp_intake_obrazy',
				'good',
				__( 'Zdjęcia: dane EXIF są usuwane', 'mp-service-intake' ),
				__( 'Serwer ma bibliotekę obrazów (Imagick lub GD), więc ze zdjęć usuwamy metadane — w tym lokalizację GPS.', 'mp-service-intake' )
			);
		}

		return SiteHealth::wynik(
			'mp_intake_obrazy',
			'recommended',
			__( 'Zdjęcia zachowują dane EXIF (w tym GPS)', 'mp-service-intake' ),
			__( 'Serwer nie ma ani Imagick, ani GD. Zdjęcia usterek trafiają do systemu z metadanymi — w tym z lokalizacją, w której zrobiono zdjęcie. To dane osobowe, których nikt nie zamierzał zbierać.', 'mp-service-intake' ),
			__( 'Poproś hosting o włączenie rozszerzenia PHP „imagick" albo „gd".', 'mp-service-intake' )
		);
	}

	/**
	 * HTTPS: magic-linki i dane osobowe nie moga leciec otwartym tekstem.
	 *
	 * @return array<string, mixed>
	 */
	public static function test_https(): array {
		if ( str_starts_with( (string) home_url(), 'https://' ) ) {
			return SiteHealth::wynik(
				'mp_intake_https',
				'good',
				__( 'Połączenie szyfrowane (HTTPS)', 'mp-service-intake' ),
				__( 'Strona działa po HTTPS, więc linki logowania i dane klientów są szyfrowane.', 'mp-service-intake' )
			);
		}

		return SiteHealth::wynik(
			'mp_intake_https',
			'critical',
			__( 'Brak HTTPS — dane klientów lecą otwartym tekstem', 'mp-service-intake' ),
			__( 'Klient loguje się jednorazowym linkiem z e-maila i widzi swoje dane osobowe oraz historię spraw. Bez HTTPS ten link i te dane może przechwycić ktoś w tej samej sieci.', 'mp-service-intake' ),
			__( 'Włącz certyfikat SSL (na większości hostingów darmowy Let\'s Encrypt) i przestaw adres witryny na https://.', 'mp-service-intake' )
		);
	}

	/**
	 * Adres nadawcy: domyslny `wordpress@domena` to prosta droga do spamu.
	 *
	 * @return array<string, mixed>
	 */
	public static function test_nadawca(): array {
		$adres = (string) apply_filters( 'wp_mail_from', self::domyslny_adres_wp() );

		if ( ! SiteHealth::nadawca_domyslny( $adres ) ) {
			return SiteHealth::wynik(
				'mp_intake_nadawca',
				'good',
				/* translators: %s: adres e-mail nadawcy. */
				sprintf( __( 'Adres nadawcy ustawiony: %s', 'mp-service-intake' ), esc_html( $adres ) ),
				__( 'Powiadomienia wychodzą z konkretnego adresu w Twojej domenie — to zmniejsza ryzyko trafienia do spamu.', 'mp-service-intake' )
			);
		}

		return SiteHealth::wynik(
			'mp_intake_nadawca',
			'recommended',
			/* translators: %s: adres e-mail nadawcy. */
			sprintf( __( 'Poczta wychodzi z domyślnego adresu %s', 'mp-service-intake' ), esc_html( $adres ) ),
			__( 'WordPress używa adresu „wordpress@" + domena, gdy nikt nie ustawi innego. Taka skrzynka zwykle nie istnieje, więc filtry antyspamowe traktują wiadomość podejrzliwie, a odbicia nie mają dokąd wrócić. Jeśli klient nie dostanie linku logowania — nie wejdzie na swoje konto.', 'mp-service-intake' ),
			__( 'Ustaw istniejący adres w domenie strony (np. serwis@twojadomena.pl) — najprościej wtyczką SMTP, np. WP Mail SMTP, która przy okazji wysyła pocztę przez serwer Twojej skrzynki.', 'mp-service-intake' )
		);
	}

	/**
	 * Limit uploadu serwera vs limit zalacznika we wtyczce.
	 *
	 * @return array<string, mixed>
	 */
	public static function test_limit_uploadu(): array {
		$serwer = (int) wp_max_upload_size();
		$nasz   = (int) Attachments::MAX_BYTES;

		if ( ! SiteHealth::upload_za_maly( $serwer, $nasz ) ) {
			return SiteHealth::wynik(
				'mp_intake_upload_limit',
				'good',
				/* translators: %s: limit rozmiaru pliku. */
				sprintf( __( 'Limit wgrywanych plików: %s', 'mp-service-intake' ), size_format( $serwer ) ),
				__( 'Serwer przyjmie załączniki w rozmiarze, jakiego oczekuje formularz zgłoszenia.', 'mp-service-intake' )
			);
		}

		return SiteHealth::wynik(
			'mp_intake_upload_limit',
			'recommended',
			/* translators: 1: limit serwera, 2: limit wtyczki. */
			sprintf( __( 'Serwer przyjmuje mniejsze pliki (%1$s) niż formularz (%2$s)', 'mp-service-intake' ), size_format( $serwer ), size_format( $nasz ) ),
			__( 'Formularz zapowiada klientowi załączniki do 8 MB, ale serwer utnie je wcześniej. Klient zobaczy błąd przy zdjęciu z telefonu, które dziś potrafi ważyć kilka megabajtów.', 'mp-service-intake' ),
			__( 'Poproś hosting o podniesienie „upload_max_filesize" i „post_max_size" do co najmniej 8 MB.', 'mp-service-intake' )
		);
	}

	/**
	 * Instalacja lokalna: poczta tu zwykle NIE WYCHODZI — i to nie jest awaria
	 * systemu, tylko brak serwera pocztowego na komputerze.
	 *
	 * PO CO TEN TEST: osoba testujaca wtyczke lokalnie wysyla zgloszenie, nie
	 * dostaje magic-linku i wyciaga wniosek „logowanie klienta nie dziala".
	 * Test mowi jej wprost, co sie dzieje i jak przejsc sciezke mimo to.
	 *
	 * @return array<string, mixed>
	 */
	public static function test_srodowisko_lokalne(): array {
		$typ = function_exists( 'wp_get_environment_type' ) ? (string) wp_get_environment_type() : 'production';

		if ( 'local' !== $typ && 'development' !== $typ ) {
			return SiteHealth::wynik(
				'mp_intake_poczta_lokal',
				'good',
				__( 'Środowisko produkcyjne', 'mp-service-intake' ),
				__( 'To nie jest instalacja lokalna, więc poczta powinna wychodzić normalnie — o ile hosting ma skonfigurowaną wysyłkę.', 'mp-service-intake' )
			);
		}

		return SiteHealth::wynik(
			'mp_intake_poczta_lokal',
			'recommended',
			__( 'Instalacja lokalna — e-maile prawdopodobnie nie będą wychodzić', 'mp-service-intake' ),
			__( 'Wygląda to na WordPressa uruchomionego lokalnie (na komputerze). Takie instalacje zwykle nie mają serwera pocztowego, więc link potwierdzający i link logowania NIE PRZYJDĄ na skrzynkę. To ograniczenie środowiska, nie systemu — na hostingu z pocztą wszystko zadziała.', 'mp-service-intake' ),
			__( 'Żeby mimo to przejść całą ścieżkę klienta, wygeneruj link logowania komendą WP-CLI: wp mp login-link adres@example.com — otworzysz panel bez maila. Alternatywnie zainstaluj lokalny przechwytywacz poczty (np. Mailpit lub MailHog) i skonfiguruj wysyłkę przez SMTP na localhost.', 'mp-service-intake' )
		);
	}

	/**
	 * Adres, ktorego uzylby rdzen WP przy braku naglowka From
	 * (`pluggable.php`: „wordpress@" + domena bez www).
	 *
	 * @return string
	 */
	private static function domyslny_adres_wp(): string {
		$host = (string) wp_parse_url( network_home_url(), PHP_URL_HOST );

		if ( str_starts_with( $host, 'www.' ) ) {
			$host = substr( $host, 4 );
		}

		return 'wordpress@' . $host;
	}
}
