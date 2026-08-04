<?php
/**
 * Ochrona zgloszen (P1.6): rate-limit warstwowy + dedup twardy waski.
 *
 * Warstwy (domyslne, konfigurowalne filtrem `mp_intake_rate_limits`):
 *  - IP:     10 / 10 min   (anty-flood z jednego adresu)
 *  - e-mail:  3 / doba
 *  - serial:  5 / doba
 * Dedup twardy: ten sam (serial + e-mail + rodzaj) w 15 min = duplikat.
 *
 * Licznik = ATOMOWA tabela mp_rate_counters (okno przesuwane; INSERT ... ON
 * DUPLICATE KEY UPDATE + LAST_INSERT_ID jak SrvCounter) — odporny na wyscig
 * rownoleglych zadan (dawny transientowy read-modify-write przepuszczal N zadan
 * naraz, D3). Wygasle wiersze sprzata cron retencji (cleanup_expired).
 * DEDUP = REZERWACJA (claim) na tej samej tabeli (znalezisko #4 audytu 27.07):
 * atomowo zajmowana PRZED utworzeniem sprawy — dwa rownolegle POST-y tego
 * samego zgloszenia nie przejda oba (dawny transientowy check-then-set
 * przepuszczal obydwa: dwie sprawy, dwa maile). Semantyka D5 zachowana:
 * blad walidacji ZWALNIA rezerwacje (release_claim) — retry po odrzuceniu
 * NIE jest falszywym duplikatem; sukces przedluza okno (mark_submitted).
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Rate-limit i dedup zgloszen z frontu.
 */
final class RateLimit {

	/**
	 * Powod blokady: przekroczony limit czestotliwosci.
	 */
	public const BLOCK_RATE = 'rate';

	/**
	 * Powod blokady: duplikat (serial+email+rodzaj w oknie dedup).
	 */
	public const BLOCK_DUPLICATE = 'duplicate';

	/**
	 * Okno dedup w sekundach (15 min).
	 *
	 * PUBLICZNA, bo ta sama liczba musi trafic do KLIENTA: komunikat o odrzuconym
	 * duplikacie mowi mu, ile ma odczekac, zanim zglosi INNA usterke tego samego
	 * sprzetu. Wpisana slownie („kwadrans") rozjechalaby sie po pierwszej zmianie
	 * okna — dokladnie tak jak TTL linku logowania (`Front\Login::TTL_SECONDS`).
	 */
	public const DEDUP_WINDOW = 900;

	/**
	 * Okno dedup w PELNYCH minutach — do komunikatow dla czlowieka.
	 *
	 * @return int Minuty (minimum 1, zeby komunikat nigdy nie mowil „0 minut").
	 */
	public static function dedup_minutes(): int {
		return max( 1, (int) round( self::DEDUP_WINDOW / 60 ) );
	}

	/**
	 * Domyslne limity (nadpisywalne filtrem).
	 *
	 * @return array{ip_max:int, ip_window:int, email_max:int, email_window:int, serial_max:int, serial_window:int}
	 */
	private static function limits(): array {
		$defaults = array(
			'ip_max'        => 10,
			'ip_window'     => 10 * MINUTE_IN_SECONDS,
			'email_max'     => 3,
			'email_window'  => DAY_IN_SECONDS,
			'serial_max'    => 5,
			'serial_window' => DAY_IN_SECONDS,
		);

		/**
		 * Filtr limitow ochrony zgloszen (admin/konfiguracja moze nadpisac).
		 *
		 * @param array $defaults Domyslne limity.
		 */
		$limits = (array) apply_filters( 'mp_intake_rate_limits', $defaults );

		return array_merge( $defaults, $limits );
	}

