<?php
/**
 * Wyjatki gwarancyjne — CRUD STANU wg PRECEDENSU z kontraktu (karta B, r6):
 *
 * - max JEDEN aktywny wyjatek per zakres (produkt+sprawa LUB produkt-globalnie);
 *   CREATE drugiego = odmowa,
 * - per-sprawa > globalny (odczyt: Repo::get_active_exception, case-first),
 * - przyznaje/cofa WYLACZNIE capability mp_system_admin,
 * - status w bazie TYLKO active/revoked — "expired" ZAWSZE WYLICZANE
 *   z valid_until, nigdy zapisywane (JEDNA wersja prawdy),
 * - valid_until > NOW przy CREATE,
 * - emisja mp_warranty_exception_changed PO COMMIT (5 argumentow,
 *   API-KONTRAKT.md); payload eventow historii BEZ reason.
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * Operacje na stanie wyjatkow gwarancyjnych.
 */
final class WarrantyExceptions {

	/**
	 * Maksymalna dlugosc powodu (kontrakt: reason <= 500).
	 */
	public const REASON_MAX = 500;

	/**
	 * Przyznaje wyjatek gwarancyjny.
	 *
	 * @param int         $product_registry_id ID produktu z rejestru.
	 * @param int|null    $case_id             Sprawa (null = wyjatek globalny na produkt).
	 * @param string      $reason              Powod (wymagany, <=500).
	 * @param string|null $valid_until      Waznosc: null (bezterminowo), 'Y-m-d' lub 'Y-m-d H:i:s' (UTC, > NOW).
	 * @return array{id: int}|array{error: string}
	 */
	public static function create( int $product_registry_id, ?int $case_id, string $reason, ?string $valid_until ): array {
		global $wpdb;

		if ( ! current_user_can( 'mp_system_admin' ) ) {
			return array( 'error' => __( 'Wyjątki gwarancyjne może przyznawać wyłącznie administrator systemu MP.', 'mp-warranty-registry' ) );
		}

		$reason_error = self::validate_reason( $reason );

		if ( null !== $reason_error ) {
			return array( 'error' => $reason_error );
		}

		$now   = gmdate( 'Y-m-d H:i:s' );
		$until = self::normalize_valid_until( $valid_until, $now );

		if ( null !== $until['error'] ) {
			return array( 'error' => $until['error'] );
		}

		$registry = Tables::full( Tables::REGISTRY );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne, zapytania przygotowane; transakcja chroni bramke max-1-aktywny.
		$product_exists = (int) $wpdb->get_var(
			$wpdb->prepare( "SELECT COUNT(*) FROM {$registry} WHERE id = %d", $product_registry_id )
		);

		if ( 0 === $product_exists ) {
			// phpcs:enable
			return array( 'error' => __( 'Produkt o tym ID nie istnieje w rejestrze.', 'mp-warranty-registry' ) );
		}

		$table    = Tables::full( Tables::EXCEPTIONS );
		$actor_id = get_current_user_id();

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne; SELECT FOR UPDATE w transakcji = bramka max-1-aktywny per zakres.
		$wpdb->query( 'START TRANSACTION' );

		$scope_sql = null === $case_id ? 'case_id IS NULL' : 'case_id = %d';
		$args      = null === $case_id
			? array( $product_registry_id, $now )
			: array( $product_registry_id, $case_id, $now );

		$active_in_scope = $wpdb->get_var(
			// phpcs:ignore WordPress.DB.PreparedSQLPlaceholders.ReplacementsWrongNumber -- $scope_sql dla case_id dodaje %d; liczba argumentow w $args zawsze rowna liczbie placeholderow.
			$wpdb->prepare(
				"SELECT id FROM {$table}
				WHERE product_registry_id = %d AND status = 'active' AND {$scope_sql}
				AND ( valid_until IS NULL OR valid_until >= %s )
				LIMIT 1 FOR UPDATE",
				$args
			)
		);

		if ( null !== $active_in_scope ) {
			$wpdb->query( 'ROLLBACK' );

			return array( 'error' => __( 'W tym zakresie (produkt + sprawa albo produkt globalnie) jest już AKTYWNY wyjątek — najpierw go cofnij.', 'mp-warranty-registry' ) );
		}

		$inserted = $wpdb->insert(
			$table,
			array(
				'product_registry_id' => $product_registry_id,
				'case_id'             => $case_id,
				'status'              => 'active',
				'valid_from'          => $now,
				'valid_until'         => $until['value'],
				'reason'              => $reason,
				'created_by'          => $actor_id,
				'created_at'          => $now,
			)
		);

		if ( 1 !== (int) $inserted ) {
			$wpdb->query( 'ROLLBACK' );

			return array( 'error' => __( 'Błąd zapisu wyjątku do bazy.', 'mp-warranty-registry' ) );
		}

		$exception_id = (int) $wpdb->insert_id;

		ProductEvents::log(
			$product_registry_id,
			ProductEvents::EXCEPTION_CREATED,
			array(
				'exception_id' => $exception_id,
				'typ'          => null === $case_id ? 'globalny' : 'per-sprawa',
				'actor_id'     => $actor_id,
			),
			$actor_id
		);

		$wpdb->query( 'COMMIT' );
		// phpcs:enable

		do_action( 'mp_warranty_exception_changed', $exception_id, $product_registry_id, $case_id, 'active', WarrantyCheck::SCHEMA_VERSION );

		return array( 'id' => $exception_id );
	}

