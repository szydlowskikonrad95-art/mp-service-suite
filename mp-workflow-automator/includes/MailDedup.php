<?php
/**
 * Dedup-okno maili ZDARZENIOWYCH — tlumi IDENTYCZNY mail w krotkim oknie.
 *
 * KLUCZ = hash(adresat + WYRENDEROWANA tresc): łapie WYLACZNIE prawdziwe duplikaty
 * — dwie rozne informacje (np. dwa rozne statusy w 60 s) NIGDY nie sa dedupowane.
 * Okno KONFIGUROWALNE per typ powiadomienia (np. wiadomosci klienta 300 s —
 * „5 wiadomosci w 3 min ≠ 5 maili"; zmiana statusu 60 s).
 *
 * REZERWACJA JEST ATOMOWA — ta sama, co przy odsiewaniu podwojnych zgloszen
 * w module C (`MP\Intake\RateLimit::claim_window`, tabela wp_mp_rate_counters:
 * INSERT ... ON DUPLICATE KEY UPDATE + LAST_INSERT_ID). Produkt rozwiazywal TEN
 * SAM problem — „nie zrob tego dwa razy" — na dwa sposoby i z dwoma roznymi
 * poziomami pewnosci (2.23): C atomowo w tabeli, D transientem, czyli
 * sprawdz-potem-zapisz. Transientowa droga przepuszczala dwa rownolegle zadania
 * (cron i klikniecie, dwa wywolania webhooka): oba widzialy pusty klucz, oba
 * wysylaly ten sam mail. Teraz odpowiedz w produkcie jest JEDNA.
 *
 * ⚠️ Transient zostaje WYLACZNIE jako droga ratunkowa, gdy modulu C nie ma
 * (samodzielna instalacja automatu — brak tabeli rezerwacji). Wtedy dedup jest
 * best-effort, jak dotad: object-cache moze wywlaszczyc klucz przed czasem,
 * a wyscig przepuszcza dubel maila ZDARZENIOWEGO.
 *
 * Gwarancje RAZ-TYLKO (przypomnienie/eskalacja/digest SLA) NIE siedza tutaj —
 * ida przez CLAIM w tabeli wp_mp_case_sla, nigdy w transiencie.
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
	 * Rezerwacja idzie ATOMOWO przez wspolny mechanizm produktu (2.23) — dwa
	 * rownolegle zadania z tym samym mailem dostana TRUE i FALSE, nigdy dwa razy
	 * TRUE. Okno liczy sie od PIERWSZEJ rezerwacji i cudza proba go nie przedluza
	 * — dokladnie tak, jak dzialal tu transient.
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

		if ( self::atomic_available() ) {
			return \MP\Intake\RateLimit::claim_window( $key, $window );
		}

		// Droga ratunkowa (brak modulu C = brak tabeli rezerwacji): sprawdz-potem-zapisz,
		// best-effort. Zostawiona swiadomie, zeby brak siostrzanej wtyczki nie ZATRZYMAL
		// poczty — ale to jest gorszy poziom pewnosci i tak jest opisana.
		if ( false !== get_transient( $key ) ) {
			return false;
		}

		set_transient( $key, 1, $window );

		return true;
	}

	/**
	 * Czy dostepna jest atomowa rezerwacja klucza z modulu C.
	 *
	 * Sprawdzane przez `is_callable` (uruchamia autoladowanie siostrzanej wtyczki),
	 * a nie przez sztywne zalozenie, ze C jest aktywne — automat da sie wlaczyc sam.
	 *
	 * @return bool
	 */
	private static function atomic_available(): bool {
		return is_callable( array( '\MP\Intake\RateLimit', 'claim_window' ) );
	}
}
