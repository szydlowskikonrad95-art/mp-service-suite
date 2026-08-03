<?php
/**
 * RODO — eraser i exporter wpiete w natywne narzedzia WP (Narzedzia -> Dane osobowe).
 *
 * Eraser szuka po EMAILU (lapie tez sprawy bez konta). Anonimizacja PRAWDZIWA
 * (nie pseudonimizacja): czyszczenie customers + redakcja messages/form_data-PII
 * + kasacja zalacznikow + odpiecie konta WP + redakcja reason wyjatkow (B przez
 * filter) + eventy. Sprawa AKTYWNA / okno roszczen => ODROCZENIE EN BLOC
 * (items_retained, jedna operacja). Exporter: dane klienta + sprawy + wiadomosci
 * + tresci z formularza + metadane zalacznikow (bez binarki — dostep przez konto, art. 15).
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
				$wpdb->query( 'ROLLBACK' ); // phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- zamkniecie transakcji.
				continue;
			}

			// Sprawa aktywna / okno roszczen => ODROCZENIE EN BLOC (nic nie tykamy).
			if ( CaseRepo::has_active_case( $customer_id ) ) {
				$wpdb->query( 'ROLLBACK' ); // phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- zamkniecie transakcji.
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
				$wpdb->query( 'ROLLBACK' ); // phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- zamkniecie transakcji.
				$retained   = true;
				$messages[] = $deferral;
				continue;
			}

			// Konto WP: id lapiemy PRZED anonimizacja (anonymize odpina wp_user_id).
			$wp_user_id = Customers::wp_user_id( $customer_id );

			Customers::anonymize( $customer_id );
			// FLAGA #6: redakcja e-maila (PII) w zgodach — rozliczalnosc art. 7 zostaje (tekst+daty).
			Consents::redact_email_for_customer( $customer_id );

			// ⛔ SLAD REDAKCJI ZAPISUJEMY W TRANSAKCJI, PRZED punktem bez powrotu.
			// Wczesniej szedl na samym koncu — PO skasowaniu plikow i konta WP,
			// czyli za dwiema operacjami nieodwracalnymi, i bez sprawdzenia wyniku.
			// Skutek: dane zanonimizowane, pliki skasowane, konto usuniete,
			// a w historii sprawy ANI SLADU, ze operacje wykonano. Ten wpis jest
			// dowodem rozliczalnosci przy zadaniu usuniecia danych — bez niego
			// nie da sie wykazac ani ZE, ani KIEDY.
			$slady_ok = true;

			foreach ( $case_ids as $case_id ) {
				$slady_ok = CaseEvents::log( $case_id, CaseEvents::PII_REDACTION, array( 'target' => 'customer' ), null ) && $slady_ok;
			}

			if ( ! $slady_ok ) {
				$wpdb->query( 'ROLLBACK' ); // phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- zamkniecie transakcji.

				// Alarm PO wycofaniu transakcji — inaczej zniknalby razem z nia
				// (`wp_options` jest w tej samej transakcji).
				Common\EventWrite::alert( Tables::full( Tables::CASE_EVENTS ), CaseEvents::PII_REDACTION );

				$retained   = true;
				$messages[] = __( 'Usunięcie danych zostało wstrzymane: nie udało się zapisać śladu operacji. Żądanie pozostaje do wykonania.', 'mp-service-intake' );
				continue;
			}

			$wpdb->query( 'COMMIT' ); // phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- zamkniecie transakcji.

			// PO COMMIT — operacje nieodwracalne lub poza naszymi tabelami.
			// Pliki: idempotentne; gdyby proces padl tuz po commicie, retencja
			// zalacznikow (Lifecycle) sprzata sieroty.
			Attachments::delete_for_cases( $case_ids );

			// D1 (RODO art. 17): usun konto WP klienta (e-mail/login/nazwisko z wp_users).
			// Tylko czyste konto klienta — personel/admin nietkniety (Accounts).
			if ( null !== $wp_user_id ) {
				Accounts::purge_client_account( $wp_user_id );
			}

			$removed    = true;
			$messages[] = __( 'Dane osobowe powiązane ze zgłoszeniami serwisowymi zostały zanonimizowane.', 'mp-service-intake' );
		}

		// ZGLOSZENIA NIEPOTWIERDZONE — poza spisem po klientach, bo klienta
		// jeszcze nie maja. To w nich leza dane osoby, ktora nigdy klientem nie
		// zostala: adres, telefon, opis usterki i ZALACZNIKI. Kasujemy je w
		// calosci (nie ma czego anonimizowac — sprawa bez potwierdzenia nie jest
		// dowodem niczego), ta sama mechanika co retencja porzuconych zgloszen.
		$pending_ids = CaseRepo::pending_ids_by_email( $email );

		if ( array() !== $pending_ids ) {
			$skasowane = CaseRepo::purge_pending_cases( $pending_ids );

			if ( $skasowane > 0 ) {
				$removed    = true;
				$messages[] = __( 'Niepotwierdzone zgłoszenia z tego adresu zostały usunięte razem z załącznikami.', 'mp-service-intake' );
			}
		}

		return array(
			'items_removed'  => $removed,
			'items_retained' => $retained,
			'messages'       => $messages,
			'done'           => true,
		);
	}

	/**
	 * Exporter: dane klienta + sprawy + TRESCI Z FORMULARZA + wiadomosci + metadane zalacznikow.
	 *
	 * Zasada (audyt 28.07): co redagujemy przy USUWANIU jako dane wrazliwe, to musi
	 * byc oddane przy ZADANIU DOSTEPU. Straznik: testy/e2e/c28-eksport-rodo-kompletny.sh.
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

				// Tresci, ktore klient WPISAL w formularzu (opis usterki, numer
				// seryjny, dokument zakupu, powod zwrotu, pola kategorii).
				// Bez tego eksport art. 15 byl niespojny z eraserem: przy USUWANIU
				// redagujemy te pola jako dane wrazliwe, a przy ZADANIU DOSTEPU
				// ich nie oddawalismy (audyt 28.07, straznik: c28-eksport-rodo-kompletny.sh).
				// Etykiety biore te same, ktore klient widzial w formularzu.
				$pola_formularza = array();

				foreach ( CaseRepo::form_data_for_case( $case_id ) as $pole ) {
					$wartosc = trim( (string) $pole['value'] );

					if ( '' === $wartosc ) {
						continue;
					}

					$pola_formularza[] = array(
						'name'  => '' !== $pole['label'] ? $pole['label'] : $pole['key'],
						'value' => $wartosc,
					);
				}

				if ( array() !== $pola_formularza ) {
					$export[] = array(
						'group_id'    => 'mp_case_form',
						'group_label' => __( 'Treść zgłoszeń MP (dane z formularza)', 'mp-service-intake' ),
						'item_id'     => 'case-form-' . $case_id,
						'data'        => array_merge(
							array(
								array(
									'name'  => __( 'Numer sprawy', 'mp-service-intake' ),
									'value' => (string) $case['case_number'],
								),
							),
							$pola_formularza
						),
					);
				}

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

		// ZGLOSZENIA NIEPOTWIERDZONE — art. 15 obejmuje je tak samo jak art. 17
		// (patrz `erase`). Bez tego czlowiek, ktory zlozyl zgloszenie i nie
		// kliknal linku, dostawal odpowiedz „nie mamy Twoich danych", choc
		// w bazie lezal jego adres, telefon, opis usterki i zdjecia.
		foreach ( CaseRepo::pending_ids_by_email( trim( $email ) ) as $case_id ) {
			$pending = get_option( 'mp_pending_contact_' . $case_id, array() );
			$dane    = array(
				array(
					'name'  => __( 'Numer sprawy', 'mp-service-intake' ),
					'value' => CaseRepo::case_number( $case_id ),
				),
				array(
					'name'  => __( 'Stan', 'mp-service-intake' ),
					'value' => __( 'zgłoszenie niepotwierdzone (nie kliknięto linku potwierdzającego)', 'mp-service-intake' ),
				),
				array(
					'name'  => __( 'Imię i nazwisko', 'mp-service-intake' ),
					'value' => is_array( $pending ) ? (string) ( $pending['name'] ?? '' ) : '',
				),
				array(
					'name'  => __( 'Telefon', 'mp-service-intake' ),
					'value' => is_array( $pending ) ? (string) ( $pending['phone'] ?? '' ) : '',
				),
				array(
					'name'  => __( 'Załączniki', 'mp-service-intake' ),
					'value' => self::attachments_summary( $case_id ),
				),
			);

			foreach ( CaseRepo::form_data_for_case( $case_id ) as $pole ) {
				$wartosc = trim( (string) $pole['value'] );

				if ( '' === $wartosc ) {
					continue;
				}

				$dane[] = array(
					'name'  => '' !== $pole['label'] ? $pole['label'] : $pole['key'],
					'value' => $wartosc,
				);
			}

			$export[] = array(
				'group_id'    => 'mp_pending_cases',
				'group_label' => __( 'Zgłoszenia niepotwierdzone MP', 'mp-service-intake' ),
				'item_id'     => 'pending-case-' . $case_id,
				'data'        => $dane,
			);
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
