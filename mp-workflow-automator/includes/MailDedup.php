<?php
/**
 * Dedup-okno maili ZDARZENIOWYCH (P3.3) — tlumi IDENTYCZNY mail w krotkim oknie.
 *
 * KLUCZ = hash(adresat + WYRENDEROWANA tresc): łapie WYLACZNIE prawdziwe duplikaty
 * — dwie rozne informacje (np. dwa rozne statusy w 60 s) NIGDY nie sa dedupowane.
 * Okno KONFIGUROWALNE per typ powiadomienia (np. wiadomosci klienta 300 s —
 * „5 wiadomosci w 3 min ≠ 5 maili"; zmiana statusu 60 s).
 *
 * ⚠️ JAWNA GRANICA: transient = BEST-EFFORT. Object-cache (Redis) moze wywlaszczyc
 * klucz przed czasem — wtedy najwyzej dubel maila ZDARZENIOWEGO (akceptowalne).
 * Gwarancje RAZ-TYLKO (przypomnienie/eskalacja/digest SLA) NIE siedza tutaj —
 * ida przez CLAIM w tabeli wp_mp_case_sla (P3.4), nigdy w transiencie.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Okno deduplikacji maili zdarzeniowych (transient, best-effort).
 */
final class MailDedup {

	/**
	 * Opcja z oknami per template_key (nadpisuje wbudowane domyslne). Sekundy.
	 */
	public const OPTION = 'mp_automator_dedup_windows';

	/**
	 * Domyslne okno (sekundy), gdy brak override i brak wbudowanego dla klucza.
	 */
	public const DEFAULT_WINDOW = 60;

	/**
	 * Prefiks klucza transienta (krotki — limit dlugosci nazwy opcji/transienta).
	 */
	private const KEY_PREFIX = 'mp_adedup_';

	/**
	 * Wbudowane okna per typ powiadomienia (wiadomosci = dluzsze, anty-spam).
	 *
	 * @return array<string, int>
	 */
	private static function builtin_windows(): array {
		return array(
			'message_from_client' => 300,
			'message_from_staff'  => 300,
		);
	}

	/**
	 * Okno dedupu dla szablonu: override z opcji > wbudowane > DEFAULT_WINDOW.
	 *
	 * @param string $template_key Klucz szablonu.
	 * @return int Sekundy (0 = brak dedupu).
	 */
	public static function window_for( string $template_key ): int {
		$cfg = get_option( self::OPTION, array() );

		if ( is_array( $cfg ) && isset( $cfg[ $template_key ] ) ) {
			return max( 0, (int) $cfg[ $template_key ] );
		}

		$builtin = self::builtin_windows();

		return $builtin[ $template_key ] ?? self::DEFAULT_WINDOW;
	}

	/**
	 * Rezerwuje wyslanie: TRUE = wolno wyslac (i zaznacza okno), FALSE = duplikat
	 * w oknie (pomin). Okno <= 0 => zawsze TRUE (dedup wylaczony dla tego typu).
	 *
	 * @param string $recipient Adres odbiorcy (surowy — tylko do hasza, nie do logu).
	 * @param string $body       Wyrenderowana tresc maila.
	 * @param int    $window     Okno w sekundach.
	 * @return bool
	 */
	public static function claim( string $recipient, string $body, int $window ): bool {
		if ( $window <= 0 ) {
			return true;
		}

		$key = self::KEY_PREFIX . md5( $recipient . '|' . $body );

		if ( false !== get_transient( $key ) ) {
			return false;
		}

		set_transient( $key, 1, $window );

		return true;
	}
}
