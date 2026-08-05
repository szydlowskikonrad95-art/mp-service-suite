<?php
/**
 * Zalaczniki zgloszenia — UPLOAD TWARDO (spec T5 + rundy krytyki C).
 *
 * Zasady: MIME PO TRESCI (finfo, nie po nazwie/rozszerzeniu); limity 8 MB/plik,
 * max 5/zgloszenie, globalny CAP przestrzeni pending; katalog mp-attachments/
 * z deny-ALL (K1: chroni przed ODCZYTEM, nie tylko wykonaniem) + LOSOWE nazwy
 * BEZ rozszerzenia; strip EXIF/GPS (imagick->GD) dla JPEG/PNG/WebP; retention_until
 * z konfiguracji per RODZAJ; KAZDY odczyt przez endpoint PHP z ownership+capability
 * (bezposredni URL => 403); kasacja ZAWSZE = wiersz + PLIK z dysku.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Bezpieczna obsluga zalacznikow spraw.
 */
final class Attachments {

	/**
	 * Limit rozmiaru pojedynczego pliku w bajtach (8 MB — konfigurowalny).
	 */
	public const MAX_BYTES = 8388608;

	/**
	 * Maksymalna liczba zalacznikow na zgloszenie.
	 */
	public const MAX_PER_CASE = 5;

	/**
	 * Globalny CAP przestrzeni zalacznikow spraw NIEPOTWIERDZONYCH (2 GB).
	 */
	public const PENDING_CAP_BYTES = 2147483648;

	/**
	 * Dozwolone typy MIME (po TRESCI) => rozszerzenie do Content-Disposition.
	 */
	public const ALLOWED = array(
		'image/jpeg'      => 'jpg',
		'image/png'       => 'png',
		'image/webp'      => 'webp',
		'application/pdf' => 'pdf',
	);

	/**
	 * Retencja per rodzaj w MIESIACACH (klepniete defaulty; DATABASE.md).
	 */
	public const RETENTION_MONTHS = array(
		'reklamacja' => 24,
		'naprawa'    => 12,
		'zwrot'      => 12,
		'zapytanie'  => 3,
	);

	/**
	 * Przyjmuje pliki zgloszenia dla sprawy (walidacja + zapis + wiersze).
	 *
	 * @param int                              $case_id ID sprawy.
	 * @param string                           $kind    Rodzaj (do retencji).
	 * @param array<int, array<string, mixed>> $files   Znormalizowane pliki (name/type/tmp_name/error/size).
	 * @return array{stored: int, errors: array<int, string>}
	 */
	public static function store_for_case( int $case_id, string $kind, array $files ): array {
		$stored = 0;
		$errors = array();

		$existing = self::count_for_case( $case_id );

		foreach ( $files as $index => $file ) {
			if ( $existing + $stored >= self::MAX_PER_CASE ) {
				$errors[] = sprintf(
					/* translators: %d: limit zalacznikow. */
					__( 'Pominięto część plików — limit to %d załączników na zgłoszenie.', 'mp-service-intake' ),
					self::MAX_PER_CASE
				);
				break;
			}

			$reason = self::validate_upload( $file );

			if ( null !== $reason ) {
				$errors[] = $reason;
				continue;
			}

			if ( self::pending_usage_bytes() + (int) $file['size'] > self::PENDING_CAP_BYTES ) {
				$errors[] = __( 'Serwer chwilowo nie przyjmuje nowych załączników (limit przestrzeni) — spróbuj później.', 'mp-service-intake' );
				break;
			}

			if ( self::save_one( $case_id, $kind, $file ) ) {
				++$stored;
			} else {
				$errors[] = __( 'Nie udało się zapisać jednego z plików.', 'mp-service-intake' );
			}

			unset( $index );
		}

		return array(
			'stored' => $stored,
			'errors' => $errors,
		);
	}

