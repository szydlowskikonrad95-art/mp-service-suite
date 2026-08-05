<?php
/**
 * Akcje personelu na karcie sprawy (specyfikacja krok 7 — „kazda decyzja zapisuje sie
 * w historii"): zmiana statusu · odpowiedz do klienta · przydzial. Handlery
 * admin-post; KAZDY sam egzekwuje capability + nonce (metody repo NIE autoryzuja).
 *
 * Model B: zmiana statusu / odpowiedz — dowolny personel; PRZYDZIAL — tylko
 * koordynator / administrator (pracownik nie przydziela innym). Wszystkie akcje
 * ida przez metody repo/hooki => audyt w case_events + maile (RuleEngine
 * slucha mp_case_status_changed / mp_case_message_added). PRG na karte z notka.
 *
 * @package MP\Intake\Admin
 */

namespace MP\Intake\Admin;

use MP\Intake\CaseRepo;
use MP\Intake\Messages;

/**
 * Handlery admin-post akcji karty sprawy.
 */
final class CaseActions {

	/**
	 * Rejestruje handlery (priv I nopriv => jawne 403 dla nieuprawnionych).
	 *
	 * @return void
	 */
	public static function register(): void {
		foreach ( array( 'status', 'reply', 'assign', 'note' ) as $act ) {
			$hook = 'mp_intake_case_' . $act;
			add_action( 'admin_post_' . $hook, array( self::class, 'handle_' . $act ) );
			add_action( 'admin_post_nopriv_' . $hook, array( self::class, 'handle_' . $act ) );
		}
	}

	/**
	 * Czy personel serwisu (dowolna z 3 rol; NIE hierarchiczne).
	 *
	 * @return bool
	 */
	private static function is_staff(): bool {
		return current_user_can( 'mp_agent' )
			|| current_user_can( 'mp_coordinator' )
			|| current_user_can( 'mp_system_admin' );
	}

	/**
	 * ⛔ 2.24, TRZECIA CZESC: akcja NA sprawie wymaga prawa DO TEJ SPRAWY.
	 *
	 * Sam `is_staff()` nie wystarcza i to byla dziura grozniejsza od podgladu:
	 * karte cudzej sprawy pracownik tylko OGLADAL, a przez zadanie POST mogl jej
	 * zmienic status, dopisac notatke albo NAPISAC DO KLIENTA, ktorego nie obsluguje.
	 *
	 * ⛔ Pytamy `CaseRepo::can_current_user_see()` — TEN SAM warunek co lista i karta.
	 * Rozstrzyga dokumentacja produktu, nie nasze przeczucie: `PRACOWNIK.md` sekcja 2
	 * wymienia jako prace pracownika dokladnie te trzy czynnosci (wiadomosci, zmiana
	 * statusu, notatka), a zasady na koncu mowia „na liscie spraw sa wylacznie sprawy
	 * przydzielone Tobie. Wszystkie sprawy widzi koordynator i administrator systemu".
	 *
	 * ⚠️ PRZYDZIALU to NIE dotyczy — ten ma wlasny, wezszy warunek `can_assign()`.
	 * `PRACOWNIK.md` mowi „obslugujesz sprawy, ktore system (albo koordynator) Ci
	 * przydzielil", a `KOORDYNATOR.md` przy sprawie nieprzydzielonej kaze poprosic
	 * administratora — pracownik nie bierze sobie sprawy sam i nigdy nie mial tego prawa.
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	private static function deny_if_not_visible( int $case_id ): void {
		if ( 0 === $case_id || ! CaseRepo::can_current_user_see( $case_id ) ) {
			self::deny();
		}
	}

	/**
	 * Czy moze przydzielac (koordynator / administrator systemu).
	 *
	 * @return bool
	 */
	private static function can_assign(): bool {
		return current_user_can( 'mp_coordinator' ) || current_user_can( 'mp_system_admin' );
	}

