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

use MP\Registry\Archive;

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
			'mp_agent',
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
}