	/**
	 * Sprawdza limity i dedup PRZED utworzeniem sprawy.
	 *
	 * D5: liczniki e-mail/serial NIE sa tu inkrementowane — tylko odczytywane.
	 * Inkrement (record_submission) nastepuje dopiero po UDANYM zgloszeniu, wiec
	 * user z literowka/bledem walidacji nie wyczerpuje swojego limitu dobowego.
	 * Limit IP (anty-flood) inkrementuje sie tutaj atomowo — kazda proba, tez
	 * nieudana, liczy sie do ochrony przed zalewem z jednego adresu.
	 * NIE ustawia markera dedup (to robi record_submission po sukcesie).
	 *
	 * @param string $ip     Adres IP klienta (z RateLimit::client_ip() — filtr mp_intake_client_ip, domyslnie REMOTE_ADDR).
	 * @param string $email  E-mail zglaszajacego.
	 * @param string $serial Numer seryjny (moze byc pusty).
	 * @param string $kind   Rodzaj sprawy.
	 * @return string|null Powod blokady (BLOCK_*) albo null gdy OK.
	 */
	public static function check( string $ip, string $email, string $serial, string $kind ): ?string {
		$email  = strtolower( trim( $email ) );
		$serial = trim( $serial );
		$limits = self::limits();

		// Dedup: rezerwacja w tabeli (nie transient — pod object-cache transient
		// omija baze i dawal osobny wyscig). Tu tylko ODCZYT (szybka odpowiedz
		// dla klienta); atomowa bramka = claim_submission przed utworzeniem sprawy.
		if ( self::current_count( self::dedup_key( $serial, $email, $kind ) ) > 0 ) {
			return self::BLOCK_DUPLICATE;
		}

		// IP (anty-flood): atomowy hit-and-check — liczy KAZDA probe (tez nieudana).
		if ( '' !== $ip && self::hit( 'mp_rl_ip_' . md5( $ip ), (int) $limits['ip_window'] ) > (int) $limits['ip_max'] ) {
			return self::BLOCK_RATE;
		}

		// E-mail/serial: TYLKO odczyt biezacej liczby w oknie (bez inkrementu — D5).
		if ( '' !== $email && self::current_count( 'mp_rl_em_' . md5( $email ) ) >= (int) $limits['email_max'] ) {
			return self::BLOCK_RATE;
		}

		if ( '' !== $serial && self::current_count( self::serial_counter_key( $serial ) ) >= (int) $limits['serial_max'] ) {
			return self::BLOCK_RATE;
		}

		return null;
	}

	/**
	 * D5: rejestruje UDANE zgloszenie — inkrementuje liczniki e-mail/serial i
	 * ustawia marker dedup. Wolane PO utworzeniu sprawy (nie na kazda probe).
	 *
	 * @param string $email  E-mail.
	 * @param string $serial Numer seryjny (moze byc pusty).
	 * @param string $kind   Rodzaj.
	 * @return void
	 */
	public static function record_submission( string $email, string $serial, string $kind ): void {
		$email  = strtolower( trim( $email ) );
		$serial = trim( $serial );
		$limits = self::limits();

		// 2.31: okno NIERUCHOME, liczone od pierwszego zgloszenia. Klient dostal na
		// pismie „3 zgloszenia na dobe" — przy oknie przesuwanym kazde udane
		// zgloszenie odsuwalo koniec doby i limit dzialal jak „trzy pod rzad".
		if ( '' !== $email ) {
			self::hit( 'mp_rl_em_' . md5( $email ), (int) $limits['email_window'], false );
		}

		if ( '' !== $serial ) {
			self::hit( self::serial_counter_key( $serial ), (int) $limits['serial_window'], false );
		}

		self::mark_submitted( $email, $serial, $kind );
	}

