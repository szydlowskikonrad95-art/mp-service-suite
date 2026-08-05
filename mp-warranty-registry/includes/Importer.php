<?php
/**
 * Procesor batchy importu CSV ( + karta B "import BEZPIECZNY").
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
	 * Znak ucieczki dla str_getcsv: PUSTY = semantyka RFC-4180 (tak pisze Excel —
	 * cudzysłów podwajany `""`, backslash literalny). Podajemy JAWNIE z dwoch
	 * powodow: (1) PHP 8.4+ deprecuje pominiecie argumentu ($escape) — przy
	 * imporcie 10k wierszy to 10k wpisow „deprecated" w logu przy WP_DEBUG,
	 * (2) domyslna wartosc ma sie ZMIENIC w przyszlym PHP, wiec bez jawnego
	 * podania parsowanie zmienilo by sie samo. Model typu „Kabel 3\4" albo
	 * sciezka „D:\dane\" parsuja sie poprawnie tylko z pustym escape.
	 */
	private const CSV_ESCAPE = '';

	/**
	 * Limit rozmiaru pliku importu w bajtach (konfigurowalny; default 8 MB).
	 *
	 * D10: obnizone z 20 MB — create_job_from_file wczytuje CALY plik do pamieci
	 * (file_get_contents + to_utf8 + preg_split w tablice), co przy ~20 MB
	 * przekraczalo 128 MB memory_limit (OOM). 8 MB daje bezpieczny zapas na
	 * domyslnym hostingu; wieksze importy klient dzieli na czesci. Wlasciwe
	 * przetwarzanie (process_batch) i tak streamuje przez fgetcsv.
	 */
	public const MAX_FILE_BYTES = 8388608;

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
			return array( 'error' => 'Plik przekracza limit importu (8 MB) — podziel go na czesci.' );
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

		// ⚠️ NIE dzielimy pliku na linie i NIE filtrujemy pustych.
		// Wczesniej `preg_split` po znakach nowej linii szedl PRZED parsowaniem CSV, wiec
		// komorka z Enterem w cudzyslowach (norma RFC 4180 — np. opis wklejony z Excela
		// z zawinietym tekstem) byla rozcinana na dwa „wiersze": kolumny sie przesuwaly,
		// licznik postepu byl zawyzony, a dane trafialy w zle pola BEZ zadnego bledu.
		// Znalezione czytaniem liniowym 30.07. Teraz normalizujemy TYLKO konce linii,
		// a rekordy wydziela czytnik CSV, ktory rozumie cudzyslowy.
		$utf8 = str_replace( array( "\r\n", "\r" ), "\n", $utf8 );

		$pierwsza_linia = strtok( $utf8, "\n" );

		if ( false === $pierwsza_linia || '' === trim( (string) $pierwsza_linia ) ) {
			return array( 'error' => 'Plik nie zawiera danych (sam naglowek lub pusty).' );
		}

		$separator = CsvParser::detect_separator( (string) $pierwsza_linia );

		if ( null === CsvParser::map_header( str_getcsv( (string) $pierwsza_linia, $separator, '"', self::CSV_ESCAPE ) ) ) {
			return array( 'error' => 'Naglowek nie zawiera kolumny serial (albo aliasu).' );
		}

		$dir = self::imports_dir();

		if ( null === $dir ) {
			return array( 'error' => 'Nie mozna utworzyc katalogu importow.' );
		}

		$target = $dir . '/' . wp_generate_uuid4() . '.csv';

		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_file_put_contents -- znormalizowany plik roboczy importu.
		if ( false === file_put_contents( $target, rtrim( $utf8, "\n" ) . "\n" ) ) {
			return array( 'error' => 'Nie mozna zapisac pliku roboczego.' );
		}

		// Liczymy REKORDY CSV, nie linie pliku (patrz komentarz wyzej).
		$total = self::policz_rekordy( $target, $separator );

		if ( $total < 1 ) {
			return array( 'error' => 'Plik nie zawiera danych (sam naglowek lub pusty).' );
		}

		$job = ImportJobs::create( $target, $total );

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
	 * Sprząta osierocone pliki w mp-imports/ starsze niz prog (cron retencji D2).
	 *
	 * Lapie: (a) zrodlowe CSV jobow przerwanych w polowie (nigdy nie wywolaly
	 * finish), (b) stare raporty .bledy.csv (PII rejestrow) po oknie wgladu admina.
	 * Pomija guardy katalogu (.htaccess, index.php). RODO art. 5 ust. 1 lit. e.
	 *
	 * @param int $max_age_seconds Prog wieku pliku (domyslnie 24 h).
	 * @return int Liczba skasowanych plikow.
	 */
	public static function sweep_import_files( int $max_age_seconds = DAY_IN_SECONDS ): int {
		$dir = self::imports_dir();

		if ( null === $dir ) {
			return 0;
		}

		$threshold = time() - max( 0, $max_age_seconds );
		$deleted   = 0;

		foreach ( (array) glob( $dir . '/*' ) as $file ) {
			if ( ! is_string( $file ) || ! is_file( $file ) ) {
				continue;
			}

			$base = basename( $file );

			if ( '.htaccess' === $base || 'index.php' === $base ) {
				continue;
			}

			if ( (int) filemtime( $file ) < $threshold ) {
				wp_delete_file( $file );
				++$deleted;
			}
		}

		return $deleted;
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

		// Audyt #7: zamek per job — dwie rownolegle partie czytaly ten sam
		// offset i podwajaly liczniki (dane chronil unikalny indeks, ale
		// postep klamal i import konczyl sie przedwczesnie z pominietymi
		// wierszami). Przegrany wyscig dostaje 'processing' i ponowi probe.
		$lock_name = 'mp_import_job_' . $job_id;
		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- zamek procesu.
		$got = (int) $wpdb->get_var( $wpdb->prepare( 'SELECT GET_LOCK(%s, 0)', $lock_name ) );
		// phpcs:enable

		if ( 1 !== $got ) {
			return array(
				'status'    => 'processing',
				'processed' => (int) $job['processed_rows'],
				'total'     => (int) $job['total_rows'],
				'errors'    => (int) $job['error_rows'],
			);
		}

		try {
			// Swiezy odczyt POD zamkiem: rownolegle wywolanie moglo przesunac
			// offset, zanim zamek trafil do nas.
			$job = ImportJobs::get( $job_id );

			if ( null === $job || 'processing' !== (string) $job['status'] || (string) $job['job_token'] !== $token ) {
				return array(
					'status'  => 'error',
					'message' => 'Job zakonczony lub przejety w trakcie oczekiwania.',
				);
			}

			return self::process_batch_locked( $job_id, $job );
		} finally {
			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- zwolnienie zamka.
			$wpdb->get_var( $wpdb->prepare( 'SELECT RELEASE_LOCK(%s)', $lock_name ) );
			// phpcs:enable
		}
	}

	/**
	 * Wlasciwa robota partii — wolane WYLACZNIE pod zamkiem per job (audyt #7).
	 *
	 * @param int                  $job_id ID joba.
	 * @param array<string, mixed> $job    Swiezy wiersz joba (odczytany pod zamkiem).
	 * @return array<string, mixed>
	 */
	private static function process_batch_locked( int $job_id, array $job ): array {
		global $wpdb;

		$token = (string) $job['job_token'];

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

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne; transakcja batcha (kontrakt ).
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

		// ⚠️ Raport bledow zapisujemy PRZED zatwierdzeniem transakcji.
		// Wczesniej szedl PO `COMMIT`: awaria dokladnie w tym okienku (timeout, brak pamieci)
		// zatwierdzala postep partii, ale wpisy bledow tej partii przepadaly na zawsze —
		// offset byl juz przesuniety, wiec partia sie nie powtarzala, a paczka obiecuje,
		// ze raport zawiera WSZYSTKIE odrzucone wiersze. Znalezione czytaniem liniowym 30.07.
		// Odwrotna kolejnosc jest bezpieczna: gorszy przypadek to wpis w raporcie o wierszu
		// z partii, ktora sie wycofala — czyli wiersz i tak zostanie przetworzony ponownie.
		self::append_errors( (string) $job['file_path'], $errors );

		$wpdb->query( 'COMMIT' );
		// phpcs:enable

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
		$map       = CsvParser::map_header( str_getcsv( trim( $header_line ), $separator, '"', self::CSV_ESCAPE ) );

		if ( null === $map ) {
			fclose( $handle ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fclose -- para do fopen.

			return null;
		}

		// REKORDY, nie linie: `fgetcsv` sam scala komorke z Enterem w cudzyslowach
		// (patrz komentarz przy zapisie pliku roboczego). Wczesniej `fgets` rozcinal
		// taki rekord na dwa i przesuwal kolumny bez zadnego bledu.
		$skipped = 0;

		while ( $skipped < $offset ) {
			$pominiety = fgetcsv( $handle, 0, $separator, '"', self::CSV_ESCAPE );

			if ( false === $pominiety ) {
				break;
			}

			// Pusta linia miedzy rekordami: `fgetcsv` zwraca array(null) — nie liczymy jej.
			if ( array( null ) === $pominiety ) {
				continue;
			}

			++$skipped;
		}

		$rows      = array();
		$collected = 0;

		while ( $collected < $limit ) {
			$cells = fgetcsv( $handle, 0, $separator, '"', self::CSV_ESCAPE );

			if ( false === $cells ) {
				break;
			}

			if ( array( null ) === $cells ) {
				continue;
			}

			$rows[] = CsvParser::parse_row( $cells, $map );
			++$collected;
		}

		fclose( $handle ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fclose -- para do fopen.

		return $rows;
	}

	/**
	 * Liczy REKORDY danych w pliku CSV (bez naglowka), respektujac cudzyslowy.
	 *
	 * Liczenie linii bylo bledne dla komorek z Enterem w cudzyslowach — patrz komentarz
	 * przy zapisie pliku roboczego w `upload()`.
	 *
	 * @param string $sciezka   Plik roboczy importu.
	 * @param string $separator Separator kolumn.
	 * @return int Liczba rekordow danych (0 przy bledzie odczytu).
	 */
	private static function policz_rekordy( string $sciezka, string $separator ): int {
		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fopen -- czytanie wlasnego pliku roboczego strumieniowo.
		$handle = fopen( $sciezka, 'rb' );

		if ( false === $handle ) {
			return 0;
		}

		$rekordy = -1; // Naglowek nie liczy sie do danych.

		while ( true ) {
			$cells = fgetcsv( $handle, 0, $separator, '"', self::CSV_ESCAPE );

			if ( false === $cells ) {
				break;
			}

			if ( array( null ) === $cells ) {
				continue;
			}

			++$rekordy;
		}

		fclose( $handle ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fclose -- para do fopen.

		return max( 0, $rekordy );
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
			// Znacznik kolejnosci bajtow PRZED naglowkiem — bez niego arkusz
			// kalkulacyjny czyta polskie znaki jako krzaki. Eksport raportow
			// (bliźniaczy modul) mial go od poczatku, raport bledow nie:
			// wlasne komunikaty produktu sa bez ogonkow, ale wartosci z pliku
			// klienta (numer seryjny, model) moga je zawierac.
			$lines .= Common\Csv::BOM . "wiersz;serial;blad\n";
		}

		// ⚠️ CYTUJEMY jak CSV, nie skladamy `implode`.
		// Numer seryjny pochodzi z pliku klienta i moze legalnie zawierac srednik
		// (w oryginale byl w cudzyslowach). Skladany `implode(';', ...)` rozbijal wtedy
		// kolumny we WLASNYM raporcie bledow — admin widzial przesuniete kolumny w Excelu.
		// Znalezione czytaniem liniowym 30.07.
		foreach ( $errors as $error ) {
			$lines .= self::wiersz_csv( array( (string) $error[0], (string) $error[1], (string) $error[2] ) );
		}

		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_file_put_contents -- raport techniczny w katalogu importow.
		file_put_contents( $report, $lines, FILE_APPEND | LOCK_EX );
	}

	/**
	 * Skleja jeden wiersz CSV z poprawnym cytowaniem (separator `;`, zakonczenie `\n`).
	 *
	 * Uzywane w raporcie bledow: wartosci pochodza z pliku klienta i moga zawierac
	 * separator, cudzyslow albo znak nowej linii.
	 *
	 * @param string[] $pola Wartosci kolumn.
	 * @return string Wiersz zakonczony znakiem nowej linii.
	 */
	private static function wiersz_csv( array $pola ): string {
		// ⛔ Wartosci ida WPROST Z PLIKU KLIENTA — administrator pobiera ten raport
		// i otwiera w arkuszu, wiec komorka zaczynajaca sie od znaku rownosci
		// jest tam formula i wykona sie. Bliźniaczy modul mial te ochrone od
		// poczatku; tutaj jej nie bylo. Wspolna regula = jedno miejsce na obie.
		return Common\Csv::row( $pola );
	}
}
