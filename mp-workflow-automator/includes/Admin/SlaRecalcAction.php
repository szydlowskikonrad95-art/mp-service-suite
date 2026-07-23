<?php
/**
 * Akcja admina „Przelicz SLA" (P3.4 / SLA-4) — BACKEND-HANDLER-ONLY.
 *
 * Handler `admin_post_mp_automator_recalc_sla`: przelicza terminy WSZYSTKICH
 * otwartych spraw wg biezacego SlaConfig (Sla::recompute_open), bez resetu markerow
 * (nieretroaktywnosc). CELOWO bez `add_menu_page` — menu/panel admina automatora to
 * osobne zadanie („panel admina D"); ta klasa rejestruje TYLKO akcje. Przycisk wpina
 * przyszly panel przez `form_fields()` (action + nonce). Wzorzec bezpieczenstwa jak
 * intake `admin_post_mp_intake_resend`: capability -> nonce -> akcja -> redirect.
 *
 * @package MP\Automator
 */

namespace MP\Automator\Admin;

use MP\Automator\Sla;
use MP\Automator\WorkflowEvents;

/**
 * Rejestracja i obsluga akcji „Przelicz SLA".
 */
final class SlaRecalcAction {

	/**
	 * Nazwa akcji admin_post (URL: admin-post.php?action=...).
	 */
	public const ACTION = 'mp_automator_recalc_sla';

	/**
	 * Akcja nonce (check_admin_referer / wp_nonce_field).
	 */
	public const NONCE = 'mp_automator_recalc_sla';

	/**
	 * Wymagana capability — WASKO: przeliczenie WSZYSTKICH terminow to operacja
	 * poziomu system-config, nie codzienna robota koordynatora (decyzja straznika).
	 */
	public const CAP = 'mp_system_admin';

	/**
	 * Rejestruje handler (wolane addytywnie z Plugin::boot). BEZ admin_post_nopriv —
	 * akcja wylacznie dla zalogowanego system-admina.
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_' . self::ACTION, array( self::class, 'handle' ) );
	}

	/**
	 * Obsluga POST: capability -> nonce -> Sla::recompute_open -> audyt -> redirect.
	 *
	 * @return void
	 */
	public static function handle(): void {
		if ( ! current_user_can( self::CAP ) ) {
			wp_die(
				esc_html__( 'Brak uprawnień do przeliczenia SLA.', 'mp-workflow-automator' ),
				'',
				array( 'response' => 403 )
			);
		}

		check_admin_referer( self::NONCE );

		$touched = Sla::recompute_open();

		// Audyt append-only: kto (actor_id) / kiedy (created_at) / ile (payload). NO-PII.
		WorkflowEvents::log(
			WorkflowEvents::SLA_RECALCULATED,
			array( 'cases_touched' => $touched ),
			null,
			get_current_user_id()
		);

		self::back( $touched );
	}

	/**
	 * Pola formularza dla PRZYSZLEGO panelu admina D (action + nonce) — panel renderuje
	 * `<form method="post" action="{admin_url('admin-post.php')}">` + te pola + przycisk.
	 *
	 * @return string HTML (hidden action + nonce field).
	 */
	public static function form_fields(): string {
		return '<input type="hidden" name="action" value="' . esc_attr( self::ACTION ) . '">'
			. wp_nonce_field( self::NONCE, '_wpnonce', true, false );
	}

	/**
	 * Powrot na strone wywolujaca (referer) z licznikiem przeliczonych spraw.
	 *
	 * @param int $touched Ile spraw dotknieto.
	 * @return void
	 */
	private static function back( int $touched ): void {
		$ref = wp_get_referer();
		$url = false !== $ref ? $ref : admin_url();
		$url = add_query_arg( 'mp_sla_recalc', (string) $touched, $url );

		wp_safe_redirect( $url );
		exit;
	}
}
