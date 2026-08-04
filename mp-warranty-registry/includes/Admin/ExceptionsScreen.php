<?php
/**
 * Ekran admina: wyjatki gwarancyjne produktu (lista + przyznanie + cofniecie).
 *
 * CRUD wylacznie za mp_system_admin (precedens karty B) — domena
 * (WarrantyExceptions) i tak sprawdza capability drugi raz (pas i szelki).
 * "Przeterminowany" to etykieta WYLICZANA przy renderze — status w bazie
 * zna tylko active/revoked.
 *
 * @package MP\Registry
 */

namespace MP\Registry\Admin;

use MP\Registry\Repo;
use MP\Registry\Tables;
use MP\Registry\WarrantyExceptions;

/**
 * Podstrona wyjatkow + akcje admin-post.
 */
final class ExceptionsScreen {

	/**
	 * Slug podstrony.
	 */
	public const PAGE_SLUG = 'mp-registry-exceptions';

	/**
	 * Prefiks transientu komunikatu (per user).
	 */
	public const NOTICE_TRANSIENT = 'mp_exceptions_notice_';

	/**
	 * Ile wyjatkow na stronie w widoku wszystkich wyjatkow.
	 */
	public const PER_PAGE = 20;

	/**
	 * Rejestruje hooki admina.
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_menu', array( self::class, 'add_menu' ) );
		add_action( 'admin_post_mp_exception_add', array( self::class, 'handle_add' ) );
		add_action( 'admin_post_mp_exception_revoke', array( self::class, 'handle_revoke' ) );
		// nopriv -> ten sam handler: anon dostaje JAWNE 403 (security-sweep kryteria odbioru sekcja 3).
		add_action( 'admin_post_nopriv_mp_exception_add', array( self::class, 'handle_add' ) );
		add_action( 'admin_post_nopriv_mp_exception_revoke', array( self::class, 'handle_revoke' ) );
	}

	/**
	 * Podstrona pod Rejestrem MP.
	 *
	 * @return void
	 */
	public static function add_menu(): void {
		add_submenu_page(
			ProductsScreen::PAGE_SLUG,
			__( 'Wyjątki gwarancyjne', 'mp-warranty-registry' ),
			__( 'Wyjątki gwarancyjne', 'mp-warranty-registry' ),
			'mp_system_admin',
			self::PAGE_SLUG,
			array( self::class, 'render' )
		);
	}

	/**
	 * Render: wyjatki produktu + formularz przyznania.
	 *
	 * @return void
	 */
	public static function render(): void {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die( esc_html__( 'Brak uprawnień do wyjątków gwarancyjnych.', 'mp-warranty-registry' ) );
		}

		global $wpdb;

		// phpcs:disable WordPress.Security.NonceVerification.Recommended -- wybor produktu do PODGLADU (GET, bez zmiany stanu).
		$product_id = isset( $_GET['product'] ) ? absint( $_GET['product'] ) : 0;
		// phpcs:enable

		$notice = get_transient( self::NOTICE_TRANSIENT . get_current_user_id() );

		if ( false !== $notice ) {
			delete_transient( self::NOTICE_TRANSIENT . get_current_user_id() );
		}

		$registry = Tables::full( Tables::REGISTRY );
		$table    = Tables::full( Tables::EXCEPTIONS );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabele wlasne, zapytania przygotowane.
		$product = 0 !== $product_id
			? $wpdb->get_row( $wpdb->prepare( "SELECT id, serial_display, model FROM {$registry} WHERE id = %d", $product_id ), ARRAY_A )
			: null;
		$rows    = 0 !== $product_id
			? $wpdb->get_results( $wpdb->prepare( "SELECT * FROM {$table} WHERE product_registry_id = %d ORDER BY id DESC LIMIT 50", $product_id ), ARRAY_A )
			: array();
		// phpcs:enable

		$now = gmdate( 'Y-m-d H:i:s' );

		if ( null === $product ) {
			// Ekran otwarty z menu, bez wybranego produktu. Do 1.3.12 stalo tu wylacznie
			// wyjasnienie i przycisk „Przejdz do Rejestru MP" — pozycja w menu, ktora nigdy
			// nie pokazywala danych. Pod spodem siedzial prawdziwy brak: KAZDE zapytanie
			// do tabeli wyjatkow filtrowalo po konkretnym produkcie, wiec administrator,
			// ktory przyznal ich dwadziescia, nie mial jak ich przejrzec.
			self::render_all( is_array( $notice ) ? $notice : null );
			return;
		}
		?>
		<div class="wrap mp-exceptions">
			<h1><?php esc_html_e( 'Wyjątki gwarancyjne', 'mp-warranty-registry' ); ?></h1>

