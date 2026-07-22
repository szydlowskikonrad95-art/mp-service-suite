<?php
/**
 * Klienci (wp_mp_customers) — upsert po emailu, odczyt, anonimizacja.
 *
 * Anonimizacja zostawia wiersz i relacje (odpina konto WP, czysci pola) —
 * historia spraw musi przezyc; PII znika. Szczegoly: OWNERSHIP.md / MAPA-PII.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Repozytorium klientow.
 */
final class Customers {

	/**
	 * Znajduje klienta po emailu albo tworzy nowego (bez duplikatow po mailu).
	 *
	 * @param string $email E-mail (klucz logiczny klienta).
	 * @param string $name  Nazwa/imie.
	 * @param string $phone Telefon.
	 * @return int ID klienta.
	 */
	public static function upsert_by_email( string $email, string $name, string $phone ): int {
		global $wpdb;

		$table = Tables::full( Tables::CUSTOMERS );
		$now   = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytania przygotowane.
		$existing = $wpdb->get_var(
			$wpdb->prepare( "SELECT id FROM {$table} WHERE email = %s AND anonymized_at IS NULL ORDER BY id LIMIT 1", $email )
		);

		if ( null !== $existing ) {
			$wpdb->query(
				$wpdb->prepare(
					"UPDATE {$table} SET name = %s, phone = %s, updated_at = %s WHERE id = %d",
					$name,
					$phone,
					$now,
					(int) $existing
				)
			);

			return (int) $existing;
		}

		$wpdb->insert(
			$table,
			array(
				'email'      => $email,
				'name'       => $name,
				'phone'      => $phone,
				'created_at' => $now,
				'updated_at' => $now,
			)
		);
		// phpcs:enable

		return (int) $wpdb->insert_id;
	}

	/**
	 * Czy konto WP nalezy do danego klienta (ownership dla dostepu do zalacznikow).
	 *
	 * @param int $wp_user_id  ID uzytkownika WP.
	 * @param int $customer_id ID klienta.
	 * @return bool
	 */
	public static function wp_user_owns_customer( int $wp_user_id, int $customer_id ): bool {
		global $wpdb;

		$table = Tables::full( Tables::CUSTOMERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$owner = $wpdb->get_var(
			$wpdb->prepare(
				"SELECT wp_user_id FROM {$table} WHERE id = %d AND anonymized_at IS NULL",
				$customer_id
			)
		);
		// phpcs:enable

		return null !== $owner && (int) $owner === $wp_user_id;
	}

	/**
	 * ID nieanonimizowanych klientow o danym emailu (eraser szuka po EMAILU).
	 *
	 * @param string $email E-mail.
	 * @return array<int, int>
	 */
	public static function ids_by_email( string $email ): array {
		global $wpdb;

		$table = Tables::full( Tables::CUSTOMERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$ids = $wpdb->get_col(
			$wpdb->prepare( "SELECT id FROM {$table} WHERE email = %s AND anonymized_at IS NULL", $email )
		);
		// phpcs:enable

		return array_map( 'intval', (array) $ids );
	}

	/**
	 * Anonimizuje klienta: czysci pola PII, flaga anonymized_at, odpina konto WP.
	 * Wiersz i relacje ZOSTAJA (bez DELETE) — historia spraw przezywa.
	 *
	 * @param int $customer_id ID klienta.
	 * @return void
	 */
	public static function anonymize( int $customer_id ): void {
		global $wpdb;

		$table = Tables::full( Tables::CUSTOMERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table}
				SET email = %s, name = '', phone = '', wp_user_id = NULL, anonymized_at = %s, updated_at = %s
				WHERE id = %d",
				'anon-' . $customer_id . '@removed.invalid',
				gmdate( 'Y-m-d H:i:s' ),
				gmdate( 'Y-m-d H:i:s' ),
				$customer_id
			)
		);
		// phpcs:enable
	}

	/**
	 * Aktualizuje dane kontaktowe klienta (art. 16 — sprostowanie z panelu).
	 *
	 * E-mail NIE jest ruszany (klucz tozsamosci; korekty danych sprawy przez
	 * wiadomosci). Anonimizowanych klientow nie tyka.
	 *
	 * @param int    $customer_id ID klienta.
	 * @param string $name        Nazwa/imie.
	 * @param string $phone       Telefon.
	 * @return void
	 */
	public static function update_contact( int $customer_id, string $name, string $phone ): void {
		global $wpdb;

		$table = Tables::full( Tables::CUSTOMERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET name = %s, phone = %s, updated_at = %s WHERE id = %d AND anonymized_at IS NULL",
				$name,
				$phone,
				gmdate( 'Y-m-d H:i:s' ),
				$customer_id
			)
		);
		// phpcs:enable
	}

	/**
	 * Odczyt klienta po ID.
	 *
	 * @param int $customer_id ID klienta.
	 * @return array<string, mixed>|null
	 */
	public static function get( int $customer_id ): ?array {
		global $wpdb;

		$table = Tables::full( Tables::CUSTOMERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT * FROM {$table} WHERE id = %d", $customer_id ),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $row ) ? $row : null;
	}

	/**
	 * Ustawia konto WP klienta (spiecie po weryfikacji — Accounts).
	 *
	 * @param int $customer_id ID klienta.
	 * @param int $wp_user_id  ID uzytkownika WP.
	 * @return void
	 */
	public static function set_wp_user( int $customer_id, int $wp_user_id ): void {
		global $wpdb;

		$table = Tables::full( Tables::CUSTOMERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET wp_user_id = %d, updated_at = %s WHERE id = %d",
				$wp_user_id,
				gmdate( 'Y-m-d H:i:s' ),
				$customer_id
			)
		);
		// phpcs:enable
	}

	/**
	 * Odczyt konta WP klienta (null = brak spiecia albo klient nie istnieje).
	 *
	 * @param int $customer_id ID klienta.
	 * @return int|null
	 */
	public static function wp_user_id( int $customer_id ): ?int {
		global $wpdb;

		$table = Tables::full( Tables::CUSTOMERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$value = $wpdb->get_var(
			$wpdb->prepare( "SELECT wp_user_id FROM {$table} WHERE id = %d", $customer_id )
		);
		// phpcs:enable

		return null === $value ? null : (int) $value;
	}

	/**
	 * ID nieanonimizowanych klientow spietych z danym kontem WP (panel).
	 *
	 * Jeden e-mail = jeden klient, ale konto personelu moze byc podpiete
	 * do >1 rekordu (rozne e-maile w czasie) — zwracamy liste.
	 *
	 * @param int $wp_user_id ID uzytkownika WP.
	 * @return array<int, int>
	 */
	public static function ids_by_wp_user( int $wp_user_id ): array {
		global $wpdb;

		$table = Tables::full( Tables::CUSTOMERS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$ids = $wpdb->get_col(
			$wpdb->prepare( "SELECT id FROM {$table} WHERE wp_user_id = %d AND anonymized_at IS NULL", $wp_user_id )
		);
		// phpcs:enable

		return array_map( 'intval', (array) $ids );
	}
}
