<?php
/**
 * Karta sprawy dla PERSONELU (kartka krok 7) — szczegoly + praca nad sprawa.
 * Render sekcji: naglowek (status/rodzaj/priorytet/przydzielony/deadline) · klient ·
 * opis zgloszenia (form_data) · zalaczniki · os czasu (case_events) · wiadomosci ·
 * checklista (interaktywna — toggle przez istniejacy handler D). Akcje personelu
 * (zmiana statusu / odpowiedz / przydzial) dochodza w CaseActions (kolejny krok).
 *
 * BEZPIECZENSTWO: WSZYSTKIE dane od klienta (opis, wiadomosci, nazwy plikow,
 * payloady zdarzen) przez esc_html/esc_attr — to jedyna nowa powierzchnia XSS.
 *
 * @package MP\Intake\Admin
 */

namespace MP\Intake\Admin;

use MP\Intake\Attachments;
use MP\Intake\CaseEvents;
use MP\Intake\CaseRepo;
use MP\Intake\Messages;
use MP\Intake\Statuses;

/**
 * Render karty sprawy (read + checklista) w ekranie MP: Sprawy.
 */
final class CaseCard {

	/**
	 * Etykiety typow zdarzen osi czasu (fallback = surowy typ).
	 *
	 * @return array<string, string>
	 */
	private static function event_labels(): array {
		return array(
			'STATUS_CHANGED'         => __( 'Zmiana statusu', 'mp-service-intake' ),
			'PRIORITY_CHANGED'       => __( 'Zmiana priorytetu', 'mp-service-intake' ),
			'CASE_ASSIGNED'          => __( 'Przydział sprawy', 'mp-service-intake' ),
			'MESSAGE_ADDED'          => __( 'Wiadomość', 'mp-service-intake' ),
			'CHECKLIST_ITEM_TOGGLED' => __( 'Checklista', 'mp-service-intake' ),
			'CONSENT_WITHDRAWN'      => __( 'Wycofanie zgody (RODO)', 'mp-service-intake' ),
			'EXCEPTION_APPLIED'      => __( 'Wyjątek gwarancyjny', 'mp-service-intake' ),
			'EXCEPTION_REVOKED'      => __( 'Cofnięcie wyjątku gwarancyjnego', 'mp-service-intake' ),
		);
	}

	/**
	 * Render calej karty sprawy. Sprawa nieznana/niezweryfikowana => komunikat.
	 *
	 * @param int    $case_id   ID sprawy.
	 * @param string $page_slug Slug strony (link powrotny).
	 * @return void
	 */
	public static function render( int $case_id, string $page_slug ): void {
		$ctx = apply_filters( 'mp_case_get_context', null, $case_id );

		$back = add_query_arg( array( 'page' => $page_slug ), admin_url( 'admin.php' ) );

		echo '<div class="wrap">';
		echo '<a href="' . esc_url( $back ) . '">&laquo; ' . esc_html__( 'Wróć do listy spraw', 'mp-service-intake' ) . '</a>';

		if ( ! is_array( $ctx ) ) {
			echo '<h1>' . esc_html__( 'Sprawa niedostępna', 'mp-service-intake' ) . '</h1>';
			echo '<p>' . esc_html__( 'Sprawa nie istnieje lub nie została jeszcze potwierdzona przez klienta.', 'mp-service-intake' ) . '</p></div>';
			return;
		}

		// Komunikat PRG (np. po toggle checklisty).
		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- tylko wyswietlenie komunikatu PRG, tresc escapowana.
		$notice = isset( $_GET['mp_notice'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['mp_notice'] ) ) : '';
		if ( '' !== $notice ) {
			echo '<div class="notice notice-info is-dismissible"><p>' . esc_html( $notice ) . '</p></div>';
		}

		echo '<h1>' . esc_html( sprintf( /* translators: %s: numer sprawy. */ __( 'Sprawa %s', 'mp-service-intake' ), (string) ( $ctx['case_number'] ?? ( '#' . $case_id ) ) ) ) . '</h1>';

		echo '<div style="display:flex;gap:1.5rem;flex-wrap:wrap;align-items:flex-start">';
		echo '<div style="flex:2 1 460px;min-width:320px">';
		self::section_header( $case_id, $ctx );
		self::section_actions( $case_id, $ctx );
		self::section_description( $case_id );
		self::section_attachments( $case_id );
		self::section_messages( $case_id, $ctx );
		echo '</div>';
		echo '<div style="flex:1 1 300px;min-width:280px">';
		self::section_client( $ctx );
		self::section_product_warranty( $ctx );
		self::section_checklist( $case_id );
		self::section_timeline( $case_id );
		echo '</div>';
		echo '</div>';

		echo '</div>';
	}

