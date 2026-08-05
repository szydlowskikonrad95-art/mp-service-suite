<?php
/**
 * Ekran USTAWIEN modulu automatyzacji (1.3.12).
 *
 * Po co powstal: produkt mial zbudowana cala warstwe ODCZYTU konfiguracji i cztery
 * dzialajace zapisy z panelu (szablony odpowiedzi, szablony maili, checklisty, pula
 * pracownikow) — ale DOKLADNIE tam, gdzie zamowienie uzylo slowa „konfigurowalne",
 * drogi dla czlowieka nie bylo:
 *  - statusy wlasne: `StatusDefs::upsert()` istnial i NIKT go nie wolal,
 *  - godziny terminow: `SlaConfig` czytal opcje, ktorej NIC nigdy nie zapisywalo,
 *  - reguly przydzialu: `Rules::insert()` wolal wylacznie test, panel dawal podglad,
 *  - przelacznik kasowania danych przy odinstalowaniu: czytany w `uninstall.php`,
 *    nieustawialny z zadnego ekranu.
 * To NIE byla warstwa niezbudowana — to byla warstwa niedoprowadzona do konca.
 * Ten ekran ja domyka i dlatego jest JEDEN, a nie cztery osobne latki.
 *
 * @package MP\Automator
 */

namespace MP\Automator\Admin;

use MP\Automator\Common\UninstallSwitch;
use MP\Automator\Rules;
use MP\Automator\SlaConfig;
use MP\Automator\StatusDefs;
use MP\Automator\WorkflowEvents;

/**
 * Podstrona „Ustawienia" pod menu automatyzacji.
 */
final class SettingsScreen {

	/**
	 * Slug podstrony.
	 */
	public const PAGE_SLUG = 'mp-automator-settings';

	/**
	 * Akcja admin-post przelacznika kasowania danych (= akcja nonce).
	 */
	public const ACTION_UNINSTALL = 'mp_automator_uninstall_switch';

	/**
	 * Opcja czytana przez `uninstall.php` tej wtyczki.
	 */
	public const OPTION_DELETE_DATA = 'mp_automator_delete_data';

	/**
	 * Capability calego ekranu — konfiguracja to poziom system-config.
	 */
	public const CAP = 'mp_system_admin';

	/**
	 * Hook suffix tej podstrony — po nim poznajemy, ze arkusz ma sie zaladowac
	 * WYLACZNIE tutaj (porownanie po slugu zlapaloby tez cudze ekrany).
	 *
	 * @var string
	 */
	private static $hook_suffix = '';

	/**
	 * Rejestruje menu i handler przelacznika (wolane addytywnie z Plugin::boot).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_menu', array( self::class, 'add_menu' ) );
		add_action( 'admin_enqueue_scripts', array( self::class, 'enqueue' ) );

		// Przelacznik kasowania danych jest WSPOLNY dla trzech wtyczek (lib/mp-common) —
		// trzy kopie decyzji, ktora kasuje dane bezpowrotnie, rozjechalyby sie.
		UninstallSwitch::register(
			self::ACTION_UNINSTALL,
			self::OPTION_DELETE_DATA,
			self::CAP,
			static fn(): string => __( 'Brak uprawnień do ustawień odinstalowania.', 'mp-workflow-automator' )
		);
		add_action( 'mp_uninstall_switch_changed', array( self::class, 'log_uninstall_switch' ), 10, 2 );
	}

	/**
	 * Slad w rejestrze zdarzen po zmianie przelacznika (kto/kiedy/jaka wartosc).
	 * Wspolny kod nie zna dziennika tej wtyczki, wiec dopisujemy go tutaj.
	 *
	 * @param string $option   Nazwa opcji, ktora sie zmienila.
	 * @param string $wlaczone '1' albo '0'.
	 * @return void
	 */
	public static function log_uninstall_switch( string $option, string $wlaczone ): void {
		if ( self::OPTION_DELETE_DATA !== $option ) {
			return;
		}

		WorkflowEvents::log(
			WorkflowEvents::CONFIG_CHANGED,
			array(
				'object' => 'uninstall_delete_data',
				'value'  => $wlaczone,
			),
			null,
			get_current_user_id()
		);
	}

	/**
	 * Podstrona pod menu automatyzacji. Koordynator jej NIE widzi (cap wezszy niz
	 * menu nadrzedne) — to swiadome: zmiana statusow i terminow przestawia caly serwis.
	 *
	 * @return void
	 */
	public static function add_menu(): void {
		self::$hook_suffix = (string) add_submenu_page(
			PanelScreen::PAGE_SLUG,
			__( 'Ustawienia automatyzacji', 'mp-workflow-automator' ),
			__( 'Ustawienia', 'mp-workflow-automator' ),
			self::CAP,
			self::PAGE_SLUG,
			array( self::class, 'render' )
		);
	}

