<?php
/**
 * Mailer D — JEDYNA brama wyjscia maili automatora (egress przez jeden punkt).
 *
 * OBRONA STRUKTURALNA (nie zaufanie): kazdy adres i temat przechodzi twarda
 * walidacje NA HOSCIE, zanim trafi do wp_mail — bo argumenty pochodza z danych
 * KLIENTA (niezaufane). Zasady:
 *  - odbiorca: is_email() (odrzuca smiecie i adresy z CRLF) — brak = NIE wysylamy;
 *  - temat: usuwamy CR/LF => ZERO header-injection (wstrzykniecia naglowka przez
 *    marker w temacie);
 *  - JEDEN odbiorca na wywolanie => klient NIGDY nie widzi adresu innego klienta
 *    (brak zbiorczego To/CC/BCC — wyciek adresow niemozliwy z konstrukcji);
 *  - tresc (body) = plain text: nie jest naglowkiem, wiec nie niesie ryzyka
 *    header-injection; idzie bez zmian (markery juz zsanityzowane w MailTemplates).
 *
 * NO-PII: ta klasa NICZEGO nie loguje (adres/tresc). Log zdarzenia (bez adresu,
 * bez tresci — tylko {template_key, recipient_ref}) robi wolajacy w RuleEngine.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Bezpieczna wysylka pojedynczego maila.
 */
final class Mailer {

	/**
	 * Wysyla JEDEN mail do JEDNEGO odbiorcy. Zwraca false gdy adres niepoprawny
	 * (nie wysyla) albo gdy wp_mail zawiodl.
	 *
	 * @param string $to      Adres odbiorcy (surowy — walidowany tutaj).
	 * @param string $subject Temat (CR/LF usuwane — anty header-injection).
	 * @param string $body    Tresc plain-text (juz zrenderowana i zsanityzowana).
	 * @return bool True gdy wp_mail zwrocil sukces.
	 */
	public static function send( string $to, string $subject, string $body ): bool {
		$to = trim( $to );

		// Odbiorca musi byc POPRAWNYM adresem — is_email odrzuca m.in. adresy
		// z osadzonym CR/LF/naglowkiem (nie ufamy adresowi z formularza).
		if ( '' === $to || ! is_email( $to ) ) {
			return false;
		}

		// Temat: twardo bez CR/LF (marker w temacie nie wstrzyknie naglowka).
		$subject = self::strip_crlf( $subject );

		return (bool) wp_mail( $to, $subject, $body );
	}

	/**
	 * Usuwa znaki CR/LF (i \0) — wartosci wchodzace do NAGLOWKA maila.
	 *
	 * @param string $value Wartosc.
	 * @return string
	 */
	public static function strip_crlf( string $value ): string {
		return str_replace( array( "\r", "\n", "\0" ), ' ', $value );
	}
}