	/**
	 * Sekcja pomocnicza: ramka z tytulem.
	 *
	 * @param string $title Tytul sekcji.
	 * @return void
	 */
	private static function open_box( string $title ): void {
		echo '<div style="background:#fff;border:1px solid #dcdcde;border-radius:6px;padding:1rem;margin:0 0 1.2rem">';
		echo '<h2 style="margin-top:0;font-size:1.05rem">' . esc_html( $title ) . '</h2>';
	}

	/**
	 * Naglowek sprawy: status/rodzaj/priorytet/przydzielony/kategoria/daty/deadline.
	 *
	 * @param int                  $case_id ID sprawy.
	 * @param array<string, mixed> $ctx     Kontekst sprawy.
	 * @return void
	 */
	private static function section_header( int $case_id, array $ctx ): void {
		$assigned = isset( $ctx['assigned_to'] ) && null !== $ctx['assigned_to'] ? (int) $ctx['assigned_to'] : 0;
		$user     = $assigned > 0 ? get_userdata( $assigned ) : null;
		$sla      = apply_filters( 'mp_case_deadline', null, $case_id );
		$deadline = is_array( $sla ) && ! empty( $sla['deadline_at'] ) ? (string) $sla['deadline_at'] : '';

		// phpcs:disable WordPress.Arrays.MultipleStatementAlignment.DoubleArrowNotAligned -- klucze __() z multibyte ('ę','ó'), docelowa kolumna wyrownania rozni sie miedzy wersjami WPCS (lokalna vs CI); stale pojedyncze spacje = wersjo-odporne.
		$rows = array(
			__( 'Status', 'mp-service-intake' ) => Statuses::label( (string) ( $ctx['status'] ?? '' ) ),
			__( 'Rodzaj', 'mp-service-intake' ) => (string) ( $ctx['rodzaj'] ?? '' ),
			__( 'Kategoria', 'mp-service-intake' ) => (string) ( $ctx['kategoria'] ?? '' ),
			__( 'Priorytet', 'mp-service-intake' ) => (string) ( $ctx['priority'] ?? '' ),
			__( 'Przydzielony', 'mp-service-intake' ) => $user ? (string) $user->display_name : __( 'nieprzydzielona', 'mp-service-intake' ),
			__( 'Kraj / język', 'mp-service-intake' ) => trim( (string) ( $ctx['kraj'] ?? '' ) . ' / ' . (string) ( $ctx['jezyk'] ?? '' ), ' /' ),
			__( 'Potwierdzono', 'mp-service-intake' ) => self::fmt_date( (string) ( $ctx['verified_at'] ?? '' ) ),
			__( 'Termin SLA', 'mp-service-intake' ) => '' !== $deadline ? self::fmt_date( $deadline ) : '—',
		);
		// phpcs:enable WordPress.Arrays.MultipleStatementAlignment.DoubleArrowNotAligned

		self::open_box( __( 'Sprawa', 'mp-service-intake' ) );
		echo '<table class="widefat striped" style="border:0"><tbody>';
		foreach ( $rows as $label => $value ) {
			echo '<tr><th style="width:38%">' . esc_html( (string) $label ) . '</th><td>' . esc_html( '' !== (string) $value ? (string) $value : '—' ) . '</td></tr>';
		}
		echo '</tbody></table></div>';
	}

