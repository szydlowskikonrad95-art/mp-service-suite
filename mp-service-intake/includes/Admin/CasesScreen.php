<?php
/**
 * Ekran „MP: Sprawy" — warsztat pracy personelu nad sprawami (kartka krok 7).
 * Lista wszystkich zweryfikowanych spraw (WP_List_Table) + wejscie w KARTE
 * sprawy (case_id). Model B: caly personel (agent/koordynator/admin) widzi
 * wszystkie sprawy. Cap = personel (OR rol — role NIE hierarchiczne).
 *
 * Karta sprawy (render_card) i handlery akcji (status/odpowiedz/przydzial)
 * dochodza w kolejnych krokach — tu lista + szkielet nawigacji.
 *
 * @package MP\Intake\Admin
 */

namespace MP\Intake\Admin;

/**
 * Rejestracja menu i render ekranu spraw personelu.
 */
final class CasesScreen {

	/**
	 * Slug strony admina.
	 */
	public const PAGE_SLUG = 'mp-cases';

	/**
	 * Rejestruje menu (wolane addytywnie z Plugin::boot w kontekscie admina).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_menu', array( self::class, 'add_menu' ) );
	}

	/**
	 * Czy biezacy uzytkownik to personel serwisu (dowolna z 3 rol; NIE hierarchiczne).
	 *
	 * @return bool
	 */
	public static function current_user_is_staff(): bool {
		return current_user_can( 'mp_agent' )
			|| current_user_can( 'mp_coordinator' )
			|| current_user_can( 'mp_system_admin' );
	}

	/**
	 * Menu „MP: Sprawy". add_menu_page bierze JEDEN cap, a role MP nie maja
	 * hierarchii — ustawiamy cap ktory biezacy user FAKTYCZNIE ma (kazdy personel
	 * widzi menu; klient/anon nie ma zadnego => ukryte). Render i tak sprawdza
	 * personel (obrona warstwowa).
	 *
	 * @return void
	 */
	public static function add_menu(): void {
		$cap = current_user_can( 'mp_system_admin' )
			? 'mp_system_admin'
			: ( current_user_can( 'mp_coordinator' ) ? 'mp_coordinator' : 'mp_agent' );

		add_menu_page(
			__( 'Sprawy serwisowe MP', 'mp-service-intake' ),
			__( 'MP: Sprawy', 'mp-service-intake' ),
			$cap,
			self::PAGE_SLUG,
			array( self::class, 'render' ),
			'dashicons-clipboard',
			57
		);
	}

	/**
	 * Render: bramka personelu => lista (albo karta sprawy gdy case_id).
	 *
	 * @return void
	 */
	public static function render(): void {
		if ( ! self::current_user_is_staff() ) {
			wp_die(
				esc_html__( 'Brak uprawnień do spraw serwisowych.', 'mp-service-intake' ),
				'',
				array( 'response' => 403 )
			);
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- GET-owa nawigacja (odczyt: lista vs karta).
		$case_id = isset( $_GET['case_id'] ) ? absint( $_GET['case_id'] ) : 0;

		if ( $case_id > 0 ) {
			self::render_card( $case_id );
			return;
		}

		self::render_list();
	}

	/**
	 * Lista spraw (WP_List_Table) w formularzu GET (filtry + wyszukiwarka).
	 *
	 * @return void
	 */
	private static function render_list(): void {
		$table = new CasesListTable( self::PAGE_SLUG );
		$table->prepare_items();

		echo '<div class="wrap">';
		echo '<h1>' . esc_html__( 'Sprawy serwisowe', 'mp-service-intake' ) . '</h1>';
		echo '<form method="get">';
		echo '<input type="hidden" name="page" value="' . esc_attr( self::PAGE_SLUG ) . '" />';
		$table->search_box( __( 'Szukaj (nr sprawy / klient)', 'mp-service-intake' ), 'mp-cases-search' );
		$table->display();
		echo '</form></div>';
	}

	/**
	 * Karta sprawy (szczegoly + akcje personelu) — DOCHODZI w kolejnym kroku.
	 * Na razie: nawigacja powrotna + potwierdzenie ze case_id dotarl.
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	private static function render_card( int $case_id ): void {
		$back = add_query_arg( array( 'page' => self::PAGE_SLUG ), admin_url( 'admin.php' ) );

		echo '<div class="wrap">';
		echo '<h1>' . esc_html__( 'Karta sprawy', 'mp-service-intake' ) . '</h1>';
		echo '<p><a href="' . esc_url( $back ) . '">&laquo; ' . esc_html__( 'Wróć do listy spraw', 'mp-service-intake' ) . '</a></p>';
		echo '<p>' . esc_html( sprintf( /* translators: %d: ID sprawy. */ __( 'Karta sprawy #%d — sekcje i akcje w budowie.', 'mp-service-intake' ), $case_id ) ) . '</p>';
		echo '</div>';
	}
}
