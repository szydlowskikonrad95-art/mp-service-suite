<?php
/**
 * Endpointy importu CSV: upload (admin-post), batch i wznowienie (AJAX),
 * pobranie raportu bledow (przez PHP z capability — raport cytuje wiersze,
 * czyli potencjalnie dane osobowe; kontrakt K-C1).
 *
 * Kazdy endpoint: nonce + capability mp_system_admin W PARZE.
 *
 * @package MP\Registry
 */

namespace MP\Registry\Admin;

use MP\Registry\Importer;
use MP\Registry\ImportJobs;

/**
 * Obsluga zadan HTTP ekranu importu.
 */
final class ImportEndpoints {

	/**
	 * Dozwolone rozszerzenia pliku importu.
	 */
	private const ALLOWED_EXTENSIONS = array( 'csv', 'txt' );

	/**
	 * Rejestruje handlery admin-post i AJAX.
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_mp_import_upload', array( self::class, 'handle_upload' ) );
		add_action( 'admin_post_mp_import_report', array( self::class, 'handle_report' ) );
		add_action( 'wp_ajax_mp_import_batch', array( self::class, 'ajax_batch' ) );
		add_action( 'wp_ajax_mp_import_reclaim', array( self::class, 'ajax_reclaim' ) );
		// nopriv -> ten sam handler: capability sprawdzana i tak => anon dostaje JAWNE 403
		// (nie 400/200-empty z braku handlera). Security-sweep DoD sekcja 3.
		add_action( 'admin_post_nopriv_mp_import_upload', array( self::class, 'handle_upload' ) );
		add_action( 'admin_post_nopriv_mp_import_report', array( self::class, 'handle_report' ) );
		add_action( 'wp_ajax_nopriv_mp_import_batch', array( self::class, 'ajax_batch' ) );
		add_action( 'wp_ajax_nopriv_mp_import_reclaim', array( self::class, 'ajax_reclaim' ) );
	}

	/**
	 * Upload CSV -> walidacja -> job importu -> redirect na ekran (PRG).
	 *
	 * @return void
	 */
	public static function handle_upload(): void {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die( esc_html__( 'Brak uprawnień do importu produktów.', 'mp-warranty-registry' ), '', 403 );
		}

		// POST uciety przez post_max_size: superglobals puste, nonce nie dotarl.
		// Bez weryfikacji nonce wolno TYLKO pokazac komunikat (zero zmian stanu).
		$content_length = isset( $_SERVER['CONTENT_LENGTH'] ) ? absint( wp_unslash( $_SERVER['CONTENT_LENGTH'] ) ) : 0;

		if ( array() === $_POST && array() === $_FILES && $content_length > 0 ) {
			self::redirect_with_error(
				sprintf(
					/* translators: %s: limit uploadu serwera. */
					__( 'Plik jest większy niż limit uploadu serwera (%s) — żądanie zostało ucięte. Podziel CSV na mniejsze części.', 'mp-warranty-registry' ),
					size_format( wp_max_upload_size() )
				)
			);
		}

		check_admin_referer( 'mp_import_upload' );

		// phpcs:disable WordPress.Security.ValidatedSanitizedInput.MissingUnslash, WordPress.Security.ValidatedSanitizedInput.InputNotSanitized -- $_FILES: error/size to liczby, tmp_name to sciezka od PHP (weryfikowana is_uploaded_file), name przechodzi przez sanitize_file_name.
		$upload_error = isset( $_FILES['mp_import_file']['error'] ) ? (int) $_FILES['mp_import_file']['error'] : UPLOAD_ERR_NO_FILE;
		$tmp_name     = isset( $_FILES['mp_import_file']['tmp_name'] ) ? (string) $_FILES['mp_import_file']['tmp_name'] : '';
		$client_name  = isset( $_FILES['mp_import_file']['name'] ) ? sanitize_file_name( (string) $_FILES['mp_import_file']['name'] ) : '';
		// phpcs:enable

