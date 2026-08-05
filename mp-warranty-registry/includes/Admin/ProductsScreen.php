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

use MP\Registry\Assets;
use MP\Registry\Archive;
use MP\Registry\Categories;
use MP\Registry\ProductEvents;
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
		// nopriv -> ten sam handler: anon dostaje JAWNE 403 (security-sweep kryteria odbioru sekcja 3).
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
			Assets::ver( 'assets/css/admin-registry.css' )
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
			Roles::registry_menu_cap(),
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
		// ⛔ TEN SAM warunek co pozycja w menu — patrz `Roles::REGISTRY_CAPS`.
		// Wczesniej menu i ekran pytaly o co innego, wiec koordynator widzial drzwi
		// i dostawal odmowe. Ta bramka zostaje: menu chowa pozycje, a ekran broni
		// wejscia z palca w adres.
		if ( ! Roles::can_current_user_see_registry() ) {
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

		// Historia egzemplarza (`?page=mp-registry&historia=ID`) — ten sam wzorzec
		// „widok pod adresem menu" co poprawianie danych. Dostepna dla personelu,
		// nie tylko dla administratora: pracownik prowadzacy sprawe musi widziec,
		// czy dane produktu zmieniano i czy zapadala decyzja gwarancyjna.
		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- wybor widoku z GET; widok tylko czyta.
		$history_id = isset( $_GET['historia'] ) ? absint( $_GET['historia'] ) : 0;

		if ( $history_id > 0 ) {
			self::render_history( $history_id );
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
	 * Widok poprawiania danych produktu (specyfikacja: „historia zmian danych produktu").
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
				<a href="<?php echo esc_url( self::history_url( $product_id ) ); ?>"><?php esc_html_e( 'Pokaż historię egzemplarza', 'mp-warranty-registry' ); ?></a>
				&nbsp;·&nbsp;
				<a href="<?php echo esc_url( $powrot ); ?>"><?php esc_html_e( 'Wróć do rejestru', 'mp-warranty-registry' ); ?></a>
			</form>
		</div>
		<?php
	}

	/**
	 * Adres widoku historii egzemplarza.
	 *
	 * @param int $product_id ID produktu.
	 * @return string
	 */
	public static function history_url( int $product_id ): string {
		return add_query_arg(
			array(
				'page'     => self::PAGE_SLUG,
				'historia' => $product_id,
			),
			admin_url( 'admin.php' )
		);
	}

	/**
	 * Widok historii egzemplarza (specyfikacja: „historia zmian danych produktu
	 * i decyzji gwarancyjnych").
	 *
	 * ⛔ Dziennik `wp_mp_product_events` byl do 1.3.12 zapisywany i nieczytany —
	 * ten widok jest jego pierwszym i jedynym czytelnikiem.
	 *
	 * @param int $product_id ID produktu.
	 * @return void
	 */
	private static function render_history( int $product_id ): void {
		$produkt = Repo::find_by_id( $product_id );

		if ( null === $produkt ) {
			wp_die( esc_html__( 'Produkt nie istnieje w rejestrze.', 'mp-warranty-registry' ), '', 404 );
		}

		$limit  = 100;
		$wpisy  = ProductEvents::history( $product_id, $limit );
		$ile    = ProductEvents::history_count( $product_id );
		$powrot = add_query_arg( 'page', self::PAGE_SLUG, admin_url( 'admin.php' ) );
		?>
		<div class="wrap mp-registry">
			<h1><?php esc_html_e( 'Historia egzemplarza', 'mp-warranty-registry' ); ?></h1>

			<p>
				<code><?php echo esc_html( (string) $produkt['serial_display'] ); ?></code>
				<?php if ( '' !== (string) $produkt['model'] ) : ?>
					· <?php echo esc_html( (string) $produkt['model'] ); ?>
				<?php endif; ?>
			</p>

			<?php if ( array() === $wpisy ) : ?>
				<p class="description">
					<?php esc_html_e( 'Ten egzemplarz nie ma jeszcze żadnego wpisu w historii. Wpis powstaje przy poprawce danych produktu, przy archiwizacji i przy każdej decyzji gwarancyjnej.', 'mp-warranty-registry' ); ?>
				</p>
			<?php else : ?>
				<?php if ( $ile > count( $wpisy ) ) : ?>
					<p class="description">
						<?php
						printf(
							/* translators: 1: ile wpisow pokazano, 2: ile wpisow ma historia. */
							esc_html__( 'Pokazujemy %1$d najnowszych wpisów z %2$d.', 'mp-warranty-registry' ),
							(int) count( $wpisy ),
							(int) $ile
						);
						?>
					</p>
				<?php endif; ?>

				<table class="widefat striped">
					<thead>
						<tr>
							<th scope="col"><?php esc_html_e( 'Kiedy', 'mp-warranty-registry' ); ?></th>
							<th scope="col"><?php esc_html_e( 'Co się stało', 'mp-warranty-registry' ); ?></th>
							<th scope="col"><?php esc_html_e( 'Kto', 'mp-warranty-registry' ); ?></th>
							<th scope="col"><?php esc_html_e( 'Szczegóły', 'mp-warranty-registry' ); ?></th>
						</tr>
					</thead>
					<tbody>
						<?php foreach ( $wpisy as $wpis ) : ?>
							<?php $opis = self::describe_event( $wpis ); ?>
							<tr>
								<td><?php echo esc_html( get_date_from_gmt( (string) $wpis['created_at'], 'Y-m-d H:i' ) ); ?></td>
								<td><?php echo esc_html( (string) $opis['label'] ); ?></td>
								<td><?php echo esc_html( self::actor_name( $wpis['actor_id'] ) ); ?></td>
								<td>
									<?php if ( array() === $opis['details'] ) : ?>
										—
									<?php else : ?>
										<?php echo esc_html( implode( ' ', $opis['details'] ) ); ?>
									<?php endif; ?>
								</td>
							</tr>
						<?php endforeach; ?>
					</tbody>
				</table>
			<?php endif; ?>

			<p>
				<?php if ( current_user_can( 'mp_system_admin' ) && empty( $produkt['archived'] ) ) : ?>
					<?php
					$edit_url = add_query_arg(
						array(
							'page' => self::PAGE_SLUG,
							'edit' => $product_id,
						),
						admin_url( 'admin.php' )
					);
					?>
					<a href="<?php echo esc_url( $edit_url ); ?>"><?php esc_html_e( 'Popraw dane produktu', 'mp-warranty-registry' ); ?></a>
					&nbsp;·&nbsp;
				<?php endif; ?>
				<a href="<?php echo esc_url( $powrot ); ?>"><?php esc_html_e( 'Wróć do rejestru', 'mp-warranty-registry' ); ?></a>
			</p>
		</div>
		<?php
	}

	/**
	 * Zamienia wpis dziennika na zdanie po polsku.
	 *
	 * Funkcja czysta (bez bazy i bez stanu) — dzieki temu da sie ja sprawdzic
	 * osobno, bez klikania po ekranie.
	 *
	 * @param array<string, mixed> $row Wpis z ProductEvents::history().
	 * @return array{label: string, details: array<int, string>}
	 */
	public static function describe_event( array $row ): array {
		$type    = (string) ( $row['event_type'] ?? '' );
		$payload = isset( $row['payload'] ) && is_array( $row['payload'] ) ? $row['payload'] : array();
		// Wersja ksztaltu wpisu jest kluczem TECHNICZNYM, nie zmiana danych produktu —
		// bez tego ekran pokazywalby wiersz „schema_version: (puste) -> 1".
		$payload = ProductEvents::pola_zmian( $payload );

		if ( ProductEvents::EXCEPTION_CREATED === $type || ProductEvents::EXCEPTION_REVOKED === $type ) {
			$label = ProductEvents::EXCEPTION_CREATED === $type
				? __( 'Nadano wyjątek gwarancyjny', 'mp-warranty-registry' )
				: __( 'Cofnięto wyjątek gwarancyjny', 'mp-warranty-registry' );

			$details = array();

			if ( isset( $payload['typ'] ) ) {
				$details[] = 'per-sprawa' === (string) $payload['typ']
					? __( 'Zakres: jedna sprawa.', 'mp-warranty-registry' )
					: __( 'Zakres: cały egzemplarz.', 'mp-warranty-registry' );
			}

			if ( ! empty( $payload['exception_id'] ) ) {
				$details[] = sprintf(
					/* translators: %d: numer wpisu wyjatku gwarancyjnego. */
					__( 'Wyjątek nr %d.', 'mp-warranty-registry' ),
					(int) $payload['exception_id']
				);
			}

			$details[] = __( 'Uzasadnienia nie zapisujemy w historii — jest przy samym wyjątku.', 'mp-warranty-registry' );

			return array(
				'label'   => $label,
				'details' => $details,
			);
		}

		if ( 'PRODUCT_UPDATED' === $type ) {
			// Archiwizacja jedzie tym samym typem zdarzenia co poprawka danych
			// (`Archive` i `Repo::update()` — swiadomie jeden ksztalt payloadu).
			// Dla czlowieka to jednak dwie rozne rzeczy, wiec je rozdzielamy.
			if ( array( 'archived' ) === array_keys( $payload ) ) {
				$do_archiwum = 1 === (int) ( $payload['archived']['after'] ?? 0 );

				return array(
					'label'   => $do_archiwum
						? __( 'Przeniesiono do archiwum', 'mp-warranty-registry' )
						: __( 'Przywrócono z archiwum', 'mp-warranty-registry' ),
					'details' => array(),
				);
			}

			$details = array();

			foreach ( $payload as $field => $zmiana ) {
				$details[] = self::describe_change( (string) $field, $zmiana );
			}

			return array(
				'label'   => __( 'Poprawiono dane produktu', 'mp-warranty-registry' ),
				'details' => $details,
			);
		}

		return array(
			'label'   => $type,
			'details' => array(),
		);
	}

	/**
	 * Jedna zmiana pola jako zdanie („Model: «A» → «B».").
	 *
	 * @param string $field  Nazwa pola.
	 * @param mixed  $zmiana Wpis diffu: {before, after} albo {field, changed} dla PII.
	 * @return string
	 */
	private static function describe_change( string $field, $zmiana ): string {
		$etykieta = self::field_label( $field );

		// Pola wrazliwe maja w dzienniku SAM FAKT zmiany, bez wartosci
		// (`ProductEvents::sanitize_payload()`) — i tak ma zostac na ekranie.
		if ( is_array( $zmiana ) && ! empty( $zmiana['changed'] ) && ! array_key_exists( 'after', $zmiana ) ) {
			return sprintf(
				/* translators: %s: nazwa pola. */
				__( '%s: zmieniony (wartości nie zapisujemy — dane wrażliwe).', 'mp-warranty-registry' ),
				$etykieta
			);
		}

		if ( ! is_array( $zmiana ) ) {
			return sprintf(
				/* translators: %s: nazwa pola. */
				__( '%s: zmieniony.', 'mp-warranty-registry' ),
				$etykieta
			);
		}

		return sprintf(
			/* translators: 1: nazwa pola, 2: wartosc przed zmiana, 3: wartosc po zmianie. */
			__( '%1$s: „%2$s" → „%3$s".', 'mp-warranty-registry' ),
			$etykieta,
			self::format_value( $zmiana['before'] ?? null ),
			self::format_value( $zmiana['after'] ?? null )
		);
	}

	/**
	 * Wartosc pola do pokazania (puste = jawne „puste", nie pusty napis).
	 *
	 * @param mixed $value Wartosc.
	 * @return string
	 */
	private static function format_value( $value ): string {
		if ( null === $value || '' === $value ) {
			return __( '(puste)', 'mp-warranty-registry' );
		}

		if ( is_array( $value ) ) {
			return __( '(zmieniono)', 'mp-warranty-registry' );
		}

		return (string) $value;
	}

	/**
	 * Nazwa pola po polsku (klucze kolumn nic nie mowia pracownikowi).
	 *
	 * @param string $field Klucz pola.
	 * @return string
	 */
	private static function field_label( string $field ): string {
		$mapa = array(
			'model'             => __( 'Model', 'mp-warranty-registry' ),
			'batch'             => __( 'Partia produkcyjna', 'mp-warranty-registry' ),
			'category'          => __( 'Kategoria', 'mp-warranty-registry' ),
			'purchase_document' => __( 'Dokument zakupu', 'mp-warranty-registry' ),
			'purchase_date'     => __( 'Data zakupu', 'mp-warranty-registry' ),
			'warranty_until'    => __( 'Gwarancja do', 'mp-warranty-registry' ),
			'archived'          => __( 'Archiwum', 'mp-warranty-registry' ),
		);

		return $mapa[ $field ] ?? $field;
	}

	/**
	 * Kto stoi za wpisem — nazwa konta, a nie samo ID.
	 *
	 * @param int|null $actor_id ID uzytkownika albo null (system).
	 * @return string
	 */
	private static function actor_name( ?int $actor_id ): string {
		if ( null === $actor_id || $actor_id <= 0 ) {
			return __( 'system', 'mp-warranty-registry' );
		}

		$user = get_userdata( $actor_id );

		if ( false === $user ) {
			return sprintf(
				/* translators: %d: ID usunietego konta. */
				__( 'konto usunięte (#%d)', 'mp-warranty-registry' ),
				$actor_id
			);
		}

		return (string) $user->display_name;
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
