<?php
/**
 * Cykl zycia jobow importu CSV (tabela wp_mp_import_jobs).
 *
 * Zasady kontraktu (karta B): jeden aktywny import globalnie (lock_key UNIQUE
 * przez INSERT-pod-UNIQUE — NIGDY add_option), job_token UUID per przejecie,
 * stale-detekcja po updated_at (>15 min), wznowienie z offsetu.
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * Repozytorium jobow importu.
 */
final class ImportJobs {

	/**
	 * Wartosc locka zywego importu (UNIQUE — drugi INSERT odbija).
	 */
	public const LOCK_LIVE = 'product-import';

	/**
	 * Minuty bezczynnosci, po ktorych job uznajemy za osierocony.
	 */
	public const STALE_MINUTES = 15;

	/**
	 * Tworzy job (atomowo przejmuje globalny lock importu).
	 *
	 * @param string $file_path Sciezka znormalizowanego pliku CSV (UTF-8).
	 * @param int    $total     Liczba wierszy danych.
	 * @return array{id: int, token: string}|null Null = inny import aktywny.
	 */
	public static function create( string $file_path, int $total ): ?array {
		global $wpdb;

		self::release_stale();

		$table = Tables::full( Tables::IMPORT_JOBS );
		$token = wp_generate_uuid4();
		$now   = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna; INSERT-pod-UNIQUE = atomowy lock.
		$inserted = $wpdb->query(
			$wpdb->prepare(
				"INSERT IGNORE INTO {$table}
				(file_path, status, total_rows, lock_key, job_token, created_at, updated_at)
				VALUES (%s, 'processing', %d, %s, %s, %s, %s)",
				$file_path,
				$total,
				self::LOCK_LIVE,
				$token,
				$now,
				$now
			)
		);
		// phpcs:enable

		if ( 1 !== (int) $inserted ) {
			return null;
		}

		return array(
			'id'    => (int) $wpdb->insert_id,
			'token' => $token,
		);
	}

	/**
	 * Pobiera job po ID (swiezy odczyt, bez cache).
	 *
	 * @param int $job_id ID joba.
	 * @return array<string, mixed>|null
	 */
	public static function get( int $job_id ): ?array {
		global $wpdb;

		$table = Tables::full( Tables::IMPORT_JOBS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT * FROM {$table} WHERE id = %d", $job_id ),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $row ) ? $row : null;
	}

	/**
	 * Zwraca zywy job (processing pod globalnym lockiem) lub null.
	 *
	 * @return array<string, mixed>|null
	 */
	public static function find_live(): ?array {
		global $wpdb;

		$table = Tables::full( Tables::IMPORT_JOBS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT * FROM {$table} WHERE lock_key = %s", self::LOCK_LIVE ),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $row ) ? $row : null;
	}

	/**
	 * Ostatnie joby importu (historia na ekranie admina).
	 *
	 * @param int $limit Ile wierszy.
	 * @return array<int, array<string, mixed>>
	 */
	public static function latest( int $limit = 5 ): array {
		global $wpdb;

		$table = Tables::full( Tables::IMPORT_JOBS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$rows = $wpdb->get_results(
			$wpdb->prepare( "SELECT * FROM {$table} ORDER BY id DESC LIMIT %d", $limit ),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * Przejecie/wznowienie joba = NOWY token (stary batch dostaje odmowe).
	 *
	 * @param int $job_id ID joba.
	 * @return string|null Nowy token lub null (job nie istnieje / zamkniety).
	 */
	public static function reclaim( int $job_id ): ?string {
		global $wpdb;

		$table = Tables::full( Tables::IMPORT_JOBS );
		$token = wp_generate_uuid4();

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$updated = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET job_token = %s, status = 'processing', lock_key = %s, updated_at = %s
				WHERE id = %d AND status IN ('processing','stale')",
				$token,
				self::LOCK_LIVE,
				gmdate( 'Y-m-d H:i:s' ),
				$job_id
			)
		);
		// phpcs:enable

		return 1 === (int) $updated ? $token : null;
	}

	/**
	 * Zamyka job (sukces lub blad) i zwalnia lock (lock_key = done-{id}).
	 *
	 * @param int    $job_id ID joba.
	 * @param string $status Status koncowy (done/failed).
	 * @return void
	 */
	public static function finish( int $job_id, string $status = 'done' ): void {
		global $wpdb;

		$table = Tables::full( Tables::IMPORT_JOBS );
		$now   = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET status = %s, lock_key = %s, finished_at = %s, updated_at = %s WHERE id = %d",
				$status,
				'done-' . $job_id,
				$now,
				$now,
				$job_id
			)
		);
		// phpcs:enable
	}

	/**
	 * Oznacza osierocone joby jako stale i zwalnia globalny lock.
	 *
	 * Wolane przy starcie nowego importu ORAZ przy renderze ekranu importu.
	 *
	 * @return void
	 */
	public static function release_stale(): void {
		global $wpdb;

		$table  = Tables::full( Tables::IMPORT_JOBS );
		$cutoff = gmdate( 'Y-m-d H:i:s', time() - self::STALE_MINUTES * 60 );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET status = 'stale', lock_key = CONCAT('stale-', id), updated_at = %s
				WHERE status = 'processing' AND lock_key = %s AND updated_at < %s",
				gmdate( 'Y-m-d H:i:s' ),
				self::LOCK_LIVE,
				$cutoff
			)
		);
		// phpcs:enable
	}
}
