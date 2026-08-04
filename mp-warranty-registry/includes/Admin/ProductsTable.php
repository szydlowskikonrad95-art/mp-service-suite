<?php
/**
 * WP_List_Table rejestru produktow (lista + paginacja; dane z Search).
 *
 * @package MP\Registry
 */

namespace MP\Registry\Admin;

use MP\Registry\Repo;
use MP\Registry\Search;
use MP\Registry\WarrantyStatus;

if ( ! defined( 'ABSPATH' ) ) {
	exit; // Plik wykonuje require na poziomie pliku — strażnik przed bezpośrednim wejściem.
}

if ( ! class_exists( '\WP_List_Table' ) ) {
	require_once ABSPATH . 'wp-admin/includes/class-wp-list-table.php';
}

/**
 * Tabela produktow w adminie.
 */
final class ProductsTable extends \WP_List_Table {

	/**
	 * Filtry biezacego widoku.
	 *
	 * @var array<string, mixed>
	 */
	private array $filters;

	/**
	 * Tryb wyszukiwania po kliencie (z Search::query).
	 *
	 * @var string
	 */
	public string $customer_mode = 'off';

	/**
	 * Aktywne wyjatki gwarancyjne dla wierszy BIEZACEJ strony: id produktu => wiersz wyjatku.
	 * Wypelniane raz w prepare_items() — patrz Repo::get_active_exceptions_for_products().
	 *
	 * @var array<int, array<string, mixed>>
	 */
	private array $exceptions = array();

	/**
	 * Czy mapa wyjatkow zostala juz zaladowana w prepare_items().
	 *
	 * ⚠️ Osobna flaga, bo PUSTA mapa jest poprawnym wynikiem (zadny produkt na stronie
	 * nie ma wyjatku). Wnioskowanie „pusta => niezaladowana" przywracalo N+1 dokladnie
	 * w najczestszym przypadku.
	 *
	 * @var bool
	 */
	private bool $exceptions_loaded = false;

	/**
	 * Konstruktor.
	 *
	 * @param array<string, mixed> $filters Filtry wyszukiwarki.
	 */
	public function __construct( array $filters ) {
		parent::__construct(
			array(
				'singular' => 'mp_product',
				'plural'   => 'mp_products',
				'ajax'     => false,
			)
		);

		$this->filters = $filters;
	}

	/**
	 * Kolumny tabeli.
	 *
	 * @return array<string, string>
	 */
	public function get_columns(): array {
		return array(
			'serial'  => __( 'Numer seryjny', 'mp-warranty-registry' ),
			'model'   => __( 'Model', 'mp-warranty-registry' ),
			'batch'   => __( 'Partia', 'mp-warranty-registry' ),
			'status'  => __( 'Status gwarancji', 'mp-warranty-registry' ),
			'until'   => __( 'Gwarancja do', 'mp-warranty-registry' ),
			'cases'   => __( 'Sprawy', 'mp-warranty-registry' ),
			'actions' => __( 'Akcje', 'mp-warranty-registry' ),
		);
	}

	/**
	 * Pobiera dane strony listy.
	 *
	 * @return void
	 */
	public function prepare_items(): void {
		$page   = max( 1, (int) $this->get_pagenum() );
		$result = Search::query( $this->filters, $page, Search::PER_PAGE );

		$this->items         = $result['rows'];
		$this->customer_mode = $result['customer_mode'];

		// Wyjatki gwarancyjne dla CALEJ strony jednym zapytaniem. Wczesniej kolumna statusu
		// wolala Repo::get_active_exception() osobno dla kazdego wiersza = 20 zapytan na strone
		// (audyt wydajnosci 30.07).
		$this->exceptions        = Repo::get_active_exceptions_for_products(
			array_map(
				static function ( $row ) {
					return (int) ( $row['id'] ?? 0 );
				},
				(array) $this->items
			)
		);
		$this->exceptions_loaded = true;

		$this->set_pagination_args(
			array(
				'total_items' => $result['total'],
				'per_page'    => Search::PER_PAGE,
				'total_pages' => (int) ceil( $result['total'] / Search::PER_PAGE ),
			)
		);

		$this->_column_headers = array( $this->get_columns(), array(), array() );
	}

	/**
	 * Kolumna: numer seryjny (+ znacznik archiwum).
	 *
	 * @param array<string, mixed> $item Wiersz.
	 * @return string
	 */
	public function column_serial( array $item ): string {
		$serial = esc_html( (string) $item['serial_display'] );

		if ( '1' === (string) $item['archived'] ) {
			$serial .= ' <span class="mp-badge mp-badge-archived">' . esc_html__( 'archiwum', 'mp-warranty-registry' ) . '</span>';
		}

		return $serial;
	}

