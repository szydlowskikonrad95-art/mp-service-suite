<?php
/**
 * Ekran admina: rejestr produktow (lista + wyszukiwarka + archiwum).
 *
 * Wyszukiwarka wg karty B: serial / klient / faktura / model.
 * Pole "klient" dziala TYLKO z zywym modulem spraw (C) — degraded mode:
 * pole nieaktywne z komunikatem (kontrakt P2.6).
 *
 * @package MP\Registry
 */

namespace MP\Registry\Admin;

use MP\Registry\Common\Roles;

use MP\Registry\Archive;
use MP\Registry\Categories;
use MP\Registry\Repo;

/**
 * Rejestracja menu, render listy, akcje archiwum.
 */
final class ProductsScreen {

	/**
	 * Slug strony glownej rejestru.
	 */
	public const PAGE_SLUG = 'mp-registry';

	/**
	 * Prefiks transientu komunikatu (per user).
	 */
	public const NOTICE_TRANSIENT = 'mp_products_notice_';

	/**
	 * Rejestruje hooki admina.
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_menu', array( self::class, 'add_menu' ), 9 );
		add_action( 'admin_enqueue_scripts', array( self::class, 'enqueue' ) );
		add_action( 'admin_post_mp_product_archive', array( self::class, 'handle_archive' ) );
		add_action( 'admin_post_mp_product_restore', array( self::class, 'handle_restore' ) );
		add_action( 'admin_post_mp_product_edit', array( self::class, 'handle_edit' ) );
		// Wersja `nopriv` NIE otwiera akcji dla niezalogowanych — handler i tak zaczyna od
		// check_admin_referer(), ktory ich odbija. Chodzi o KOD ODPOWIEDZI: bez tej rejestracji
		// WordPress konczy wlasnym 400 („nieprawidlowe zadanie"), a reszta naszych endpointow
		// oddaje 403. Macierz bezpieczenstwa wymaga 403 wszedzie — zlapane przez CI.
		add_action( 'admin_post_nopriv_mp_product_edit', array( self::class, 'handle_edit' ) );
		// nopriv -> ten sam handler: anon dostaje JAWNE 403 (security-sweep DoD sekcja 3).
		add_action( 'admin_post_nopriv_mp_product_archive', array( self::class, 'handle_archive' ) );
		add_action( 'admin_post_nopriv_mp_product_restore', array( self::class, 'handle_restore' ) );
	}

	/**
	 * Hook suffix strony (do enqueue tylko u nas).
	 *
	 * @var string
	 */
	private static string $hook_suffix = '';

	/**
	 * Laduje CSS wylacznie na liscie produktow.
	 *
	 * @param string $hook Hook suffix biezacej strony admina.
	 * @return void
	 */
	public static function enqueue( string $hook ): void {
		if ( '' === self::$hook_suffix || $hook !== self::$hook_suffix ) {
			return;
		}

		wp_enqueue_style(
			'mp-registry-admin',
			plugin_dir_url( MP_REGISTRY_FILE ) . 'assets/css/admin-registry.css',
			array(),
			MP_REGISTRY_VERSION
		);
	}

	/**
	 * Menu: Rejestr MP (lista produktow) — personel serwisu.
	 *
	 * Lista/wyszukiwarka za cap mp_agent (agent pracuje z rejestrem przy
	 * sprawach); operacje na danych (archiwum/wyjatki/import) osobno za
	 * mp_system_admin. Pelna macierz: SECURITY.md (D2).
	 *
	 * @return void
	 */
	public static function add_menu(): void {
		self::$hook_suffix = (string) add_menu_page(
			__( 'Rejestr produktów MP', 'mp-warranty-registry' ),
			__( 'Rejestr MP', 'mp-warranty-registry' ),
			Roles::menu_cap_for_current_user(),
			self::PAGE_SLUG,
			array( self::class, 'render' ),
			'dashicons-database'
		);
	}