	/**
	 * Zmiana statusu: cap personelu + nonce; optimistic-lock (expected_status);
	 * powod przy „odrzucone". change_status loguje event + emituje maile .
	 *
	 * @return void
	 */
	public static function handle_status(): void {
		if ( ! self::is_staff() ) {
			self::deny();
		}

		check_admin_referer( 'mp_intake_case_status' );

		// phpcs:disable WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$case_id  = isset( $_POST['case_id'] ) ? absint( $_POST['case_id'] ) : 0;
		$new      = isset( $_POST['new_status'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['new_status'] ) ) : '';
		$expected = isset( $_POST['expected_status'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['expected_status'] ) ) : '';
		$reason   = isset( $_POST['rejection_reason_code'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['rejection_reason_code'] ) ) : '';
		// phpcs:enable

		// ⛔ prawo DO TEJ SPRAWY, nie tylko „jestem personelem" — patrz deny_if_not_visible().
		self::deny_if_not_visible( $case_id );

		if ( 0 === $case_id || '' === $new ) {
			self::back( $case_id, __( 'Brak danych zmiany statusu.', 'mp-service-intake' ) );
		}

		$result = CaseRepo::change_status( $case_id, $new, $expected, get_current_user_id(), '' !== $reason ? $reason : null );

		self::back( $case_id, self::status_notice( $result ) );
	}

	/**
	 * Mapuje wynik change_status na komunikat dla personelu.
	 *
	 * @param array<string, mixed> $result Wynik CaseRepo::change_status.
	 * @return string
	 */
	private static function status_notice( array $result ): string {
		if ( ! empty( $result['success'] ) ) {
			return __( 'Status zmieniony (klient i przypisany pracownik powiadomieni).', 'mp-service-intake' );
		}

		$code = isset( $result['error_code'] ) ? (string) $result['error_code'] : '';

		switch ( $code ) {
			case 'STATUS_CONFLICT':
				return __( 'Ktoś zmienił status w międzyczasie — odśwież stronę i spróbuj ponownie.', 'mp-service-intake' );
			case 'REJECTION_REASON_REQUIRED':
				return __( 'Odrzucenie wymaga podania powodu.', 'mp-service-intake' );
			case 'INVALID_TRANSITION':
				return __( 'Niedozwolone przejście statusu (sprawę zamkniętą można tylko wznowić do „w analizie").', 'mp-service-intake' );
			case 'CASE_NOT_FOUND':
				return __( 'Sprawa nie istnieje lub niepotwierdzona.', 'mp-service-intake' );
			default:
				return __( 'Nie udało się zmienić statusu.', 'mp-service-intake' );
		}
	}

	/**
	 * Odpowiedz do klienta: cap personelu + nonce; Messages::add('staff') emituje
	 * mp_case_message_added => regula powiadamia klienta. Sprawa musi istniec.
	 *
	 * @return void
	 */
	public static function handle_reply(): void {
		if ( ! self::is_staff() ) {
			self::deny();
		}

		check_admin_referer( 'mp_intake_case_reply' );

		// phpcs:disable WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$case_id = isset( $_POST['case_id'] ) ? absint( $_POST['case_id'] ) : 0;
		$body    = isset( $_POST['body'] ) ? sanitize_textarea_field( wp_unslash( (string) $_POST['body'] ) ) : '';
		// phpcs:enable

		// ⛔ prawo DO TEJ SPRAWY, nie tylko „jestem personelem" — patrz deny_if_not_visible().
		self::deny_if_not_visible( $case_id );

		if ( 0 === $case_id ) {
			self::back( $case_id, __( 'Brak sprawy.', 'mp-service-intake' ) );
		}

		$ctx = apply_filters( 'mp_case_get_context', null, $case_id );

		if ( ! is_array( $ctx ) ) {
			self::back( $case_id, __( 'Sprawa nie istnieje lub niepotwierdzona.', 'mp-service-intake' ) );
		}

		if ( '' === trim( $body ) ) {
			self::back( $case_id, __( 'Wiadomość jest pusta.', 'mp-service-intake' ) );
		}

		Messages::add( $case_id, 'staff', get_current_user_id(), $body );

		self::back( $case_id, __( 'Odpowiedź wysłana do klienta.', 'mp-service-intake' ) );
	}

