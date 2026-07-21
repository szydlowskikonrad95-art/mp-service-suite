<?php
/**
 * Ekran admina: import produktow z CSV (karta B, czesc 2b).
 *
 * Upload zaklada job (admin-post), potem JS mieli porcje przez AJAX —
 * TEN SAM silnik Importer::process_batch co WP-CLI. Stale-detekcja
 * odpala sie PRZY RENDERZE (kontrakt K-C2 — bez dodatkowego crona).
 *
 * @package MP\Registry
 */

namespace MP\Registry\Admin;

use MP\Registry\CsvParser;
use MP\Registry\Importer;
use MP\Registry\ImportJobs;

/**
 * Rejestracja menu, render ekranu i zasoby JS/CSS importu.
 */
final class ImportScreen {

	/**
	 * Slug strony w menu admina.
	 */
	public const PAGE_SLUG = 'mp-registry-import';

	/**
	 * Prefiks transientu ze swiezym tokenem joba (per user, TTL 10 min).
	 */
	public const TOKEN_TRANSIENT = 'mp_import_fresh_';

	/**
	 * Prefiks transientu z komunikatem bledu uploadu (per user).
	 */
	public const ERROR_TRANSIENT = 'mp_import_error_';

	/**
	 * Hook suffix strony (do enqueue tylko na naszym ekranie).
	 *
	 * @var string
	 */
	private static string $hook_suffix = '';

	/**
	 * Rejestruje hooki admina.
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_menu', array( self::class, 'add_menu' ) );
		add_action( 'admin_enqueue_scripts', array( self::class, 'enqueue' ) );
	}

	/**
	 * Dodaje strone importu jako podstrone Rejestru MP.
	 *
	 * @return void
	 */
	public static function add_menu(): void {
		self::$hook_suffix = (string) add_submenu_page(
			ProductsScreen::PAGE_SLUG,
			__( 'Import produktów z CSV', 'mp-warranty-registry' ),
			__( 'Import CSV', 'mp-warranty-registry' ),
			'mp_system_admin',
			self::PAGE_SLUG,
			array( self::class, 'render' )
		);
	}

	/**
	 * Laduje JS/CSS wylacznie na ekranie importu.
	 *
	 * @param string $hook Hook suffix biezacej strony admina.
	 * @return void
	 */
	public static function enqueue( string $hook ): void {
		if ( '' === self::$hook_suffix || $hook !== self::$hook_suffix ) {
			return;
		}

		$base = plugin_dir_url( MP_REGISTRY_FILE );

		wp_enqueue_style(
			'mp-import-admin',
			$base . 'assets/css/admin-import.css',
			array(),
			MP_REGISTRY_VERSION
		);

		wp_enqueue_script(
			'mp-import-admin',
			$base . 'assets/js/admin-import.js',
			array(),
			MP_REGISTRY_VERSION,
			true
		);

		wp_localize_script( 'mp-import-admin', 'mpImportCfg', self::js_config() );
	}

	/**
	 * Konfiguracja przekazywana do JS (job + nonce + teksty).
	 *
	 * @return array<string, mixed>
	 */
	private static function js_config(): array {
		$live  = ImportJobs::find_live();
		$token = null;

		if ( null !== $live ) {
			$fresh = get_transient( self::TOKEN_TRANSIENT . get_current_user_id() );

			if ( is_array( $fresh ) && (int) $fresh['job_id'] === (int) $live['id'] ) {
				$token = (string) $fresh['token'];
				delete_transient( self::TOKEN_TRANSIENT . get_current_user_id() );
			}
		}

		return array(
			'ajaxUrl' => admin_url( 'admin-ajax.php' ),
			'nonce'   => wp_create_nonce( 'mp_import_ajax' ),
			'job'     => null === $live ? null : array(
				'id'        => (int) $live['id'],
				'status'    => (string) $live['status'],
				'processed' => (int) $live['processed_rows'],
				'total'     => (int) $live['total_rows'],
				'errors'    => (int) $live['error_rows'],
				'token'     => $token,
			),
			'i18n'    => array(
				/* translators: 1: przetworzone wiersze, 2: wszystkie wiersze, 3: liczba bledow. */
				'progress'   => __( 'Przetworzono %1$s z %2$s wierszy (błędy: %3$s).', 'mp-warranty-registry' ),
				/* translators: 1: przetworzone wiersze, 2: wszystkie wiersze, 3: liczba bledow. */
				'done'       => __( 'Import zakończony: %1$s z %2$s wierszy, błędy: %3$s.', 'mp-warranty-registry' ),
				'doneErrors' => __( 'Pobierz raport błędów poniżej (tabela „Ostatnie importy").', 'mp-warranty-registry' ),
				'netError'   => __( 'Błąd połączenia — import NIE przepadł. Kliknij „Wznów import", żeby kontynuować od miejsca przerwania.', 'mp-warranty-registry' ),
				'resuming'   => __( 'Wznawiam import…', 'mp-warranty-registry' ),
			),
		);
	}