	/**
	 * Laduje arkusz modulu WYLACZNIE na tej podstronie.
	 *
	 * ⛔ TU SIEDZIALA WADA S4 nr 6, i nie byla nia zla regula CSS — byl nia BRAK
	 * ZALADOWANIA ARKUSZA W OGOLE. Ekran od poczatku pisany byl pod styl panelu
	 * (`mp-automator-panel`, `-intro`, `-h2`, `-h3` sa w jego markupie), ale
	 * `PanelScreen::enqueue()` wypuszcza plik tylko na SWOJ hook, a ta klasa
	 * zadnego `enqueue` nie miala. Skutkiem bylo m.in. to, ze naprawa poz. 2.6
	 * (region przewijany `.mp-automator-table-scroll`) tutaj nie obowiazywala,
	 * wiec trzy szerokie tabele rozpychaly CALA strone: przy 390 px widac bylo
	 * z „Statusow wlasnych" wylacznie pierwsza kolumne, a przy 1440 px strona
	 * przewijala sie w bok o 148 px.
	 *
	 * Porownanie po hook suffiksie, a nie po `$_GET['page']`, jest tu istotne:
	 * slug w adresie da sie dopisac do dowolnego ekranu admina, a wtedy styl
	 * wyciekalby na cudze strony — m.in. na liste spraw i karte sprawy.
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
			PanelScreen::asset_ver( 'assets/css/admin-automator.css' )
		);
	}

	/**
	 * Ekran. Bramka capability jest TU, nie tylko w menu — ukryta pozycja menu
	 * nie jest zabezpieczeniem, adres strony da sie wpisac recznie.
	 *
	 * @return void
	 */
	public static function render(): void {
		if ( ! current_user_can( self::CAP ) ) {
			wp_die(
				esc_html__( 'Brak uprawnień do ustawień automatyzacji.', 'mp-workflow-automator' ),
				'',
				array( 'response' => 403 )
			);
		}

		?>
		<div class="wrap mp-automator-panel">
			<h1><?php esc_html_e( 'Ustawienia automatyzacji', 'mp-workflow-automator' ); ?></h1>
			<p class="mp-automator-intro">
				<?php esc_html_e( 'Statusy spraw, godziny terminów, reguły przydziału i kasowanie danych przy odinstalowaniu. Każdą sekcję zapisuje się osobnym przyciskiem.', 'mp-workflow-automator' ); ?>
			</p>
			<?php
			self::render_notices();
			self::render_statuses_form();
			self::render_sla_form();
			self::render_rules_form();
			self::render_uninstall_form();
			?>
		</div>
		<?php
	}

	/**
	 * Komunikaty po zapisie. Blad NIE jest ogolny („cos poszlo nie tak") — mowi,
	 * ktora sekcja i czego dotyczy, bo inaczej czlowiek zapisuje w kolko to samo.
	 *
	 * @return void
	 */
	private static function render_notices(): void {
		// phpcs:disable WordPress.Security.NonceVerification.Recommended -- odczyt flag z wlasnego redirectu (bez zmiany stanu); handlery zapisu maja nonce.
		$blad  = isset( $_GET['mp_settings_error'] ) ? sanitize_key( (string) wp_unslash( $_GET['mp_settings_error'] ) ) : '';
		$ok    = isset( $_GET['mp_settings_ok'] ) ? sanitize_key( (string) wp_unslash( $_GET['mp_settings_ok'] ) ) : '';
		$detal = isset( $_GET['mp_settings_detal'] ) ? sanitize_text_field( wp_unslash( $_GET['mp_settings_detal'] ) ) : '';
		$detal = sanitize_text_field( rawurldecode( $detal ) );
		// phpcs:enable WordPress.Security.NonceVerification.Recommended

		if ( '' !== $blad ) {
			$komunikaty = array(
				'konflikt-statusy' => __( 'Ktoś zapisał statusy w międzyczasie — Twoje zmiany NIE zostały zapisane, żeby nie nadpisać cudzych. Odśwież stronę i nanieś je ponownie.', 'mp-workflow-automator' ),
				'konflikt-terminy' => __( 'Ktoś zapisał godziny terminów w międzyczasie — Twoje zmiany NIE zostały zapisane. Odśwież stronę i nanieś je ponownie.', 'mp-workflow-automator' ),
			);

			$tresc = $komunikaty[ $blad ] ?? '';

			if ( 'statusy-odrzucone' === $blad ) {
				$tresc = sprintf(
					/* translators: %s = lista odrzuconych kluczy statusów */
					__( 'Te statusy NIE zostały zapisane, bo klucz jest pusty albo dłuższy niż 20 znaków: %s. Klucz to nazwa techniczna (małe litery, cyfry, myślnik) — nazwę widoczną dla ludzi wpisuje się w polu obok.', 'mp-workflow-automator' ),
					$detal
				);
			}

			if ( '' !== $tresc ) {
				?>
				<div class="notice notice-error is-dismissible"><p><?php echo esc_html( $tresc ); ?></p></div>
				<?php
			}
		}

		if ( '' !== $ok ) {
			$potwierdzenia = array(
				'statusy'    => __( 'Statusy zapisane.', 'mp-workflow-automator' ),
				'terminy'    => __( 'Godziny terminów zapisane. Sprawy już otwarte mają nadal STARE terminy — przelicz je przyciskiem „Przelicz terminy obsługi" w panelu automatyzacji.', 'mp-workflow-automator' ),
				'reguly'     => __( 'Reguły przydziału zapisane.', 'mp-workflow-automator' ),
				'odinstaluj' => __( 'Ustawienie kasowania danych zapisane.', 'mp-workflow-automator' ),
			);

			$tresc = $potwierdzenia[ $ok ] ?? '';

			if ( '' !== $tresc ) {
				?>
				<div class="notice notice-success is-dismissible"><p><?php echo esc_html( $tresc ); ?></p></div>
				<?php
			}
		}
	}