	/**
	 * Render listy produktow z wyszukiwarka.
	 *
	 * @return void
	 */
	public static function render(): void {
		if ( ! current_user_can( 'mp_agent' ) && ! current_user_can( 'mp_system_admin' ) ) {
			wp_die( esc_html__( 'Brak uprawnień do rejestru produktów.', 'mp-warranty-registry' ) );
		}

		// Ekran poprawiania danych produktu — osobny widok pod tym samym adresem menu
		// (`?page=mp-registry&edit=ID`), zeby nie mnozyc pozycji w menu dla czynnosci,
		// ktora zdarza sie rzadko: poprawka literowki po imporcie z systemu firmy.
		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- wybor widoku z GET; nic nie mutuje, zapis idzie POST-em z tokenem.
		$edit_id = isset( $_GET['edit'] ) ? absint( $_GET['edit'] ) : 0;

		if ( $edit_id > 0 ) {
			self::render_edit( $edit_id );
			return;
		}

		// phpcs:disable WordPress.Security.NonceVerification.Recommended -- filtry wyszukiwarki: odczyt bez zmiany stanu (GET).
		$filters = array(
			'serial'           => isset( $_GET['f_serial'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['f_serial'] ) ) : '',
			'model'            => isset( $_GET['f_model'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['f_model'] ) ) : '',
			'invoice'          => isset( $_GET['f_invoice'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['f_invoice'] ) ) : '',
			'customer'         => isset( $_GET['f_customer'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['f_customer'] ) ) : '',
			'include_archived' => isset( $_GET['f_archived'] ) && '1' === $_GET['f_archived'],
		);
		// phpcs:enable

		$table = new ProductsTable( $filters );
		$table->prepare_items();

		$notice = get_transient( self::NOTICE_TRANSIENT . get_current_user_id() );

		if ( false !== $notice ) {
			delete_transient( self::NOTICE_TRANSIENT . get_current_user_id() );
		}

		$customer_available = has_filter( 'mp_customer_find_products' );
		?>
		<div class="wrap mp-registry">
			<h1><?php esc_html_e( 'Rejestr produktów MP', 'mp-warranty-registry' ); ?></h1>

			<?php if ( is_array( $notice ) ) : ?>
				<div class="notice notice-<?php echo esc_attr( (string) $notice['type'] ); ?>"><p><?php echo esc_html( (string) $notice['text'] ); ?></p></div>
			<?php endif; ?>

			<?php if ( 'truncated' === $table->customer_mode ) : ?>
				<div class="notice notice-warning"><p><?php esc_html_e( 'Wynik wyszukiwania po kliencie został przycięty — doprecyzuj zapytanie (np. pełny e-mail zamiast fragmentu nazwiska).', 'mp-warranty-registry' ); ?></p></div>
			<?php endif; ?>

			<?php if ( 'unavailable' === $table->customer_mode ) : ?>
				<div class="notice notice-warning"><p><?php esc_html_e( 'Wyszukiwanie po kliencie wymaga aktywnego modułu zgłoszeń (mp-service-intake) — filtr klienta został pominięty.', 'mp-warranty-registry' ); ?></p></div>
			<?php endif; ?>

			<form method="get">
				<input type="hidden" name="page" value="<?php echo esc_attr( self::PAGE_SLUG ); ?>" />
				<p class="mp-registry-filters">
					<label><?php esc_html_e( 'Serial', 'mp-warranty-registry' ); ?>
						<input type="text" name="f_serial" value="<?php echo esc_attr( (string) $filters['serial'] ); ?>" /></label>
					<label><?php esc_html_e( 'Model', 'mp-warranty-registry' ); ?>
						<input type="text" name="f_model" value="<?php echo esc_attr( (string) $filters['model'] ); ?>" /></label>
					<label><?php esc_html_e( 'Faktura', 'mp-warranty-registry' ); ?>
						<input type="text" name="f_invoice" value="<?php echo esc_attr( (string) $filters['invoice'] ); ?>" /></label>
					<label><?php esc_html_e( 'Klient', 'mp-warranty-registry' ); ?>
						<input type="text" name="f_customer" value="<?php echo esc_attr( (string) $filters['customer'] ); ?>"
							<?php disabled( ! $customer_available ); ?>
							<?php if ( ! $customer_available ) : ?>
								title="<?php esc_attr_e( 'Wymaga aktywnego modułu zgłoszeń (mp-service-intake).', 'mp-warranty-registry' ); ?>"
							<?php endif; ?> /></label>
					<label><input type="checkbox" name="f_archived" value="1" <?php checked( $filters['include_archived'] ); ?> />
						<?php esc_html_e( 'pokaż archiwalne', 'mp-warranty-registry' ); ?></label>
					<?php submit_button( __( 'Szukaj', 'mp-warranty-registry' ), 'secondary', 'submit', false ); ?>
				</p>
			</form>

			<?php $table->display(); ?>
		</div>
		<?php
	}

	/**
	 * Akcja: archiwizuj produkt (admin-post, nonce per produkt).
	 *
	 * @return void
	 */
	public static function handle_archive(): void {
		self::handle_toggle( 'mp_product_archive' );
	}

	/**
	 * Akcja: przywroc produkt (admin-post, nonce per produkt).
	 *
	 * @return void
	 */
	public static function handle_restore(): void {
		self::handle_toggle( 'mp_product_restore' );
	}

