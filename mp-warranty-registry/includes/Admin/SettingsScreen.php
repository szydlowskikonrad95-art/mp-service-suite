<?php
/**
 * Ekran USTAWIEN rejestru produktow (1.3.12).
 *
 * Mieszka tu decyzja o kasowaniu danych przy odinstalowaniu. `uninstall.php`
 * czytal ta opcje od poczatku i domyslnie ZOSTAWIAL dane — ustawic jej nie dalo
 * sie z zadnego ekranu.
 *
 * @package MP\Registry
 */

namespace MP\Registry\Admin;

use MP\Registry\Common\UninstallSwitch;

/**
 * Podstrona „Ustawienia" pod menu rejestru.
 */
final class SettingsScreen {

	/**
	 * Slug podstrony.
	 */
	public const PAGE_SLUG = 'mp-registry-settings';

	/**
	 * Akcja admin-post przelacznika (= akcja nonce).
	 */
	public const ACTION_UNINSTALL = 'mp_registry_uninstall_switch';

	/**
	 * Opcja czytana przez `uninstall.php` tej wtyczki.
	 */
	public const OPTION_DELETE_DATA = 'mp_registry_delete_data';

	/**
	 * Capability ekranu — konfiguracja to poziom system-config.
	 */
	public const CAP = 'mp_system_admin';

	/**
	 * Rejestruje menu i handler przelacznika.
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_menu', array( self::class, 'add_menu' ) );

		UninstallSwitch::register(
			self::ACTION_UNINSTALL,
			self::OPTION_DELETE_DATA,
			self::CAP,
			__( 'Brak uprawnień do ustawień rejestru.', 'mp-warranty-registry' )
		);
	}

	/**
	 * Podstrona pod menu rejestru.
	 *
	 * @return void
	 */
	public static function add_menu(): void {
		add_submenu_page(
			ProductsScreen::PAGE_SLUG,
			__( 'Ustawienia rejestru', 'mp-warranty-registry' ),
			__( 'Ustawienia', 'mp-warranty-registry' ),
			self::CAP,
			self::PAGE_SLUG,
			array( self::class, 'render' )
		);
	}

	/**
	 * Ekran. Bramka capability TU, nie tylko w menu.
	 *
	 * @return void
	 */
	public static function render(): void {
		if ( ! current_user_can( self::CAP ) ) {
			wp_die(
				esc_html__( 'Brak uprawnień do ustawień rejestru.', 'mp-warranty-registry' ),
				'',
				array( 'response' => 403 )
			);
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- odczyt flagi z wlasnego redirectu (bez zmiany stanu); handler zapisu mial nonce.
		$ok = isset( $_GET['mp_settings_ok'] ) ? sanitize_key( (string) wp_unslash( $_GET['mp_settings_ok'] ) ) : '';

		?>
		<div class="wrap">
			<h1><?php esc_html_e( 'Ustawienia rejestru', 'mp-warranty-registry' ); ?></h1>
			<?php if ( 'odinstaluj' === $ok ) : ?>
				<div class="notice notice-success is-dismissible"><p><?php esc_html_e( 'Ustawienie kasowania danych zapisane.', 'mp-warranty-registry' ); ?></p></div>
			<?php endif; ?>

			<h2><?php esc_html_e( 'Kasowanie danych przy odinstalowaniu', 'mp-warranty-registry' ); ?></h2>
			<?php
			UninstallSwitch::render(
				self::ACTION_UNINSTALL,
				self::OPTION_DELETE_DATA,
				__( 'Przy odinstalowaniu wtyczki skasuj także jej dane (produkty, gwarancje, wyjątki gwarancyjne).', 'mp-warranty-registry' ),
				__( 'Domyślnie WYŁĄCZONE: odinstalowanie zostawia dane, więc ponowna instalacja je zastaje. Włączenie oznacza kasowanie bezpowrotne — razem z całym rejestrem produktów. Ustawienie dotyczy WYŁĄCZNIE rejestru; pozostałe wtyczki mają własne.', 'mp-warranty-registry' ),
				__( 'Zapisz ustawienie', 'mp-warranty-registry' )
			);
			?>
		</div>
		<?php
	}
}