	/**
	 * Panel akcji personelu: zmiana statusu (+powod przy odrzuceniu) i przydzial
	 * (koordynator/admin). Handlery = CaseActions (admin-post, cap+nonce+audyt).
	 * expected_status = biezacy status (optimistic-lock w change_status).
	 *
	 * @param int                  $case_id ID sprawy.
	 * @param array<string, mixed> $ctx     Kontekst sprawy.
	 * @return void
	 */
	private static function section_actions( int $case_id, array $ctx ): void {
		$current = (string) ( $ctx['status'] ?? '' );
		$action  = admin_url( 'admin-post.php' );
		$reasons = apply_filters( 'mp_rejection_reasons', array() );
		$reasons = is_array( $reasons ) ? $reasons : array();

		self::open_box( __( 'Akcje', 'mp-service-intake' ) );

		echo '<form method="post" action="' . esc_url( $action ) . '" style="margin:0 0 1rem;display:flex;gap:.5rem;flex-wrap:wrap;align-items:center">';
		echo '<input type="hidden" name="action" value="mp_intake_case_status" />';
		echo '<input type="hidden" name="case_id" value="' . esc_attr( (string) $case_id ) . '" />';
		echo '<input type="hidden" name="expected_status" value="' . esc_attr( $current ) . '" />';
		wp_nonce_field( 'mp_intake_case_status' );
		echo '<label>' . esc_html__( 'Status:', 'mp-service-intake' ) . ' <select name="new_status">';
		foreach ( Statuses::all() as $slug => $def ) {
			// Statuses::all() normalizuje kazdy wpis => 'label' zawsze obecny (rdzen i custom).
			$label = (string) $def['label'];
			printf( '<option value="%s"%s>%s</option>', esc_attr( (string) $slug ), selected( $current, (string) $slug, false ), esc_html( $label ) );
		}
		echo '</select></label>';
		if ( array() !== $reasons ) {
			echo '<label>' . esc_html__( 'Powód (odrzucenie):', 'mp-service-intake' ) . ' <select name="rejection_reason_code"><option value="">—</option>';
			foreach ( $reasons as $code => $rlabel ) {
				printf( '<option value="%s">%s</option>', esc_attr( (string) $code ), esc_html( (string) $rlabel ) );
			}
			echo '</select></label>';
		}
		submit_button( __( 'Zmień status', 'mp-service-intake' ), 'primary', 'mp_status_submit', false );
		echo '</form>';

		if ( current_user_can( 'mp_coordinator' ) || current_user_can( 'mp_system_admin' ) ) {
			$assigned = isset( $ctx['assigned_to'] ) && null !== $ctx['assigned_to'] ? (int) $ctx['assigned_to'] : 0;
			$staff    = get_users(
				array(
					'role__in' => array( 'mp_agent', 'mp_coordinator', 'mp_system_admin' ),
					'orderby'  => 'display_name',
					'number'   => 200,
					'fields'   => array( 'ID', 'display_name' ),
				)
			);

			echo '<form method="post" action="' . esc_url( $action ) . '" style="margin:0;display:flex;gap:.5rem;flex-wrap:wrap;align-items:center">';
			echo '<input type="hidden" name="action" value="mp_intake_case_assign" />';
			echo '<input type="hidden" name="case_id" value="' . esc_attr( (string) $case_id ) . '" />';
			wp_nonce_field( 'mp_intake_case_assign' );
			echo '<label>' . esc_html__( 'Przydziel do:', 'mp-service-intake' ) . ' <select name="assignee"><option value="">—</option>';
			foreach ( $staff as $u ) {
				printf( '<option value="%d"%s>%s</option>', (int) $u->ID, selected( $assigned, (int) $u->ID, false ), esc_html( (string) $u->display_name ) );
			}
			echo '</select></label>';
			submit_button( __( 'Przydziel', 'mp-service-intake' ), 'secondary', 'mp_assign_submit', false );
			echo '</form>';
		}

		echo '</div>';
	}

