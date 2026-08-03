<?php
/**
 * Ekran USTAWIEN modulu zgloszen (1.3.12).
 *
 * Na razie mieszka tu jedna decyzja, ale wazna: czy odinstalowanie wtyczki ma
 * skasowac jej dane. `uninstall.php` czytal ta opcje od poczatku i domyslnie
 * ZOSTAWIAL dane — tyle ze ustawic jej nie dalo sie z zadnego ekranu.
 *
 * @package MP\Intake
 */

namespace MP\Intake\Admin;

use MP\Intake\Common\UninstallSwitch;

/**
 * Podstrona „Ustawienia" pod menu spraw.
 */
final class SettingsScreen {

	/**
	 * Slug podstrony.
	 */
	public const PAGE_SLUG = 'mp-intake-settings';

	/**
	 * Akcja admin-post przelacznika (= akcja nonce).
	 */
	public const ACTION_UNINSTALL = 'mp_intake_uninstall_switch';

	/**
	 * Opcja czytana przez `uninstall.php` tej wtyczki.
	 */
	public const OPTION_DELETE_DATA = 'mp_intake_delete_data';

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
			__( 'Brak uprawnień do ustawień modułu zgłoszeń.', 'mp-service-intake' )
		);
	}

	/**
	 * Podstrona pod menu spraw.
	 *
	 * @return void
	 */
	public static function add_menu(): void {
		add_submenu_page(
			CasesScreen::PAGE_SLUG,
			__( 'Ustawienia zgłoszeń', 'mp-service-intake' ),
			__( 'Ustawienia', 'mp-service-intake' ),
			self::CAP,
			self::PAGE_SLUG,
			array( self::class, 'render' )
		);
	}

	/**
	 * Ekran. Bramka capability TU, nie tylko w menu — ukryta pozycja menu nie jest
	 * zabezpieczeniem, adres strony da sie wpisac recznie.
	 *
	 * @return void
	 */
	public static function render(): void {
		if ( ! current_user_can( self::CAP ) ) {
			wp_die(
				esc_html__( 'Brak uprawnień do ustawień modułu zgłoszeń.', 'mp-service-intake' ),
				'',
				array( 'response' => 403 )
			);
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- odczyt flagi z wlasnego redirectu (bez zmiany stanu); handler zapisu mial nonce.
		$ok = isset( $_GET['mp_settings_ok'] ) ? sanitize_key( (string) wp_unslash( $_GET['mp_settings_ok'] ) ) : '';

		?>
		<div class="wrap">
			<h1><?php esc_html_e( 'Ustawienia zgłoszeń', 'mp-service-intake' ); ?></h1>
			<?php if ( 'odinstaluj' === $ok ) : ?>
				<div class="notice notice-success is-dismissible"><p><?php esc_html_e( 'Ustawienie kasowania danych zapisane.', 'mp-service-intake' ); ?></p></div>
			<?php endif; ?>

			<h2><?php esc_html_e( 'Kasowanie danych przy odinstalowaniu', 'mp-service-intake' ); ?></h2>
			<?php
			UninstallSwitch::render(
				self::ACTION_UNINSTALL,
				self::OPTION_DELETE_DATA,
				__( 'Przy odinstalowaniu wtyczki skasuj także jej dane (sprawy, wiadomości, załączniki, zgody).', 'mp-service-intake' ),
				__( 'Domyślnie WYŁĄCZONE: odinstalowanie zostawia dane, więc ponowna instalacja je zastaje. Włączenie oznacza kasowanie bezpowrotne — razem ze sprawami klientów i ich załącznikami. Ustawienie dotyczy WYŁĄCZNIE modułu zgłoszeń; pozostałe wtyczki mają własne.', 'mp-service-intake' ),
				__( 'Zapisz ustawienie', 'mp-service-intake' )
			);
			?>
		</div>
		<?php
	}
}
