<?php
/**
 * Panel admina automatora (klocek D) — pierwszy ekran menu wtyczki.
 *
 * TU `add_menu_page` JEST wlasciwe: to menu spina istniejace handlery
 * backend-only (Przelicz SLA — SlaRecalcAction; Eksport CSV — CsvExport) oraz
 * daje read-only podglad regul/statusow/rejestru zdarzen. Checklisty+szablony
 * (P3.5) maja tu SLOT (placeholder) — doszyje builder #2.
 *
 * Bezpieczenstwo warstwowe: menu za cap coordinator|system_admin; przyciski
 * per-rola; nonce w kazdym formularzu (handlery i tak maja check_admin_referer);
 * escaping wszedzie; dane z WLASNYCH tabel D przez $wpdb->prepare.
 *
 * @package MP\Automator
 */

namespace MP\Automator\Admin;

use MP\Automator\Tables;

/**
 * Rejestracja menu + render panelu automatyzacji.
 */
final class PanelScreen {

	/**
	 * Slug strony panelu.
	 */
	public const PAGE_SLUG = 'mp-automator';

	/**
	 * Ile zdarzen rejestru na strone (paginacja).
	 */
	private const EVENTS_PER_PAGE = 20;

	/**
	 * Hook suffix strony (enqueue CSS tylko u nas).
	 *
	 * @var string
	 */
	private static string $hook_suffix = '';

	/**
	 * Rejestruje hooki admina (wolane addytywnie z Plugin::boot).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_menu', array( self::class, 'add_menu' ) );
		add_action( 'admin_enqueue_scripts', array( self::class, 'enqueue' ) );
	}

	/**
	 * Czy biezacy uzytkownik moze WIDZIEC panel (koordynator lub system-admin).
	 *
	 * @return bool
	 */
	private static function can_view(): bool {
		return current_user_can( 'mp_coordinator' ) || current_user_can( 'mp_system_admin' );
	}

	/**
	 * Menu automatora. add_menu_page bierze JEDEN cap, a role MP nie maja
	 * hierarchii (system_admin NIE ma capa koordynatora i odwrotnie) — wiec cap
	 * ustawiamy na TEN, ktory biezacy user faktycznie ma; klient/anon nie ma
	 * zadnego => menu ukryte. Render i tak sprawdza can_view (obrona warstwowa).
	 *
	 * @return void
	 */
	public static function add_menu(): void {
		$cap = current_user_can( 'mp_system_admin' ) ? 'mp_system_admin' : 'mp_coordinator';

		self::$hook_suffix = (string) add_menu_page(
			__( 'Automatyzacje MP', 'mp-workflow-automator' ),
			__( 'Automatyzacje MP', 'mp-workflow-automator' ),
			$cap,
			self::PAGE_SLUG,
			array( self::class, 'render' ),
			'dashicons-controls-repeat',
			58
		);
	}

	/**
	 * Laduje CSS panelu wylacznie na tej stronie.
	 *
	 * @param string $hook Hook suffix biezacej strony admina.
	 * @return void
	 */
	public static function enqueue( string $hook ): void {
		if ( '' === self::$hook_suffix || $hook !== self::$hook_suffix ) {
			return;
		}

		wp_enqueue_style(
			'mp-automator-admin',
			plugin_dir_url( MP_AUTOMATOR_FILE ) . 'assets/css/admin-automator.css',
			array(),
			MP_AUTOMATOR_VERSION
		);
	}

	/**
	 * Render panelu (bramka warstwowa + sekcje).
	 *
	 * @return void
	 */
	public static function render(): void {
		if ( ! self::can_view() ) {
			wp_die(
				esc_html__( 'Brak uprawnień do panelu automatyzacji.', 'mp-workflow-automator' ),
				'',
				array( 'response' => 403 )
			);
		}

		?>
		<div class="wrap mp-automator-panel">
			<h1><?php esc_html_e( 'Automatyzacje MP', 'mp-workflow-automator' ); ?></h1>
			<p class="mp-automator-intro"><?php esc_html_e( 'Panel administracyjny modułu automatyzacji: akcje serwisowe oraz podgląd reguł, statusów i rejestru zdarzeń.', 'mp-workflow-automator' ); ?></p>
			<?php
			self::render_notice();
			self::render_actions();
			self::render_rules();
			self::render_statuses();
			self::render_events();
			self::render_p35_slot();
			?>
		</div>
		<?php
	}

