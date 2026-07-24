<?php
/**
 * Lista spraw serwisowych dla PERSONELU (WP_List_Table) — kartka krok 7.
 * Model B: caly personel widzi WSZYSTKIE zweryfikowane sprawy. Kolumny: SRV
 * (link do karty) / klient / rodzaj / status / przydzielony / termin SLA / data.
 * Filtry: status, rodzaj, przydzielony + wyszukiwarka (SRV/klient). Sortowanie
 * po WHITELIST kolumn (anty-SQLi — egzekwuje CaseRepo::query_for_staff).
 *
 * @package MP\Intake\Admin
 */

namespace MP\Intake\Admin;

use MP\Intake\CaseRepo;
use MP\Intake\FormConfig;
use MP\Intake\Statuses;

// Bezposredni dostep zablokowany (plik rozszerza WP_List_Table => fatal bez zaladowanego WP).
defined( 'ABSPATH' ) || exit;

if ( ! class_exists( '\WP_List_Table' ) ) {
	require_once ABSPATH . 'wp-admin/includes/class-wp-list-table.php';
}

/**
 * Tabela spraw serwisowych (personel).
 */
final class CasesListTable extends \WP_List_Table {

	/**
	 * Slug strony (do linkow karty).
	 *
	 * @var string
	 */
	private string $page_slug;

	/**
	 * Konstruktor: zapamietuje slug strony (link do karty sprawy).
	 *
	 * @param string $page_slug Slug strony admina.
	 */
	public function __construct( string $page_slug ) {
		$this->page_slug = $page_slug;

		parent::__construct(
			array(
				'singular' => 'sprawa',
				'plural'   => 'sprawy',
				'ajax'     => false,
			)
		);
	}

	/**
	 * Kolumny tabeli.
	 *
	 * @return array<string, string>
	 */
	public function get_columns(): array {
		return array(
			'case_number' => __( 'Nr sprawy', 'mp-service-intake' ),
			'customer'    => __( 'Klient', 'mp-service-intake' ),
			'kind'        => __( 'Rodzaj', 'mp-service-intake' ),
			'status'      => __( 'Status', 'mp-service-intake' ),
			'assigned'    => __( 'Przydzielony', 'mp-service-intake' ),
			'deadline'    => __( 'Termin SLA', 'mp-service-intake' ),
			'created_at'  => __( 'Utworzono', 'mp-service-intake' ),
		);
	}

	/**
	 * Kolumny sortowalne (klucz = whitelist w CaseRepo::query_for_staff).
	 *
	 * @return array<string, array{0: string, 1: bool}>
	 */
	public function get_sortable_columns(): array {
		return array(
			'case_number' => array( 'case_number', false ),
			'status'      => array( 'status', false ),
			'kind'        => array( 'kind', false ),
			'created_at'  => array( 'created_at', true ),
		);
	}

	/**
	 * Ladowanie danych: filtry z GET (odczyt, bez mutacji => bez nonce), paginacja,
	 * sortowanie (whitelist w repo). Personel widzi wszystko (model B).
	 *
	 * @return void
	 */
	public function prepare_items(): void {
		$per_page = 20;
		$paged    = $this->get_pagenum();

		// phpcs:disable WordPress.Security.NonceVerification.Recommended -- GET-owe filtry/sort listy (odczyt, zero mutacji stanu).
		$orderby = isset( $_GET['orderby'] ) ? sanitize_key( wp_unslash( (string) $_GET['orderby'] ) ) : 'created_at';
		$order   = isset( $_GET['order'] ) && 'asc' === strtolower( sanitize_key( wp_unslash( (string) $_GET['order'] ) ) ) ? 'ASC' : 'DESC';

		$filters = array(
			'status'   => isset( $_GET['mp_status'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['mp_status'] ) ) : '',
			'kind'     => isset( $_GET['mp_kind'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['mp_kind'] ) ) : '',
			'assigned' => isset( $_GET['mp_assigned'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['mp_assigned'] ) ) : '',
			'q'        => isset( $_REQUEST['s'] ) ? sanitize_text_field( wp_unslash( (string) $_REQUEST['s'] ) ) : '',
		);
		// phpcs:enable

		$result = CaseRepo::query_for_staff( $filters, $paged, $per_page, $orderby, $order );

		$this->items = $result['rows'];

		$this->set_pagination_args(
			array(
				'total_items' => $result['total'],
				'per_page'    => $per_page,
				'total_pages' => (int) ceil( $result['total'] / $per_page ),
			)
		);

		$this->_column_headers = array( $this->get_columns(), array(), $this->get_sortable_columns(), 'case_number' );
	}

