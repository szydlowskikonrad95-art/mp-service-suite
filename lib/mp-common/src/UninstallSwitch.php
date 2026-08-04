<?php
/**
 * Przelacznik „skasuj dane przy odinstalowaniu" — wspolny dla trzech wtyczek.
 *
 * Kazdy `uninstall.php` czytal wlasna opcje (`mp_*_delete_data`) i domyslnie
 * ZOSTAWIAL dane. To bylo poprawne, ale opcji nie dalo sie ustawic z zadnego
 * ekranu — czytana byla trzykrotnie, zapisywana zero razy. Administrator, ktory
 * chcial odinstalowac wtyczke razem z danymi, nie mial jak.
 *
 * Kod jest TU, a nie trzy razy w kazdej wtyczce, bo trzy kopie tej samej decyzji
 * rozjezdzaja sie po pierwszej poprawce — a ta decyzja kasuje dane bezpowrotnie.
 *
 * @package MP\Common
 */

namespace MP\Common;

/**
 * Rejestracja, render i obsluga przelacznika kasowania danych.
 */
final class UninstallSwitch {

	/**
	 * Akcja admin-post => {option, cap}. Wypelniane przez register().
	 *
	 * @var array<string, array{option: string, cap: string, msg_403: callable}>
	 */
	private static array $zarejestrowane = array();

	/**
	 * Podpina handler akcji. Wolane raz per wtyczka, z jej wlasna nazwa akcji
	 * i wlasna opcja — wtyczki sa niezalezne i kasuja swoje dane osobno.
	 *
	 * ⚠️ Komunikat odmowy przychodzi Z WTYCZKI, a nie stad: wspolny kod trafia do
	 * trzech wtyczek o TRZECH roznych domenach tlumaczen i nie ma jak przetlumaczyc
	 * wlasnego zdania.
	 * ⛔ I przychodzi jako FUNKCJA, nie jako gotowy tekst: rejestracja dzieje sie przy
	 * wczytaniu wtyczki, a tlumaczenie wywolane tak wczesnie WordPress 6.7+ zglasza
	 * jako blad uzycia (i slusznie — jezyk nie jest jeszcze ustalony). Funkcje wolamy
	 * dopiero przy zapisie, czyli long po `init`.
	 *
	 * @param string $action  Nazwa akcji admin-post (= akcja nonce).
	 * @param string $option  Nazwa opcji czytanej przez uninstall.php tej wtyczki.
	 * @param string $cap     Wymagana capability.
	 * @param callable $msg_403 Funkcja zwracajaca komunikat odmowy (wolana przy zapisie).
	 * @return void
	 */
	public static function register( string $action, string $option, string $cap, callable $msg_403 ): void {
		self::$zarejestrowane[ $action ] = array(
			'option'  => $option,
			'cap'     => $cap,
			'msg_403' => $msg_403,
		);

		add_action( 'admin_post_' . $action, array( self::class, 'handle' ) );
		add_action( 'admin_post_nopriv_' . $action, array( self::class, 'handle' ) );
	}

	/**
	 * Czy przelacznik jest wlaczony.
	 *
	 * @param string $option Nazwa opcji.
	 * @return bool
	 */
	public static function is_on( string $option ): bool {
		return '1' === (string) get_option( $option, '0' );
	}

	/**
	 * Formularz sekcji. Tekst ostrzezenia jest CZESCIA tego formularza, a nie
	 * ozdobnikiem: wlaczenie przelacznika kasuje dane bez mozliwosci cofniecia.
	 *
	 * @param string $action Nazwa akcji admin-post.
	 * @param string $option Nazwa opcji.
	 * @param string $etykieta Tresc przy polu wyboru (juz przetlumaczona).
	 * @param string $opis     Zdanie pod polem (juz przetlumaczone).
	 * @param string $przycisk Etykieta przycisku (juz przetlumaczona).
	 * @return void
	 */
	public static function render( string $action, string $option, string $etykieta, string $opis, string $przycisk ): void {
		?>
		<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
			<input type="hidden" name="action" value="<?php echo esc_attr( $action ); ?>" />
			<?php wp_nonce_field( $action ); ?>
			<p>
				<label>
					<input type="checkbox" name="mp_delete_data" value="1" <?php checked( self::is_on( $option ) ); ?> />
					<?php echo esc_html( $etykieta ); ?>
				</label>
			</p>
			<p class="description"><?php echo esc_html( $opis ); ?></p>
			<?php submit_button( $przycisk, 'secondary', 'mp-zapisz-odinstalowanie', false ); ?>
		</form>
		<?php
	}

	/**
	 * Handler zapisu. Akcje rozpoznajemy po `$_POST['action']`, bo jeden handler
	 * obsluguje trzy wtyczki — i kazda ma WLASNA opcje oraz wlasna bramke.
	 *
	 * @return void
	 */
	public static function handle(): void {
		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- nonce sprawdzany nizej, po ustaleniu ktora to akcja (nazwa nonce = nazwa akcji).
		$action = isset( $_POST['action'] ) ? sanitize_key( (string) wp_unslash( $_POST['action'] ) ) : '';

		if ( ! isset( self::$zarejestrowane[ $action ] ) ) {
			wp_die( 'Nieznana akcja.', '', array( 'response' => 400 ) );
		}

		$cfg = self::$zarejestrowane[ $action ];

		if ( ! current_user_can( $cfg['cap'] ) ) {
			wp_die( esc_html( (string) call_user_func( $cfg['msg_403'] ) ), '', array( 'response' => 403 ) );
		}

		check_admin_referer( $action );

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$wlaczone = ! empty( $_POST['mp_delete_data'] ) ? '1' : '0';

		update_option( $cfg['option'], $wlaczone, false );

		/**
		 * Zmiana przelacznika kasowania danych. Wtyczka dopisuje to do WLASNEGO
		 * rejestru zdarzen — wspolny kod nie zna dziennika konkretnej wtyczki,
		 * a decyzja o kasowaniu danych musi zostawiac slad KTO i KIEDY.
		 *
		 * @param string $option   Nazwa opcji.
		 * @param string $wlaczone '1' albo '0'.
		 */
		do_action( 'mp_uninstall_switch_changed', $cfg['option'], $wlaczone );

		$ref = wp_get_referer();
		wp_safe_redirect( add_query_arg( 'mp_settings_ok', 'odinstaluj', false !== $ref ? $ref : admin_url() ) );
		exit;
	}
}