	/**
	 * Sekcja statusow wlasnych. Rdzenia 7 tu NIE MA i nie moze byc — nalezy do
	 * walidatora modulu zgloszen i jest nieusuwalny; ekran, ktory udawalby,
	 * ze da sie go skasowac, klamalby.
	 *
	 * @return void
	 */
	private static function render_statuses_form(): void {
		$statusy = StatusDefs::all();
		?>
		<h2 class="mp-automator-h2"><?php esc_html_e( 'Statusy własne', 'mp-workflow-automator' ); ?></h2>
		<p class="description">
			<?php esc_html_e( 'Siedem statusów wbudowanych (nowe, do uzupełnienia, w analizie, zaakceptowane, odrzucone, w naprawie, zamknięte) jest nieusuwalnych. Tutaj dokładasz własne — pojawią się w filtrze spraw i w walidatorze zmian statusu.', 'mp-workflow-automator' ); ?>
		</p>
		<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
			<input type="hidden" name="action" value="<?php echo esc_attr( StatusDefs::ACTION_CONFIG ); ?>" />
			<input type="hidden" name="mp_config_rev" value="<?php echo esc_attr( StatusDefs::config_rev() ); ?>" />
			<?php wp_nonce_field( StatusDefs::ACTION_CONFIG ); ?>
			<?php // Region przewijany — ten sam wzorzec co panel (poz. 2.6). Bez niego siedem kolumn rozpychalo CALA strone i przy 390 px widac bylo wylacznie „Klucz techniczny". ?>
			<div class="mp-automator-table-scroll" role="region" tabindex="0" aria-label="<?php echo esc_attr__( 'Tabela statusów własnych', 'mp-workflow-automator' ); ?>">
			<table class="widefat striped">
				<thead>
					<tr>
						<th scope="col"><?php esc_html_e( 'Klucz techniczny', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Nazwa widoczna', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Aktywny', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Kończy sprawę', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Termin (godz.)', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Ostrzeż na (godz. przed)', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Usuń', 'mp-workflow-automator' ); ?></th>
					</tr>
				</thead>
				<tbody>
				<?php
				$i = 0;
				foreach ( $statusy as $slug => $def ) :
					?>
					<tr>
						<td>
							<label class="screen-reader-text" for="mp-status-slug-<?php echo esc_attr( (string) $i ); ?>"><?php esc_html_e( 'Klucz techniczny statusu', 'mp-workflow-automator' ); ?></label>
							<input type="hidden" name="mp_status[<?php echo esc_attr( (string) $i ); ?>][orig]" value="<?php echo esc_attr( $slug ); ?>" />
							<input type="text" id="mp-status-slug-<?php echo esc_attr( (string) $i ); ?>" name="mp_status[<?php echo esc_attr( (string) $i ); ?>][slug]" value="<?php echo esc_attr( $slug ); ?>" maxlength="20" class="regular-text" />
						</td>
						<td>
							<label class="screen-reader-text" for="mp-status-label-<?php echo esc_attr( (string) $i ); ?>"><?php esc_html_e( 'Nazwa widoczna', 'mp-workflow-automator' ); ?></label>
							<input type="text" id="mp-status-label-<?php echo esc_attr( (string) $i ); ?>" name="mp_status[<?php echo esc_attr( (string) $i ); ?>][label]" value="<?php echo esc_attr( $def['label'] ); ?>" class="regular-text" />
						</td>
						<td><input type="checkbox" name="mp_status[<?php echo esc_attr( (string) $i ); ?>][active]" value="1" <?php checked( $def['active'] ); ?> aria-label="<?php esc_attr_e( 'Status aktywny', 'mp-workflow-automator' ); ?>" /></td>
						<td><input type="checkbox" name="mp_status[<?php echo esc_attr( (string) $i ); ?>][terminal]" value="1" <?php checked( $def['terminal'] ); ?> aria-label="<?php esc_attr_e( 'Status kończy sprawę', 'mp-workflow-automator' ); ?>" /></td>
						<td><input type="number" min="0" name="mp_status[<?php echo esc_attr( (string) $i ); ?>][sla_hours]" value="<?php echo esc_attr( (string) $def['sla_hours'] ); ?>" class="small-text" aria-label="<?php esc_attr_e( 'Termin w godzinach', 'mp-workflow-automator' ); ?>" /></td>
						<td><input type="number" min="0" name="mp_status[<?php echo esc_attr( (string) $i ); ?>][warning_hours]" value="<?php echo esc_attr( (string) $def['warning_hours'] ); ?>" class="small-text" aria-label="<?php esc_attr_e( 'Ostrzeżenie na ile godzin przed terminem', 'mp-workflow-automator' ); ?>" /></td>
						<td><input type="checkbox" name="mp_status[<?php echo esc_attr( (string) $i ); ?>][delete]" value="1" aria-label="<?php esc_attr_e( 'Usuń ten status', 'mp-workflow-automator' ); ?>" /></td>
					</tr>
					<?php
					++$i;
				endforeach;
				?>
					<tr>
						<td>
							<label class="screen-reader-text" for="mp-status-slug-nowy"><?php esc_html_e( 'Klucz techniczny nowego statusu', 'mp-workflow-automator' ); ?></label>
							<input type="text" id="mp-status-slug-nowy" name="mp_status[nowy][slug]" value="" maxlength="20" class="regular-text" placeholder="<?php esc_attr_e( 'np. u-dostawcy', 'mp-workflow-automator' ); ?>" />
						</td>
						<td>
							<label class="screen-reader-text" for="mp-status-label-nowy"><?php esc_html_e( 'Nazwa widoczna nowego statusu', 'mp-workflow-automator' ); ?></label>
							<input type="text" id="mp-status-label-nowy" name="mp_status[nowy][label]" value="" class="regular-text" placeholder="<?php esc_attr_e( 'np. U dostawcy', 'mp-workflow-automator' ); ?>" />
						</td>
						<td><input type="checkbox" name="mp_status[nowy][active]" value="1" checked="checked" aria-label="<?php esc_attr_e( 'Nowy status aktywny', 'mp-workflow-automator' ); ?>" /></td>
						<td><input type="checkbox" name="mp_status[nowy][terminal]" value="1" aria-label="<?php esc_attr_e( 'Nowy status kończy sprawę', 'mp-workflow-automator' ); ?>" /></td>
						<td><input type="number" min="0" name="mp_status[nowy][sla_hours]" value="0" class="small-text" aria-label="<?php esc_attr_e( 'Termin nowego statusu w godzinach', 'mp-workflow-automator' ); ?>" /></td>
						<td><input type="number" min="0" name="mp_status[nowy][warning_hours]" value="0" class="small-text" aria-label="<?php esc_attr_e( 'Ostrzeżenie nowego statusu', 'mp-workflow-automator' ); ?>" /></td>
						<td>&mdash;</td>
					</tr>
				</tbody>
			</table>
			</div>
			<p class="description">
				<?php esc_html_e( 'Klucz techniczny: małe litery, cyfry, myślnik lub podkreślenie, najwyżej 20 znaków — tyle mieści kolumna statusu sprawy. Termin 0 = ten status nie jest pilnowany.', 'mp-workflow-automator' ); ?>
			</p>
			<?php submit_button( __( 'Zapisz statusy', 'mp-workflow-automator' ), 'primary', 'mp-zapisz-statusy', false ); ?>
		</form>
		<?php
	}