	/**
	 * Domyslny render komorki (escaping twardy).
	 *
	 * @param array<string, mixed> $item   Wiersz sprawy.
	 * @param string               $column Klucz kolumny.
	 * @return string
	 */
	public function column_default( $item, $column ): string {
		switch ( $column ) {
			case 'kind':
				return esc_html( (string) ( $item['kind'] ?? '' ) );
			case 'status':
				return esc_html( Statuses::label( (string) ( $item['status'] ?? '' ) ) );
			case 'created_at':
				$raw = (string) ( $item['created_at'] ?? '' );
				return '' !== $raw ? esc_html( get_date_from_gmt( $raw, 'Y-m-d H:i' ) ) : '—';
			default:
				return '';
		}
	}

	/**
	 * Kolumna SRV — link do karty sprawy.
	 *
	 * @param array<string, mixed> $item Wiersz sprawy.
	 * @return string
	 */
	public function column_case_number( $item ): string {
		$case_id = (int) ( $item['id'] ?? 0 );
		$url     = add_query_arg(
			array(
				'page'    => $this->page_slug,
				'case_id' => $case_id,
			),
			admin_url( 'admin.php' )
		);

		return sprintf(
			'<strong><a href="%s">%s</a></strong>',
			esc_url( $url ),
			esc_html( (string) ( $item['case_number'] ?? ( '#' . $case_id ) ) )
		);
	}

	/**
	 * Kolumna klient — imie + e-mail (personel obsluguje sprawe; escaping).
	 *
	 * @param array<string, mixed> $item Wiersz sprawy.
	 * @return string
	 */
	public function column_customer( $item ): string {
		$name  = (string) ( $item['customer_name'] ?? '' );
		$email = (string) ( $item['customer_email'] ?? '' );

		if ( '' === $name && '' === $email ) {
			return '—';
		}

		$out = '' !== $name ? '<strong>' . esc_html( $name ) . '</strong>' : '';

		if ( '' !== $email ) {
			$out .= ( '' !== $out ? '<br />' : '' ) . '<span style="color:#666">' . esc_html( $email ) . '</span>';
		}

		return $out;
	}

	/**
	 * Kolumna przydzielony — login pracownika albo „nieprzydzielona".
	 *
	 * @param array<string, mixed> $item Wiersz sprawy.
	 * @return string
	 */
	public function column_assigned( $item ): string {
		$uid = isset( $item['assigned_to'] ) && null !== $item['assigned_to'] ? (int) $item['assigned_to'] : 0;

		if ( 0 === $uid ) {
			return '<span style="color:#a33">' . esc_html__( 'nieprzydzielona', 'mp-service-intake' ) . '</span>';
		}

		$user = get_userdata( $uid );

		return esc_html( $user ? (string) $user->display_name : ( '#' . $uid ) );
	}