	/**
	 * Komunikat po przeliczeniu SLA (SlaRecalcAction redirectuje z ?mp_sla_recalc=N).
	 *
	 * @return void
	 */
	private static function render_notice(): void {
		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- odczyt licznika z redirectu (bez zmiany stanu); handler mial nonce.
		if ( ! isset( $_GET['mp_sla_recalc'] ) ) {
			return;
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- j.w.
		$count = absint( $_GET['mp_sla_recalc'] );
		?>
		<div class="notice notice-success is-dismissible">
			<p>
				<?php
				echo esc_html(
					sprintf(
						/* translators: %d = liczba przeliczonych spraw */
						_n( 'Przeliczono SLA dla %d sprawy.', 'Przeliczono SLA dla %d spraw.', $count, 'mp-workflow-automator' ),
						$count
					)
				);
				?>
			</p>
		</div>
		<?php
	}

	/**
	 * Sekcja AKCJE: Przelicz SLA (tylko system-admin) + Eksport CSV (koordynator|admin).
	 * Nonce w kazdym formularzu; przycisk widoczny tylko dla uprawnionej roli.
	 *
	 * @return void
	 */
	private static function render_actions(): void {
		$post_url = esc_url( admin_url( 'admin-post.php' ) );
		?>
		<h2 class="mp-automator-h2"><?php esc_html_e( 'Akcje', 'mp-workflow-automator' ); ?></h2>
		<div class="mp-automator-actions">
			<?php if ( current_user_can( 'mp_system_admin' ) ) : ?>
				<form method="post" action="<?php echo $post_url; ?>" class="mp-automator-action">
					<?php echo SlaRecalcAction::form_fields(); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped -- form_fields zwraca gotowy, bezpieczny HTML (hidden action + wp_nonce_field). ?>
					<?php submit_button( __( 'Przelicz SLA', 'mp-workflow-automator' ), 'secondary', 'mp_recalc_submit', false ); ?>
					<span class="description"><?php esc_html_e( 'Przelicza terminy otwartych spraw wg bieżącej konfiguracji (nie wysyła ponownie już wysłanych powiadomień).', 'mp-workflow-automator' ); ?></span>
				</form>
			<?php endif; ?>

			<form method="post" action="<?php echo $post_url; ?>" class="mp-automator-action">
				<input type="hidden" name="action" value="mp_automator_export_csv" />
				<?php wp_nonce_field( 'mp_automator_export_csv' ); ?>
				<?php submit_button( __( 'Eksport CSV', 'mp-workflow-automator' ), 'secondary', 'mp_export_submit', false ); ?>
				<span class="description"><?php esc_html_e( 'Pobiera zestawienie spraw w formacie CSV.', 'mp-workflow-automator' ); ?></span>
			</form>
		</div>
		<?php
	}

	/**
	 * Read-only podglad regul przydzialu (wlasna tabela D).
	 *
	 * @return void
	 */
	private static function render_rules(): void {
		global $wpdb;

		$table = Tables::full( Tables::WORKFLOW_RULES );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna D, read-only podglad.
		$rows = $wpdb->get_results(
			"SELECT id, trigger_type, condition_key, condition_operator, condition_value, action_type, priority, enabled, source
			FROM {$table} ORDER BY priority ASC, id ASC"
		);
		// phpcs:enable
		?>
		<h2 class="mp-automator-h2"><?php esc_html_e( 'Reguły przydziału', 'mp-workflow-automator' ); ?></h2>
		<table class="widefat striped mp-automator-table">
			<caption class="screen-reader-text"><?php esc_html_e( 'Lista reguł przydziału automatyzacji', 'mp-workflow-automator' ); ?></caption>
			<thead>
				<tr>
					<th scope="col"><?php esc_html_e( 'ID', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Wyzwalacz', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Warunek', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Akcja', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Priorytet', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Aktywna', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Źródło', 'mp-workflow-automator' ); ?></th>
				</tr>
			</thead>
			<tbody>
				<?php if ( empty( $rows ) ) : ?>
					<tr><td colspan="7"><?php esc_html_e( 'Brak reguł.', 'mp-workflow-automator' ); ?></td></tr>
				<?php else : ?>
					<?php foreach ( $rows as $r ) : ?>
						<tr>
							<td><?php echo esc_html( (string) $r->id ); ?></td>
							<td><?php echo esc_html( (string) $r->trigger_type ); ?></td>
							<td><?php echo esc_html( trim( $r->condition_key . ' ' . $r->condition_operator . ' ' . $r->condition_value ) ); ?></td>
							<td><?php echo esc_html( (string) $r->action_type ); ?></td>
							<td><?php echo esc_html( (string) $r->priority ); ?></td>
							<td><?php echo (int) $r->enabled ? esc_html__( 'tak', 'mp-workflow-automator' ) : esc_html__( 'nie', 'mp-workflow-automator' ); ?></td>
							<td><?php echo esc_html( (string) $r->source ); ?></td>
						</tr>
					<?php endforeach; ?>
				<?php endif; ?>
			</tbody>
		</table>
		<?php
	}

	/**
	 * Read-only podglad statusow: PELNA lista (rdzen 7 + wlasne) przez kontraktowy
	 * hook C->D `mp_all_statuses` (kanoniczne zrodlo = MP\Intake\Statuses::all).
	 * Degrade wg wzorca registry: gdy modul zgloszen (C) nieaktywny => hooka brak,
	 * pokazujemy tylko wlasne D z mp_registered_statuses + nota. NIE siegamy w klase C.
	 *
	 * @return void
	 */
	private static function render_statuses(): void {
		$degraded = ! has_filter( 'mp_all_statuses' );

		$statuses = $degraded
			? apply_filters( 'mp_registered_statuses', array() ) // tylko wlasne D
			: apply_filters( 'mp_all_statuses', array() );        // pelna: rdzen 7 + wlasne

		$statuses = is_array( $statuses ) ? $statuses : array();
		?>
		<h2 class="mp-automator-h2"><?php esc_html_e( 'Statusy spraw', 'mp-workflow-automator' ); ?></h2>
		<?php if ( $degraded ) : ?>
			<div class="notice notice-warning inline"><p><?php esc_html_e( 'Moduł zgłoszeń (mp-service-intake) jest nieaktywny — pokazuję tylko statusy własne. Rdzeń statusów pojawi się po jego aktywacji.', 'mp-workflow-automator' ); ?></p></div>
		<?php endif; ?>
		<table class="widefat striped mp-automator-table">
			<caption class="screen-reader-text"><?php esc_html_e( 'Lista statusów spraw', 'mp-workflow-automator' ); ?></caption>
			<thead>
				<tr>
					<th scope="col"><?php esc_html_e( 'Status', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Etykieta', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Terminalny', 'mp-workflow-automator' ); ?></th>
				</tr>
			</thead>
			<tbody>
				<?php if ( empty( $statuses ) ) : ?>
					<tr><td colspan="3"><?php esc_html_e( 'Brak statusów.', 'mp-workflow-automator' ); ?></td></tr>
				<?php else : ?>
					<?php foreach ( $statuses as $slug => $def ) : ?>
						<?php $terminal = is_array( $def ) && ! empty( $def['terminal'] ); ?>
						<tr>
							<td><code><?php echo esc_html( (string) $slug ); ?></code></td>
							<td><?php echo esc_html( is_array( $def ) && isset( $def['label'] ) ? (string) $def['label'] : (string) $slug ); ?></td>
							<td><?php echo $terminal ? esc_html__( 'tak', 'mp-workflow-automator' ) : esc_html__( 'nie', 'mp-workflow-automator' ); ?></td>
						</tr>
					<?php endforeach; ?>
				<?php endif; ?>
			</tbody>
		</table>
		<?php
	}

	/**
	 * Read-only rejestr zdarzen (append-only D), paginowany. Payload jest
	 * strukturalny (NO-PII); pokazujemy typ, sprawe (id), aktora, czas, payload.
	 *
	 * @return void
	 */
	private static function render_events(): void {
		global $wpdb;

		$table = Tables::full( Tables::WORKFLOW_EVENTS );

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- paginacja GET (odczyt, bez zmiany stanu).
		$page   = isset( $_GET['ev_page'] ) ? max( 1, absint( $_GET['ev_page'] ) ) : 1;
		$offset = ( $page - 1 ) * self::EVENTS_PER_PAGE;

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna D, read-only.
		$total = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$table}" );
		$rows  = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT id, case_id, event_type, actor_id, created_at, payload
				FROM {$table} ORDER BY id DESC LIMIT %d OFFSET %d",
				self::EVENTS_PER_PAGE,
				$offset
			)
		);
		// phpcs:enable

		$pages = (int) max( 1, (int) ceil( $total / self::EVENTS_PER_PAGE ) );
		?>
		<h2 class="mp-automator-h2"><?php esc_html_e( 'Rejestr zdarzeń', 'mp-workflow-automator' ); ?></h2>
		<table class="widefat striped mp-automator-table">
			<caption class="screen-reader-text"><?php esc_html_e( 'Rejestr zdarzeń automatyzacji (tylko do odczytu)', 'mp-workflow-automator' ); ?></caption>
			<thead>
				<tr>
					<th scope="col"><?php esc_html_e( 'ID', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Zdarzenie', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Sprawa', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Wykonawca', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Kiedy (UTC)', 'mp-workflow-automator' ); ?></th>
					<th scope="col"><?php esc_html_e( 'Szczegóły', 'mp-workflow-automator' ); ?></th>
				</tr>
			</thead>
			<tbody>
				<?php if ( empty( $rows ) ) : ?>
					<tr><td colspan="6"><?php esc_html_e( 'Brak zdarzeń.', 'mp-workflow-automator' ); ?></td></tr>
				<?php else : ?>
					<?php foreach ( $rows as $e ) : ?>
						<tr>
							<td><?php echo esc_html( (string) $e->id ); ?></td>
							<td><code><?php echo esc_html( (string) $e->event_type ); ?></code></td>
							<td><?php echo null !== $e->case_id ? esc_html( '#' . (string) (int) $e->case_id ) : '—'; ?></td>
							<td><?php echo esc_html( self::actor_label( $e->actor_id ) ); ?></td>
							<td><?php echo esc_html( (string) $e->created_at ); ?></td>
							<td class="mp-automator-payload"><?php echo esc_html( self::payload_summary( (string) $e->payload ) ); ?></td>
						</tr>
					<?php endforeach; ?>
				<?php endif; ?>
			</tbody>
		</table>
		<?php
		self::render_pagination( $page, $pages, $total );
	}

	/**
	 * Etykieta wykonawcy zdarzenia (login uzytkownika albo „system"/„—").
	 *
	 * @param mixed $actor_id ID aktora (moze byc NULL).
	 * @return string
	 */
	private static function actor_label( $actor_id ): string {
		$id = (int) $actor_id;

		if ( $id <= 0 ) {
			return __( 'system', 'mp-workflow-automator' );
		}

		$user = get_userdata( $id );

		return $user ? (string) $user->user_login : ( '#' . $id );
	}

	/**
	 * Skrocony podglad payloadu (strukturalny JSON, NO-PII) — max 120 znakow.
	 *
	 * @param string $payload Surowy JSON z rejestru.
	 * @return string
	 */
	private static function payload_summary( string $payload ): string {
		if ( '' === $payload ) {
			return '—';
		}

		$data = json_decode( $payload, true );

		if ( ! is_array( $data ) ) {
			return self::truncate( $payload );
		}

		$parts = array();

		foreach ( $data as $k => $v ) {
			if ( is_scalar( $v ) ) {
				$parts[] = $k . '=' . (string) $v;
			}
		}

		return self::truncate( implode( ', ', $parts ) );
	}

	/**
	 * Przycina string do 120 znakow z wielokropkiem.
	 *
	 * @param string $s Wejscie.
	 * @return string
	 */
	private static function truncate( string $s ): string {
		return mb_strlen( $s ) > 120 ? mb_substr( $s, 0, 117 ) . '…' : $s;
	}

	/**
	 * Prosta paginacja rejestru (poprzednia/nastepna + „strona X z Y”).
	 *
	 * @param int $page  Biezaca strona.
	 * @param int $pages Liczba stron.
	 * @param int $total Laczna liczba zdarzen.
	 * @return void
	 */
	private static function render_pagination( int $page, int $pages, int $total ): void {
		if ( $pages <= 1 ) {
			return;
		}

		$base = add_query_arg( 'page', self::PAGE_SLUG, admin_url( 'admin.php' ) );
		?>
		<nav class="mp-automator-pagination" aria-label="<?php esc_attr_e( 'Paginacja rejestru zdarzeń', 'mp-workflow-automator' ); ?>">
			<?php if ( $page > 1 ) : ?>
				<a class="button" href="<?php echo esc_url( add_query_arg( 'ev_page', $page - 1, $base ) ); ?>">&laquo; <?php esc_html_e( 'Poprzednia', 'mp-workflow-automator' ); ?></a>
			<?php endif; ?>
			<span class="mp-automator-page-of">
				<?php
				echo esc_html(
					sprintf(
						/* translators: 1 = strona biezaca, 2 = liczba stron, 3 = laczna liczba zdarzen */
						__( 'Strona %1$d z %2$d (%3$d zdarzeń)', 'mp-workflow-automator' ),
						$page,
						$pages,
						$total
					)
				);
				?>
			</span>
			<?php if ( $page < $pages ) : ?>
				<a class="button" href="<?php echo esc_url( add_query_arg( 'ev_page', $page + 1, $base ) ); ?>"><?php esc_html_e( 'Następna', 'mp-workflow-automator' ); ?> &raquo;</a>
			<?php endif; ?>
		</nav>
		<?php
	}

	/**
	 * SLOT na checklisty + szablony (P3.5, builder #2). Placeholder — nie budujemy tu tej funkcji.
	 *
	 * @return void
	 */
	private static function render_p35_slot(): void {
		?>
		<h2 class="mp-automator-h2"><?php esc_html_e( 'Checklisty i szablony', 'mp-workflow-automator' ); ?></h2>
		<div class="mp-automator-slot" role="note">
			<p><?php esc_html_e( 'Zarządzanie checklistami i szablonami wiadomości pojawi się tutaj wkrótce (moduł P3.5).', 'mp-workflow-automator' ); ?></p>
		</div>
		<?php
	}
}