	/**
	 * Klient + dane kontaktowe (z kontekstu — anonimizacja RODO respektowana w C).
	 *
	 * @param array<string, mixed> $ctx Kontekst sprawy.
	 * @return void
	 */
	private static function section_client( array $ctx ): void {
		$kontakt = isset( $ctx['kontakt'] ) && is_array( $ctx['kontakt'] ) ? $ctx['kontakt'] : array();

		self::open_box( __( 'Klient', 'mp-service-intake' ) );
		echo '<p style="margin:.2rem 0"><strong>' . esc_html( (string) ( $kontakt['name'] ?? '' ) ) . '</strong></p>';
		echo '<p style="margin:.2rem 0;color:#555">' . esc_html( (string) ( $kontakt['email'] ?? '' ) ) . '</p>';
		if ( '' !== (string) ( $kontakt['phone'] ?? '' ) ) {
			echo '<p style="margin:.2rem 0;color:#555">' . esc_html( (string) $kontakt['phone'] ) . '</p>';
		}
		echo '</div>';
	}

	/**
	 * Produkt + gwarancja z Rejestru (B) — kontrakt `mp_product_details` (B->C).
	 * Degraduje: modul B nieaktywny (brak filtra) albo sprawa bez powiazanego produktu.
	 *
	 * @param array<string, mixed> $ctx Kontekst sprawy.
	 * @return void
	 */
	private static function section_product_warranty( array $ctx ): void {
		self::open_box( __( 'Produkt i gwarancja', 'mp-service-intake' ) );

		if ( ! has_filter( 'mp_product_details' ) ) {
			echo '<p style="color:#666">' . esc_html__( 'Moduł rejestru produktów nieaktywny.', 'mp-service-intake' ) . '</p></div>';
			return;
		}

		$pid = isset( $ctx['product_registry_id'] ) && $ctx['product_registry_id'] ? (int) $ctx['product_registry_id'] : 0;
		$p   = $pid > 0 ? apply_filters( 'mp_product_details', null, $pid ) : null;

		if ( ! is_array( $p ) ) {
			echo '<p style="color:#666">' . esc_html__( 'Brak powiązanego produktu w rejestrze.', 'mp-service-intake' ) . '</p></div>';
			return;
		}

		$status_map = array(
			'aktywna'     => array( __( 'aktywna', 'mp-service-intake' ), '#1a7f37' ),
			'wygasla'     => array( __( 'wygasła', 'mp-service-intake' ), '#b32d2e' ),
			'brak_danych' => array( __( 'brak danych', 'mp-service-intake' ), '#646970' ),
			'weryfikacja' => array( __( 'do weryfikacji', 'mp-service-intake' ), '#996800' ),
		);
		$st         = (string) ( $p['warranty_status'] ?? 'brak_danych' );
		$sm         = $status_map[ $st ] ?? $status_map['brak_danych'];

		// phpcs:disable WordPress.Arrays.MultipleStatementAlignment.DoubleArrowNotAligned -- klucze __() z multibyte; wyrownanie zalezne od wersji WPCS -> stale spacje.
		$rows = array(
			__( 'Model', 'mp-service-intake' ) => (string) ( $p['model'] ?? '' ),
			__( 'Nr seryjny', 'mp-service-intake' ) => (string) ( $p['serial'] ?? '' ),
			__( 'Dokument zakupu', 'mp-service-intake' ) => (string) ( $p['purchase_document'] ?? '' ),
			__( 'Data zakupu', 'mp-service-intake' ) => self::fmt_date( (string) ( $p['purchase_date'] ?? '' ) ),
			__( 'Gwarancja do', 'mp-service-intake' ) => self::fmt_date( (string) ( $p['warranty_until'] ?? '' ) ),
		);
		// phpcs:enable WordPress.Arrays.MultipleStatementAlignment.DoubleArrowNotAligned

		echo '<table class="widefat striped" style="border:0"><tbody>';
		foreach ( $rows as $label => $value ) {
			echo '<tr><th style="width:45%">' . esc_html( (string) $label ) . '</th><td>' . esc_html( '' !== (string) $value ? (string) $value : '—' ) . '</td></tr>';
		}
		echo '<tr><th style="width:45%">' . esc_html__( 'Status gwarancji', 'mp-service-intake' ) . '</th><td><strong style="color:' . esc_attr( (string) $sm[1] ) . '">' . esc_html( (string) $sm[0] ) . '</strong></td></tr>';
		echo '</tbody></table>';
		if ( ! empty( $p['archived'] ) ) {
			echo '<p style="margin:.5rem 0 0;color:#b32d2e">' . esc_html__( '⚠ Produkt zarchiwizowany w rejestrze.', 'mp-service-intake' ) . '</p>';
		}
		echo '</div>';
	}