	/**
	 * Biezaca liczba hitow licznika w AKTYWNYM oknie (0 gdy brak/wygaslo).
	 * Odczyt bez inkrementu (D5).
	 *
	 * @param string $key Klucz licznika.
	 * @return int
	 */
	private static function current_count( string $key ): int {
		global $wpdb;

		$table = Tables::full( Tables::RATE_COUNTERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; odczyt licznika w oknie.
		$hits = $wpdb->get_var(
			$wpdb->prepare(
				"SELECT hits FROM {$table} WHERE rl_key = %s AND window_expires_at > %s",
				$key,
				gmdate( 'Y-m-d H:i:s' )
			)
		);
		// phpcs:enable

		return null === $hits ? 0 : (int) $hits;
	}

	/**
	 * Realny adres IP klienta uzywany do rate-limitu.
	 *
	 * DOMYSLNIE = REMOTE_ADDR (bezpiecznie). Za reverse-proxy / Cloudflare
	 * WSZYSCY klienci maja IP proxy = 1 adres => rate-limit zablokowalby
	 * wszystkich. Wdrozeniowiec podpina filtr `mp_intake_client_ip` do
	 * ZAUFANEGO zrodla IP. Kod celowo NIE ufa slepo `X-Forwarded-For`
	 * (spoofowalny naglowek) — to decyzja wdrozenia, nie domyslka kodu.
	 * Nota wdrozeniowa: patrz dokumentacja-techniczna/SECURITY.md §7.
	 *
	 * @return string Adres IP (moze byc pusty, gdy brak REMOTE_ADDR).
	 */
	public static function client_ip(): string {
		$remote_addr = isset( $_SERVER['REMOTE_ADDR'] )
			? sanitize_text_field( wp_unslash( (string) $_SERVER['REMOTE_ADDR'] ) )
			: '';

		/**
		 * Filtr realnego IP klienta do rate-limitu.
		 *
		 * Domyslnie REMOTE_ADDR. Za proxy podepnij ZAUFANE zrodlo IP.
		 *
		 * @param string $remote_addr REMOTE_ADDR (juz zsanityzowany) = domyslne zrodlo.
		 */
		$ip = (string) apply_filters( 'mp_intake_client_ip', $remote_addr );

		// Ponowna sanityzacja wyniku filtra (hook moze zwrocic surowa wartosc naglowka).
		return sanitize_text_field( $ip );
	}

	/**
	 * Atomowa REZERWACJA dedup PRZED utworzeniem sprawy (znalezisko #4).
	 *
	 * Dwa rownolegle POST-y tego samego zgloszenia: pierwszy dostaje true
	 * (licznik = 1), drugi false (licznik > 1 w aktywnym oknie). Wygasle okno
	 * = rezerwacja od nowa. Ten sam wzorzec LAST_INSERT_ID co hit(), ale okno
	 * NIE jest przedluzane cudza proba (liczy sie od pierwszej rezerwacji).
	 *
	 * @param string $email  E-mail.
	 * @param string $serial Numer seryjny (moze byc pusty).
	 * @param string $kind   Rodzaj.
	 * @return bool True = rezerwacja nasza (mozna tworzyc sprawe).
	 */
	public static function claim_submission( string $email, string $serial, string $kind ): bool {
		return self::claim_window( self::dedup_key( trim( $serial ), strtolower( trim( $email ) ), $kind ), self::DEDUP_WINDOW );
	}

	/**
	 * Generyczna atomowa rezerwacja klucza w oknie (audyt #4/#5).
	 *
	 * Pierwsze zadanie w oknie dostaje true; kazde kolejne false, dopoki okno
	 * zyje. Okno NIE jest przedluzane cudza proba (liczy sie od pierwszej
	 * rezerwacji). Wzorzec LAST_INSERT_ID jak hit()/SrvCounter.
	 *
	 * @param string $key    Klucz (bez PII — hash).
	 * @param int    $window Okno w sekundach.
	 * @return bool True = rezerwacja nasza.
	 */
	public static function claim_window( string $key, int $window ): bool {
		global $wpdb;

		$table   = Tables::full( Tables::RATE_COUNTERS );
		$now     = gmdate( 'Y-m-d H:i:s' );
		$expires = gmdate( 'Y-m-d H:i:s', time() + $window );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; jedna kwerenda = atomowa rezerwacja pod unikalnym kluczem.
		$wpdb->query(
			$wpdb->prepare(
				"INSERT INTO {$table} (rl_key, hits, window_expires_at)
				VALUES (%s, LAST_INSERT_ID(1), %s)
				ON DUPLICATE KEY UPDATE
					hits = LAST_INSERT_ID( IF( window_expires_at <= %s, 1, hits + 1 ) ),
					window_expires_at = IF( window_expires_at <= %s, %s, window_expires_at )",
				$key,
				$expires,
				$now,
				$now,
				$expires
			)
		);

		$count = (int) $wpdb->insert_id;
		// phpcs:enable

		return 1 === $count;
	}

	/**
	 * Zwalnia rezerwacje dedup po ODRZUCONYM zgloszeniu (blad walidacji).
	 *
	 * D5: retry po odrzuceniu nie jest duplikatem — klient poprawia literowke
	 * i wysyla ponownie bez czekania 15 min.
	 *
	 * @param string $email  E-mail.
	 * @param string $serial Numer seryjny (moze byc pusty).
	 * @param string $kind   Rodzaj.
	 * @return void
	 */
	public static function release_claim( string $email, string $serial, string $kind ): void {
		global $wpdb;

		$key   = self::dedup_key( trim( $serial ), strtolower( trim( $email ) ), $kind );
		$table = Tables::full( Tables::RATE_COUNTERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; zwolnienie rezerwacji.
		$wpdb->query( $wpdb->prepare( "DELETE FROM {$table} WHERE rl_key = %s", $key ) );
		// phpcs:enable
	}

	/**
	 * Utrwala marker dedup po UDANYM zgloszeniu: okno 15 min liczone od
	 * SUKCESU (rezerwacja z claim_submission mogla powstac chwile wczesniej).
	 *
	 * @param string $email  E-mail.
	 * @param string $serial Numer seryjny.
	 * @param string $kind   Rodzaj.
	 * @return void
	 */
	public static function mark_submitted( string $email, string $serial, string $kind ): void {
		global $wpdb;

		$key     = self::dedup_key( trim( $serial ), strtolower( trim( $email ) ), $kind );
		$table   = Tables::full( Tables::RATE_COUNTERS );
		$expires = gmdate( 'Y-m-d H:i:s', time() + self::DEDUP_WINDOW );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; utrwalenie markera dedup.
		$wpdb->query(
			$wpdb->prepare(
				"INSERT INTO {$table} (rl_key, hits, window_expires_at)
				VALUES (%s, 1, %s)
				ON DUPLICATE KEY UPDATE window_expires_at = %s",
				$key,
				$expires,
				$expires
			)
		);
		// phpcs:enable
	}

	/**
	 * Klucz dedup (hash serial|email|rodzaj — bez PII w nazwie opcji).
	 *
	 * @param string $serial Serial.
	 * @param string $email  E-mail (juz znormalizowany).
	 * @param string $kind   Rodzaj.
	 * @return string
	 */
	private static function dedup_key( string $serial, string $email, string $kind ): string {
		// 2.1(a): numer seryjny wchodzi do klucza ZNORMALIZOWANY, tak jak wszedzie
		// indziej w produkcie. Wczesniej szedl po samym `trim()`, wiec „ABC-123"
		// i „abc123" dawaly DWA klucze i ochrona przed duplikatem konczyla sie na
		// jednym myslniku. Reguly nie wymyslamy: `Common\Str::normalize_serial()`
		// istnieje w produkcie z kontraktem autora („«ABC-123» i «abc 123» to TEN
		// SAM serial") i tak samo liczy ja rejestr produktow oraz walidator.
		// NORMALIZUJEMY TUTAJ, w jednym gardle — cztery miejsca wolajace ten klucz
		// (odczyt, rezerwacja, zwolnienie, marker sukcesu) musza liczyc go IDENTYCZNIE,
		// inaczej rezerwacji nie da sie zwolnic tym samym kluczem, ktorym powstala.
		return 'mp_rl_dd_' . md5( Common\Str::normalize_serial( $serial ) . '|' . $email . '|' . $kind );
	}

	/**
	 * Klucz licznika dobowego dla numeru seryjnego (2.1a — ta sama normalizacja).
	 *
	 * Limit „5 zgloszen na numer seryjny na dobe" obchodzilo sie tak samo jak
	 * ochrone przed duplikatem: doklejeniem myslnika. Licznik i dedup musza
	 * rozpoznawac ten sam egzemplarz sprzetu, wiec licza numer tak samo.
	 *
	 * @param string $serial Numer seryjny (surowy).
	 * @return string
	 */
	private static function serial_counter_key( string $serial ): string {
		return 'mp_rl_sn_' . md5( Common\Str::normalize_serial( $serial ) );
	}

	/**
	 * Domyslne limity ZADAN LINKU LOGOWANIA (magic-link) — nadpisywalne filtrem.
	 *
	 * @return array{ip_max:int, ip_window:int, email_max:int, email_window:int}
	 */
	private static function login_limits(): array {
		$defaults = array(
			'ip_max'       => 5,
			'ip_window'    => 15 * MINUTE_IN_SECONDS,
			'email_max'    => 5,
			'email_window' => HOUR_IN_SECONDS,
		);

		/**
		 * Filtr limitow zadan linku logowania (wdrozeniowiec moze nadpisac).
		 *
		 * @param array $defaults Domyslne limity.
		 */
		return array_merge( $defaults, (array) apply_filters( 'mp_intake_login_rate_limits', $defaults ) );
	}

	/**
	 * Rate-limit ZADAN LINKU LOGOWANIA (osobne liczniki od formularza zgloszen).
	 *
	 * Chroni skrzynki klientow przed zalewem linkami + endpoint przed naduzyciem.
	 * Klucze rozlaczne z `check()` (prefiks `mp_rl_login_`). Przy przejsciu bumpuje
	 * IP i email. NIE zdradza istnienia konta — wolajacy pokazuje neutralny komunikat.
	 *
	 * @param string $ip    Adres IP (z RateLimit::client_ip()).
	 * @param string $email E-mail z formularza logowania.
	 * @return string|null BLOCK_RATE gdy limit przekroczony, null gdy OK.
	 */
	public static function check_login( string $ip, string $email ): ?string {
		$email  = strtolower( trim( $email ) );
		$limits = self::login_limits();

		if ( '' !== $ip && self::hit( 'mp_rl_login_ip_' . md5( $ip ), (int) $limits['ip_window'] ) > (int) $limits['ip_max'] ) {
			return self::BLOCK_RATE;
		}

		if ( '' !== $email && self::hit( 'mp_rl_login_em_' . md5( $email ), (int) $limits['email_window'] ) > (int) $limits['email_max'] ) {
			return self::BLOCK_RATE;
		}

		return null;
	}

	/**
	 * Atomowy licznik rate-limitu w oknie (wlasna tabela).
	 *
	 * Jedna kwerenda = init/inkrement + reset po wygasnieciu okna (jak SrvCounter):
	 * pierwszy hit zaklada wiersz z hits=1; kolejne w oknie inkrementuja; gdy okno
	 * minelo, licznik startuje od 1. LAST_INSERT_ID zwraca NOWA wartosc licznika
	 * w tej samej sesji => brak wyscigu read-modify-write.
	 *
	 * ⛔ DWA RODZAJE OKNA (audyt 2.31) — roznica jest widoczna dla klienta:
	 *
	 * · `$przesuwane = true` (OCHRONA PRZECIWZALEWOWA: IP, zadania linku logowania).
	 *   Koniec okna odswiezany przy KAZDYM trafieniu. Kto puka bez przerwy, zostaje
	 *   zablokowany, dopoki nie przestanie. Dla ochrony przed zalewem to zachowanie
	 *   pozadane i celowo zostaje.
	 *
	 * · `$przesuwane = false` (LIMITY ZGLOSZEN: e-mail, numer seryjny).
	 *   Okno liczone od PIERWSZEGO zgloszenia i nieruchome. Tego wymaga obietnica
	 *   dana klientowi na pismie — „3 zgloszenia na dobe". Przy oknie przesuwanym
	 *   klient skladajacy po jednym zgloszeniu dziennie dostawal odmowe czwartego
	 *   dnia, bo kazde udane zgloszenie przesuwalo koniec okna i licznik nigdy sie
	 *   nie zerowal. „Na dobe" dzialalo jak „trzy pod rzad" — a instrukcja kazala
	 *   obsludze sprawdzic, ile klient wyslal DZIS, wiec pracownik widzial zero
	 *   zgloszen z dzisiaj i nie znajdowal przyczyny blokady.
	 *
	 * @param string $key        Klucz licznika (bez PII — hash).
	 * @param int    $window     Okno w sekundach.
	 * @param bool   $przesuwane Czy koniec okna ma sie przesuwac przy kazdym trafieniu.
	 * @return int Aktualna liczba hitow w oknie (po tym hicie).
	 */
	private static function hit( string $key, int $window, bool $przesuwane = true ): int {
		global $wpdb;

		$table   = Tables::full( Tables::RATE_COUNTERS );
		$now     = gmdate( 'Y-m-d H:i:s' );
		$expires = gmdate( 'Y-m-d H:i:s', time() + $window );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; jedna kwerenda = atomowy inkrement + reset okna (D3).
		$wpdb->query(
			$wpdb->prepare(
				"INSERT INTO {$table} (rl_key, hits, window_expires_at)
				VALUES (%s, LAST_INSERT_ID(1), %s)
				ON DUPLICATE KEY UPDATE
					hits = LAST_INSERT_ID( IF( window_expires_at <= %s, 1, hits + 1 ) ),
					window_expires_at = IF( %d = 1 OR window_expires_at <= %s, %s, window_expires_at )",
				$key,
				$expires,
				$now,
				$przesuwane ? 1 : 0,
				$now,
				$expires
			)
		);

		// D7: nowa wartosc z $wpdb->insert_id (INSERT..ODKU z LAST_INSERT_ID(expr)
		// odswieza insert_id — zweryfikowane). Bezpieczniejsze na HyperDB niz osobny
		// SELECT LAST_INSERT_ID() (moglby trafic na replike odczytowa).
		$count = (int) $wpdb->insert_id;
		// phpcs:enable

		return $count;
	}

	/**
	 * Kasuje wygasle liczniki rate-limitu (wolane z crona retencji).
	 *
	 * @return int Liczba usunietych wierszy.
	 */
	public static function cleanup_expired(): int {
		global $wpdb;

		$table = Tables::full( Tables::RATE_COUNTERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; sprzatanie wygaslych okien.
		$deleted = $wpdb->query(
			$wpdb->prepare( "DELETE FROM {$table} WHERE window_expires_at <= %s", gmdate( 'Y-m-d H:i:s' ) )
		);
		// phpcs:enable

		return (int) $deleted;
	}
}