	/**
	 * Renderuje ekran importu.
	 *
	 * @return void
	 */
	public static function render(): void {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die( esc_html__( 'Brak uprawnień do importu produktów.', 'mp-warranty-registry' ) );
		}

		ImportJobs::release_stale();

		$live       = ImportJobs::find_live();
		$stale_jobs = array_values(
			array_filter(
				ImportJobs::latest(),
				static fn( array $j ): bool => 'stale' === (string) $j['status']
			)
		);
		$error      = get_transient( self::ERROR_TRANSIENT . get_current_user_id() );

		if ( false !== $error ) {
			delete_transient( self::ERROR_TRANSIENT . get_current_user_id() );
		}

		$max_bytes = min( Importer::MAX_FILE_BYTES, (int) wp_max_upload_size() );
		?>
		<div class="wrap mp-import">
			<h1><?php esc_html_e( 'Import produktów z CSV', 'mp-warranty-registry' ); ?></h1>

			<?php if ( ! CsvParser::has_transcoder() ) : ?>
				<div class="notice notice-warning">
					<p><?php esc_html_e( 'Serwer nie ma rozszerzenia iconv ani intl — import przyjmie wyłącznie pliki zapisane w UTF-8. Plik z polskiego Excela (Windows-1250) zostanie uczciwie odrzucony zamiast przekłamać polskie znaki.', 'mp-warranty-registry' ); ?></p>
				</div>
			<?php endif; ?>

			<?php if ( is_string( $error ) && '' !== $error ) : ?>
				<div class="notice notice-error"><p><?php echo esc_html( $error ); ?></p></div>
			<?php endif; ?>

			<div id="mp-import-status" class="notice notice-info<?php echo null === $live ? ' hidden' : ''; ?>">
				<p id="mp-import-message">
					<?php
					if ( null !== $live ) {
						printf(
							/* translators: 1: przetworzone wiersze, 2: wszystkie wiersze, 3: liczba bledow. */
							esc_html__( 'Przetworzono %1$s z %2$s wierszy (błędy: %3$s).', 'mp-warranty-registry' ),
							esc_html( number_format_i18n( (int) $live['processed_rows'] ) ),
							esc_html( number_format_i18n( (int) $live['total_rows'] ) ),
							esc_html( number_format_i18n( (int) $live['error_rows'] ) )
						);
					}
					?>
				</p>
				<p>
					<progress id="mp-import-progress" max="<?php echo esc_attr( (string) max( 1, (int) ( $live['total_rows'] ?? 0 ) ) ); ?>" value="<?php echo esc_attr( (string) (int) ( $live['processed_rows'] ?? 0 ) ); ?>"></progress>
				</p>
				<p>
					<button type="button" class="button button-secondary hidden" id="mp-import-resume" data-job="<?php echo esc_attr( (string) (int) ( $live['id'] ?? 0 ) ); ?>">
						<?php esc_html_e( 'Wznów import', 'mp-warranty-registry' ); ?>
					</button>
				</p>
			</div>

			<?php foreach ( $stale_jobs as $stale ) : ?>
				<div class="notice notice-warning">
					<p>
						<?php
						printf(
							/* translators: 1: numer joba, 2: przetworzone, 3: wszystkie wiersze. */
							esc_html__( 'Import #%1$s został przerwany (%2$s z %3$s wierszy). Możesz go wznowić — ruszy od miejsca przerwania.', 'mp-warranty-registry' ),
							esc_html( (string) (int) $stale['id'] ),
							esc_html( number_format_i18n( (int) $stale['processed_rows'] ) ),
							esc_html( number_format_i18n( (int) $stale['total_rows'] ) )
						);
						?>
						<button type="button" class="button button-secondary mp-import-resume-stale" data-job="<?php echo esc_attr( (string) (int) $stale['id'] ); ?>">
							<?php esc_html_e( 'Wznów import', 'mp-warranty-registry' ); ?>
						</button>
					</p>
				</div>
			<?php endforeach; ?>