	/**
	 * Kolumna termin SLA — z kontraktu D (mp_case_deadline). '—' gdy brak.
	 *
	 * @param array<string, mixed> $item Wiersz sprawy.
	 * @return string
	 */
	public function column_deadline( $item ): string {
		$sla = apply_filters( 'mp_case_deadline', null, (int) ( $item['id'] ?? 0 ) );

		if ( ! is_array( $sla ) || empty( $sla['deadline_at'] ) ) {
			return '—';
		}

		$deadline = (string) $sla['deadline_at'];
		$overdue  = strtotime( $deadline . ' UTC' ) < time();
		$label    = esc_html( get_date_from_gmt( $deadline, 'Y-m-d H:i' ) );

		return $overdue
			? '<span style="color:#a33;font-weight:600">' . $label . '</span>'
			: $label;
	}

	/**
	 * Pasek filtrow nad tabela (status / rodzaj / przydzielony). GET => bez nonce.
	 *
	 * @param string $which top|bottom.
	 * @return void
	 */
	protected function extra_tablenav( $which ): void {
		if ( 'top' !== $which ) {
			return;
		}

		// phpcs:disable WordPress.Security.NonceVerification.Recommended -- GET-owe filtry listy (odczyt).
		$cur_status   = isset( $_GET['mp_status'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['mp_status'] ) ) : '';
		$cur_kind     = isset( $_GET['mp_kind'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['mp_kind'] ) ) : '';
		$cur_assigned = isset( $_GET['mp_assigned'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['mp_assigned'] ) ) : '';
		// phpcs:enable

		echo '<div class="alignleft actions">';

		echo '<label class="screen-reader-text" for="mp_status">' . esc_html__( 'Filtr statusu', 'mp-service-intake' ) . '</label>';
		echo '<select name="mp_status" id="mp_status"><option value="">' . esc_html__( 'Status: wszystkie', 'mp-service-intake' ) . '</option>';
		foreach ( Statuses::all() as $slug => $def ) {
			// Statuses::all() normalizuje kazdy wpis => 'label' zawsze obecny (rdzen i custom).
			$label = (string) $def['label'];
			printf(
				'<option value="%s"%s>%s</option>',
				esc_attr( (string) $slug ),
				selected( $cur_status, (string) $slug, false ),
				esc_html( $label )
			);
		}
		echo '</select> ';

		echo '<label class="screen-reader-text" for="mp_kind">' . esc_html__( 'Filtr rodzaju', 'mp-service-intake' ) . '</label>';
		echo '<select name="mp_kind" id="mp_kind"><option value="">' . esc_html__( 'Rodzaj: wszystkie', 'mp-service-intake' ) . '</option>';
		foreach ( FormConfig::KINDS as $kind ) {
			printf(
				'<option value="%s"%s>%s</option>',
				esc_attr( (string) $kind ),
				selected( $cur_kind, (string) $kind, false ),
				esc_html( (string) $kind )
			);
		}
		echo '</select> ';

		echo '<label class="screen-reader-text" for="mp_assigned">' . esc_html__( 'Filtr przydzielenia', 'mp-service-intake' ) . '</label>';
		echo '<select name="mp_assigned" id="mp_assigned">';
		echo '<option value=""' . selected( $cur_assigned, '', false ) . '>' . esc_html__( 'Przydzielony: wszyscy', 'mp-service-intake' ) . '</option>';
		echo '<option value="none"' . selected( $cur_assigned, 'none', false ) . '>' . esc_html__( 'Nieprzydzielone', 'mp-service-intake' ) . '</option>';
		echo '<option value="' . esc_attr( (string) get_current_user_id() ) . '"' . selected( $cur_assigned, (string) get_current_user_id(), false ) . '>' . esc_html__( 'Moje sprawy', 'mp-service-intake' ) . '</option>';
		echo '</select> ';

		submit_button( __( 'Filtruj', 'mp-service-intake' ), '', 'filter_action', false );
		echo '</div>';
	}

	/**
	 * Komunikat pustej listy.
	 *
	 * @return void
	 */
	public function no_items(): void {
		esc_html_e( 'Brak spraw spełniających kryteria.', 'mp-service-intake' );
	}
}
