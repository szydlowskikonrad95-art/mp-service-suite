<?php
/**
 * Raport koncowy przy zamknieciu sprawy (przebieg krok 8) — STRUKTURALNE zachowanie D
 * (gwarancja, nie regula z tabeli): przy przejsciu w status 'zamknięte' D sklada
 * podsumowanie sprawy i wola kontrakt C `mp_case_add_system_message` (wpis systemowy
 * widoczny w panelu klienta i na karcie personelu).
 *
 * Tresc KLIENT-FRIENDLY + NO-PII: numer sprawy, rodzaj, data zamkniecia, czas obslugi.
 * BEZ danych wewnetrznych (priorytet / przydzielony pracownik) — wpis jest widoczny
 * dla klienta. Wiadomosc systemowa (author_type=system) NIE wyzwala regul mailowych
 * (te reaguja na author_type client/staff).
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Generator raportu koncowego sprawy.
 */
final class ClosingReport {

	/**
	 * Status wyzwalajacy raport koncowy (rdzen „zamkniete").
	 */
	public const CLOSING_STATUS = 'zamknięte';

	/**
	 * Rejestruje listener (PO regulach — priorytet 30 na mp_case_status_changed).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'mp_case_status_changed', array( self::class, 'on_status_changed' ), 30, 4 );
	}

	/**
	 * Przy przejsciu w 'zamknięte': sklada raport i dopisuje wpis systemowy w C.
	 *
	 * @param int    $case_id    ID sprawy.
	 * @param string $old_status Poprzedni status (nieuzywany).
	 * @param string $new_status Nowy status.
	 * @param int    $actor_id   Kto zmienil (nieuzywany — raport to zachowanie systemu).
	 * @return void
	 */
	public static function on_status_changed( $case_id, $old_status, $new_status, $actor_id ): void {
		unset( $old_status, $actor_id );

		if ( self::CLOSING_STATUS !== (string) $new_status ) {
			return;
		}

		$ctx = apply_filters( 'mp_case_get_context', null, (int) $case_id );

		if ( ! is_array( $ctx ) ) {
			return;
		}

		$report = self::build( $ctx );

		apply_filters( 'mp_case_add_system_message', null, (int) $case_id, $report );

		WorkflowEvents::log(
			WorkflowEvents::CLOSING_REPORT_GENERATED,
			array( 'case_number' => (string) ( $ctx['case_number'] ?? '' ) ),
			(int) $case_id
		);
	}

	/**
	 * Sklada tresc raportu koncowego (KLIENT-FRIENDLY, NO-PII).
	 *
	 * @param array<string, mixed> $ctx Kontekst sprawy.
	 * @return string
	 */
	private static function build( array $ctx ): string {
		$number = (string) ( $ctx['case_number'] ?? '' );
		$kind   = (string) ( $ctx['rodzaj'] ?? '' );
		$closed = (string) ( $ctx['status_changed_at'] ?? '' );
		$opened = (string) ( $ctx['verified_at'] ?? '' );

		$lines = array();

		$lines[] = sprintf(
			/* translators: %s: numer sprawy SRV. */
			__( 'Sprawa %s została zamknięta.', 'mp-workflow-automator' ),
			$number
		);

		if ( '' !== $kind ) {
			/* translators: %s: rodzaj zgloszenia. */
			$lines[] = sprintf( __( 'Rodzaj zgłoszenia: %s', 'mp-workflow-automator' ), $kind );
		}

		if ( '' !== $closed ) {
			$lines[] = sprintf(
				/* translators: %s: data zamkniecia w czasie lokalnym. */
				__( 'Data zamknięcia: %s', 'mp-workflow-automator' ),
				get_date_from_gmt( $closed, 'Y-m-d H:i' )
			);
		}

		$handling = self::handling_label( $opened, $closed );

		if ( '' !== $handling ) {
			/* translators: %s: czas obslugi (np. „2 dni 3 godz"). */
			$lines[] = sprintf( __( 'Czas obsługi: %s', 'mp-workflow-automator' ), $handling );
		}

		$lines[] = __( 'Dziękujemy za zgłoszenie.', 'mp-workflow-automator' );

		return implode( "\n", $lines );
	}

	/**
	 * Czas obslugi od potwierdzenia do zamkniecia (czytelny). '' gdy brak danych.
	 *
	 * @param string $opened verified_at (UTC).
	 * @param string $closed status_changed_at (UTC).
	 * @return string
	 */
	private static function handling_label( string $opened, string $closed ): string {
		if ( '' === $opened || '' === $closed ) {
			return '';
		}

		$from = strtotime( $opened . ' UTC' );
		$to   = strtotime( $closed . ' UTC' );

		if ( false === $from || false === $to || $to < $from ) {
			return '';
		}

		$seconds = $to - $from;
		$days    = (int) floor( $seconds / DAY_IN_SECONDS );
		$hours   = (int) floor( ( $seconds % DAY_IN_SECONDS ) / HOUR_IN_SECONDS );

		if ( $days > 0 ) {
			/* translators: 1: liczba dni, 2: liczba godzin. */
			return sprintf( __( '%1$d dni %2$d godz', 'mp-workflow-automator' ), $days, $hours );
		}

		if ( $hours > 0 ) {
			/* translators: %d: liczba godzin. */
			return sprintf( __( '%d godz', 'mp-workflow-automator' ), $hours );
		}

		return __( 'poniżej godziny', 'mp-workflow-automator' );
	}
}
