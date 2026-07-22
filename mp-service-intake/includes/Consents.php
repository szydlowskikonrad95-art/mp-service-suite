<?php
/**
 * Zgody RODO — wp_mp_consents (rozliczalnosc art. 7).
 *
 * PELNY TEKST zgody zamrazany w wierszu przy zbieraniu (nie wisi na plikach
 * wtyczki — admin nie podmieni historii). Wycofanie = wpis withdrawn_at +
 * event CONSENT_WITHDRAWN (art. 7(3) „rownie latwe jak udzielenie").
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Rejestr zgod klienta.
 */
final class Consents {

	/**
	 * Klucz zgody na przetwarzanie danych w celu obslugi zgloszenia.
	 */
	public const KEY_PROCESSING = 'processing';

	/**
	 * Wersja tresci zgody (bump przy zmianie tekstu — pliki wersjonowane).
	 */
	public const VERSION = '1.0';

	/**
	 * Kanoniczna tresc zgody (zrodlo wyswietlania; zamrazana w wierszu przy zbieraniu).
	 *
	 * @return string
	 */
	public static function processing_text(): string {
		return __(
			'Wyrażam zgodę na przetwarzanie moich danych osobowych podanych w zgłoszeniu w celu jego obsługi serwisowej, zgodnie z informacją o przetwarzaniu danych. Zgodę mogę wycofać w każdej chwili z poziomu mojego konta, co nie wpływa na zgodność z prawem przetwarzania sprzed wycofania.',
			'mp-service-intake'
		);
	}

	/**
	 * Zapisuje zgode (pelny tekst zamrozony) spieta ze sprawa i emailem.
	 *
	 * @param string   $email   E-mail zglaszajacego.
	 * @param int|null $case_id Sprawa (moze byc null przed podpieciem).
	 * @param string   $key     Klucz zgody.
	 * @param string   $version Wersja tresci.
	 * @param string   $text    Pelna tresc zgody z chwili zbierania.
	 * @return int ID wiersza zgody.
	 */
	public static function record( string $email, ?int $case_id, string $key, string $version, string $text ): int {
		global $wpdb;

		$now = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna.
		$wpdb->insert(
			Tables::full( Tables::CONSENTS ),
			array(
				'customer_id'     => null,
				'email'           => $email,
				'case_id'         => $case_id,
				'consent_key'     => $key,
				'consent_version' => $version,
				'consent_text'    => $text,
				'consented_at'    => $now,
			)
		);
		// phpcs:enable

		return (int) $wpdb->insert_id;
	}

	/**
	 * Podpina zgody zebrane przy zgloszeniu do klienta (po weryfikacji).
	 *
	 * @param int $case_id     ID sprawy.
	 * @param int $customer_id ID klienta.
	 * @return void
	 */
	public static function attach_case_to_customer( int $case_id, int $customer_id ): void {
		global $wpdb;

		$table = Tables::full( Tables::CONSENTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET customer_id = %d WHERE case_id = %d AND customer_id IS NULL",
				$customer_id,
				$case_id
			)
		);
		// phpcs:enable
	}

	/**
	 * Wycofuje zgode klienta (self-service; art. 7(3)).
	 *
	 * @param int    $customer_id ID klienta.
	 * @param string $key         Klucz zgody.
	 * @return bool Czy cokolwiek wycofano.
	 */
	public static function withdraw( int $customer_id, string $key ): bool {
		global $wpdb;

		$table = Tables::full( Tables::CONSENTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$affected = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET withdrawn_at = %s WHERE customer_id = %d AND consent_key = %s AND withdrawn_at IS NULL",
				gmdate( 'Y-m-d H:i:s' ),
				$customer_id,
				$key
			)
		);
		// phpcs:enable

		return (int) $affected > 0;
	}

	/**
	 * Zgody klienta (do panelu i eksportu).
	 *
	 * @param int $customer_id ID klienta.
	 * @return array<int, array<string, mixed>>
	 */
	public static function for_customer( int $customer_id ): array {
		global $wpdb;

		$table = Tables::full( Tables::CONSENTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT * FROM {$table} WHERE customer_id = %d ORDER BY id DESC",
				$customer_id
			),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $rows ) ? $rows : array();
	}
}
