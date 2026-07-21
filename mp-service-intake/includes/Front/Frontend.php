<?php
/**
 * Front Intake: shortcode + blok Gutenberga + auto-strona + naglowki bezp.
 *
 * Renderowanie przez BLOK (lekcja: buildery nie renderuja shortcode) ORAZ
 * shortcode jako fallback — oba wolaja ten sam FormRenderer. Auto-strona
 * tworzona przy aktywacji z ODCISKIEM PALCA (kasowana w uninstall tylko gdy
 * nieedytowana recznie — wzorzec catsnboard). Naglowki SAMEORIGIN+nosniff
 * na stronie formularza.
 *
 * @package MP\Intake
 */

namespace MP\Intake\Front;

/**
 * Rejestracja frontu i utrzymanie auto-strony.
 */
final class Frontend {

	/**
	 * Opcja z ID auto-utworzonej strony formularza.
	 */
	public const PAGE_OPTION = 'mp_intake_form_page_id';

	/**
	 * Opcja z odciskiem palca oryginalnej tresci (kasacja tylko gdy nietkniete).
	 */
	public const FINGERPRINT_OPTION = 'mp_intake_form_page_fingerprint';

	/**
	 * Znacznik bloku w tresci auto-strony.
	 */
	private const BLOCK_MARKUP = '<!-- wp:mp/intake-form /-->';

	/**
	 * Rejestruje shortcode, blok i naglowki (na init/front).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_shortcode( 'mp_intake_form', array( self::class, 'render_shortcode' ) );
		add_action( 'init', array( self::class, 'register_block' ) );
		add_action( 'template_redirect', array( self::class, 'maybe_security_headers' ) );
	}

	/**
	 * Render shortcode (fallback dla motywow/builderow bez bloku).
	 *
	 * @return string
	 */
	public static function render_shortcode(): string {
		return FormRenderer::render( SubmissionHandler::pull_context() );
	}

	/**
	 * Rejestruje dynamiczny blok (server-render tym samym rendererem).
	 *
	 * @return void
	 */
	public static function register_block(): void {
		if ( ! function_exists( 'register_block_type' ) ) {
			return;
		}

		register_block_type(
			'mp/intake-form',
			array(
				'api_version'     => '3',
				'title'           => __( 'Formularz zgłoszenia MP', 'mp-service-intake' ),
				'category'        => 'widgets',
				'icon'            => 'clipboard',
				'render_callback' => array( self::class, 'render_block' ),
			)
		);
	}

	/**
	 * Render bloku (front).
	 *
	 * @return string
	 */
	public static function render_block(): string {
		return FormRenderer::render( SubmissionHandler::pull_context() );
	}

	/**
	 * Dokłada nagłówki bezpieczeństwa na stronie formularza.
	 *
	 * @return void
	 */
	public static function maybe_security_headers(): void {
		$page_id = (int) get_option( self::PAGE_OPTION, 0 );

		if ( 0 === $page_id || ! is_page( $page_id ) || headers_sent() ) {
			return;
		}

		header( 'X-Frame-Options: SAMEORIGIN' );
		header( 'X-Content-Type-Options: nosniff' );
	}

	/**
	 * Tworzy auto-stronę formularza (idempotentnie) z odciskiem palca.
	 *
	 * @return void
	 */
	public static function ensure_page(): void {
		$existing = (int) get_option( self::PAGE_OPTION, 0 );

		if ( $existing > 0 && 'page' === get_post_type( $existing ) && 'trash' !== get_post_status( $existing ) ) {
			return;
		}

		$content = self::BLOCK_MARKUP;
		$page_id = wp_insert_post(
			array(
				'post_title'   => __( 'Zgłoszenie serwisowe', 'mp-service-intake' ),
				'post_content' => $content,
				'post_status'  => 'publish',
				'post_type'    => 'page',
			)
		);

		if ( is_int( $page_id ) && $page_id > 0 ) {
			update_option( self::PAGE_OPTION, $page_id, false );
			update_option( self::FINGERPRINT_OPTION, md5( $content ), false );
		}
	}

	/**
	 * Odcisk palca oryginalnej tresci (do decyzji o kasacji przy uninstall).
	 *
	 * @return string
	 */
	public static function original_fingerprint(): string {
		return md5( self::BLOCK_MARKUP );
	}
}
