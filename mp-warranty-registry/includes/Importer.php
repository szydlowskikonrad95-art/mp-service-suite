<?php
/**
 * Procesor batchy importu CSV (spec P2.1 + karta B "import BEZPIECZNY").
 *
 * Batch = 100 wierszy w JEDNEJ transakcji DB razem z podbiciem offsetu
 * (processed_rows) — crash w polowie batcha => rollback calego => wznowienie
 * od starego offsetu: zero duplikatow, zero pol-zapisow.
 *
 * @package MP\Registry
 */

namespace MP\Registry;

use MP\Registry\Common\Str;

/**
 * Przetwarzanie porcji wierszy joba importu.
 */
final class Importer {

	/**
	 * Rozmiar batcha (kontrakt: porcje po 100 w OSOBNYCH zadaniach).
	 */
	public const BATCH_SIZE = 100;

	/**
	 * Limit rozmiaru pliku importu w bajtach (konfigurowalny; default 20 MB).
	 */
	public const MAX_FILE_BYTES = 20971520;

	/**
	 * Przygotowuje plik i zaklada job importu.
	 *
	 * Kroki: limit rozmiaru (jawna odmowa), normalizacja do UTF-8 (BOM/Win-1250),
	 * zapis pod LOSOWA nazwa w uploads/mp-imports/ (deny-exec + index.php),
	 * walidacja naglowka, zliczenie wierszy danych, atomowy lock (ImportJobs).
	 *
	 * @param string $source_path Sciezka zrodlowego CSV.
	 * @return array{job_id: int, token: string, total: int}|array{error: string}
	 */
	public static function create_job_from_file( string $source_path ): array {
		if ( ! is_file( $source_path ) ) {
			return array( 'error' => 'Plik nie istnieje.' );
		}

		$size = (int) filesize( $source_path );

		if ( $size > self::MAX_FILE_BYTES ) {
			return array( 'error' => 'Plik przekracza limit importu (20 MB) — podziel go na czesci.' );
		}

		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_get_contents_file_get_contents -- lokalny plik importu.
		$raw = file_get_contents( $source_path );

		if ( false === $raw ) {
			return array( 'error' => 'Nie mozna odczytac pliku.' );
		}

		$utf8 = CsvParser::to_utf8( $raw );

		if ( null === $utf8 ) {
			return array( 'error' => 'Plik nie jest w UTF-8, a serwer nie ma iconv ani intl — zapisz CSV jako UTF-8 i sprobuj ponownie.' );
		}

		$lines = preg_split( '/\r\n|\r|\n/', $utf8 );
		$lines = array_values( array_filter( (array) $lines, static fn( $l ) => '' !== trim( (string) $l ) ) );

		if ( count( $lines ) < 2 ) {
			return array( 'error' => 'Plik nie zawiera danych (sam naglowek lub pusty).' );
		}

		$separator = CsvParser::detect_separator( (string) $lines[0] );

		if ( null === CsvParser::map_header( str_getcsv( (string) $lines[0], $separator ) ) ) {
			return array( 'error' => 'Naglowek nie zawiera kolumny serial (albo aliasu).' );
		}

		$dir = self::imports_dir();

		if ( null === $dir ) {
			return array( 'error' => 'Nie mozna utworzyc katalogu importow.' );
		}

		$target = $dir . '/' . wp_generate_uuid4() . '.csv';

		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_file_put_contents -- znormalizowany plik roboczy importu.
		if ( false === file_put_contents( $target, implode( "\n", $lines ) . "\n" ) ) {
			return array( 'error' => 'Nie mozna zapisac pliku roboczego.' );
		}

		$total = count( $lines ) - 1;
		$job   = ImportJobs::create( $target, $total );

		if ( null === $job ) {
			return array( 'error' => 'Inny import jest w toku — dokoncz go albo poczekaj na stale-detekcje (15 min).' );
		}

		return array(
			'job_id' => $job['id'],
			'token'  => $job['token'],
			'total'  => $total,
		);
	}