	/**
	 * Sekcja godzin terminow rdzenia. Statusy terminalne (odrzucone/zamkniete)
	 * nie maja terminu z zalozenia i dlatego nie ma ich w tabeli.
	 *
	 * @return void
	 */
	private static function render_sla_form(): void {
		$godziny = SlaConfig::core_effective();
		?>
		<h2 class="mp-automator-h2"><?php esc_html_e( 'Godziny terminów (statusy wbudowane)', 'mp-workflow-automator' ); ?></h2>
		<p class="description">
			<?php esc_html_e( 'Ile godzin sprawa może stać w danym statusie, zanim termin minie. Priorytet wysoki skraca termin o połowę, niski podwaja go. Statusy „odrzucone" i „zamknięte" terminu nie mają.', 'mp-workflow-automator' ); ?>
		</p>
		<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
			<input type="hidden" name="action" value="<?php echo esc_attr( SlaConfig::ACTION_CONFIG ); ?>" />
			<input type="hidden" name="mp_config_rev" value="<?php echo esc_attr( SlaConfig::config_rev() ); ?>" />
			<?php wp_nonce_field( SlaConfig::ACTION_CONFIG ); ?>
			<div class="mp-automator-table-scroll" role="region" tabindex="0" aria-label="<?php echo esc_attr__( 'Tabela godzin terminów', 'mp-workflow-automator' ); ?>">
			<table class="widefat striped">
				<thead>
					<tr>
						<th scope="col"><?php esc_html_e( 'Status', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Termin (godz.)', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Ostrzeż na (godz. przed)', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Wartość fabryczna', 'mp-workflow-automator' ); ?></th>
					</tr>
				</thead>
				<tbody>
				<?php
				$domyslne = SlaConfig::core_defaults();
				$nr       = 0;
				foreach ( $godziny as $slug => $cfg ) :
					$id_pola = 'mp-sla-' . $nr;
					?>
					<tr>
						<th scope="row"><label for="<?php echo esc_attr( $id_pola ); ?>"><?php echo esc_html( $slug ); ?></label></th>
						<td><input type="number" min="0" id="<?php echo esc_attr( $id_pola ); ?>" name="mp_sla[<?php echo esc_attr( $slug ); ?>][sla_hours]" value="<?php echo esc_attr( (string) $cfg['sla_hours'] ); ?>" class="small-text" /></td>
						<td><input type="number" min="0" name="mp_sla[<?php echo esc_attr( $slug ); ?>][warning_hours]" value="<?php echo esc_attr( (string) $cfg['warning_hours'] ); ?>" class="small-text" aria-label="<?php esc_attr_e( 'Ostrzeżenie na ile godzin przed terminem', 'mp-workflow-automator' ); ?>" /></td>
						<td><?php echo esc_html( (string) ( $domyslne[ $slug ] ?? 0 ) ); ?></td>
					</tr>
					<?php
					++$nr;
				endforeach;
				?>
				</tbody>
			</table>
			</div>
			<p class="description">
				<?php esc_html_e( 'UWAGA: zmiana godzin dotyczy terminów liczonych OD TERAZ. Sprawy już otwarte zachowują stare terminy do czasu użycia przycisku „Przelicz terminy obsługi" w panelu automatyzacji.', 'mp-workflow-automator' ); ?>
			</p>
			<?php submit_button( __( 'Zapisz godziny terminów', 'mp-workflow-automator' ), 'primary', 'mp-zapisz-terminy', false ); ?>
		</form>
		<?php
	}

	/**
	 * Sekcja regul przydzialu. Reguly systemowe zostaja widoczne i daja sie wylaczyc,
	 * ale nie skasowac — skasowana nie wroci (bramka SEED_VERSION jest jednorazowa).
	 *
	 * @return void
	 */
	private static function render_rules_form(): void {
		$reguly = Rules::all();
		?>
		<h2 class="mp-automator-h2"><?php esc_html_e( 'Reguły przydziału i powiadomień', 'mp-workflow-automator' ); ?></h2>
		<p class="description">
			<?php esc_html_e( 'Reguła działa tak: KIEDY coś się dzieje (wyzwalacz) → JEŚLI sprawa spełnia warunek → ZRÓB akcję. Reguły o niższym numerze kolejności sprawdzane są wcześniej. Pusty warunek znaczy „pasuje zawsze".', 'mp-workflow-automator' ); ?>
		</p>
		<div class="notice notice-warning inline">
			<p>
				<?php esc_html_e( 'Warunki „kraj" i „język" nie zadziałają: produkt nigdzie tych danych nie zbiera — ani formularz zgłoszenia, ani wiersz poleceń ich nie wypełnia, więc pole zawsze jest puste. Zostawiamy je na liście, bo kolumny istnieją, ale reguła oparta na nich nie dopasuje żadnej sprawy.', 'mp-workflow-automator' ); ?>
			</p>
		</div>
		<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
			<input type="hidden" name="action" value="<?php echo esc_attr( Rules::ACTION_CONFIG ); ?>" />
			<?php wp_nonce_field( Rules::ACTION_CONFIG ); ?>
			<?php // Osiem kolumn — to ta tabela robila poziome przewijanie CALEJ strony takze przy 1440 px (1406 px w polu tresci szerokim na 1280 px). ?>
			<div class="mp-automator-table-scroll" role="region" tabindex="0" aria-label="<?php echo esc_attr__( 'Tabela reguł przydziału i powiadomień', 'mp-workflow-automator' ); ?>">
			<table class="widefat striped">
				<thead>
					<tr>
						<th scope="col"><?php esc_html_e( 'Kiedy', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Warunek', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Operator', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Wartość', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Zrób', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Kolejność', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Włączona', 'mp-workflow-automator' ); ?></th>
						<th scope="col"><?php esc_html_e( 'Usuń', 'mp-workflow-automator' ); ?></th>
					</tr>
				</thead>
				<tbody>
				<?php foreach ( $reguly as $regula ) : ?>
					<?php
					$id        = (int) $regula['id'];
					$systemowa = 'system' === (string) $regula['source'];
					$pole      = 'mp_rule[' . $id . ']';
					?>
					<tr>
						<td>
							<?php echo esc_html( self::etykieta_wyzwalacza( (string) $regula['trigger_type'] ) ); ?>
							<?php if ( $systemowa ) : ?>
								<br /><span class="description"><?php esc_html_e( '(reguła systemowa)', 'mp-workflow-automator' ); ?></span>
							<?php else : ?>
								<input type="hidden" name="<?php echo esc_attr( $pole ); ?>[trigger_type]" value="<?php echo esc_attr( (string) $regula['trigger_type'] ); ?>" />
							<?php endif; ?>
						</td>
						<td>
							<label class="screen-reader-text" for="mp-rule-key-<?php echo esc_attr( (string) $id ); ?>"><?php esc_html_e( 'Klucz warunku', 'mp-workflow-automator' ); ?></label>
							<select id="mp-rule-key-<?php echo esc_attr( (string) $id ); ?>" name="<?php echo esc_attr( $pole ); ?>[condition_key]">
								<option value="" <?php selected( '', (string) $regula['condition_key'] ); ?>><?php esc_html_e( '— zawsze —', 'mp-workflow-automator' ); ?></option>
								<?php foreach ( Rules::CONDITION_KEYS as $klucz ) : ?>
									<option value="<?php echo esc_attr( $klucz ); ?>" <?php selected( $klucz, (string) $regula['condition_key'] ); ?>>
										<?php echo esc_html( self::etykieta_warunku( $klucz ) ); ?>
									</option>
								<?php endforeach; ?>
							</select>
						</td>
						<td>
							<label class="screen-reader-text" for="mp-rule-op-<?php echo esc_attr( (string) $id ); ?>"><?php esc_html_e( 'Operator warunku', 'mp-workflow-automator' ); ?></label>
							<select id="mp-rule-op-<?php echo esc_attr( (string) $id ); ?>" name="<?php echo esc_attr( $pole ); ?>[condition_operator]">
								<?php foreach ( Rules::OPERATORS as $op ) : ?>
									<option value="<?php echo esc_attr( $op ); ?>" <?php selected( $op, (string) $regula['condition_operator'] ); ?>>
										<?php echo esc_html( self::etykieta_operatora( $op ) ); ?>
									</option>
								<?php endforeach; ?>
							</select>
						</td>
						<td>
							<label class="screen-reader-text" for="mp-rule-val-<?php echo esc_attr( (string) $id ); ?>"><?php esc_html_e( 'Wartość warunku', 'mp-workflow-automator' ); ?></label>
							<input type="text" id="mp-rule-val-<?php echo esc_attr( (string) $id ); ?>" name="<?php echo esc_attr( $pole ); ?>[condition_value]" value="<?php echo esc_attr( (string) $regula['condition_value'] ); ?>" class="regular-text" />
						</td>
						<td>
							<?php echo esc_html( self::etykieta_akcji( (string) $regula['action_type'] ) ); ?>
							<?php if ( ! $systemowa ) : ?>
								<input type="hidden" name="<?php echo esc_attr( $pole ); ?>[action_type]" value="<?php echo esc_attr( (string) $regula['action_type'] ); ?>" />
							<?php endif; ?>
						</td>
						<td>
							<label class="screen-reader-text" for="mp-rule-prio-<?php echo esc_attr( (string) $id ); ?>"><?php esc_html_e( 'Kolejność sprawdzania', 'mp-workflow-automator' ); ?></label>
							<input type="number" min="0" id="mp-rule-prio-<?php echo esc_attr( (string) $id ); ?>" name="<?php echo esc_attr( $pole ); ?>[priority]" value="<?php echo esc_attr( (string) $regula['priority'] ); ?>" class="small-text" />
						</td>
						<td><input type="checkbox" name="<?php echo esc_attr( $pole ); ?>[enabled]" value="1" <?php checked( 1, (int) $regula['enabled'] ); ?> aria-label="<?php esc_attr_e( 'Reguła włączona', 'mp-workflow-automator' ); ?>" /></td>
						<td>
							<?php if ( $systemowa ) : ?>
								<span class="description"><?php esc_html_e( 'nieusuwalna', 'mp-workflow-automator' ); ?></span>
							<?php else : ?>
								<input type="checkbox" name="<?php echo esc_attr( $pole ); ?>[delete]" value="1" aria-label="<?php esc_attr_e( 'Usuń tę regułę', 'mp-workflow-automator' ); ?>" />
							<?php endif; ?>
						</td>
					</tr>
				<?php endforeach; ?>
				</tbody>
			</table>
			</div>

			<h3 class="mp-automator-h3"><?php esc_html_e( 'Nowa reguła', 'mp-workflow-automator' ); ?></h3>
			<table class="form-table" role="presentation">
				<tr>
					<th scope="row"><label for="mp-rule-new-trigger"><?php esc_html_e( 'Kiedy', 'mp-workflow-automator' ); ?></label></th>
					<td>
						<select id="mp-rule-new-trigger" name="mp_rule_new[trigger_type]">
							<option value=""><?php esc_html_e( '— nie dodawaj —', 'mp-workflow-automator' ); ?></option>
							<?php foreach ( Rules::TRIGGERS as $wyzwalacz ) : ?>
								<option value="<?php echo esc_attr( $wyzwalacz ); ?>"><?php echo esc_html( self::etykieta_wyzwalacza( $wyzwalacz ) ); ?></option>
							<?php endforeach; ?>
						</select>
					</td>
				</tr>
				<tr>
					<th scope="row"><label for="mp-rule-new-key"><?php esc_html_e( 'Warunek', 'mp-workflow-automator' ); ?></label></th>
					<td>
						<select id="mp-rule-new-key" name="mp_rule_new[condition_key]">
							<option value=""><?php esc_html_e( '— zawsze —', 'mp-workflow-automator' ); ?></option>
							<?php foreach ( Rules::CONDITION_KEYS as $klucz ) : ?>
								<option value="<?php echo esc_attr( $klucz ); ?>"><?php echo esc_html( self::etykieta_warunku( $klucz ) ); ?></option>
							<?php endforeach; ?>
						</select>
						<select name="mp_rule_new[condition_operator]" aria-label="<?php esc_attr_e( 'Operator warunku', 'mp-workflow-automator' ); ?>">
							<?php foreach ( Rules::OPERATORS as $op ) : ?>
								<option value="<?php echo esc_attr( $op ); ?>"><?php echo esc_html( self::etykieta_operatora( $op ) ); ?></option>
							<?php endforeach; ?>
						</select>
						<input type="text" name="mp_rule_new[condition_value]" value="" class="regular-text" aria-label="<?php esc_attr_e( 'Wartość warunku', 'mp-workflow-automator' ); ?>" placeholder="<?php esc_attr_e( 'wartość', 'mp-workflow-automator' ); ?>" />
					</td>
				</tr>
				<tr>
					<th scope="row"><label for="mp-rule-new-action"><?php esc_html_e( 'Zrób', 'mp-workflow-automator' ); ?></label></th>
					<td>
						<select id="mp-rule-new-action" name="mp_rule_new[action_type]">
							<option value=""><?php esc_html_e( '— nie dodawaj —', 'mp-workflow-automator' ); ?></option>
							<?php foreach ( Rules::ACTIONS as $akcja ) : ?>
								<option value="<?php echo esc_attr( $akcja ); ?>"><?php echo esc_html( self::etykieta_akcji( $akcja ) ); ?></option>
							<?php endforeach; ?>
						</select>
					</td>
				</tr>
				<tr>
					<th scope="row"><label for="mp-rule-new-config"><?php esc_html_e( 'Szczegóły akcji', 'mp-workflow-automator' ); ?></label></th>
					<td>
						<textarea id="mp-rule-new-config" name="mp_rule_new[action_config_json]" rows="3" class="large-text code" spellcheck="false" placeholder="{&quot;pool&quot;:[12,15]}"></textarea>
						<p class="description"><?php esc_html_e( 'Zapis techniczny (JSON). Przydział: {"pool":[ID pracowników]}. Zmiana statusu: {"new_status":"w analizie"} (dawny zapis {"status":"..."} nadal działa). Priorytet: {"priority":"high"}. Powiadomienie: {"template_key":"...","recipient_ref":"agent"}.', 'mp-workflow-automator' ); ?></p>
					</td>
				</tr>
				<tr>
					<th scope="row"><label for="mp-rule-new-prio"><?php esc_html_e( 'Kolejność', 'mp-workflow-automator' ); ?></label></th>
					<td>
						<input type="number" min="0" id="mp-rule-new-prio" name="mp_rule_new[priority]" value="10" class="small-text" />
						<label><input type="checkbox" name="mp_rule_new[enabled]" value="1" checked="checked" /> <?php esc_html_e( 'włączona od razu', 'mp-workflow-automator' ); ?></label>
					</td>
				</tr>
			</table>
			<?php submit_button( __( 'Zapisz reguły', 'mp-workflow-automator' ), 'primary', 'mp-zapisz-reguly', false ); ?>
		</form>
		<?php
	}

	/**
	 * Sekcja przelacznika kasowania danych przy odinstalowaniu.
	 *
	 * @return void
	 */
	private static function render_uninstall_form(): void {
		?>
		<h2 class="mp-automator-h2"><?php esc_html_e( 'Kasowanie danych przy odinstalowaniu', 'mp-workflow-automator' ); ?></h2>
		<?php
		UninstallSwitch::render(
			self::ACTION_UNINSTALL,
			self::OPTION_DELETE_DATA,
			__( 'Przy odinstalowaniu wtyczki skasuj także jej dane (tabele, reguły, ustawienia).', 'mp-workflow-automator' ),
			__( 'Domyślnie WYŁĄCZONE: odinstalowanie zostawia dane, więc ponowna instalacja je zastaje. Włączenie oznacza kasowanie bezpowrotne — bez kopii nie da się tego cofnąć. Ustawienie dotyczy WYŁĄCZNIE modułu automatyzacji; pozostałe wtyczki mają własne.', 'mp-workflow-automator' ),
			__( 'Zapisz ustawienie', 'mp-workflow-automator' )
		);
	}

	/**
	 * Nazwa wyzwalacza po polsku.
	 *
	 * @param string $trigger Stala TRIGGER_*.
	 * @return string
	 */
	private static function etykieta_wyzwalacza( string $trigger ): string {
		$mapa = array(
			Rules::TRIGGER_CASE_CREATED   => __( 'powstaje nowa sprawa', 'mp-workflow-automator' ),
			Rules::TRIGGER_STATUS_CHANGED => __( 'zmienia się status sprawy', 'mp-workflow-automator' ),
			Rules::TRIGGER_MESSAGE_ADDED  => __( 'dochodzi wiadomość', 'mp-workflow-automator' ),
		);

		return $mapa[ $trigger ] ?? $trigger;
	}

	/**
	 * Nazwa klucza warunku po polsku (z ostrzezeniem przy polach zawsze pustych).
	 *
	 * @param string $klucz Klucz kontekstu sprawy.
	 * @return string
	 */
	private static function etykieta_warunku( string $klucz ): string {
		$mapa = array(
			'kategoria' => __( 'kategoria produktu', 'mp-workflow-automator' ),
			'kraj'      => __( 'kraj', 'mp-workflow-automator' ),
			'jezyk'     => __( 'język', 'mp-workflow-automator' ),
			'priority'  => __( 'priorytet', 'mp-workflow-automator' ),
			'rodzaj'    => __( 'rodzaj sprawy', 'mp-workflow-automator' ),
			'status'    => __( 'status', 'mp-workflow-automator' ),
		);

		$nazwa = $mapa[ $klucz ] ?? $klucz;

		if ( in_array( $klucz, Rules::CONDITION_KEYS_MARTWE, true ) ) {
			/* translators: %s = nazwa pola warunku */
			$nazwa = sprintf( __( '%s (pole zawsze puste — reguła nie zadziała)', 'mp-workflow-automator' ), $nazwa );
		}

		return $nazwa;
	}

	/**
	 * Nazwa operatora po polsku.
	 *
	 * @param string $op Operator.
	 * @return string
	 */
	private static function etykieta_operatora( string $op ): string {
		$mapa = array(
			'equals'       => __( 'równa się', 'mp-workflow-automator' ),
			'not_equals'   => __( 'różni się od', 'mp-workflow-automator' ),
			'in_list'      => __( 'jest jedną z (po przecinku)', 'mp-workflow-automator' ),
			'is_empty'     => __( 'jest puste', 'mp-workflow-automator' ),
			'is_not_empty' => __( 'nie jest puste', 'mp-workflow-automator' ),
		);

		return $mapa[ $op ] ?? $op;
	}

	/**
	 * Nazwa akcji po polsku.
	 *
	 * @param string $akcja Stala ACTION_*.
	 * @return string
	 */
	private static function etykieta_akcji( string $akcja ): string {
		$mapa = array(
			Rules::ACTION_ASSIGN        => __( 'przydziel pracownikowi', 'mp-workflow-automator' ),
			Rules::ACTION_CHANGE_STATUS => __( 'zmień status', 'mp-workflow-automator' ),
			Rules::ACTION_NOTIFY        => __( 'wyślij powiadomienie', 'mp-workflow-automator' ),
			Rules::ACTION_SET_PRIORITY  => __( 'ustaw priorytet', 'mp-workflow-automator' ),
		);

		return $mapa[ $akcja ] ?? $akcja;
	}
}