			<?php if ( is_array( $notice ) ) : ?>
				<div class="notice notice-<?php echo esc_attr( (string) $notice['type'] ); ?>"><p><?php echo esc_html( (string) $notice['text'] ); ?></p></div>
			<?php endif; ?>

			<h2>
				<?php
				printf(
					/* translators: 1: numer seryjny, 2: model. */
					esc_html__( 'Produkt %1$s (%2$s)', 'mp-warranty-registry' ),
					esc_html( (string) $product['serial_display'] ),
					esc_html( '' !== (string) $product['model'] ? (string) $product['model'] : '—' )
				);
				?>
			</h2>

			<table class="widefat striped">
				<thead>
					<tr>
						<th scope="col">ID</th>
						<th scope="col"><?php esc_html_e( 'Zakres', 'mp-warranty-registry' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Status', 'mp-warranty-registry' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Ważny do', 'mp-warranty-registry' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Powód', 'mp-warranty-registry' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Akcja', 'mp-warranty-registry' ); ?></th>
					</tr>
				</thead>
				<tbody>
					<?php if ( ! is_array( $rows ) || array() === $rows ) : ?>
						<tr><td colspan="6"><?php esc_html_e( 'Brak wyjątków dla tego produktu.', 'mp-warranty-registry' ); ?></td></tr>
					<?php endif; ?>
					<?php foreach ( (array) $rows as $row ) : ?>
						<?php $is_active = 'active' === (string) $row['status']; ?>
						<tr>
							<td>#<?php echo esc_html( (string) (int) $row['id'] ); ?></td>
							<td>
								<?php
								echo null === $row['case_id']
									? esc_html__( 'globalny', 'mp-warranty-registry' )
									: esc_html( sprintf( /* translators: %d: numer sprawy. */ __( 'sprawa #%d', 'mp-warranty-registry' ), (int) $row['case_id'] ) );
								?>
							</td>
							<td><?php echo esc_html( self::status_label( $row, $now ) ); ?></td>
							<td><?php echo esc_html( (string) ( $row['valid_until'] ?? __( 'bezterminowo', 'mp-warranty-registry' ) ) ); ?></td>
							<td><?php echo esc_html( (string) $row['reason'] ); ?></td>
							<td>
								<?php if ( $is_active ) : ?>
									<a href="<?php echo esc_url( self::revoke_url( (int) $row['id'], $product_id ) ); ?>">
										<?php esc_html_e( 'cofnij', 'mp-warranty-registry' ); ?>
									</a>
								<?php else : ?>
									&mdash;
								<?php endif; ?>
							</td>
						</tr>
					<?php endforeach; ?>
				</tbody>
			</table>