	/**
	 * Waliduje pojedynczy plik: kod bledu uploadu, rozmiar, MIME PO TRESCI.
	 *
	 * @param array<string, mixed> $file Wpis z $_FILES (znormalizowany).
	 * @return string|null Komunikat bledu albo null gdy OK.
	 */
	public static function validate_upload( array $file ): ?string {
		$error = (int) ( $file['error'] ?? UPLOAD_ERR_NO_FILE );

		if ( UPLOAD_ERR_NO_FILE === $error ) {
			return null; // Puste pole pliku = brak zalacznika, nie blad.
		}

		// Za duzy plik wg limitu PHP/formularza: rada „sprobuj ponownie" byla mylaca
		// (druga proba tez sie nie uda). Klient dostaje LICZBE, ktora obowiazuje na
		// TYM serwerze — nie nasza stala, bo hosting bywa ciasniejszy.
		if ( UPLOAD_ERR_INI_SIZE === $error || UPLOAD_ERR_FORM_SIZE === $error ) {
			return sprintf(
				/* translators: %s: obowiazujacy limit rozmiaru pliku. */
				__( 'Plik jest za duży — ten serwer przyjmuje pliki do %s. Wyślij mniejszy (np. pomniejsz zdjęcie).', 'mp-service-intake' ),
				size_format( self::effective_max_bytes() )
			);
		}

		if ( UPLOAD_ERR_OK !== $error ) {
			return __( 'Plik nie wgrał się poprawnie — spróbuj ponownie.', 'mp-service-intake' );
		}

		$tmp = (string) ( $file['tmp_name'] ?? '' );

		if ( '' === $tmp || ! is_uploaded_file( $tmp ) ) {
			return __( 'Plik nie dotarł na serwer.', 'mp-service-intake' );
		}

		if ( (int) ( $file['size'] ?? 0 ) > self::effective_max_bytes() ) {
			return sprintf(
				/* translators: %s: obowiazujacy limit rozmiaru pliku. */
				__( 'Plik przekracza limit %s — wyślij mniejszy.', 'mp-service-intake' ),
				size_format( self::effective_max_bytes() )
			);
		}

		$mime = self::detect_mime( $tmp );

		if ( ! isset( self::ALLOWED[ $mime ] ) ) {
			return __( 'Niedozwolony typ pliku — przyjmujemy tylko JPG, PNG, WebP i PDF.', 'mp-service-intake' );
		}

		return null;
	}

	/**
	 * Limit rozmiaru pliku OBOWIAZUJACY NA TYM SERWERZE.
	 *
	 * Nasza stala `MAX_BYTES` (8 MB) to gora; hosting bywa ciasniejszy
	 * (`upload_max_filesize` / `post_max_size` — `wp_max_upload_size()` bierze
	 * mniejsza z nich). Klientowi podajemy liczbe, ktora naprawde obowiazuje,
	 * inaczej komunikat obiecuje wiecej, niz serwer przyjmie. Diagnostyka
	 * w „Stanie witryny" osobno alarmuje admina o tym rozjezdzie.
	 *
	 * @return int Limit w bajtach.
	 */
	public static function effective_max_bytes(): int {
		$serwer = function_exists( 'wp_max_upload_size' ) ? (int) wp_max_upload_size() : 0;

		return ( $serwer > 0 && $serwer < self::MAX_BYTES ) ? $serwer : self::MAX_BYTES;
	}

	/**
	 * Wykrywa MIME PO TRESCI (finfo). Bez ext-fileinfo => pusty (odmowa).
	 *
	 * @param string $path Sciezka pliku.
	 * @return string
	 */
	public static function detect_mime( string $path ): string {
		if ( ! function_exists( 'finfo_open' ) ) {
			return '';
		}

		$finfo = finfo_open( FILEINFO_MIME_TYPE );

		if ( false === $finfo ) {
			return '';
		}

		$mime = (string) finfo_file( $finfo, $path );

		return $mime;
	}

