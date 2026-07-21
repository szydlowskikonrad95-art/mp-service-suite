<?php
/**
 * Maile Intake: magic-link weryfikacji + potwierdzenie z numerem SRV.
 *
 * Szablony w C z kotwicami (C degraded bez D — nie zalezy od szablonow D).
 * Magic-link: token w URL, GET na endpoint weryfikacji. 2. mail (po weryfikacji)
 * niesie NUMER SRV (krok 6 kartki) — SRV ujawniany dopiero po potwierdzeniu.
 *
 * @package MP\Intake
 */

namespace MP\Intake\Front;

/**
 * Wysylka maili zgloszenia.
 */
final class Mailer {

	/**
	 * Wysyla magic-link potwierdzenia zgloszenia.
	 *
	 * @param string $email Adres odbiorcy.
	 * @param string $token Surowy token (do URL).
	 * @return bool Wynik wp_mail.
	 */
	public static function send_magic_link( string $email, string $token ): bool {
		$url = add_query_arg(
			array(
				'action' => 'mp_intake_verify',
				'token'  => rawurlencode( $token ),
			),
			admin_url( 'admin-post.php' )
		);

		$subject = __( 'Potwierdź swoje zgłoszenie serwisowe', 'mp-service-intake' );
		$body    = sprintf(
			/* translators: %s: link potwierdzajacy. */
			__( "Dziękujemy za zgłoszenie serwisowe.\n\nAby je potwierdzić i uruchomić obsługę, kliknij w link poniżej (ważny 24 godziny):\n\n%s\n\nJeśli to nie Ty wysłałeś to zgłoszenie, zignoruj tę wiadomość.", 'mp-service-intake' ),
			$url
		);

		return wp_mail( $email, $subject, $body );
	}

	/**
	 * Wysyla potwierdzenie z numerem SRV (po weryfikacji).
	 *
	 * @param string $email       Adres odbiorcy.
	 * @param string $case_number Numer SRV.
	 * @return bool Wynik wp_mail.
	 */
	public static function send_confirmation( string $email, string $case_number ): bool {
		$subject = sprintf(
			/* translators: %s: numer sprawy SRV. */
			__( 'Zgłoszenie %s zostało przyjęte', 'mp-service-intake' ),
			$case_number
		);
		$body = sprintf(
			/* translators: %s: numer sprawy SRV. */
			__( "Twoje zgłoszenie zostało potwierdzone i przyjęte do obsługi.\n\nNumer sprawy: %s\n\nPodawaj ten numer w kontakcie z serwisem. Status sprawy możesz śledzić po zalogowaniu na swoje konto.", 'mp-service-intake' ),
			$case_number
		);

		return wp_mail( $email, $subject, $body );
	}
}