			<h2><?php esc_html_e( 'Przyznaj wyjątek', 'mp-warranty-registry' ); ?></h2>
			<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
				<input type="hidden" name="action" value="mp_exception_add" />
				<input type="hidden" name="product" value="<?php echo esc_attr( (string) $product_id ); ?>" />
				<?php wp_nonce_field( 'mp_exception_add_' . $product_id ); ?>
				<table class="form-table" role="presentation">
					<tr>
						<th scope="row"><label for="mp-exc-case"><?php esc_html_e( 'Sprawa (opcjonalnie)', 'mp-warranty-registry' ); ?></label></th>
						<td>
							<input type="number" min="1" id="mp-exc-case" name="case_id" />
							<p class="description"><?php esc_html_e( 'Puste = wyjątek globalny na produkt. Z numerem sprawy działa TYLKO dla tej sprawy.', 'mp-warranty-registry' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="mp-exc-until"><?php esc_html_e( 'Ważny do (opcjonalnie)', 'mp-warranty-registry' ); ?></label></th>
						<td>
							<input type="date" id="mp-exc-until" name="valid_until" />
							<p class="description"><?php esc_html_e( 'Puste = bezterminowo. Data musi być w przyszłości; wyjątek wygasa z końcem wskazanego dnia (czas UTC — w Polsce zegar jest o 1–2 godziny do przodu).', 'mp-warranty-registry' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="mp-exc-reason"><?php esc_html_e( 'Powód (wymagany)', 'mp-warranty-registry' ); ?></label></th>
						<td>
							<textarea id="mp-exc-reason" name="reason" rows="3" cols="50" maxlength="500" required></textarea>
							<p class="description"><?php esc_html_e( 'Notatka wewnętrzna, do 500 znaków. Nie trafia do historii zdarzeń ani do innych modułów.', 'mp-warranty-registry' ); ?></p>
						</td>
					</tr>
				</table>
				<?php submit_button( __( 'Przyznaj wyjątek', 'mp-warranty-registry' ) ); ?>
			</form>
		</div>
		<?php
	}

	/**
	 * Widok WSZYSTKICH udzielonych wyjatkow — ekran otwarty z menu, bez produktu.
	 *
	 * Zamienia dawny slepy zaulek („wybierz produkt" + przycisk) w to, czego
	 * naprawde brakowalo: przeglad decyzji gwarancyjnych w calym serwisie.
	 * Droga „Rejestr MP → kolumna Akcje → wyjątki" zostaje bez zmian — jest
	 * opisana w instrukcji i nadal jest jedyna droga do NADANIA wyjatku.
	 *
	 * @param array<string, string>|null $notice Komunikat po akcji (albo null).
	 * @return void
	 */
	private static function render_all( ?array $notice ): void {
		// phpcs:disable WordPress.Security.NonceVerification.Recommended -- filtr i strona z GET; widok tylko czyta.
		$filter = isset( $_GET['f_status'] ) ? sanitize_key( wp_unslash( (string) $_GET['f_status'] ) ) : 'active';
		$paged  = isset( $_GET['paged'] ) ? max( 1, absint( $_GET['paged'] ) ) : 1;
		// phpcs:enable

		if ( ! in_array( $filter, Repo::EXCEPTION_FILTERS, true ) ) {
			$filter = 'active';
		}

		$wynik       = Repo::all_exceptions( $filter, $paged, self::PER_PAGE );
		$now         = gmdate( 'Y-m-d H:i:s' );
		$rejestr_url = add_query_arg( 'page', ProductsScreen::PAGE_SLUG, admin_url( 'admin.php' ) );
		$strony      = (int) ceil( $wynik['total'] / self::PER_PAGE );

		$etykiety = array(
			'active'  => __( 'aktywne', 'mp-warranty-registry' ),
			'expired' => __( 'przeterminowane', 'mp-warranty-registry' ),
			'revoked' => __( 'cofnięte', 'mp-warranty-registry' ),
			'all'     => __( 'wszystkie', 'mp-warranty-registry' ),
		);
		?>
		<div class="wrap mp-exceptions">
			<h1><?php esc_html_e( 'Wyjątki gwarancyjne', 'mp-warranty-registry' ); ?></h1>

			<?php if ( null !== $notice ) : ?>
				<div class="notice notice-<?php echo esc_attr( (string) $notice['type'] ); ?>"><p><?php echo esc_html( (string) $notice['text'] ); ?></p></div>
			<?php endif; ?>

			<p class="description">
				<?php esc_html_e( 'Wyjątek gwarancyjny to zgoda administratora na obsługę zgłoszenia mimo wygasłej gwarancji lub braku danych. Poniżej są wszystkie udzielone wyjątki. Nowy nadaje się zawsze przy konkretnym produkcie: Rejestr MP → kolumna Akcje → „wyjątki".', 'mp-warranty-registry' ); ?>
			</p>

			<form method="get">
				<input type="hidden" name="page" value="<?php echo esc_attr( self::PAGE_SLUG ); ?>" />
				<p>
					<label for="mp-exc-filter"><?php esc_html_e( 'Pokaż:', 'mp-warranty-registry' ); ?></label>
					<select id="mp-exc-filter" name="f_status">
						<?php foreach ( $etykiety as $klucz => $etykieta ) : ?>
							<option value="<?php echo esc_attr( (string) $klucz ); ?>" <?php selected( $filter, $klucz ); ?>>
								<?php echo esc_html( (string) $etykieta ); ?>
							</option>
						<?php endforeach; ?>
					</select>
					<?php submit_button( __( 'Pokaż', 'mp-warranty-registry' ), 'secondary', 'submit', false ); ?>
				</p>
			</form>

			<p class="description">
				<?php
				printf(
					/* translators: 1: liczba wyjatkow, 2: nazwa filtru (aktywne/cofniete/...). */
					esc_html__( 'Wyjątków w tym widoku: %1$d (%2$s).', 'mp-warranty-registry' ),
					(int) $wynik['total'],
					esc_html( (string) $etykiety[ $filter ] )
				);
				?>
			</p>

			<table class="widefat striped">
				<thead>
					<tr>
						<th scope="col">ID</th>
						<th scope="col"><?php esc_html_e( 'Produkt', 'mp-warranty-registry' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Zakres', 'mp-warranty-registry' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Status', 'mp-warranty-registry' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Ważny do', 'mp-warranty-registry' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Nadany', 'mp-warranty-registry' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Powód', 'mp-warranty-registry' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Akcja', 'mp-warranty-registry' ); ?></th>
					</tr>
				</thead>
				<tbody>
					<?php if ( array() === $wynik['rows'] ) : ?>
						<tr><td colspan="8"><?php esc_html_e( 'W tym widoku nie ma żadnego wyjątku.', 'mp-warranty-registry' ); ?></td></tr>
					<?php endif; ?>
					<?php foreach ( $wynik['rows'] as $row ) : ?>
						<?php
						$pid       = (int) $row['product_registry_id'];
						$produkt   = add_query_arg(
							array(
								'page'    => self::PAGE_SLUG,
								'product' => $pid,
							),
							admin_url( 'admin.php' )
						);
						$is_active = 'active' === (string) $row['status'];
						?>
						<tr>
							<td>#<?php echo esc_html( (string) (int) $row['id'] ); ?></td>
							<td>
								<?php if ( null === $row['serial_display'] ) : ?>
									<?php
									echo esc_html(
										sprintf(
											/* translators: %d: ID produktu, ktorego nie ma juz w rejestrze. */
											__( 'produkt spoza rejestru (#%d)', 'mp-warranty-registry' ),
											$pid
										)
									);
									?>
								<?php else : ?>
									<a href="<?php echo esc_url( $produkt ); ?>"><code><?php echo esc_html( (string) $row['serial_display'] ); ?></code></a>
									<?php if ( '' !== (string) $row['model'] ) : ?>
										<br /><span class="description"><?php echo esc_html( (string) $row['model'] ); ?></span>
									<?php endif; ?>
								<?php endif; ?>
							</td>
							<td>
								<?php
								echo null === $row['case_id']
									? esc_html__( 'globalny', 'mp-warranty-registry' )
									: esc_html( sprintf( /* translators: %d: numer sprawy. */ __( 'sprawa #%d', 'mp-warranty-registry' ), (int) $row['case_id'] ) );
								?>
							</td>
							<td><?php echo esc_html( self::status_label( $row, $now ) ); ?></td>
							<td><?php echo esc_html( (string) ( $row['valid_until'] ?? __( 'bezterminowo', 'mp-warranty-registry' ) ) ); ?></td>
							<td>
								<?php echo esc_html( get_date_from_gmt( (string) $row['created_at'], 'Y-m-d H:i' ) ); ?>
								<br /><span class="description"><?php echo esc_html( self::autor( (int) $row['created_by'] ) ); ?></span>
							</td>
							<td><?php echo esc_html( (string) $row['reason'] ); ?></td>
							<td>
								<?php if ( $is_active ) : ?>
									<a href="<?php echo esc_url( self::revoke_url( (int) $row['id'], 0 ) ); ?>">
										<?php esc_html_e( 'cofnij', 'mp-warranty-registry' ); ?>
									</a>
								<?php else : ?>
									&mdash;
								<?php endif; ?>
							</td>
						</tr>
					<?php endforeach; ?>
				</tbody>
			</table>

			<?php if ( $strony > 1 ) : ?>
				<p>
					<?php
					echo wp_kses_post(
						(string) paginate_links(
							array(
								'base'      => add_query_arg( 'paged', '%#%' ),
								'format'    => '',
								'total'     => $strony,
								'current'   => $paged,
								'add_args'  => array( 'f_status' => $filter ),
								'prev_text' => __( '« poprzednie', 'mp-warranty-registry' ),
								'next_text' => __( 'następne »', 'mp-warranty-registry' ),
							)
						)
					);
					?>
				</p>
			<?php endif; ?>

			<p>
				<a class="button" href="<?php echo esc_url( $rejestr_url ); ?>">
					<?php esc_html_e( 'Przejdź do Rejestru MP', 'mp-warranty-registry' ); ?>
				</a>
			</p>
		</div>
		<?php
	}

	/**
	 * Etykieta stanu wyjatku.
	 *
	 * „Przeterminowany" NIE jest stanem w bazie — status zna tylko active/revoked
	 * — wiec liczy sie go z daty. Jedna funkcja dla obu widokow, zeby lista
	 * wszystkich wyjatkow i ekran produktu nie nazywaly tego samego inaczej.
	 *
	 * @param array<string, mixed> $row Wiersz wyjatku.
	 * @param string               $now Teraz w 'Y-m-d H:i:s' (UTC).
	 * @return string
	 */
	public static function status_label( array $row, string $now ): string {
		$is_active = 'active' === (string) ( $row['status'] ?? '' );

		if ( $is_active && null !== ( $row['valid_until'] ?? null ) && (string) $row['valid_until'] < $now ) {
			return __( 'przeterminowany (wyliczone z daty)', 'mp-warranty-registry' );
		}

		return $is_active
			? __( 'aktywny', 'mp-warranty-registry' )
			: __( 'cofnięty', 'mp-warranty-registry' );
	}

	/**
	 * Kto nadal wyjatek — nazwa konta zamiast samego ID.
	 *
	 * @param int $user_id ID konta.
	 * @return string
	 */
	private static function autor( int $user_id ): string {
		if ( $user_id <= 0 ) {
			return __( 'system', 'mp-warranty-registry' );
		}

		$user = get_userdata( $user_id );

		return false === $user
			? sprintf( /* translators: %d: ID usunietego konta. */ __( 'konto usunięte (#%d)', 'mp-warranty-registry' ), $user_id )
			: (string) $user->display_name;
	}

	/**
	 * Akcja: przyznanie wyjatku (admin-post).
	 *
	 * @return void
	 */
	public static function handle_add(): void {
		$product_id = isset( $_POST['product'] ) ? absint( $_POST['product'] ) : 0;

		check_admin_referer( 'mp_exception_add_' . $product_id );

		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die( esc_html__( 'Brak uprawnień.', 'mp-warranty-registry' ), '', 403 );
		}

		$case_raw = isset( $_POST['case_id'] ) ? absint( $_POST['case_id'] ) : 0;
		$until    = isset( $_POST['valid_until'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['valid_until'] ) ) : '';
		$reason   = isset( $_POST['reason'] ) ? sanitize_textarea_field( wp_unslash( (string) $_POST['reason'] ) ) : '';

		$result = WarrantyExceptions::create(
			$product_id,
			0 !== $case_raw ? $case_raw : null,
			$reason,
			'' !== $until ? $until : null
		);

		self::redirect_back(
			$product_id,
			isset( $result['id'] )
			? array(
				'type' => 'success',
				'text' => sprintf( /* translators: %d: ID wyjatku. */ __( 'Wyjątek #%d przyznany.', 'mp-warranty-registry' ), (int) $result['id'] ),
			)
			: array(
				'type' => 'error',
				'text' => (string) $result['error'],
			)
		);
	}