	/**
	 * Katalog uploads/mp-imports/ z ochrona przed wykonaniem.
	 *
	 * @return string|null Sciezka lub null.
	 */
	private static function imports_dir(): ?string {
		$uploads = wp_upload_dir();
		$dir     = rtrim( (string) $uploads['basedir'], '/' ) . '/mp-imports';

		if ( ! wp_mkdir_p( $dir ) ) {
			return null;
		}

		$guards = array(
			$dir . '/.htaccess' => "Require all denied\n",
			$dir . '/index.php' => "<?php\n// Silence is golden.\n",
		);

		foreach ( $guards as $path => $content ) {
			if ( ! file_exists( $path ) ) {
				// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_file_put_contents -- guard techniczny katalogu.
				file_put_contents( $path, $content );
			}
		}

		return $dir;
	}

	/**
	 * Przetwarza jeden batch joba.
	 *
	 * @param int    $job_id ID joba.
	 * @param string $token  Token batcha (stary token po przejeciu = odmowa).
	 * @return array{status: string, processed: int, total: int, errors: int}|array{status: string, message: string}
	 */
	public static function process_batch( int $job_id, string $token ): array {
		global $wpdb;

		$job = ImportJobs::get( $job_id );

		if ( null === $job ) {
			return array(
				'status'  => 'error',
				'message' => 'Job nie istnieje.',
			);
		}

		if ( (string) $job['job_token'] !== $token ) {
			return array(
				'status'  => 'error',
				'message' => 'Nieaktualny token joba (import przejety w innym oknie).',
			);
		}

		if ( 'processing' !== (string) $job['status'] ) {
			return array(
				'status'  => 'error',
				'message' => 'Job nie jest w trakcie przetwarzania.',
			);
		}

		$offset = (int) $job['processed_rows'];
		$total  = (int) $job['total_rows'];
		$rows   = self::read_rows( (string) $job['file_path'], $offset, self::BATCH_SIZE );

		if ( null === $rows ) {
			ImportJobs::finish( $job_id, 'failed' );

			return array(
				'status'  => 'error',
				'message' => 'Plik importu nie istnieje lub nie ma naglowka z kolumna serial.',
			);
		}

		$jobs_table     = Tables::full( Tables::IMPORT_JOBS );
		$registry_table = Tables::full( Tables::REGISTRY );
		$now            = gmdate( 'Y-m-d H:i:s' );
		$success        = 0;
		$errors         = array();

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne; transakcja batcha (kontrakt P2.1).
		$wpdb->query( 'START TRANSACTION' );

		foreach ( $rows as $index => $parsed ) {
			$row_number = $offset + $index + 2; // 1-indeks + linia naglowka.

			if ( ! $parsed['ok'] ) {
				$errors[] = array( $row_number, '', $parsed['error'] );
				continue;
			}

			$row        = $parsed['row'];
			$normalized = Str::normalize_serial( $row['serial'] );

			$existing = $wpdb->get_row(
				$wpdb->prepare(
					"SELECT id, archived FROM {$registry_table} WHERE serial_normalized = %s",
					$normalized
				),
				ARRAY_A
			);

			if ( is_array( $existing ) ) {
				$errors[] = array(
					$row_number,
					$row['serial'],
					'1' === (string) $existing['archived']
						? 'serial zajety przez produkt ARCHIWALNY — przywroc jawnie (WP-CLI), import go nie wskrzesza'
						: 'duplikat: serial juz istnieje w rejestrze',
				);
				continue;
			}

			$inserted = $wpdb->insert(
				$registry_table,
				array(
					'serial_display'    => $row['serial'],
					'serial_normalized' => $normalized,
					'model'             => $row['model'],
					'batch'             => $row['batch'],
					'category'          => $row['category'],
					'purchase_document' => $row['purchase_doc'],
					'purchase_date'     => $row['purchase_date'],
					'warranty_until'    => $row['warranty_until'],
					'source'            => 'csv_import',
					'import_job_id'     => $job_id,
					'created_at'        => $now,
					'updated_at'        => $now,
				)
			);

			if ( 1 === (int) $inserted ) {
				++$success;
			} else {
				$errors[] = array( $row_number, $row['serial'], 'blad zapisu do bazy' );
			}
		}

		$processed_now = count( $rows );

		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$jobs_table}
				SET processed_rows = processed_rows + %d,
					success_rows = success_rows + %d,
					error_rows = error_rows + %d,
					updated_at = %s
				WHERE id = %d AND job_token = %s",
				$processed_now,
				$success,
				count( $errors ),
				gmdate( 'Y-m-d H:i:s' ),
				$job_id,
				$token
			)
		);

		$wpdb->query( 'COMMIT' );
		// phpcs:enable

		self::append_errors( (string) $job['file_path'], $errors );

		$processed_total = $offset + $processed_now;

		if ( $processed_total >= $total || 0 === $processed_now ) {
			ImportJobs::finish( $job_id, 'done' );

			return array(
				'status'    => 'done',
				'processed' => $processed_total,
				'total'     => $total,
				'errors'    => (int) $job['error_rows'] + count( $errors ),
			);
		}

		return array(
			'status'    => 'processing',
			'processed' => $processed_total,
			'total'     => $total,
			'errors'    => (int) $job['error_rows'] + count( $errors ),
		);
	}

	/**
	 * Czyta porcje wierszy danych ze znormalizowanego pliku (UTF-8).
	 *
	 * @param string $file_path Sciezka pliku.
	 * @param int    $offset    Ile wierszy DANYCH pominac.
	 * @param int    $limit     Ile wierszy wziac.
	 * @return array<int, array{ok: bool, row?: array<string, string|null>, error?: string}>|null Null = plik/naglowek zly.
	 */
	private static function read_rows( string $file_path, int $offset, int $limit ): ?array {
		if ( ! is_file( $file_path ) ) {
			return null;
		}

		$handle = fopen( $file_path, 'r' ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fopen -- odczyt lokalnego pliku importu porcjami.

		if ( false === $handle ) {
			return null;
		}

		$header_line = fgets( $handle );

		if ( false === $header_line ) {
			fclose( $handle ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fclose -- para do fopen.

			return null;
		}

		$separator = CsvParser::detect_separator( $header_line );
		$map       = CsvParser::map_header( str_getcsv( trim( $header_line ), $separator ) );

		if ( null === $map ) {
			fclose( $handle ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fclose -- para do fopen.

			return null;
		}

		$skipped = 0;

		while ( $skipped < $offset && false !== fgets( $handle ) ) {
			++$skipped;
		}

		$rows      = array();
		$collected = 0;

		while ( $collected < $limit ) {
			$line = fgets( $handle );

			if ( false === $line ) {
				break;
			}

			if ( '' === trim( $line ) ) {
				continue;
			}

			$rows[] = CsvParser::parse_row( str_getcsv( trim( $line ), $separator ), $map );
			++$collected;
		}

		fclose( $handle ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fclose -- para do fopen.

		return $rows;
	}

	/**
	 * Dopisuje bledy do raportu per wiersz (plik obok importu).
	 *
	 * @param string                                 $file_path Sciezka pliku importu.
	 * @param array<int, array{int, string, string}> $errors Wiersze bledow.
	 * @return void
	 */
	private static function append_errors( string $file_path, array $errors ): void {
		if ( array() === $errors ) {
			return;
		}

		$report = $file_path . '.bledy.csv';
		$lines  = '';

		if ( ! file_exists( $report ) ) {
			$lines .= "wiersz;serial;blad\n";
		}

		foreach ( $errors as $error ) {
			$lines .= implode( ';', array( $error[0], $error[1], $error[2] ) ) . "\n";
		}

		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_file_put_contents -- raport techniczny w katalogu importow.
		file_put_contents( $report, $lines, FILE_APPEND | LOCK_EX );
	}
}
