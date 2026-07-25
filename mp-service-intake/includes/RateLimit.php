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
 * DEDUP-MARKER dalej transient, ustawiany DOPIERO po UDANYM zgloszeniu
 * (mark_submitted) — retry po odrzuceniu NIE jest falszywym duplikatem.
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
	 */
	private const DEDUP_WINDOW = 900;

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
	 * Sprawdza limity i dedup; przy przejsciu inkrementuje liczniki.
	 *
	 * NIE ustawia markera dedup (to robi mark_submitted po sukcesie).
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

		if ( false !== get_transient( self::dedup_key( $serial, $email, $kind ) ) ) {
			return self::BLOCK_DUPLICATE;
		}

		// Atomowy hit-and-check: inkrementujemy licznik i porownujemy NOWA wartosc.
		// N-ta proba => count N (przechodzi), (N+1)-sza => count N+1 > max (blok) —
		// ta sama obserwowalna granica co dawny read-then-bump, ale bez wyscigu.
		if ( '' !== $ip && self::hit( 'mp_rl_ip_' . md5( $ip ), (int) $limits['ip_window'] ) > (int) $limits['ip_max'] ) {
			return self::BLOCK_RATE;
		}

		if ( '' !== $email && self::hit( 'mp_rl_em_' . md5( $email ), (int) $limits['email_window'] ) > (int) $limits['email_max'] ) {
			return self::BLOCK_RATE;
		}

		if ( '' !== $serial && self::hit( 'mp_rl_sn_' . md5( $serial ), (int) $limits['serial_window'] ) > (int) $limits['serial_max'] ) {
			return self::BLOCK_RATE;
		}

		return null;
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
	 * Ustawia marker dedup po UDANYM zgloszeniu (15 min).
	 *
	 * @param string $email  E-mail.
	 * @param string $serial Numer seryjny.
	 * @param string $kind   Rodzaj.
	 * @return void
	 */
	public static function mark_submitted( string $email, string $serial, string $kind ): void {
		set_transient( self::dedup_key( trim( $serial ), strtolower( trim( $email ) ), $kind ), 1, self::DEDUP_WINDOW );
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
		return 'mp_rl_dd_' . md5( $serial . '|' . $email . '|' . $kind );
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
	 * Atomowy licznik rate-limitu w oknie przesuwanym (wlasna tabela).
	 *
	 * Jedna kwerenda = init/inkrement + reset po wygasnieciu okna (jak SrvCounter):
	 * pierwszy hit zaklada wiersz z hits=1; kolejne w oknie inkrementuja; gdy okno
	 * minelo, licznik startuje od 1. window_expires_at odswiezany na kazdym hicie
	 * (okno przesuwane — zgodnie z dawna semantyka odswiezania TTL). LAST_INSERT_ID
	 * zwraca NOWA wartosc licznika w tej samej sesji => brak wyscigu read-modify-write.
	 *
	 * @param string $key    Klucz licznika (bez PII — hash).
	 * @param int    $window Okno w sekundach.
	 * @return int Aktualna liczba hitow w oknie (po tym hicie).
	 */
	private static function hit( string $key, int $window ): int {
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
					window_expires_at = %s",
				$key,
				$expires,
				$now,
				$expires
			)
		);

		$count = (int) $wpdb->get_var( 'SELECT LAST_INSERT_ID()' );
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