	/**
	 * Opis zgloszenia — pola z form_data (etykieta + wartosc; esc_html twardo).
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	private static function section_description( int $case_id ): void {
		$fields = CaseRepo::form_data_for_case( $case_id );

		self::open_box( __( 'Opis zgłoszenia', 'mp-service-intake' ) );

		if ( array() === $fields ) {
			echo '<p style="color:#666">' . esc_html__( 'Brak dodatkowych pól opisu.', 'mp-service-intake' ) . '</p></div>';
			return;
		}

		echo '<table class="widefat striped" style="border:0"><tbody>';
		foreach ( $fields as $field ) {
			// form_data_for_case normalizuje pola => 'label'/'value' zawsze obecne.
			$label = (string) $field['label'];
			$value = (string) $field['value'];
			echo '<tr><th style="width:35%">' . esc_html( $label ) . '</th><td>' . nl2br( esc_html( $value ) ) . '</td></tr>';
		}
		echo '</tbody></table></div>';
	}

	/**
	 * Zalaczniki — metadane + pobranie przez endpoint (kontrola dostepu w C).
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	private static function section_attachments( int $case_id ): void {
		$atts = Attachments::metadata_for_case( $case_id );

		self::open_box( __( 'Załączniki', 'mp-service-intake' ) );

		if ( array() === $atts ) {
			echo '<p style="color:#666">' . esc_html__( 'Brak załączników.', 'mp-service-intake' ) . '</p></div>';
			return;
		}

		echo '<ul style="margin:0;padding-left:1.1rem">';
		foreach ( $atts as $att ) {
			$id   = (int) ( $att['id'] ?? 0 );
			$name = (string) ( $att['original_name'] ?? ( 'zalacznik-' . $id ) );
			$size = isset( $att['size_bytes'] ) ? size_format( (int) $att['size_bytes'] ) : '';
			$url  = wp_nonce_url(
				add_query_arg(
					array(
						'action' => 'mp_intake_attachment',
						'id'     => $id,
					),
					admin_url( 'admin-post.php' )
				),
				'mp_intake_attachment_' . $id
			);
			echo '<li style="margin:.3rem 0"><a href="' . esc_url( $url ) . '">' . esc_html( $name ) . '</a>'
				. ( '' !== $size ? ' <span style="color:#777">(' . esc_html( $size ) . ')</span>' : '' ) . '</li>';
		}
		echo '</ul></div>';
	}

	/**
	 * Historia wiadomosci klient<->serwis + FORMULARZ ODPOWIEDZI personelu.
	 * Odpowiedz => Messages::add('staff') (mp_case_message_added => mail do klienta).
	 * Szablony (hook D) wypelniaja pole przez data-body (esc_attr — bez XSS).
	 *
	 * @param int                  $case_id ID sprawy.
	 * @param array<string, mixed> $ctx     Kontekst (rodzaj => szablony odpowiedzi).
	 * @return void
	 */
	private static function section_messages( int $case_id, array $ctx ): void {
		$messages = Messages::for_case( $case_id );

		self::open_box( __( 'Wiadomości', 'mp-service-intake' ) );

		if ( array() === $messages ) {
			echo '<p style="color:#666">' . esc_html__( 'Brak wiadomości.', 'mp-service-intake' ) . '</p>';
		} else {
			$labels = array(
				'client' => __( 'Klient', 'mp-service-intake' ),
				'staff'  => __( 'Serwis', 'mp-service-intake' ),
				'system' => __( 'System', 'mp-service-intake' ),
			);

			echo '<ul style="list-style:none;margin:0 0 1rem;padding:0">';
			foreach ( $messages as $msg ) {
				$author = (string) ( $msg['author_type'] ?? 'system' );
				$label  = $labels[ $author ] ?? $labels['system'];
				$when   = self::fmt_date( (string) ( $msg['created_at'] ?? '' ) );
				$bg     = 'staff' === $author ? '#eef6ec' : ( 'client' === $author ? '#eef2f7' : '#f4f4f4' );

				echo '<li style="margin:.4rem 0;padding:.5rem .7rem;background:' . esc_attr( $bg ) . ';border-radius:4px">';
				echo '<span style="font-weight:600">' . esc_html( $label ) . '</span> ';
				echo '<span style="color:#666;font-size:.85em">' . esc_html( $when ) . '</span><br />';
				echo nl2br( esc_html( (string) ( $msg['body'] ?? '' ) ) );
				echo '</li>';
			}
			echo '</ul>';
		}

		$kind      = (string) ( $ctx['rodzaj'] ?? '' );
		$templates = apply_filters( 'mp_response_templates', null, $kind );
		$templates = is_array( $templates ) ? $templates : array();
		$action    = admin_url( 'admin-post.php' );
		$tpl_id    = 'mp-reply-tpl-' . $case_id;
		$body_id   = 'mp-reply-body-' . $case_id;

		echo '<form method="post" action="' . esc_url( $action ) . '" style="border-top:1px solid #eee;padding-top:.8rem">';
		echo '<input type="hidden" name="action" value="mp_intake_case_reply" />';
		echo '<input type="hidden" name="case_id" value="' . esc_attr( (string) $case_id ) . '" />';
		wp_nonce_field( 'mp_intake_case_reply' );

		if ( array() !== $templates ) {
			echo '<p style="margin:.2rem 0"><label>' . esc_html__( 'Szablon odpowiedzi:', 'mp-service-intake' ) . ' ';
			echo '<select id="' . esc_attr( $tpl_id ) . '"><option value="">—</option>';
			foreach ( $templates as $t ) {
				$key  = (string) ( $t['key'] ?? '' );
				$body = (string) apply_filters( 'mp_render_response_template', null, $key, $case_id );
				printf(
					'<option value="%s" data-body="%s">%s</option>',
					esc_attr( $key ),
					esc_attr( $body ),
					esc_html( (string) ( $t['label'] ?? $key ) )
				);
			}
			echo '</select></label></p>';
		}

		echo '<p style="margin:.2rem 0"><textarea id="' . esc_attr( $body_id ) . '" name="body" rows="4" required style="width:100%;box-sizing:border-box"></textarea></p>';
		submit_button( __( 'Wyślij odpowiedź do klienta', 'mp-service-intake' ), 'primary', 'mp_reply_submit', false );
		echo '</form>';

		if ( array() !== $templates ) {
			echo '<script>(function(){var s=document.getElementById(' . wp_json_encode( $tpl_id ) . '),t=document.getElementById(' . wp_json_encode( $body_id ) . ');if(s&&t){s.addEventListener("change",function(){var o=this.options[this.selectedIndex];if(o&&typeof o.dataset.body!=="undefined"){t.value=o.dataset.body;}});}})();</script>';
		}

		echo '</div>';
	}

