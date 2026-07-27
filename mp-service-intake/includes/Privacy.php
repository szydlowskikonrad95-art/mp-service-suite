<?php
/**
 * RODO — eraser i exporter wpiete w natywne narzedzia WP (Narzedzia -> Dane osobowe).
 *
 * Eraser szuka po EMAILU (lapie tez sprawy bez konta). Anonimizacja PRAWDZIWA
 * (nie pseudonimizacja): czyszczenie customers + redakcja messages/form_data-PII
 * + kasacja zalacznikow + odpiecie konta WP + redakcja reason wyjatkow (B przez
 * filter) + eventy. Sprawa AKTYWNA / okno roszczen => ODROCZENIE EN BLOC
 * (items_retained, jedna operacja). Exporter: dane klienta + sprawy + wiadomosci
 * + metadane zalacznikow (bez binarki — dostep przez konto, art. 15).
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Orkiestracja RODO C.
 */
final class Privacy {

	/**
	 * Rejestruje eraser i exporter w natywnym mechanizmie WP.
	 *
	 * @return void
	 */
	public static function register(): void {
		add_filter( 'wp_privacy_personal_data_erasers', array( self::class, 'register_eraser' ) );
		add_filter( 'wp_privacy_personal_data_exporters', array( self::class, 'register_exporter' ) );
	}

	/**
	 * Dopisuje eraser MP do listy WP.
	 *
	 * @param array<string, mixed> $erasers Lista eraserow.
	 * @return array<string, mixed>
	 */
	public static function register_eraser( array $erasers ): array {
		$erasers['mp-service-intake'] = array(
			'eraser_friendly_name' => __( 'Zgłoszenia serwisowe MP', 'mp-service-intake' ),
			'callback'             => array( self::class, 'erase' ),
		);

		return $erasers;
	}

	/**
	 * Dopisuje exporter MP do listy WP.
	 *
	 * @param array<string, mixed> $exporters Lista exporterow.
	 * @return array<string, mixed>
	 */
	public static function register_exporter( array $exporters ): array {
		$exporters['mp-service-intake'] = array(
			'exporter_friendly_name' => __( 'Zgłoszenia serwisowe MP', 'mp-service-intake' ),
			'callback'               => array( self::class, 'export' ),
		);

		return $exporters;
	}

	/**
	 * Eraser: anonimizuje dane klienta o danym emailu (z odroczeniem EN BLOC).
	 *
	 * @param string $email E-mail (klucz erasera).
	 * @param int    $page  Strona (paginacja WP — u nas 1 przebieg).
	 * @return array{items_removed: bool, items_retained: bool, messages: array<int, string>, done: bool}
	 */
	public static function erase( string $email, int $page = 1 ): array {
		global $wpdb;

		unset( $page );

		$email     = trim( $email );
		$messages  = array();
		$removed   = false;
		$retained  = false;
		$customers = Tables::full( Tables::CUSTOMERS );
		$deferral  = __( 'Dane zatrzymane do zakończenia aktywnej sprawy serwisowej lub upływu okresu roszczeń (gwarancja/rękojmia).', 'mp-service-intake' );

		foreach ( Customers::ids_by_email( $email ) as $customer_id ) {
			// Transakcja + blokada wiersza klienta (audyt #8): rownolegla
			// weryfikacja zgloszenia (attach_customer_on_verify) czeka na tej
			// blokadzie, wiec miedzy spisem spraw a anonimizacja NIC nie moze
			// sie dopiac. Bez tego nowa sprawa dopieta w oknie wyscigu
			// zostawala z pelnym PII przy "usunietym" kliencie, a raport
			// klamal, ze dane usunieto.
			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
			$wpdb->query( 'START TRANSACTION' );

			$locked = $wpdb->get_var(
				$wpdb->prepare( "SELECT id FROM {$customers} WHERE id = %d AND anonymized_at IS NULL FOR UPDATE", $customer_id )
			);
			// phpcs:enable

			// Ktos zdazyl zanonimizowac przed nami — nic do roboty.
			if ( null === $locked ) {
				$wpdb->query( 'ROLLBACK' ); // phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery -- zamkniecie transakcji.
				continue;
			}

			// Sprawa aktywna / okno roszczen => ODROCZENIE EN BLOC (nic nie tykamy).
			if ( CaseRepo::has_active_case( $customer_id ) ) {
				$wpdb->query( 'ROLLBACK' ); // phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery -- zamkniecie transakcji.
				$retained   = true;
				$messages[] = $deferral;
				continue;
			}

			$cases    = CaseRepo::for_customer( $customer_id );
			$case_ids = array_map( static fn( array $c ): int => (int) $c['id'], $cases );

			// Najpierw operacje CZYSTO bazodanowe (cofalne rollbackiem);
			// pliki zalacznikow dopiero PO commicie — rollback nie umie
			// przywrocic skasowanego pliku.
			Messages::redact_for_cases( $case_ids );
			CaseRepo::redact_pii_for_cases( $case_ids );

			// B redaguje reason wyjatkow powiazanych ze sprawami klienta.
			if ( has_filter( 'mp_privacy_redact_for_customer' ) ) {
				apply_filters( 'mp_privacy_redact_for_customer', null, $customer_id, $case_ids );
			}

			// RECHECK pod blokada (audyt #8, pas i szelki): jesli mimo blokady
			// jakas sciezka dopiela sprawe po pierwszym spisie (np. wpiecie w tym
			// samym procesie), to jest to NOWA, aktywna sprawa => pelne
			// odroczenie: cofamy redakcje w calosci, sprawa trafi do spisu
			// przy nastepnym przebiegu erasera.
			$ids_after = array_map( static fn( array $c ): int => (int) $c['id'], CaseRepo::for_customer( $customer_id ) );

			if ( array() !== array_diff( $ids_after, $case_ids ) ) {
				$wpdb->query( 'ROLLBACK' ); // phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery -- zamkniecie transakcji.
				$retained   = true;
				$messages[] = $deferral;
				continue;
			}

			// Konto WP: id lapiemy PRZED anonimizacja (anonymize odpina wp_user_id).
			$wp_user_id = Customers::wp_user_id( $customer_id );

			Customers::anonymize( $customer_id );
			// FLAGA #6: redakcja e-maila (PII) w zgodach — rozliczalnosc art. 7 zostaje (tekst+daty).
			Consents::redact_email_for_customer( $customer_id );

			$wpdb->query( 'COMMIT' ); // phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery -- zamkniecie transakcji.

			// PO COMMIT — operacje nieodwracalne lub poza naszymi tabelami.
			// Pliki: idempotentne; gdyby proces padl tuz po commicie, retencja
			// zalacznikow (Lifecycle) sprzata sieroty.
			Attachments::delete_for_cases( $case_ids );

			// D1 (RODO art. 17): usun konto WP klienta (e-mail/login/nazwisko z wp_users).
			// Tylko czyste konto klienta — personel/admin nietkniety (Accounts).
			if ( null !== $wp_user_id ) {
				Accounts::purge_client_account( $wp_user_id );
			}

			foreach ( $case_ids as $case_id ) {
				CaseEvents::log( $case_id, CaseEvents::PII_REDACTION, array( 'target' => 'customer' ), null );
			}

			$removed    = true;
			$messages[] = __( 'Dane osobowe powiązane ze zgłoszeniami serwisowymi zostały zanonimizowane.', 'mp-service-intake' );
		}

		return array(
			'items_removed'  => $removed,
			'items_retained' => $retained,
			'messages'       => $messages,
			'done'           => true,
		);
	}