	/**
	 * Wylicza retention_until z rodzaju sprawy (czysta funkcja).
	 *
	 * @param string $kind Rodzaj sprawy.
	 * @param string $now  Teraz 'Y-m-d H:i:s' (UTC).
	 * @return string Data 'Y-m-d H:i:s' w UTC.
	 */
	public static function retention_until_for_kind( string $kind, string $now ): string {
		$months = self::RETENTION_MONTHS[ $kind ] ?? 12;
		$date   = \DateTime::createFromFormat( 'Y-m-d H:i:s', $now, new \DateTimeZone( 'UTC' ) );

		if ( false === $date ) {
			$date = new \DateTime( 'now', new \DateTimeZone( 'UTC' ) );
		}

		$date->modify( '+' . $months . ' months' );

		return $date->format( 'Y-m-d H:i:s' );
	}

	/**
	 * Zapisuje jeden plik: strip EXIF, losowa nazwa BEZ rozszerzenia, wiersz.
	 *
	 * @param int                  $case_id ID sprawy.
	 * @param string               $kind    Rodzaj (retencja).
	 * @param array<string, mixed> $file    Wpis z $_FILES.
	 * @return bool
	 */
	private static function save_one( int $case_id, string $kind, array $file ): bool {
		global $wpdb;

		$dir = self::dir();

		if ( null === $dir ) {
			return false;
		}

		$tmp  = (string) $file['tmp_name'];
		$mime = self::detect_mime( $tmp );
		$name = wp_generate_uuid4(); // Losowa nazwa BEZ rozszerzenia (Content-Type z finfo przy serwowaniu).
		$dest = $dir . '/' . $name;

		// is_uploaded_file zweryfikowane w validate_upload PRZED tym wywolaniem;
		// copy zamiast move_uploaded_file (to drugie zakazane przez Plugin Check).
		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_copy -- bezpieczny zapis zalacznika (tmp z is_uploaded_file); tmp sprzatany przez PHP na koncu requestu.
		if ( ! copy( $tmp, $dest ) ) {
			return false;
		}

		self::strip_metadata( $dest, $mime );

		$now = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna.
		$inserted = $wpdb->insert(
			Tables::full( Tables::ATTACHMENTS ),
			array(
				'case_id'         => $case_id,
				'path'            => $name,
				'mime'            => $mime,
				'size_bytes'      => (int) filesize( $dest ),
				'original_name'   => sanitize_file_name( (string) ( $file['name'] ?? '' ) ),
				'retention_until' => self::retention_until_for_kind( $kind, $now ),
				'created_at'      => $now,
			)
		);
		// phpcs:enable

		if ( 1 !== (int) $inserted ) {
			// Audyt awarii 27.07: plik lezal juz na dysku, a wiersz nie powstal
			// (zerwane polaczenie do bazy, pelny dysk, za duzy pakiet). Bez tego
			// kasowania zostawal plik-widmo: retencja go nie ruszy (chodzi po
			// wierszach), wiec zdjecie klienta lezaloby w uploads bezterminowo.
			wp_delete_file( $dest );

			return false;
		}

		return true;
	}

	/**
	 * Usuwa metadane (EXIF/GPS) z obrazu: imagick stripImage, fallback reenkod GD.
	 * PDF swiadomie NIE (nota w SECURITY.md).
	 *
	 * @param string $path Sciezka pliku.
	 * @param string $mime Typ MIME.
	 * @return void
	 */
	private static function strip_metadata( string $path, string $mime ): void {
		if ( ! in_array( $mime, array( 'image/jpeg', 'image/png', 'image/webp' ), true ) ) {
			return;
		}

		if ( class_exists( '\Imagick' ) ) {
			try {
				$img = new \Imagick( $path );
				$img->stripImage();
				$img->writeImage( $path );
				$img->clear();

				return;
			} catch ( \Exception $e ) {
				unset( $e ); // Spadamy na GD.
			}
		}

		self::strip_with_gd( $path, $mime );
	}