	/**
	 * Checklista sprawy — kroki z hooka D (definicja + stan). INTERAKTYWNA:
	 * kazdy krok = przycisk toggle POST-ujacy na istniejacy handler D
	 * (`mp_automator_checklist_toggle`, nonce + autoryzacja C).
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	private static function section_checklist( int $case_id ): void {
		$steps = apply_filters( 'mp_case_checklist_state', null, $case_id );
		$steps = is_array( $steps ) ? $steps : array();

		self::open_box( __( 'Checklista', 'mp-service-intake' ) );

		if ( array() === $steps ) {
			echo '<p style="color:#666">' . esc_html__( 'Brak checklisty dla tego rodzaju sprawy.', 'mp-service-intake' ) . '</p></div>';
			return;
		}

		$action = admin_url( 'admin-post.php' );

		echo '<ul style="list-style:none;margin:0;padding:0">';
		foreach ( $steps as $step ) {
			$key       = (string) ( $step['step_key'] ?? '' );
			$label     = (string) ( $step['label'] ?? $key );
			$completed = ! empty( $step['completed'] );
			$by        = isset( $step['completed_by'] ) && null !== $step['completed_by'] ? (int) $step['completed_by'] : 0;
			$who       = $by > 0 ? get_userdata( $by ) : null;
			$meta      = $completed && $who ? ' — ' . $who->display_name . ' ' . self::fmt_date( (string) ( $step['completed_at'] ?? '' ) ) : '';

			echo '<li style="margin:.35rem 0;display:flex;gap:.5rem;align-items:flex-start">';
			echo '<form method="post" action="' . esc_url( $action ) . '" style="margin:0">';
			echo '<input type="hidden" name="action" value="mp_automator_checklist_toggle" />';
			echo '<input type="hidden" name="case_id" value="' . esc_attr( (string) $case_id ) . '" />';
			echo '<input type="hidden" name="step_key" value="' . esc_attr( $key ) . '" />';
			echo '<input type="hidden" name="completed" value="' . ( $completed ? '0' : '1' ) . '" />';
			wp_nonce_field( 'mp_automator_checklist_toggle' );
			echo '<button type="submit" class="button button-small" style="min-width:2.2rem">' . ( $completed ? '✓' : '☐' ) . '</button>';
			echo '</form>';
			echo '<span style="line-height:2">' . ( $completed ? '<s>' . esc_html( $label ) . '</s>' : esc_html( $label ) ) . '<span style="color:#777;font-size:.85em">' . esc_html( $meta ) . '</span></span>';
			echo '</li>';
		}
		echo '</ul></div>';
	}

	/**
	 * Os czasu sprawy (append-only) — typ zdarzenia + wykonawca + data.
	 *
	 * @param int $case_id ID sprawy.
	 * @return void
	 */
	private static function section_timeline( int $case_id ): void {
		$events = CaseEvents::for_case( $case_id );
		$labels = self::event_labels();

		self::open_box( __( 'Historia sprawy', 'mp-service-intake' ) );

		if ( array() === $events ) {
			echo '<p style="color:#666">' . esc_html__( 'Brak zdarzeń.', 'mp-service-intake' ) . '</p></div>';
			return;
		}

		echo '<ul style="list-style:none;margin:0;padding:0;font-size:.9em">';
		foreach ( $events as $ev ) {
			$type  = (string) ( $ev['event_type'] ?? '' );
			$label = $labels[ $type ] ?? $type;
			$aid   = isset( $ev['actor_id'] ) && null !== $ev['actor_id'] ? (int) $ev['actor_id'] : 0;
			$actor = $aid > 0 ? get_userdata( $aid ) : null;
			$who   = $actor ? (string) $actor->display_name : __( 'system', 'mp-service-intake' );
			$when  = self::fmt_date( (string) ( $ev['created_at'] ?? '' ) );

			echo '<li style="margin:.3rem 0;padding:.3rem .5rem;border-left:3px solid #c3c4c7">';
			echo '<strong>' . esc_html( $label ) . '</strong> · ' . esc_html( $who ) . '<br /><span style="color:#777">' . esc_html( $when ) . '</span>';
			echo '</li>';
		}
		echo '</ul></div>';
	}

	/**
	 * Data UTC => lokalna czytelna (puste => '—').
	 *
	 * @param string $gmt Data 'Y-m-d H:i:s' UTC.
	 * @return string
	 */
	private static function fmt_date( string $gmt ): string {
		return '' !== $gmt ? get_date_from_gmt( $gmt, 'Y-m-d H:i' ) : '—';
	}
}
