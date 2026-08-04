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
			'temat'       => __( 'Czego dotyczy', 'mp-service-intake' ),
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

		// Terminy SLA dla CALEJ strony jednym zapytaniem (kontrakt hurtowy `mp_case_deadlines`).
		// Wczesniej kolumna terminu wolala `mp_case_deadline` osobno dla kazdego wiersza
		// = 20 zapytan na strone (audyt wydajnosci 30.07).
		$ids       = array_map(
			static function ( $row ) {
				return (int) ( $row['id'] ?? 0 );
			},
			(array) $this->items
		);
		$deadlines = apply_filters( 'mp_case_deadlines', null, $ids );

		// null => wariantu hurtowego nikt nie obsluguje (np. starszy modul D).
		// Wtedy mapa zostaje pusta, flaga NIE wstaje i kolumna spada na `mp_case_deadline`.
		if ( is_array( $deadlines ) ) {
			$this->deadlines        = $deadlines;
			$this->deadlines_loaded = true;
		}

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
				return esc_html( FormConfig::kind_label( (string) ( $item['kind'] ?? '' ) ) );
			case 'status':
				return self::status_badge( (string) ( $item['status'] ?? '' ) );
			case 'created_at':
				$raw = (string) ( $item['created_at'] ?? '' );
				return '' !== $raw ? esc_html( get_date_from_gmt( $raw, 'Y-m-d H:i' ) ) : '—';
			default:
				return '';
		}
	}

	/**
	 * Kolorowa plakietka statusu (czytelnosc na liscie). Kolor per status rdzenia;
	 * status custom (filtr) => neutralny szary. Styl inline (brak osobnego admin-CSS).
	 *
	 * @param string $status Slug statusu.
	 * @return string HTML plakietki.
	 */
	private static function status_badge( string $status ): string {
		$color = Statuses::badge_color( $status );

		return sprintf(
			'<span style="display:inline-block;padding:.16em .62em;border-radius:999px;font-size:.82em;font-weight:600;line-height:1.5;color:#fff;background:%1$s">%2$s</span>',
			esc_attr( $color ),
			esc_html( Statuses::label( $status ) )
		);
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
			// Neutralny szary, NIE czerwony. Brak przydziału to zwykły stan
			// początkowy, a nie awaria — gdy świecił na czerwono w każdym
			// wierszu, oko przestawało go zauważać i realna pilność (termin
			// po czasie) nie miała się czym wyróżnić (audyt uzytecznosci).
			return '<span style="color:#646970">' . esc_html__( 'nieprzydzielona', 'mp-service-intake' ) . '</span>';
		}

		$user = get_userdata( $uid );

		return esc_html( $user ? (string) $user->display_name : ( '#' . $uid ) );
	}

	/**
	 * Terminy SLA dla wierszy BIEZACEJ strony: id sprawy => {deadline_at,warning_at,status}.
	 * Pobierane raz przez hurtowy kontrakt `mp_case_deadlines` (patrz prepare_items).
	 *
	 * @var array<int, array<string, mixed>>
	 */
	private array $deadlines = array();

	/**
	 * Czy mapa terminow zostala zaladowana. Osobna flaga, bo PUSTA mapa jest poprawnym
	 * wynikiem (zadna sprawa na stronie nie ma jeszcze wpisu SLA) — wnioskowanie
	 * „pusta => niezaladowana" przywracaloby N+1 w najczestszym przypadku.
	 *
	 * @var bool
	 */
	private bool $deadlines_loaded = false;

	/**
	 * Kolumna termin SLA — z kontraktu D (mp_case_deadline). '—' gdy brak.
	 *
	 * @param array<string, mixed> $item Wiersz sprawy.
	 * @return string
	 */
	public function column_deadline( $item ): string {
		$case_id = (int) ( $item['id'] ?? 0 );

		// Mapa z prepare_items() — jedno zapytanie na strone zamiast jednego na wiersz.
		// Zapas przez `mp_case_deadline` zostaje: render wiersza poza tabela oraz sytuacja,
		// gdy Automator nie obsluguje wariantu hurtowego (starsza wersja modulu D).
		if ( $this->deadlines_loaded ) {
			$sla = $this->deadlines[ $case_id ] ?? null;
		} else {
			$sla = apply_filters( 'mp_case_deadline', null, $case_id );
		}

		if ( ! is_array( $sla ) || empty( $sla['deadline_at'] ) ) {
			// Zegar terminu STOI, gdy czekamy na ruch klienta — i to musi byc WIDOCZNE.
			// Sama pustka nie odroznia „terminu nie ma, bo tak ma byc" od „termin sie zepsul",
			// a koordynator patrzy na te kolumne, zeby wiedziec, gdzie ma zajrzec.
			// ⛔ Pytamy o STATUS, nie o brak daty: pusty termin ma tez inne przyczyny
			// (sprawa zamknieta, modul automatu nieaktywny) i tam ten napis bylby klamstwem.
			if ( Statuses::is_awaiting_customer( (string) ( $item['status'] ?? '' ) ) ) {
				return '<span style="color:#a16207" title="' . esc_attr__( 'Termin nie biegnie, dopóki sprawa czeka na odpowiedź klienta', 'mp-service-intake' ) . '">'
					. esc_html( Statuses::awaiting_customer_label() ) . '</span>';
			}

			return '—';
		}

		$deadline = (string) $sla['deadline_at'];
		$do_konca = strtotime( $deadline . ' UTC' ) - time();
		$label    = esc_html( get_date_from_gmt( $deadline, 'Y-m-d H:i' ) );

		// Trzy stany zamiast dwoch. Powod (audyt uzytecznosci): koordynator
		// obslugujacy 30 zgloszen dziennie musial liczyc daty W GLOWIE — sam
		// termin bez sygnalu nie mowi nic o pilnosci, a czerwien pojawiala sie
		// dopiero PO fakcie, gdy juz nic nie da sie uratowac.
		if ( $do_konca < 0 ) {
			return '<span style="color:#a33;font-weight:600" title="' . esc_attr__( 'Termin minął', 'mp-service-intake' ) . '">'
				. $label . ' <strong>' . esc_html__( '· po terminie', 'mp-service-intake' ) . '</strong></span>';
		}

		if ( $do_konca < DAY_IN_SECONDS ) {
			$godzin = max( 1, (int) round( $do_konca / HOUR_IN_SECONDS ) );

			return '<span style="color:#8a5a00;font-weight:600">' . $label . ' <strong>'
				. esc_html(
					sprintf(
						/* translators: %d: liczba godzin do konca terminu. */
						_n( '· zostało %d godz.', '· zostało %d godz.', $godzin, 'mp-service-intake' ),
						$godzin
					)
				) . '</strong></span>';
		}

		return $label;
	}

	/**
	 * „Czego dotyczy" — pierwsze zdanie opisu zgloszenia.
	 *
	 * Bez tego lista pokazywala e-mail i rodzaj („reklamacja"), wiec zeby
	 * dowiedziec sie O CO CHODZI, trzeba bylo wejsc w kazda sprawe osobno.
	 * Przy 30 zgloszeniach dziennie to sama strata czasu (audyt uzytecznosci).
	 *
	 * @param array<string, mixed> $item Wiersz sprawy.
	 * @return string
	 */
	public function column_temat( $item ): string {
		// `form_data` przychodzi JUZ w wierszu z list_cases() — jeden SELECT na cala strone.
		// Dowolywanie sie po `id` dla kazdego wiersza bylo N+1 (audyt wydajnosci 30.07).
		// Zapas przez form_data_for_case() zostaje na wypadek wywolania z wierszem bez tego pola.
		$pola = isset( $item['form_data'] )
			? CaseRepo::form_data_from_json( (string) $item['form_data'] )
			: CaseRepo::form_data_for_case( (int) ( $item['id'] ?? 0 ) );

		// ZWROT nie ma opisu usterki — klient wpisuje POWOD ZWROTU. Czytajac samo
		// issue_description lista pokazywala „— bez opisu" przy kazdym zwrocie,
		// mimo ze klient napisal, dlaczego oddaje (zlapane na zrzutach 27.07).
		$zrodla = array();

		foreach ( (array) $pola as $pole ) {
			$klucz = (string) $pole['key'];

			if ( 'issue_description' !== $klucz && 'return_reason' !== $klucz ) {
				continue;
			}

			$tekst = trim( preg_replace( '/\s+/u', ' ', (string) $pole['value'] ) ?? '' );

			if ( '' !== $tekst ) {
				$zrodla[ $klucz ] = $tekst;
			}
		}

		// Opis usterki ma pierwszenstwo; powod zwrotu wchodzi, gdy opisu nie ma.
		$tekst = $zrodla['issue_description'] ?? ( $zrodla['return_reason'] ?? '' );

		if ( '' !== $tekst ) {
			$skrot = mb_substr( $tekst, 0, 70 );

			return esc_html( mb_strlen( $tekst ) > 70 ? $skrot . '…' : $skrot );
		}

		return '<span style="color:#646970">' . esc_html__( '— bez opisu', 'mp-service-intake' ) . '</span>';
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
				esc_html( FormConfig::kind_label( (string) $kind ) )
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