	/**
	 * Reenkod przez GD (naturalnie gubi EXIF) — fallback bez imagick.
	 *
	 * @param string $path Sciezka.
	 * @param string $mime Typ MIME.
	 * @return void
	 */
	private static function strip_with_gd( string $path, string $mime ): void {
		if ( ! function_exists( 'imagecreatefromstring' ) ) {
			return;
		}

		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_get_contents_file_get_contents -- lokalny plik zalacznika.
		$data = file_get_contents( $path );

		if ( false === $data ) {
			return;
		}

		// Uszkodzone albo uciete zdjecie (przerwany transfer, dziwny aparat)
		// przechodzi kontrole typu po naglowku, ale GD go nie odczyta — i zanim
		// zwroci false, wypisuje wlasne ostrzezenia do logu. Blad obslugujemy
		// linijke nizej, wiec sam diagnostyk jest zbedny: bez wyciszenia klient
		// dostaje w debug.log trzy PHP Warning z nazwa naszego pliku, a paczka
		// obiecuje „zero PHP notice z naszego kodu".
		// phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged -- wynik sprawdzany jawnie ponizej; wyciszamy tylko halas GD.
		$img = @imagecreatefromstring( $data );

		if ( false === $img ) {
			return;
		}

		if ( 'image/png' === $mime ) {
			imagealphablending( $img, false );
			imagesavealpha( $img, true );
			imagepng( $img, $path );
		} elseif ( 'image/webp' === $mime ) {
			// D8: bez imagewebp NIE re-enkodujemy do JPEG — mime w bazie zostaje
			// image/webp, wiec serve() daloby Content-Type: image/webp + nosniff na
			// bajtach JPEG (nie otworzy). Zostawiamy oryginalny plik (spojny; EXIF
			// nietkniety, ale to rzadki webp — Imagick strip-uje go wczesniej).
			if ( function_exists( 'imagewebp' ) ) {
				imagewebp( $img, $path );
			}
		} else {
			imagejpeg( $img, $path, 90 );
		}

		imagedestroy( $img );
	}

	/**
	 * Czy serwer ma biblioteke obrazow do stripowania EXIF/GPS (Imagick albo GD).
	 *
	 * @return bool
	 */
	public static function has_image_library(): bool {
		return class_exists( '\Imagick' ) || function_exists( 'imagecreatefromstring' );
	}

	/**
	 * D9: admin notice gdy brak biblioteki obrazow — EXIF/GPS NIE bedzie usuwany
	 * (deklaracja prywatnosci nie moze cicho zawiesc). Tylko dla admina.
	 *
	 * @return void
	 */
	public static function admin_notice_no_image_library(): void {
		if ( self::has_image_library() || ! current_user_can( 'manage_options' ) ) {
			return;
		}

		printf(
			'<div class="notice notice-warning"><p>%s</p></div>',
			esc_html__(
				'MP Service Intake: serwer nie ma biblioteki obrazów (Imagick ani GD) — metadane EXIF/GPS z załączanych zdjęć NIE będą usuwane. Zainstaluj rozszerzenie PHP imagick lub gd.',
				'mp-service-intake'
			)
		);
	}

