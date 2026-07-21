<?php
/**
 * Testy czystych helperow endpointow importu (sciezka raportu + komunikaty).
 *
 * @package MP\Testy
 */

declare(strict_types=1);

use MP\Registry\Admin\ImportEndpoints;
use PHPUnit\Framework\TestCase;

/**
 * Raport bledow wolno serwowac WYLACZNIE z katalogu importow (K-C1).
 */
final class ImportEndpointsTest extends TestCase {

	/**
	 * Tymczasowy "katalog uploads" testu.
	 *
	 * @var string
	 */
	private string $dir;

	/**
	 * Buduje katalog importow z raportem i wabikiem poza katalogiem.
	 */
	protected function setUp(): void {
		$this->dir = sys_get_temp_dir() . '/mp-import-test-' . bin2hex( random_bytes( 4 ) );
		mkdir( $this->dir . '/mp-imports', 0700, true );
		file_put_contents( $this->dir . '/mp-imports/job.csv.bledy.csv', "wiersz;serial;blad\n" );
		file_put_contents( $this->dir . '/sekret-poza-importami.txt', "nie serwowac\n" );
	}

	/**
	 * Sprzata pliki testu.
	 */
	protected function tearDown(): void {
		array_map( 'unlink', (array) glob( $this->dir . '/mp-imports/*' ) );
		array_map( 'unlink', (array) glob( $this->dir . '/*.txt' ) );
		rmdir( $this->dir . '/mp-imports' );
		rmdir( $this->dir );
	}

	/**
	 * Raport w katalogu importow przechodzi.
	 */
	public function test_report_inside_imports_dir_is_safe(): void {
		self::assertTrue(
			ImportEndpoints::is_report_path_safe(
				$this->dir . '/mp-imports/job.csv.bledy.csv',
				$this->dir . '/mp-imports'
			)
		);
	}

	/**
	 * Traversal ../ nie wyprowadzi odczytu poza katalog importow.
	 */
	public function test_traversal_outside_imports_dir_is_rejected(): void {
		self::assertFalse(
			ImportEndpoints::is_report_path_safe(
				$this->dir . '/mp-imports/../sekret-poza-importami.txt',
				$this->dir . '/mp-imports'
			)
		);
	}

	/**
	 * Plik spoza katalogu (bez traversalu) tez odpada.
	 */
	public function test_absolute_path_outside_imports_dir_is_rejected(): void {
		self::assertFalse(
			ImportEndpoints::is_report_path_safe(
				$this->dir . '/sekret-poza-importami.txt',
				$this->dir . '/mp-imports'
			)
		);
	}

	/**
	 * Nieistniejacy raport odpada (zero fatali przy readfile).
	 */
	public function test_missing_report_is_rejected(): void {
		self::assertFalse(
			ImportEndpoints::is_report_path_safe(
				$this->dir . '/mp-imports/nie-ma-mnie.csv',
				$this->dir . '/mp-imports'
			)
		);
	}

	/**
	 * Kazdy kod bledu uploadu ma niepusty komunikat PL.
	 */
	public function test_every_upload_error_code_has_message(): void {
		$codes = array(
			UPLOAD_ERR_INI_SIZE,
			UPLOAD_ERR_FORM_SIZE,
			UPLOAD_ERR_PARTIAL,
			UPLOAD_ERR_NO_FILE,
			UPLOAD_ERR_NO_TMP_DIR,
			UPLOAD_ERR_CANT_WRITE,
			UPLOAD_ERR_EXTENSION,
		);

		foreach ( $codes as $code ) {
			self::assertNotSame( '', ImportEndpoints::upload_error_message( $code ) );
		}
	}

	/**
	 * Za duzy plik dostaje komunikat o dzieleniu CSV (czytelna akcja dla usera).
	 */
	public function test_ini_size_message_tells_user_to_split_file(): void {
		self::assertStringContainsString(
			'podziel CSV',
			ImportEndpoints::upload_error_message( UPLOAD_ERR_INI_SIZE )
		);
	}
}