	/**
	 * Wspolna obsluga archiwizacji/przywrocenia.
	 *
	 * @param string $action Nazwa akcji (klucz nonce).
	 * @return void
	 */
	private static function handle_toggle( string $action ): void {
		$product_id = isset( $_GET['product'] ) ? absint( $_GET['product'] ) : 0;

		check_admin_referer( $action . '_' . $product_id );

		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die( esc_html__( 'Brak uprawnień.', 'mp-warranty-registry' ), '', 403 );
		}

		$result = 'mp_product_archive' === $action
			? Archive::archive( $product_id )
			: Archive::restore( $product_id );

		$notice = true === $result
			? array(
				'type' => 'success',
				'text' => 'mp_product_archive' === $action
					? __( 'Produkt zarchiwizowany.', 'mp-warranty-registry' )
					: __( 'Produkt przywrócony z archiwum.', 'mp-warranty-registry' ),
			)
			: array(
				'type' => 'error',
				'text' => (string) $result['error'],
			);

		set_transient( self::NOTICE_TRANSIENT . get_current_user_id(), $notice, 5 * MINUTE_IN_SECONDS );
		wp_safe_redirect( add_query_arg( 'page', self::PAGE_SLUG, admin_url( 'admin.php' ) ) );
		exit;
	}

	/**
	 * Widok poprawiania danych produktu (kartka: „historia zmian danych produktu").
	 *
	 * Numer seryjny pokazujemy, ale tylko do odczytu — jest kluczem, po ktorym sprawy
	 * trzymaja sie produktu (patrz `Repo::EDITABLE_FIELDS`).
	 *
	 * @param int $product_id ID produktu.
	 * @return void
	 */
	private static function render_edit( int $product_id ): void {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die( esc_html__( 'Brak uprawnień do poprawiania danych produktu.', 'mp-warranty-registry' ), '', 403 );
		}

		$produkt = Repo::find_by_id( $product_id );

		if ( null === $produkt ) {
			wp_die( esc_html__( 'Produkt nie istnieje w rejestrze.', 'mp-warranty-registry' ), '', 404 );
		}

		$notice = get_transient( self::NOTICE_TRANSIENT . get_current_user_id() );

		if ( false !== $notice ) {
			delete_transient( self::NOTICE_TRANSIENT . get_current_user_id() );
		}

		$powrot = add_query_arg( 'page', self::PAGE_SLUG, admin_url( 'admin.php' ) );
		?>
		<div class="wrap mp-registry">
			<h1><?php esc_html_e( 'Popraw dane produktu', 'mp-warranty-registry' ); ?></h1>

			<?php if ( is_array( $notice ) ) : ?>
				<div class="notice notice-<?php echo esc_attr( (string) $notice['type'] ); ?>"><p><?php echo esc_html( (string) $notice['text'] ); ?></p></div>
			<?php endif; ?>

			<?php if ( ! empty( $produkt['archived'] ) ) : ?>
				<div class="notice notice-warning"><p><?php esc_html_e( 'Produkt jest w archiwum — przywróć go, żeby móc poprawić dane.', 'mp-warranty-registry' ); ?></p></div>
			<?php endif; ?>

			<p class="description">
				<?php esc_html_e( 'Zmiana zapisuje się w historii produktu: kto, kiedy i co poprawił. Numeru seryjnego nie da się zmienić — sprawy klientów są z nim powiązane. Jeśli numer jest błędny, zarchiwizuj wpis i zaimportuj poprawny.', 'mp-warranty-registry' ); ?>
			</p>

			<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
				<input type="hidden" name="action" value="mp_product_edit" />
				<input type="hidden" name="product" value="<?php echo esc_attr( (string) $product_id ); ?>" />
				<?php wp_nonce_field( 'mp_product_edit_' . $product_id ); ?>

				<table class="form-table" role="presentation">
					<tr>
						<th scope="row"><?php esc_html_e( 'Numer seryjny', 'mp-warranty-registry' ); ?></th>
						<td>
							<code><?php echo esc_html( (string) $produkt['serial_display'] ); ?></code>
							<p class="description"><?php esc_html_e( 'Tylko do odczytu.', 'mp-warranty-registry' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="mp-f-model"><?php esc_html_e( 'Model', 'mp-warranty-registry' ); ?></label></th>
						<td><input type="text" class="regular-text" id="mp-f-model" name="model" value="<?php echo esc_attr( (string) $produkt['model'] ); ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><label for="mp-f-batch"><?php esc_html_e( 'Partia produkcyjna', 'mp-warranty-registry' ); ?></label></th>
						<td><input type="text" class="regular-text" id="mp-f-batch" name="batch" value="<?php echo esc_attr( (string) $produkt['batch'] ); ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><label for="mp-f-category"><?php esc_html_e( 'Kategoria', 'mp-warranty-registry' ); ?></label></th>
						<td>
							<select id="mp-f-category" name="category">
								<?php foreach ( Categories::all() as $slug => $label ) : ?>
									<option value="<?php echo esc_attr( (string) $slug ); ?>" <?php selected( (string) $produkt['category'], (string) $slug ); ?>>
										<?php echo esc_html( (string) $label ); ?>
									</option>
								<?php endforeach; ?>
							</select>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="mp-f-document"><?php esc_html_e( 'Dokument zakupu', 'mp-warranty-registry' ); ?></label></th>
						<td><input type="text" class="regular-text" id="mp-f-document" name="purchase_document" value="<?php echo esc_attr( (string) $produkt['purchase_document'] ); ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><label for="mp-f-purchase"><?php esc_html_e( 'Data zakupu', 'mp-warranty-registry' ); ?></label></th>
						<td>
							<input type="text" id="mp-f-purchase" name="purchase_date" value="<?php echo esc_attr( null === $produkt['purchase_date'] ? '' : (string) $produkt['purchase_date'] ); ?>" placeholder="RRRR-MM-DD" />
							<p class="description"><?php esc_html_e( 'Format RRRR-MM-DD albo DD.MM.RRRR. Puste = brak daty.', 'mp-warranty-registry' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="mp-f-warranty"><?php esc_html_e( 'Gwarancja do', 'mp-warranty-registry' ); ?></label></th>
						<td>
							<input type="text" id="mp-f-warranty" name="warranty_until" value="<?php echo esc_attr( null === $produkt['warranty_until'] ? '' : (string) $produkt['warranty_until'] ); ?>" placeholder="RRRR-MM-DD" />
							<p class="description"><?php esc_html_e( 'Ta data decyduje o statusie gwarancji w zgłoszeniach.', 'mp-warranty-registry' ); ?></p>
						</td>
					</tr>
				</table>

				<?php submit_button( __( 'Zapisz zmiany', 'mp-warranty-registry' ) ); ?>
				<a href="<?php echo esc_url( $powrot ); ?>"><?php esc_html_e( 'Wróć do rejestru', 'mp-warranty-registry' ); ?></a>
			</form>
		</div>
		<?php
	}

	/**
	 * Akcja: zapis poprawionych danych produktu (admin-post, nonce per produkt).
	 *
	 * @return void
	 */
	public static function handle_edit(): void {
		$product_id = isset( $_POST['product'] ) ? absint( $_POST['product'] ) : 0;

		check_admin_referer( 'mp_product_edit_' . $product_id );

		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die( esc_html__( 'Brak uprawnień do poprawiania danych produktu.', 'mp-warranty-registry' ), '', 403 );
		}

		$pola = array();

		// phpcs:disable WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		foreach ( Repo::EDITABLE_FIELDS as $field ) {
			if ( isset( $_POST[ $field ] ) ) {
				$pola[ $field ] = sanitize_text_field( wp_unslash( (string) $_POST[ $field ] ) );
			}
		}
		// phpcs:enable

		$wynik = Repo::update( $product_id, $pola, get_current_user_id() );

		if ( isset( $wynik['error'] ) ) {
			$notice = array(
				'type' => 'error',
				'text' => (string) $wynik['error'],
			);
		} elseif ( 0 === (int) $wynik['changed'] ) {
			$notice = array(
				'type' => 'info',
				'text' => __( 'Nic nie zmieniono — dane są takie same jak wcześniej.', 'mp-warranty-registry' ),
			);
		} else {
			$notice = array(
				'type' => 'success',
				'text' => sprintf(
					/* translators: %d: liczba poprawionych pol. */
					_n( 'Zapisano zmianę w %d polu. Wpis trafił do historii produktu.', 'Zapisano zmiany w %d polach. Wpis trafił do historii produktu.', (int) $wynik['changed'], 'mp-warranty-registry' ),
					(int) $wynik['changed']
				),
			);
		}

		set_transient( self::NOTICE_TRANSIENT . get_current_user_id(), $notice, 5 * MINUTE_IN_SECONDS );

		// Przy bledzie wracamy na formularz (user poprawia), przy sukcesie na liste.
		$cel = isset( $wynik['error'] )
			? add_query_arg(
				array(
					'page' => self::PAGE_SLUG,
					'edit' => $product_id,
				),
				admin_url( 'admin.php' )
			)
			: add_query_arg( 'page', self::PAGE_SLUG, admin_url( 'admin.php' ) );

		wp_safe_redirect( $cel );
		exit;
	}
}