	/**
	 * Serwuje zalacznik przez PHP (endpoint) — ownership/capability + finfo + nosniff.
	 *
	 * IDOR-safe: dostep ma personel (mp_agent+) ALBO wlasciciel sprawy (klient
	 * przez konto). Sprawa niepotwierdzona: TYLKO personel. Bezposredni URL do
	 * pliku odbija deny-ALL katalogu (403).
	 *
	 * @param int $attachment_id ID zalacznika.
	 * @return void
	 */
	public static function serve( int $attachment_id ): void {
		global $wpdb;

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne, zapytanie przygotowane.
		$att_table  = Tables::full( Tables::ATTACHMENTS );
		$case_table = Tables::full( Tables::CASES );
		$row        = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT a.path, a.mime, a.original_name, a.deleted_at, a.case_id, s.customer_id, s.identity_status
				FROM {$att_table} a INNER JOIN {$case_table} s ON s.id = a.case_id
				WHERE a.id = %d",
				$attachment_id
			),
			ARRAY_A
		);
		// phpcs:enable

		if ( ! is_array( $row ) || null !== $row['deleted_at'] ) {
			self::deny( 404 );
		}

		if ( ! self::can_access( (int) $row['customer_id'], (string) $row['identity_status'], null === $row['customer_id'], (int) $row['case_id'] ) ) {
			self::deny( 403 );
		}

		$dir  = self::dir();
		$file = null === $dir ? '' : $dir . '/' . (string) $row['path'];

		if ( '' === $file || ! is_file( $file ) ) {
			self::deny( 404 );
		}

		$mime = (string) $row['mime'];
		$ext  = self::ALLOWED[ $mime ] ?? 'bin';

		nocache_headers();
		header( 'Content-Type: ' . $mime );
		header( 'X-Content-Type-Options: nosniff' );
		header( 'Content-Disposition: attachment; filename="zalacznik-' . $attachment_id . '.' . $ext . '"' );
		header( 'Content-Length: ' . (string) (int) filesize( $file ) );

		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_readfile -- serwowanie zalacznika przez PHP z bramka dostepu (K1).
		readfile( $file );
		exit;
	}

	/**
	 * Czy biezacy uzytkownik ma dostep do zalacznika sprawy (bramka IDOR).
	 *
	 * Personel: prawo do zalacznika = prawo do SPRAWY, tym samym kodem, ktorym
	 * bramkuja lista i karta (CaseRepo::can_current_user_see — koordynator/admin
	 * widza wszystko, pracownik TYLKO sprawy przydzielone jemu). Klient — TYLKO
	 * gdy sprawa verified i konto WP nalezy do wlasciciela sprawy. Sprawa
	 * niepotwierdzona / bez klienta => tylko personel z prawem do sprawy.
	 *
	 * M2 (2026-08-05): wczesniej KAZDY mp_agent przechodzil ta bramka do
	 * zalacznika DOWOLNEJ sprawy, choc karte cudzej sprawy odbijal
	 * NOT_CASE_OWNER (CaseRepo.php:751) — zalacznik byl boczna furtka do
	 * cudzych danych (zdjecia, skany dokumentow zakupu). Drugiego, wlasnego
	 * sposobu sprawdzania nie budujemy — lekcja z audytu 2.24.
	 *
	 * @param int    $customer_id     ID klienta sprawy (0 gdy brak).
	 * @param string $identity_status pending|verified.
	 * @param bool   $no_customer     Czy sprawa nie ma jeszcze klienta.
	 * @param int    $case_id         ID sprawy zalacznika.
	 * @return bool
	 */
	public static function can_access( int $customer_id, string $identity_status, bool $no_customer, int $case_id ): bool {
		if ( current_user_can( 'mp_agent' ) || current_user_can( 'mp_system_admin' ) || current_user_can( 'mp_coordinator' ) ) {
			return CaseRepo::can_current_user_see( $case_id );
		}

		if ( 'verified' !== $identity_status || $no_customer || 0 === $customer_id ) {
			return false;
		}

		$user_id = get_current_user_id();

		if ( 0 === $user_id ) {
			return false;
		}

		return Customers::wp_user_owns_customer( $user_id, $customer_id );
	}

	/**
	 * Bramka dostepu po ID sprawy (testowalna; napedza tez serve()).
	 *
	 * @param int $case_id ID sprawy.
	 * @return bool
	 */
	public static function can_access_case( int $case_id ): bool {
		global $wpdb;

		$case_table = Tables::full( Tables::CASES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT customer_id, identity_status FROM {$case_table} WHERE id = %d", $case_id ),
			ARRAY_A
		);
		// phpcs:enable

		if ( ! is_array( $row ) ) {
			return false;
		}

		return self::can_access(
			null === $row['customer_id'] ? 0 : (int) $row['customer_id'],
			(string) $row['identity_status'],
			null === $row['customer_id'],
			$case_id
		);
	}

	/**
	 * Kasuje zalacznik: wiersz (soft: deleted_at) + PLIK z dysku (twardo).
	 *
	 * @param int $attachment_id ID zalacznika.
	 * @return void
	 */
	public static function delete( int $attachment_id ): void {
		global $wpdb;

		$att_table = Tables::full( Tables::ATTACHMENTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$path = (string) $wpdb->get_var(
			$wpdb->prepare( "SELECT path FROM {$att_table} WHERE id = %d AND deleted_at IS NULL", $attachment_id )
		);
		// phpcs:enable

		if ( '' === $path ) {
			return;
		}

		$dir = self::dir();

		if ( null !== $dir && is_file( $dir . '/' . $path ) ) {
			wp_delete_file( $dir . '/' . $path );
		}

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		// ⛔ RODO: razem z plikiem znika NAZWA NADANA PRZEZ KLIENTA. Wiersz zostaje —
		// jest sladem operacji (kiedy, jaka sprawa, jaki typ, jaki rozmiar) i tego nie
		// odbieramy — ale `original_name` to tresc pisana przez czlowieka: skany dowodow
		// zakupu ludzie nazywaja wlasnym imieniem i nazwiskiem. Po skasowaniu pliku ta
		// nazwa nie sluzy juz do niczego, a przezywala zadanie usuniecia danych.
		// Redagujemy TU, w jednym gardle: te metode wola i sciezka RODO
		// (delete_for_cases), i cron retencji, i kasowanie recznie.
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$att_table} SET deleted_at = %s, original_name = %s WHERE id = %d",
				gmdate( 'Y-m-d H:i:s' ),
				Messages::REDACTED,
				$attachment_id
			)
		);
		// phpcs:enable
	}

	/**
	 * Kasuje wszystkie zywe zalaczniki podanych spraw (wiersz + PLIK) — RODO.
	 *
	 * @param array<int> $case_ids Sprawy.
	 * @return int Liczba skasowanych.
	 */
	public static function delete_for_cases( array $case_ids ): int {
		global $wpdb;

		$ids = array_values( array_filter( array_map( 'absint', $case_ids ) ) );

		if ( array() === $ids ) {
			return 0;
		}

		$att_table    = Tables::full( Tables::ATTACHMENTS );
		$placeholders = implode( ',', array_fill( 0, count( $ids ), '%d' ) );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared, WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare -- tabela wlasna; lista %d w IN() z count().
		$att_ids = $wpdb->get_col(
			$wpdb->prepare(
				"SELECT id FROM {$att_table} WHERE deleted_at IS NULL AND case_id IN ({$placeholders})",
				$ids
			)
		);
		// phpcs:enable

		foreach ( $att_ids as $att_id ) {
			self::delete( (int) $att_id );
		}

		return count( (array) $att_ids );
	}

	/**
	 * Metadane zalacznikow sprawy (eksport RODO — bez binarki, link przez konto).
	 *
	 * @param int $case_id ID sprawy.
	 * @return array<int, array<string, mixed>>
	 */
	public static function metadata_for_case( int $case_id ): array {
		global $wpdb;

		$att_table = Tables::full( Tables::ATTACHMENTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT id, mime, size_bytes, original_name, created_at FROM {$att_table} WHERE case_id = %d AND deleted_at IS NULL",
				$case_id
			),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * Cron retencji: kasuje zalaczniki po retention_until (wiersz + plik).
	 *
	 * ⛔ SPRAWA ZYWA NIE TRACI DOWODOW (cz.1 pkt 2, waga duza). Zapytanie NIE MIALO
	 * zadnego warunku o stanie sprawy: liczyla sie wylacznie data. Poniewaz
	 * `retention_until` wyliczane jest RAZ, przy wgraniu pliku (`store_for_case`),
	 * i nigdy nie bylo przeliczane, sprawa prowadzona dluzej niz okno retencji
	 * tracila zalaczniki W TRAKCIE — po cichu, bez sladu i bez kopii. Przy rodzaju
	 * „zapytanie" okno wynosi TRZY MIESIACE, wiec wystarczylo, ze sprawa czekala
	 * kwartal. To samo dotyczylo sprawy WZNOWIONEJ: produkt pozwala otworzyc
	 * zamknieta sprawe (`CaseRepo::change_status`, REOPEN), a terminu kasowania
	 * dowodow nigdy przy tym nie przeliczal.
	 *
	 * ⛔ CHRONIMY DOKLADNIE JEDNO: sprawe ZYWA, czyli POTWIERDZONA przez klienta
	 * i NIE w statusie koncowym. Wszystko inne sprzatamy po terminie:
	 *  · sprawa w statusie TERMINALNYM — zamknieta naprawde, sprzatamy;
	 *  · sprawa NIGDY NIEPOTWIERDZONA (`identity_status <> 'verified'`) — klient
	 *    nie dokonczyl zgloszenia, to nie jest praca w toku;
	 *  · wiersza sprawy JUZ NIE MA — zalacznik osierocony.
	 *
	 * ⚠️ Dwie ostatnie galezie NIE sa ozdobnikiem i nie wolno ich sciac „dla
	 * prostoty":
	 *  · sciezka usuwania danych osobowych (RODO) jawnie liczy na to, ze
	 *    osierocone pliki posprzata retencja — zwykle zlaczenie z tabela spraw
	 *    wycieloby ta droge PO CICHU, dlatego LEFT JOIN i jawne `s.id IS NULL`;
	 *  · porzucone zgloszenia niepotwierdzone maja WLASNY limit przestrzeni
	 *    (`pending_usage_bytes`) — gdyby ich zalaczniki przestaly znikac, limit
	 *    zatkalby sie plikami po ludziach, ktorzy nigdy nie potwierdzili zgloszenia.
	 *
	 * ⚠️ Lista statusow terminalnych jest DYNAMICZNA (`Statuses::terminal_slugs()`),
	 * bo administrator moze dodac wlasny status i sam oznaczyc go jako konczacy.
	 *
	 * @return int Liczba skasowanych.
	 */
	public static function run_retention_sweep(): int {
		global $wpdb;

		$att_table  = Tables::full( Tables::ATTACHMENTS );
		$case_table = Tables::full( Tables::CASES );
		$now        = gmdate( 'Y-m-d H:i:s' );

		$terminalne = Statuses::terminal_slugs();

		// Gdy nie ma ANI JEDNEGO statusu terminalnego (ktos odebral rdzeniowi
		// terminalnosc filtrem), zostaja same sieroty — pusta lista w SQL-owym
		// IN() jest bledem skladni, a nie "zadnym dopasowaniem".
		// „Sprawa NIE jest zywa" — wspolna czesc dla obu wariantow nizej.
		$nie_zyje = "s.id IS NULL OR s.identity_status <> 'verified' OR s.status IS NULL";

		if ( array() === $terminalne ) {
			$warunek_stanu = "( {$nie_zyje} )";
			$parametry     = array( $now );
		} else {
			$miejsca       = implode( ',', array_fill( 0, count( $terminalne ), '%s' ) );
			$warunek_stanu = "( {$nie_zyje} OR s.status IN ({$miejsca}) )";
			$parametry     = array_merge( array( $now ), $terminalne );
		}

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne, zapytanie przygotowane; lista miejsc na statusy zbudowana z LICZBY elementow, nie z ich tresci.
		$ids = $wpdb->get_col(
			$wpdb->prepare(
				"SELECT a.id FROM {$att_table} a
				LEFT JOIN {$case_table} s ON s.id = a.case_id
				WHERE a.deleted_at IS NULL
					AND a.retention_until IS NOT NULL
					AND a.retention_until < %s
					AND {$warunek_stanu}
				LIMIT 500",
				$parametry
			)
		);
		// phpcs:enable

		foreach ( $ids as $id ) {
			self::delete( (int) $id );
		}

		return count( (array) $ids );
	}

	/**
	 * Przelicza `retention_until` zalacznikow sprawy OD TERAZ (cz.1 pkt 2).
	 *
	 * Wolane, gdy sprawa wchodzi w status terminalny — czyli w chwili, od ktorej
	 * okno retencji ma naprawde biec. Wczesniej termin byl ustawiany raz, przy
	 * wgraniu pliku, wiec dla sprawy prowadzonej dlugo potrafil minac, ZANIM
	 * ktokolwiek sprawe zamknal.
	 *
	 * ⚠️ Sprawa WZNOWIONA nie potrzebuje tu nic osobnego: przestaje byc terminalna,
	 * wiec sprzatanie ja pomija (patrz `run_retention_sweep`), a przy kolejnym
	 * zamknieciu termin policzy sie na nowo, od tamtej chwili.
	 *
	 * @param int $case_id ID sprawy.
	 * @return int Liczba zalacznikow, ktorym przesunieto termin.
	 */
	public static function refresh_retention_for_case( int $case_id ): int {
		global $wpdb;

		if ( $case_id <= 0 ) {
			return 0;
		}

		$att_table  = Tables::full( Tables::ATTACHMENTS );
		$case_table = Tables::full( Tables::CASES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne, zapytanie przygotowane.
		$kind = (string) $wpdb->get_var(
			$wpdb->prepare( "SELECT kind FROM {$case_table} WHERE id = %d", $case_id )
		);

		if ( '' === $kind ) {
			return 0;
		}

		$until = self::retention_until_for_kind( $kind, gmdate( 'Y-m-d H:i:s' ) );

		$zmienione = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$att_table} SET retention_until = %s WHERE case_id = %d AND deleted_at IS NULL",
				$until,
				$case_id
			)
		);
		// phpcs:enable

		return (int) $zmienione;
	}

	/**
	 * Liczba zywych zalacznikow sprawy.
	 *
	 * @param int $case_id ID sprawy.
	 * @return int
	 */
	public static function count_for_case( int $case_id ): int {
		global $wpdb;

		$att_table = Tables::full( Tables::ATTACHMENTS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		return (int) $wpdb->get_var(
			$wpdb->prepare( "SELECT COUNT(*) FROM {$att_table} WHERE case_id = %d AND deleted_at IS NULL", $case_id )
		);
		// phpcs:enable
	}

	/**
	 * Zajetosc przestrzeni zalacznikow spraw NIEPOTWIERDZONYCH (CAP pending).
	 *
	 * @return int Bajty.
	 */
	private static function pending_usage_bytes(): int {
		global $wpdb;

		$att_table  = Tables::full( Tables::ATTACHMENTS );
		$case_table = Tables::full( Tables::CASES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne.
		return (int) $wpdb->get_var(
			"SELECT COALESCE(SUM(a.size_bytes),0) FROM {$att_table} a
			INNER JOIN {$case_table} s ON s.id = a.case_id
			WHERE a.deleted_at IS NULL AND s.identity_status = 'pending'"
		);
		// phpcs:enable
	}

	/**
	 * Katalog zalacznikow uploads/mp-attachments z deny-ALL + index.php.
	 *
	 * ⚠️ `.htaccess` deny dziala TYLKO na Apache/LiteSpeed — **nginx go IGNORUJE**.
	 * Realna, przenosna brama (kazdy serwer) = odczyt WYLACZNIE przez endpoint
	 * `mp_intake_attachment` (nonce + ownership). Nota + snippet nginx: SECURITY.md.
	 *
	 * @return string|null
	 */
	public static function dir(): ?string {
		$uploads = wp_upload_dir();
		$dir     = rtrim( (string) $uploads['basedir'], '/' ) . '/mp-attachments';

		if ( ! wp_mkdir_p( $dir ) ) {
			return null;
		}

		$guards = array(
			$dir . '/.htaccess' => "Require all denied\nDeny from all\n",
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
	 * Odmowa dostepu (status + koniec).
	 *
	 * @param int $status Kod HTTP.
	 * @return never
	 */
	private static function deny( int $status ): void {
		status_header( $status );
		nocache_headers();
		header( 'X-Content-Type-Options: nosniff' );
		exit;
	}
}