	/**
	 * NOTATKA WEWNETRZNA (audyt 2.15): cap personelu + nonce; NIE idzie do klienta.
	 *
	 * Osobny endpoint i osobny nonce, a nie „pole wyboru przy odpowiedzi" — pomylka
	 * przy odhaczaniu kosztowalaby wyslanie klientowi uwagi napisanej dla kolegi.
	 * Dwie drogi, ktorych nie da sie pomylic jednym kliknieciem, sa tu warte
	 * kilkunastu linii wiecej.
	 *
	 * @return void
	 */
	public static function handle_note(): void {
		if ( ! self::is_staff() ) {
			self::deny();
		}

		check_admin_referer( 'mp_intake_case_note' );

		// phpcs:disable WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$case_id = isset( $_POST['case_id'] ) ? absint( $_POST['case_id'] ) : 0;
		$body    = isset( $_POST['body'] ) ? sanitize_textarea_field( wp_unslash( (string) $_POST['body'] ) ) : '';
		// phpcs:enable

		// ⛔ prawo DO TEJ SPRAWY, nie tylko „jestem personelem" — patrz deny_if_not_visible().
		self::deny_if_not_visible( $case_id );

		if ( 0 === $case_id ) {
			self::back( $case_id, __( 'Brak sprawy.', 'mp-service-intake' ) );
		}

		$ctx = apply_filters( 'mp_case_get_context', null, $case_id );

		if ( ! is_array( $ctx ) ) {
			self::back( $case_id, __( 'Sprawa nie istnieje lub niepotwierdzona.', 'mp-service-intake' ) );
		}

		if ( '' === trim( $body ) ) {
			self::back( $case_id, __( 'Notatka jest pusta.', 'mp-service-intake' ) );
		}

		Messages::add_internal_note( $case_id, get_current_user_id(), $body );

		self::back( $case_id, __( 'Notatka zapisana — widzi ją tylko personel.', 'mp-service-intake' ) );
	}

	/**
	 * Przydzial sprawy: cap koordynator/admin + nonce; CaseRepo::assign loguje
	 * event + emituje mp_case_assigned (mail agenta).
	 *
	 * @return void
	 */
	public static function handle_assign(): void {
		if ( ! self::can_assign() ) {
			self::deny();
		}

		check_admin_referer( 'mp_intake_case_assign' );

		// phpcs:disable WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$case_id  = isset( $_POST['case_id'] ) ? absint( $_POST['case_id'] ) : 0;
		$assignee = isset( $_POST['assignee'] ) ? absint( $_POST['assignee'] ) : 0;
		// phpcs:enable

		if ( 0 === $case_id || 0 === $assignee ) {
			self::back( $case_id, __( 'Wybierz pracownika do przydziału.', 'mp-service-intake' ) );
		}

		$result = CaseRepo::assign( $case_id, $assignee, get_current_user_id() );

		// Komunikat podaje POWOD, gdy go znamy. Samo „Nie udalo sie przydzielic
		// sprawy." zostawialo koordynatora z pytaniem, czy to awaria, czy jego blad.
		if ( ! empty( $result['success'] ) ) {
			$notice = __( 'Sprawa przydzielona (pracownik powiadomiony).', 'mp-service-intake' );
		} elseif ( 'INVALID_ASSIGNEE' === ( $result['error_code'] ?? '' ) ) {
			$notice = __( 'Sprawy prowadzą pracownicy serwisu — koordynatora ani administratora nie da się na nią przydzielić.', 'mp-service-intake' );
		} elseif ( 'CASE_NOT_FOUND' === ( $result['error_code'] ?? '' ) ) {
			$notice = __( 'Nie znaleziono sprawy albo klient nie potwierdził jeszcze zgłoszenia.', 'mp-service-intake' );
		} else {
			$notice = __( 'Nie udało się przydzielić sprawy.', 'mp-service-intake' );
		}

		self::back( $case_id, $notice );
	}

	/**
	 * Odmowa dostepu (403) — jawne dla nieuprawnionych.
	 *
	 * @return never
	 */
	private static function deny(): void {
		wp_die(
			esc_html__( 'Brak uprawnień do tej operacji.', 'mp-service-intake' ),
			'',
			array( 'response' => 403 )
		);
	}

	/**
	 * PRG na karte sprawy z komunikatem.
	 *
	 * @param int    $case_id ID sprawy.
	 * @param string $notice  Komunikat.
	 * @return never
	 */
	private static function back( int $case_id, string $notice ): void {
		$url = add_query_arg(
			array(
				'page'      => CasesScreen::PAGE_SLUG,
				'case_id'   => $case_id,
				'mp_notice' => rawurlencode( $notice ),
			),
			admin_url( 'admin.php' )
		);

		wp_safe_redirect( $url );
		exit;
	}
}
