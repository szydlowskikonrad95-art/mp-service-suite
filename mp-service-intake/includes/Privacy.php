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
		unset( $page );

		$email    = trim( $email );
		$messages = array();
		$removed  = false;
		$retained = false;

		foreach ( Customers::ids_by_email( $email ) as $customer_id ) {
			// Sprawa aktywna / okno roszczen => ODROCZENIE EN BLOC (nic nie tykamy).
			if ( CaseRepo::has_active_case( $customer_id ) ) {
				$retained   = true;
				$messages[] = __( 'Dane zatrzymane do zakończenia aktywnej sprawy serwisowej lub upływu okresu roszczeń (gwarancja/rękojmia).', 'mp-service-intake' );
				continue;
			}

			$cases    = CaseRepo::for_customer( $customer_id );
			$case_ids = array_map( static fn( array $c ): int => (int) $c['id'], $cases );

			Messages::redact_for_cases( $case_ids );
			CaseRepo::redact_pii_for_cases( $case_ids );
			Attachments::delete_for_cases( $case_ids );

			// B redaguje reason wyjatkow powiazanych ze sprawami klienta.
			if ( has_filter( 'mp_privacy_redact_for_customer' ) ) {
				apply_filters( 'mp_privacy_redact_for_customer', null, $customer_id, $case_ids );
			}

			Customers::anonymize( $customer_id );
			// FLAGA #6: redakcja e-maila (PII) w zgodach — rozliczalnosc art. 7 zostaje (tekst+daty).
			Consents::redact_email_for_customer( $customer_id );

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