	/**
	 * Kolumna: status gwarancji (WYLICZANY, sargable poza lista; tu per wiersz)
	 * + znacznik aktywnego wyjatku (wyjatek to NIE status — kontrakt).
	 *
	 * @param array<string, mixed> $item Wiersz.
	 * @return string
	 */
	public function column_status( array $item ): string {
		$status = WarrantyStatus::compute( true, isset( $item['warranty_until'] ) ? (string) $item['warranty_until'] : null, null, null );
		// Klucze ze STALYCH (compute zwraca polskie slugi — angielskie klucze nie
		// trafialy, przez co lista pokazywala surowe „wygasla"/„brak_danych").
		$labels = array(
			WarrantyStatus::ACTIVE       => __( 'aktywna', 'mp-warranty-registry' ),
			WarrantyStatus::EXPIRED      => __( 'wygasła', 'mp-warranty-registry' ),
			WarrantyStatus::NO_DATA      => __( 'brak danych', 'mp-warranty-registry' ),
			WarrantyStatus::VERIFICATION => __( 'wymagana weryfikacja', 'mp-warranty-registry' ),
		);
		$label  = $labels[ $status ] ?? $status;
		$out    = '<span class="mp-badge mp-badge-status mp-badge-status--' . esc_attr( $status ) . '">' . esc_html( $label ) . '</span>';

		// Mapa z prepare_items() (jedno zapytanie na strone). Zapas przez get_active_exception()
		// zostaje na wypadek renderu wiersza poza normalnym przebiegiem tabeli.
		$pid = (int) ( $item['id'] ?? 0 );

		if ( $this->exceptions_loaded ) {
			$exception = $this->exceptions[ $pid ] ?? null;
		} else {
			$exception = Repo::get_active_exception( $pid, null );
		}

		if ( null !== $exception ) {
			$out .= ' <span class="mp-badge mp-badge-exception">' . esc_html__( 'wyjątek', 'mp-warranty-registry' ) . '</span>';
		}

		return $out;
	}

	/**
	 * Kolumna: liczba spraw (dane z C; bez C UCZCIWE "brak danych", nie zero).
	 *
	 * @param array<string, mixed> $item Wiersz.
	 * @return string
	 */
	public function column_cases( array $item ): string {
		$count = apply_filters( 'mp_serial_usage_count', null, (string) $item['serial_display'] );

		if ( null === $count ) {
			return '<em>' . esc_html__( 'brak danych (moduł spraw nieaktywny)', 'mp-warranty-registry' ) . '</em>';
		}

		return esc_html( number_format_i18n( (int) $count ) );
	}

	/**
	 * Kolumna: akcje (wyjatki / archiwizuj / przywroc).
	 *
	 * @param array<string, mixed> $item Wiersz.
	 * @return string
	 */
	public function column_actions( array $item ): string {
		$id  = (int) $item['id'];
		$out = array();

		// Historia egzemplarza — POZA blokiem administratora: pracownik prowadzacy
		// sprawe musi widziec, co i kiedy zmieniano przy tym produkcie. Bez tego
		// linku dziennik `wp_mp_product_events` nie ma zadnego wejscia z ekranu.
		$out[] = '<a href="' . esc_url( ProductsScreen::history_url( $id ) ) . '">'
			. esc_html__( 'historia', 'mp-warranty-registry' ) . '</a>';

		if ( current_user_can( 'mp_system_admin' ) ) {
			$out[] = '<a href="' . esc_url(
				add_query_arg(
					array(
						'page'    => ExceptionsScreen::PAGE_SLUG,
						'product' => $id,
					),
					admin_url( 'admin.php' )
				)
			) . '">' . esc_html__( 'wyjątki', 'mp-warranty-registry' ) . '</a>';

			// Poprawianie danych ma sens tylko dla wpisu czynnego — archiwalny najpierw
			// sie przywraca (`Repo::update()` odbija archiwalne, wiec link tez nie kusi).
			if ( '1' !== (string) $item['archived'] ) {
				$out[] = '<a href="' . esc_url(
					add_query_arg(
						array(
							'page' => ProductsScreen::PAGE_SLUG,
							'edit' => $id,
						),
						admin_url( 'admin.php' )
					)
				) . '">' . esc_html__( 'popraw dane', 'mp-warranty-registry' ) . '</a>';
			}

			$archive_action = '1' === (string) $item['archived'] ? 'mp_product_restore' : 'mp_product_archive';
			$archive_label  = '1' === (string) $item['archived']
				? __( 'przywróć', 'mp-warranty-registry' )
				: __( 'archiwizuj', 'mp-warranty-registry' );

			$out[] = '<a href="' . esc_url(
				wp_nonce_url(
					add_query_arg(
						array(
							'action'  => $archive_action,
							'product' => $id,
						),
						admin_url( 'admin-post.php' )
					),
					$archive_action . '_' . $id
				)
			) . '">' . esc_html( $archive_label ) . '</a>';
		}

		return implode( ' · ', $out );
	}

	/**
	 * Domyslny render kolumny.
	 *
	 * @param array<string, mixed> $item        Wiersz.
	 * @param string               $column_name Nazwa kolumny.
	 * @return string
	 */
	public function column_default( $item, $column_name ): string {
		switch ( $column_name ) {
			case 'model':
				return esc_html( (string) $item['model'] );
			case 'batch':
				return esc_html( (string) $item['batch'] );
			case 'until':
				return esc_html( (string) ( $item['warranty_until'] ?? '—' ) );
			default:
				return '';
		}
	}
}