		if ( UPLOAD_ERR_OK !== $upload_error ) {
			self::redirect_with_error( self::upload_error_message( $upload_error ) );
		}

		if ( '' === $tmp_name || ! is_uploaded_file( $tmp_name ) ) {
			self::redirect_with_error( __( 'Plik nie dotarł na serwer — spróbuj ponownie.', 'mp-warranty-registry' ) );
		}

		$extension = strtolower( pathinfo( $client_name, PATHINFO_EXTENSION ) );

		if ( ! in_array( $extension, self::ALLOWED_EXTENSIONS, true ) ) {
			self::redirect_with_error( __( 'Dozwolone są tylko pliki .csv (ewentualnie .txt z danymi CSV).', 'mp-warranty-registry' ) );
		}

		$job = Importer::create_job_from_file( $tmp_name );

		if ( isset( $job['error'] ) ) {
			self::redirect_with_error( (string) $job['error'] );
		}

		set_transient(
			ImportScreen::TOKEN_TRANSIENT . get_current_user_id(),
			array(
				'job_id' => (int) $job['job_id'],
				'token'  => (string) $job['token'],
			),
			10 * MINUTE_IN_SECONDS
		);

		wp_safe_redirect( self::screen_url() );
		exit;
	}

	/**
	 * AJAX: przetworzenie jednego batcha (TEN SAM silnik co WP-CLI).
	 *
	 * @return void
	 */
	public static function ajax_batch(): void {
		check_ajax_referer( 'mp_import_ajax', 'nonce' );

		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_send_json_error( array( 'message' => __( 'Brak uprawnień.', 'mp-warranty-registry' ) ), 403 );
		}

		$job_id = isset( $_POST['job_id'] ) ? absint( $_POST['job_id'] ) : 0;
		$token  = isset( $_POST['token'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['token'] ) ) : '';

		if ( 0 === $job_id || '' === $token ) {
			wp_send_json_error( array( 'message' => __( 'Niepełne dane batcha.', 'mp-warranty-registry' ) ), 400 );
		}

		$result = Importer::process_batch( $job_id, $token );

		if ( 'error' === $result['status'] ) {
			wp_send_json_error( array( 'message' => (string) $result['message'] ), 409 );
		}

		wp_send_json_success( $result );
	}

	/**
	 * AJAX: wznowienie/przejecie joba = NOWY token (stare batche dostaja odmowe).
	 *
	 * @return void
	 */
	public static function ajax_reclaim(): void {
		check_ajax_referer( 'mp_import_ajax', 'nonce' );

		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_send_json_error( array( 'message' => __( 'Brak uprawnień.', 'mp-warranty-registry' ) ), 403 );
		}

		$job_id = isset( $_POST['job_id'] ) ? absint( $_POST['job_id'] ) : 0;

		if ( 0 === $job_id ) {
			wp_send_json_error( array( 'message' => __( 'Niepełne dane wznowienia.', 'mp-warranty-registry' ) ), 400 );
		}

		$job = ImportJobs::get( $job_id );

		if ( null === $job || ! is_file( (string) $job['file_path'] ) ) {
			wp_send_json_error( array( 'message' => __( 'Nie można wznowić: job nie istnieje albo jego plik roboczy został już usunięty.', 'mp-warranty-registry' ) ), 409 );
		}

		$token = ImportJobs::reclaim( $job_id );

		if ( null === $token ) {
			wp_send_json_error( array( 'message' => __( 'Nie można wznowić: import jest już zakończony.', 'mp-warranty-registry' ) ), 409 );
		}

		wp_send_json_success(
			array(
				'token'     => $token,
				'processed' => (int) $job['processed_rows'],
				'total'     => (int) $job['total_rows'],
				'errors'    => (int) $job['error_rows'],
			)
		);
	}

	/**
	 * Pobranie raportu bledow przez PHP (capability + nonce; katalog pilnowany).
	 *
	 * @return void
	 */
	public static function handle_report(): void {
		$job_id = isset( $_GET['job'] ) ? absint( $_GET['job'] ) : 0;

		check_admin_referer( 'mp_import_report_' . $job_id );

		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die( esc_html__( 'Brak uprawnień do raportu importu.', 'mp-warranty-registry' ), '', 403 );
		}

		$job = ImportJobs::get( $job_id );

		if ( null === $job ) {
			wp_die( esc_html__( 'Job importu nie istnieje.', 'mp-warranty-registry' ), '', 404 );
		}

		$report  = (string) $job['file_path'] . '.bledy.csv';
		$uploads = wp_upload_dir();

		if ( ! self::is_report_path_safe( $report, rtrim( (string) $uploads['basedir'], '/' ) . '/mp-imports' ) ) {
			wp_die( esc_html__( 'Raport błędów nie istnieje.', 'mp-warranty-registry' ), '', 404 );
		}

		nocache_headers();
		header( 'Content-Type: text/csv; charset=UTF-8' );
		header( 'X-Content-Type-Options: nosniff' );
		header( 'Content-Disposition: attachment; filename="import-' . $job_id . '-bledy.csv"' );
		header( 'Content-Length: ' . (string) (int) filesize( $report ) );

		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_readfile -- serwowanie raportu przez PHP z capability (kontrakt K-C1).
		readfile( $report );
		exit;
	}

	/**
	 * Czy sciezka raportu jest ISTNIEJACYM plikiem wewnatrz katalogu importow.
	 *
	 * Czysta logika (testowana jednostkowo): realpath rozbraja traversal,
	 * warunek prefiksu trzyma plik w mp-imports/.
	 *
	 * @param string $report_path Sciezka raportu z joba.
	 * @param string $imports_dir Katalog importow (bez slasha na koncu).
	 * @return bool
	 */
	public static function is_report_path_safe( string $report_path, string $imports_dir ): bool {
		$real_report = realpath( $report_path );
		$real_dir    = realpath( $imports_dir );

		if ( false === $real_report || false === $real_dir || ! is_file( $real_report ) ) {
			return false;
		}

		return str_starts_with( $real_report, $real_dir . DIRECTORY_SEPARATOR );
	}

	/**
	 * Komunikat PL dla kodu bledu uploadu PHP.
	 *
	 * @param int $error_code Kod UPLOAD_ERR_*.
	 * @return string
	 */
	public static function upload_error_message( int $error_code ): string {
		switch ( $error_code ) {
			case UPLOAD_ERR_INI_SIZE:
			case UPLOAD_ERR_FORM_SIZE:
				return __( 'Plik przekracza limit uploadu serwera — podziel CSV na mniejsze części.', 'mp-warranty-registry' );
			case UPLOAD_ERR_PARTIAL:
				return __( 'Plik wgrał się tylko częściowo — spróbuj ponownie.', 'mp-warranty-registry' );
			case UPLOAD_ERR_NO_FILE:
				return __( 'Nie wybrano pliku.', 'mp-warranty-registry' );
			default:
				return __( 'Serwer nie przyjął pliku (błąd zapisu tymczasowego) — spróbuj ponownie lub skontaktuj się z administratorem.', 'mp-warranty-registry' );
		}
	}

	/**
	 * Zapisuje komunikat bledu w transiencie i wraca na ekran importu.
	 *
	 * @param string $message Komunikat dla usera.
	 * @return never
	 */
	private static function redirect_with_error( string $message ): void {
		set_transient( ImportScreen::ERROR_TRANSIENT . get_current_user_id(), $message, 5 * MINUTE_IN_SECONDS );
		wp_safe_redirect( self::screen_url() );
		exit;
	}

	/**
	 * URL ekranu importu.
	 *
	 * @return string
	 */
	private static function screen_url(): string {
		return add_query_arg( 'page', ImportScreen::PAGE_SLUG, admin_url( 'admin.php' ) );
	}
}
