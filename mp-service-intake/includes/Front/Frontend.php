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
		add_filter( 'wp_robots', array( self::class, 'no_index_client_author_archive' ) );
	}

	/**
	 * Archiwum autora konta KLIENTA nie idzie do wyszukiwarek.
	 *
	 * Pas zapasowy do naprawy 2.54. Nazwa wyswietlana i adres strony sa juz
	 * neutralne, wiec dane osobowe stamtad nie wyciekaja — ale ta strona nadal
	 * powstaje dla kazdego konta klienta, a konto klienta nie jest autorem
	 * zadnej tresci. Panel klienta ma `noindex` od poczatku; tutaj brakowalo
	 * czegokolwiek. Ekrany personelu i administratora zostaja bez zmian.
	 *
	 * @param array<string, bool> $robots Dyrektywy dla robotow.
	 * @return array<string, bool>
	 */
	public static function no_index_client_author_archive( $robots ) {
		if ( ! is_array( $robots ) || ! is_author() ) {
			return $robots;
		}

		$autor = get_queried_object();

		if ( ! $autor instanceof \WP_User || ! \MP\Intake\Accounts::is_client_only( $autor ) ) {
			return $robots;
		}

		return wp_robots_no_robots( $robots );
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

		if ( ! PageDetect::is_plugin_page( $page_id, 'mp_intake_form' ) ) {
			return;
		}

		PageDetect::send(
			array(
				'X-Frame-Options'         => 'SAMEORIGIN',
				'X-Content-Type-Options'  => 'nosniff',
				// Nowoczesny odpowiednik X-Frame-Options (starsze przegladarki czytaja tamten).
				'Content-Security-Policy' => "frame-ancestors 'self';",
				'Referrer-Policy'         => 'strict-origin-when-cross-origin',
			),
			'form'
		);
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