	/**
	 * Exporter: dane klienta + sprawy + wiadomosci + metadane zalacznikow.
	 *
	 * @param string $email E-mail.
	 * @param int    $page  Strona.
	 * @return array{data: array<int, array<string, mixed>>, done: bool}
	 */
	public static function export( string $email, int $page = 1 ): array {
		unset( $page );

		$export = array();

		foreach ( Customers::ids_by_email( trim( $email ) ) as $customer_id ) {
			$customer = Customers::get( $customer_id );

			if ( null !== $customer ) {
				$export[] = array(
					'group_id'    => 'mp_customer',
					'group_label' => __( 'Dane klienta (serwis MP)', 'mp-service-intake' ),
					'item_id'     => 'customer-' . $customer_id,
					'data'        => array(
						array(
							'name'  => __( 'E-mail', 'mp-service-intake' ),
							'value' => (string) $customer['email'],
						),
						array(
							'name'  => __( 'Imię i nazwisko', 'mp-service-intake' ),
							'value' => (string) $customer['name'],
						),
						array(
							'name'  => __( 'Telefon', 'mp-service-intake' ),
							'value' => (string) $customer['phone'],
						),
					),
				);
			}

			foreach ( CaseRepo::for_customer( $customer_id ) as $case ) {
				$case_id  = (int) $case['id'];
				$export[] = array(
					'group_id'    => 'mp_cases',
					'group_label' => __( 'Zgłoszenia serwisowe MP', 'mp-service-intake' ),
					'item_id'     => 'case-' . $case_id,
					'data'        => array(
						array(
							'name'  => __( 'Numer sprawy', 'mp-service-intake' ),
							'value' => (string) $case['case_number'],
						),
						array(
							'name'  => __( 'Rodzaj', 'mp-service-intake' ),
							'value' => (string) $case['kind'],
						),
						array(
							'name'  => __( 'Status', 'mp-service-intake' ),
							'value' => (string) ( $case['status'] ?? '' ),
						),
						array(
							'name'  => __( 'Załączniki', 'mp-service-intake' ),
							'value' => self::attachments_summary( $case_id ),
						),
					),
				);

				foreach ( Messages::for_case( $case_id ) as $msg ) {
					$export[] = array(
						'group_id'    => 'mp_messages',
						'group_label' => __( 'Wiadomości w sprawach MP', 'mp-service-intake' ),
						'item_id'     => 'message-' . (int) $msg['id'],
						'data'        => array(
							array(
								'name'  => __( 'Sprawa', 'mp-service-intake' ),
								'value' => (string) $case['case_number'],
							),
							array(
								'name'  => __( 'Treść', 'mp-service-intake' ),
								'value' => (string) $msg['body'],
							),
						),
					);
				}
			}
		}

		return array(
			'data' => $export,
			'done' => true,
		);
	}

	/**
	 * Zwięzły opis załączników sprawy do eksportu (metadane + info o dostępie).
	 *
	 * @param int $case_id ID sprawy.
	 * @return string
	 */
	private static function attachments_summary( int $case_id ): string {
		$meta = Attachments::metadata_for_case( $case_id );

		if ( array() === $meta ) {
			return __( 'brak', 'mp-service-intake' );
		}

		$names = array_map(
			static fn( array $a ): string => (string) $a['original_name'] . ' (' . size_format( (int) $a['size_bytes'] ) . ')',
			$meta
		);

		return implode( ', ', $names ) . ' — ' . __( 'pliki dostępne po zalogowaniu na konto.', 'mp-service-intake' );
	}
}