	/**
	 * Cofa wyjatek gwarancyjny.
	 *
	 * @param int $exception_id ID wyjatku.
	 * @return true|array{error: string}
	 */
	public static function revoke( int $exception_id ) {
		global $wpdb;

		if ( ! current_user_can( 'mp_system_admin' ) ) {
			return array( 'error' => __( 'Wyjątki gwarancyjne może cofać wyłącznie administrator systemu MP.', 'mp-warranty-registry' ) );
		}

		$table    = Tables::full( Tables::EXCEPTIONS );
		$actor_id = get_current_user_id();
		$now      = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne; UPDATE warunkowy = ochrona przed podwojnym cofnieciem.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT product_registry_id, case_id, status FROM {$table} WHERE id = %d", $exception_id ),
			ARRAY_A
		);

		if ( ! is_array( $row ) ) {
			// phpcs:enable
			return array( 'error' => __( 'Wyjątek o tym ID nie istnieje.', 'mp-warranty-registry' ) );
		}

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- jw.
		$wpdb->query( 'START TRANSACTION' );

		$updated = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET status = 'revoked', revoked_by = %d, revoked_at = %s WHERE id = %d AND status = 'active'",
				$actor_id,
				$now,
				$exception_id
			)
		);

		if ( 1 !== (int) $updated ) {
			$wpdb->query( 'ROLLBACK' );

			return array( 'error' => __( 'Ten wyjątek jest już cofnięty.', 'mp-warranty-registry' ) );
		}

		ProductEvents::log(
			(int) $row['product_registry_id'],
			ProductEvents::EXCEPTION_REVOKED,
			array(
				'exception_id' => $exception_id,
				'typ'          => null === $row['case_id'] ? 'globalny' : 'per-sprawa',
				'actor_id'     => $actor_id,
			),
			$actor_id
		);

		$wpdb->query( 'COMMIT' );
		// phpcs:enable

		$case_id = null === $row['case_id'] ? null : (int) $row['case_id'];

		do_action( 'mp_warranty_exception_changed', $exception_id, (int) $row['product_registry_id'], $case_id, 'revoked', WarrantyCheck::SCHEMA_VERSION );

		return true;
	}

	/**
	 * Listener mp_cases_data_erased (C -> B): tabele spraw przestaly istniec.
	 *
	 * Kontrakt: wyjatki z case_id NOT NULL -> revoked + event; GLOBALNE zostaja.
	 * SWIADOMIE bez emisji mp_warranty_exception_changed — sygnal przychodzi
	 * z uninstalla C (spraw juz nie ma; hook per wyjatek napedzalby reguly D
	 * na martwych sprawach). Slad: PR #7.
	 *
	 * @return int Liczba cofnietych wyjatkow.
	 */
	public static function on_cases_data_erased(): int {
		global $wpdb;

		$table = Tables::full( Tables::EXCEPTIONS );
		$now   = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; operacja systemowa (uninstall C).
		$rows = $wpdb->get_results(
			"SELECT id, product_registry_id FROM {$table} WHERE status = 'active' AND case_id IS NOT NULL",
			ARRAY_A
		);

		if ( ! is_array( $rows ) || array() === $rows ) {
			// phpcs:enable
			return 0;
		}

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- jw.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET status = 'revoked', revoked_by = NULL, revoked_at = %s
				WHERE status = 'active' AND case_id IS NOT NULL",
				$now
			)
		);
		// phpcs:enable

		foreach ( $rows as $row ) {
			ProductEvents::log(
				(int) $row['product_registry_id'],
				ProductEvents::EXCEPTION_REVOKED,
				array(
					'exception_id'    => (int) $row['id'],
					'typ'             => 'per-sprawa',
					'powod_systemowy' => 'cases_data_erased',
				),
				null
			);
		}

		return count( $rows );
	}

	/**
	 * Listener filtra mp_privacy_redact_for_customer (eraser RODO z C).
	 *
	 * B redaguje `reason` wyjatkow powiazanych ze sprawami klienta
	 * (wszystkie statusy — revoked tez trzyma tekst). Zwrotka wg kontraktu.
	 *
	 * @param mixed      $result      Wartosc wejsciowa filtra (ignorowana — B odpowiada za siebie).
	 * @param int        $customer_id ID klienta (u nas nieuzywane — zakres daja sprawy).
	 * @param array<int> $case_ids    Sprawy klienta.
	 * @return array{success: bool, redacted_count: int}
	 */
	public static function privacy_redact( $result, int $customer_id, array $case_ids ): array {
		global $wpdb;

		unset( $result, $customer_id );

		$ids = array_values( array_filter( array_map( 'absint', $case_ids ) ) );

		if ( array() === $ids ) {
			return array(
				'success'        => true,
				'redacted_count' => 0,
			);
		}

		$table        = Tables::full( Tables::EXCEPTIONS );
		$placeholders = implode( ',', array_fill( 0, count( $ids ), '%d' ) );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared, WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare -- tabela wlasna; lista %d w IN() budowana z count($ids), sniff nie widzi placeholderow po interpolacji.
		$redacted = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET reason = '[zredagowano — RODO]' WHERE case_id IN ({$placeholders}) AND reason <> '[zredagowano — RODO]'",
				$ids
			)
		);
		// phpcs:enable

		return array(
			'success'        => false !== $redacted,
			'redacted_count' => false === $redacted ? 0 : (int) $redacted,
		);
	}

	/**
	 * Walidacja powodu (czysta — testowana jednostkowo).
	 *
	 * @param string $reason Powod.
	 * @return string|null Komunikat bledu lub null (OK).
	 */
	public static function validate_reason( string $reason ): ?string {
		if ( '' === trim( $reason ) ) {
			return __( 'Powód wyjątku jest wymagany.', 'mp-warranty-registry' );
		}

		if ( mb_strlen( $reason ) > self::REASON_MAX ) {
			return __( 'Powód wyjątku może mieć najwyżej 500 znaków.', 'mp-warranty-registry' );
		}

		return null;
	}

	/**
	 * Normalizacja terminu waznosci (czysta — testowana jednostkowo).
	 *
	 * Wejscie null = bezterminowo. 'Y-m-d' dostaje 23:59:59 (koniec dnia UTC).
	 * Wynik MUSI byc > $now (kontrakt: valid_until > NOW przy CREATE).
	 *
	 * @param string|null $input Wejscie od usera.
	 * @param string      $now   Teraz w 'Y-m-d H:i:s' (UTC).
	 * @return array{value: string|null, error: string|null}
	 */
	public static function normalize_valid_until( ?string $input, string $now ): array {
		if ( null === $input || '' === trim( $input ) ) {
			return array(
				'value' => null,
				'error' => null,
			);
		}

		$input = trim( $input );

		if ( 1 === preg_match( '/^\d{4}-\d{2}-\d{2}$/', $input ) ) {
			$input .= ' 23:59:59';
		}

		$parsed = \DateTime::createFromFormat( 'Y-m-d H:i:s', $input, new \DateTimeZone( 'UTC' ) );

		if ( false === $parsed || $parsed->format( 'Y-m-d H:i:s' ) !== $input ) {
			return array(
				'value' => null,
				'error' => __( 'Termin ważności podaj jako RRRR-MM-DD (albo RRRR-MM-DD GG:MM:SS, czas UTC).', 'mp-warranty-registry' ),
			);
		}

		if ( $input <= $now ) {
			return array(
				'value' => null,
				'error' => __( 'Termin ważności wyjątku musi być w przyszłości.', 'mp-warranty-registry' ),
			);
		}

		return array(
			'value' => $input,
			'error' => null,
		);
	}
}