			<h2><?php esc_html_e( 'Wgraj plik CSV', 'mp-warranty-registry' ); ?></h2>
			<p>
				<?php
				printf(
					/* translators: %s: maksymalny rozmiar pliku. */
					esc_html__( 'Wymagana kolumna: serial (aliasy: numer_seryjny, sn). Separator ; lub , — kodowanie UTF-8 albo Windows-1250 (polski Excel). Maksymalny rozmiar pliku: %s.', 'mp-warranty-registry' ),
					esc_html( size_format( $max_bytes ) )
				);
				?>
			</p>
			<form method="post" enctype="multipart/form-data" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
				<input type="hidden" name="action" value="mp_import_upload" />
				<?php wp_nonce_field( 'mp_import_upload' ); ?>
				<label for="mp-import-file" class="screen-reader-text"><?php esc_html_e( 'Plik CSV z produktami', 'mp-warranty-registry' ); ?></label>
				<input type="file" id="mp-import-file" name="mp_import_file" accept=".csv,.txt" required />
				<?php submit_button( __( 'Rozpocznij import', 'mp-warranty-registry' ), 'primary', 'submit', false ); ?>
			</form>

			<h2><?php esc_html_e( 'Ostatnie importy', 'mp-warranty-registry' ); ?></h2>
			<?php self::render_history(); ?>
		</div>
		<?php
	}

	/**
	 * Tabela ostatnich jobow z linkiem do raportu bledow.
	 *
	 * @return void
	 */
	private static function render_history(): void {
		$jobs = ImportJobs::latest();

		if ( array() === $jobs ) {
			echo '<p>' . esc_html__( 'Brak importów.', 'mp-warranty-registry' ) . '</p>';

			return;
		}

		$labels = array(
			'pending'    => __( 'oczekuje', 'mp-warranty-registry' ),
			'processing' => __( 'w trakcie', 'mp-warranty-registry' ),
			'stale'      => __( 'przerwany', 'mp-warranty-registry' ),
			'done'       => __( 'zakończony', 'mp-warranty-registry' ),
			'failed'     => __( 'nieudany', 'mp-warranty-registry' ),
		);
		?>
		<table class="widefat striped mp-import-history">
			<thead>
				<tr>
					<th scope="col"><?php esc_html_e( 'Job', 'mp-warranty-registry' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Status', 'mp-warranty-registry' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Wiersze', 'mp-warranty-registry' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Błędy', 'mp-warranty-registry' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Utworzony (UTC)', 'mp-warranty-registry' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Raport błędów', 'mp-warranty-registry' ); ?></th>
				</tr>
			</thead>
			<tbody>
				<?php foreach ( $jobs as $job ) : ?>
					<tr>
						<td>#<?php echo esc_html( (string) (int) $job['id'] ); ?></td>
						<td><?php echo esc_html( $labels[ (string) $job['status'] ] ?? (string) $job['status'] ); ?></td>
						<td><?php echo esc_html( number_format_i18n( (int) $job['processed_rows'] ) . ' / ' . number_format_i18n( (int) $job['total_rows'] ) ); ?></td>
						<td><?php echo esc_html( number_format_i18n( (int) $job['error_rows'] ) ); ?></td>
						<td><?php echo esc_html( (string) $job['created_at'] ); ?></td>
						<td>
							<?php if ( (int) $job['error_rows'] > 0 ) : ?>
								<a href="<?php echo esc_url( self::report_url( (int) $job['id'] ) ); ?>">
									<?php esc_html_e( 'pobierz CSV', 'mp-warranty-registry' ); ?>
								</a>
							<?php else : ?>
								&mdash;
							<?php endif; ?>
						</td>
					</tr>
				<?php endforeach; ?>
			</tbody>
		</table>
		<?php
	}

	/**
	 * URL pobrania raportu bledow (przez PHP z capability, nie wprost z uploads).
	 *
	 * @param int $job_id ID joba.
	 * @return string
	 */
	private static function report_url( int $job_id ): string {
		return wp_nonce_url(
			add_query_arg(
				array(
					'action' => 'mp_import_report',
					'job'    => $job_id,
				),
				admin_url( 'admin-post.php' )
			),
			'mp_import_report_' . $job_id
		);
	}
}
