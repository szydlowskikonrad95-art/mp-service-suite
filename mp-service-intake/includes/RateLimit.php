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
 * Licznik = transient (okno przesuwane; TTL odswiezany przy DOZWOLONYM hicie).
 * DEDUP-MARKER ustawiany DOPIERO po UDANYM zgloszeniu (mark_submitted) — dzieki
 * temu retry po odrzuceniu (np. brak zgody) NIE jest falszywym duplikatem.
 *
 * ⚠️ Transienty pod obiektowym cache (redis/memcached) moga sie roznic od DB;
 * na demo (bez object-cache) licza sie z wp_options. Dla twardszej gwarancji
 * = wlasna tabela (poza zakresem P1.6 anty-spamu).
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
	 * @param string $ip     Adres IP (REMOTE_ADDR).
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

		if ( '' !== $ip && self::over_limit( 'mp_rl_ip_' . md5( $ip ), (int) $limits['ip_max'] ) ) {
			return self::BLOCK_RATE;
		}

		if ( '' !== $email && self::over_limit( 'mp_rl_em_' . md5( $email ), (int) $limits['email_max'] ) ) {
			return self::BLOCK_RATE;
		}

		if ( '' !== $serial && self::over_limit( 'mp_rl_sn_' . md5( $serial ), (int) $limits['serial_max'] ) ) {
			return self::BLOCK_RATE;
		}

		if ( '' !== $ip ) {
			self::bump( 'mp_rl_ip_' . md5( $ip ), (int) $limits['ip_window'] );
		}
		if ( '' !== $email ) {
			self::bump( 'mp_rl_em_' . md5( $email ), (int) $limits['email_window'] );
		}
		if ( '' !== $serial ) {
			self::bump( 'mp_rl_sn_' . md5( $serial ), (int) $limits['serial_window'] );
		}

		return null;
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
	 * Czy licznik osiagnal limit.
	 *
	 * @param string $key Klucz transienta.
	 * @param int    $max Limit.
	 * @return bool
	 */
	private static function over_limit( string $key, int $max ): bool {
		return (int) get_transient( $key ) >= $max;
	}

	/**
	 * Inkrementuje licznik (okno przesuwane — TTL odswiezany przy hicie).
	 *
	 * @param string $key    Klucz transienta.
	 * @param int    $window Okno w sekundach.
	 * @return void
	 */
	private static function bump( string $key, int $window ): void {
		$count = (int) get_transient( $key );
		set_transient( $key, $count + 1, $window );
	}
}
