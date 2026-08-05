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

use MP\Registry\Assets;
use MP\Registry\Categories;
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
			Assets::ver( 'assets/css/admin-import.css' )
		);

		// Region przewijany tabeli historii importow (S4 nr 6, czesc druga). Wspolny,
		// maly arkusz dzielony z ekranem wyjatkow — jedna definicja klasy zamiast
		// dwoch kopii, ktore rozjechalyby sie przy pierwszej zmianie.
		wp_enqueue_style(
			'mp-registry-tabele',
			$base . 'assets/css/admin-tabele.css',
			array(),
			Assets::ver( 'assets/css/admin-tabele.css' )
		);

		wp_enqueue_script(
			'mp-import-admin',
			$base . 'assets/js/admin-import.js',
			array(),
			Assets::ver( 'assets/js/admin-import.js' ),
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
				// Z1b: po zakonczeniu importu JS odswieza wiersz tabeli historii,
				// w tym link raportu bledow — URL z noncem musi powstac w PHP.
				'reportUrl' => self::report_url( (int) $live['id'] ),
			),
			'i18n'    => array(
				/* translators: 1: przetworzone wiersze, 2: wszystkie wiersze, 3: liczba bledow. */
				'progress'   => __( 'Przetworzono %1$s z %2$s wierszy (błędy: %3$s).', 'mp-warranty-registry' ),
				/* translators: 1: przetworzone wiersze, 2: wszystkie wiersze, 3: liczba bledow. */
				'done'       => __( 'Import zakończony: %1$s z %2$s wierszy, błędy: %3$s.', 'mp-warranty-registry' ),
				'doneErrors' => __( 'Pobierz raport błędów poniżej (tabela „Ostatnie importy").', 'mp-warranty-registry' ),
				'netError'   => __( 'Błąd połączenia — import NIE przepadł. Kliknij „Wznów import", żeby kontynuować od miejsca przerwania.', 'mp-warranty-registry' ),
				'resuming'   => __( 'Wznawiam import…', 'mp-warranty-registry' ),
				// Z1b: te same napisy, ktorymi tabele historii renderuje PHP —
				// wiersz odswiezony JS-em nie moze mowic innym jezykiem niz reszta.
				'statusDone' => __( 'zakończony', 'mp-warranty-registry' ),
				'reportLink' => __( 'pobierz CSV', 'mp-warranty-registry' ),
				// Teksty dla czytnika ekranu. Postep ogłaszany co 10%, a nie po
				// kazdej paczce — inaczej czytnik zagadalby operatora na smierc
				// i komunikat o BLEDZIE utonalby w strumieniu „przetworzono…".
				'srStarted'  => __( 'Import rozpoczęty.', 'mp-warranty-registry' ),
				/* translators: %1$s: postep w procentach. */
				'srProgress' => __( 'Import w toku: %1$s procent.', 'mp-warranty-registry' ),
			),
		);
	}

	/**
	 * Postep w procentach (0..100) — do ogloszenia dla czytnika ekranu.
	 *
	 * Funkcja czysta. Zero wierszy w pliku to NIE jest blad (pusty CSV),
	 * wiec zwracamy 0, a nie dzielimy przez zero.
	 *
	 * @param int $processed Przetworzone wiersze.
	 * @param int $total     Wszystkie wiersze.
	 * @return int
	 */
	public static function percent( int $processed, int $total ): int {
		if ( $total <= 0 ) {
			return 0;
		}

		return (int) max( 0, min( 100, (int) floor( $processed * 100 / $total ) ) );
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
					<progress id="mp-import-progress" aria-label="<?php esc_attr_e( 'Postęp importu', 'mp-warranty-registry' ); ?>" max="<?php echo esc_attr( (string) max( 1, (int) ( $live['total_rows'] ?? 0 ) ) ); ?>" value="<?php echo esc_attr( (string) (int) ( $live['processed_rows'] ?? 0 ) ); ?>"></progress>
				</p>
				<p>
					<button type="button" class="button button-secondary hidden" id="mp-import-resume" data-job="<?php echo esc_attr( (string) (int) ( $live['id'] ?? 0 ) ); ?>">
						<?php esc_html_e( 'Wznów import', 'mp-warranty-registry' ); ?>
					</button>
				</p>
			</div>

			<?php
			/*
			 * ⛔ Obszary ogłaszane czytnikowi ekranu. Do 1.3.12 stan importu istniał
			 * WYŁĄCZNIE wizualnie: skrypt podmieniał tekst w `#mp-import-message`,
			 * a w całym tym pliku nie było ANI JEDNEGO atrybutu `aria-`. Osoba
			 * z czytnikiem uruchamiała import i nie dowiadywała się ani że trwa,
			 * ani że się skończył, ani że padł — tekst zmieniał się w ciszy.
			 *
			 * Dwa OSOBNE obszary, oba na stałe w dokumencie i nigdy nieukrywane:
			 * ukryty (`display:none`) obszar aria-live bywa pomijany, gdy odsłania
			 * się go i zapełnia w tej samej chwili — a dokładnie tak działa `show()`.
			 * Postęp idzie „polite" (nie przerywa), błąd „assertive" (przerywa).
			 *
			 * Ta sama technika stoi w OŚMIU miejscach na powierzchni klienta
			 * (`Front/AccountPage.php`, `Front/FormRenderer.php`) — tutaj, na
			 * powierzchni personelu, nie została użyta ani razu.
			 */
			?>
			<p id="mp-import-live" class="screen-reader-text" role="status" aria-live="polite" aria-atomic="true">
				<?php
				if ( null !== $live ) {
					printf(
						/* translators: %1$s: postep w procentach. */
						esc_html__( 'Import w toku: %1$s procent.', 'mp-warranty-registry' ),
						esc_html( number_format_i18n( self::percent( (int) $live['processed_rows'], (int) $live['total_rows'] ) ) )
					);
				}
				?>
			</p>
			<p id="mp-import-alert" class="screen-reader-text" role="alert" aria-live="assertive" aria-atomic="true"></p>

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
			<p>
				<?php
				printf(
					/* translators: %s: lista dozwolonych slugow kategorii. */
					esc_html__( 'Kolumny opcjonalne: model, partia, faktura (albo dokument_zakupu), data_zakupu, gwarancja_do, kategoria. Daty w formacie 2026-04-12 albo 12.04.2026; puste pole jest dozwolone. Kategoria — jedna z: %s (wartość spoza listy trafia do „inne"). Bez kolumny gwarancja_do rejestr nie policzy statusu gwarancji.', 'mp-warranty-registry' ),
					esc_html( implode( ', ', Categories::slugs() ) )
				);
				?>
			</p>
			<p>
				<?php esc_html_e( 'Import DODAJE produkty do rejestru. Numer seryjny, który już w nim jest, trafia do raportu błędów i NIE nadpisuje istniejącego wpisu. Przy porównywaniu seriali spacje i myślniki są pomijane, a wielkość liter nie ma znaczenia.', 'mp-warranty-registry' ); ?>
			</p>
			<p>
				<a href="<?php echo esc_url( plugin_dir_url( MP_REGISTRY_FILE ) . 'przyklady/przyklad-import-produktow.csv' ); ?>" download>
					<?php esc_html_e( 'Pobierz przykładowy plik CSV (8 wierszy, gotowy do wgrania)', 'mp-warranty-registry' ); ?>
				</a>
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
		<div class="mp-registry-table-scroll" role="region" tabindex="0" aria-label="<?php echo esc_attr__( 'Tabela historii importów', 'mp-warranty-registry' ); ?>">
		<table class="widefat striped mp-import-history">
			<thead>
				<tr>
					<th scope="col"><?php esc_html_e( 'Import', 'mp-warranty-registry' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Status', 'mp-warranty-registry' ); ?></th>
					<?php
					/*
					 * ⛔ WADA W5 (kontrola na zywej instalacji): ten sam import pokazywal
					 * jednoczesnie „8 / 8 wierszy" i „8 bledow", co czyta sie jak sprzecznosc.
					 * W danych sprzecznosci nie bylo — `processed_rows` liczy wiersze
					 * PRZETWORZONE (udane RAZEM z bledami), wiec „8 z 8" znaczylo „wszystkie
					 * osiem przerobione", a nie „osiem dodanych". Sprzecznosc siedziala
					 * w NAPISIE: naglowek „Wiersze" obiecywal wynik, a pokazywal postep.
					 *
					 * Tabela ma juz kolumne `success_rows` i to jej klient szuka. Pokazujemy
					 * ZAIMPORTOWANE z wszystkich — wtedy dla tamtego importu wychodzi
					 * „0 / 8" i „8 bledow", czyli zdanie prawdziwe i zgodne samo ze soba
					 * na kazdym etapie (zaimportowane + bledy <= wszystkie).
					 */
					?>
					<th scope="col"><?php esc_html_e( 'Zaimportowane / wszystkie', 'mp-warranty-registry' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Błędy', 'mp-warranty-registry' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Utworzony', 'mp-warranty-registry' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Raport błędów', 'mp-warranty-registry' ); ?></th>
				</tr>
			</thead>
			<tbody>
				<?php // Z1b: data-job + klasy komorek to zaczepy dla JS, ktory po zakonczeniu importu AJAX odswieza ten wiersz (admin-import.js). ?>
				<?php foreach ( $jobs as $job ) : ?>
					<tr data-job="<?php echo esc_attr( (string) (int) $job['id'] ); ?>">
						<td>#<?php echo esc_html( (string) (int) $job['id'] ); ?></td>
						<td class="mp-import-h-status"><?php echo esc_html( $labels[ (string) $job['status'] ] ?? (string) $job['status'] ); ?></td>
						<td class="mp-import-h-counts"><?php echo esc_html( number_format_i18n( (int) $job['success_rows'] ) . ' / ' . number_format_i18n( (int) $job['total_rows'] ) ); ?></td>
						<td class="mp-import-h-errors"><?php echo esc_html( number_format_i18n( (int) $job['error_rows'] ) ); ?></td>
						<td><?php echo esc_html( (string) $job['created_at'] ); ?></td>
						<td class="mp-import-h-report">
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
		</div>
		<p class="description">
			<?php esc_html_e( 'Godziny w kolumnie „Utworzony” podane są w czasie uniwersalnym (UTC) — w Polsce zegar jest o 1 godzinę (zimą) lub 2 godziny (latem) do przodu.', 'mp-warranty-registry' ); ?>
		</p>
		<?php
	}

	/**
	 * URL pobrania raportu bledow (przez PHP z capability, nie wprost z uploads).
	 *
	 * Publiczna, bo ten sam URL musi trafic do JS przy wznowieniu importu
	 * (ImportEndpoints::ajax_reclaim) — inaczej wiersz odswiezany po done (Z1b)
	 * nie mialby skad wziac linku raportu.
	 *
	 * @param int $job_id ID joba.
	 * @return string
	 */
	public static function report_url( int $job_id ): string {
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