	/**
	 * Akcja: cofniecie wyjatku (admin-post, nonce per wyjatek).
	 *
	 * @return void
	 */
	public static function handle_revoke(): void {
		$exception_id = isset( $_GET['exception'] ) ? absint( $_GET['exception'] ) : 0;
		$product_id   = isset( $_GET['product'] ) ? absint( $_GET['product'] ) : 0;

		check_admin_referer( 'mp_exception_revoke_' . $exception_id );

		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die( esc_html__( 'Brak uprawnień.', 'mp-warranty-registry' ), '', 403 );
		}

		$result = WarrantyExceptions::revoke( $exception_id );

		self::redirect_back(
			$product_id,
			true === $result
			? array(
				'type' => 'success',
				'text' => __( 'Wyjątek cofnięty.', 'mp-warranty-registry' ),
			)
			: array(
				'type' => 'error',
				'text' => (string) $result['error'],
			)
		);
	}

	/**
	 * URL cofniecia wyjatku.
	 *
	 * @param int $exception_id ID wyjatku.
	 * @param int $product_id   ID produktu (powrot na ekran).
	 * @return string
	 */
	private static function revoke_url( int $exception_id, int $product_id ): string {
		return wp_nonce_url(
			add_query_arg(
				array(
					'action'    => 'mp_exception_revoke',
					'exception' => $exception_id,
					'product'   => $product_id,
				),
				admin_url( 'admin-post.php' )
			),
			'mp_exception_revoke_' . $exception_id
		);
	}

	/**
	 * Komunikat do transientu + powrot na ekran wyjatkow produktu.
	 *
	 * @param int                   $product_id ID produktu.
	 * @param array<string, string> $notice     Komunikat {type, text}.
	 * @return never
	 */
	private static function redirect_back( int $product_id, array $notice ): void {
		set_transient( self::NOTICE_TRANSIENT . get_current_user_id(), $notice, 5 * MINUTE_IN_SECONDS );
		wp_safe_redirect(
			add_query_arg(
				array(
					'page'    => self::PAGE_SLUG,
					'product' => $product_id,
				),
				admin_url( 'admin.php' )
			)
		);
		exit;
	}
}
