<?php
/**
 * Definicje statusow WLASNYCH (P3.2 — D = ZRODLO definicji, C = walidator przejsc).
 *
 * Rdzen 7 nalezy do C (Statuses::CORE) i jest NIEUSUWALNY — D go NIE definiuje ani
 * nie hardkoduje (dzieki temu zero ryzyka rozjazdu slugow, np. pulapka
 * `zamkniete` vs `zamknięte`). D dokłada WLASNE statusy przez filtr
 * `mp_registered_statuses`; slug przechodzi `sanitize_key` (male litery/cyfry/_/-),
 * wiec NIGDY nie zderzy sie z rdzeniem (rdzen ma spacje i znaki diakrytyczne).
 *
 * Definicje = OPCJA-TRESC (warstwa ii uninstalla): przezywaja deaktywacje,
 * kasowane wylacznie sciezka ON (mp_automator_delete_data=1).
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Przechowywanie i publikacja statusow wlasnych do C.
 */
final class StatusDefs {

	/**
	 * Opcja-tresc z definicjami statusow wlasnych (warstwa ii).
	 * Ksztalt: slug => array{label, active, terminal, sla_hours, warning_hours}.
	 */
	public const OPTION = 'mp_automator_status_defs';

	/**
	 * Akcja admin-post ekranu ustawien (= akcja nonce). Do 1.3.12 mechanizm
	 * statusow wlasnych NIE MIAL zadnego wywolania w produkcie: upsert()/delete()
	 * wolal wylacznie test. Zamowienie zada statusow KONFIGUROWALNYCH, wiec droga
	 * dla czlowieka musi istniec w panelu, nie tylko w kodzie.
	 */
	public const ACTION_CONFIG = 'mp_automator_status_config';

	/**
	 * Gorny limit dlugosci etykiety (spojnie z VARCHAR(190) statusow C-side).
	 */
	private const LABEL_MAX = 190;

	/**
	 * TWARDY limit dlugosci SLUGA statusu = szerokosc kolumny C
	 * `wp_mp_service_cases.status` VARCHAR(20) (mp-service-intake/includes/Schema.php).
	 *
	 * D NIE MOZE opublikowac statusu dluzszego niz C potrafi zapisac — inaczej
	 * na hoscie non-strict MySQL slug zostaje CICHO uciety (status sprawy zepsuty,
	 * optimistic-lock nastepnej zmiany pada), a na strict = blad DB. Slug to KLUCZ
	 * maszynowy (label niesie dluga nazwe ludzka) — 20 znakow wystarcza.
	 * JESLI kontrakt/kolumna C sie poszerzy, ta stala idzie za nia.
	 */
	private const SLUG_MAX = 20;

	/**
	 * Buduje IDENTYFIKATOR statusu z tego, co wpisal czlowiek (audyt 2.26).
	 *
	 * PROBLEM: `sanitize_key()` USUWA polskie znaki i spacje, zamiast je zamieniac.
	 * Administrator wpisujacy „W realizacji" dostawal identyfikator `wrealizacji`,
	 * a „Do uzupełnienia" — `douzupenienia`. Cicho, bez slowa, i nie do odczytania
	 * przez czlowieka, ktory kiedys na to spojrzy.
	 *
	 * ⭐ WZORZEC WZIETY Z SASIEDNIEGO MODULU, nie wymyslony: kategorie produktow
	 * maja klucz `elektronarzedzia` przy etykiecie „Elektronarzędzia" — ktos
	 * swiadomie napisal klucz bez ogonka, zeby przezyl normalizacje. Robimy to
	 * samo, tylko maszynowo: `remove_accents()` zamienia ę na e, spacje staja sie
	 * lacznikiem, a dopiero potem wchodzi ta sama funkcja co dotad.
	 *
	 * ⛔ Statusy RDZENIA (z kartki: „do uzupełnienia", „w naprawie", „zamknięte")
	 * TA DROGA NIE IDA — sa zaszyte w module zgloszen i zapisane w tysiacach
	 * wierszy spraw. Ich zmiana to migracja danych, nie poprawka nazwy, i nie
	 * robi sie jej tydzien przed wydaniem. Zgodnosc statusow wlasnych z kontraktem
	 * zalatwia to, po co pozycja powstala: pierwszy status wlasny z polskim znakiem
	 * nie stworzy juz drugiej konwencji nazw.
	 *
	 * @param string $raw Surowy identyfikator albo etykieta od administratora.
	 * @return string Identyfikator zgodny z kontraktem ('' gdy nie zostalo nic).
	 */
	public static function slug_from_input( string $raw ): string {
		$raw = trim( $raw );

		if ( '' === $raw ) {
			return '';
		}

		$bez_ogonkow = function_exists( 'remove_accents' ) ? remove_accents( $raw ) : $raw;
		// ⛔ TYLKO BIALE ZNAKI. Podkreslenie jest w kontrakcie znakiem DOZWOLONYM,
		// wiec zamiana go na lacznik zmienialaby identyfikatory, ktore juz dzialaja
		// (`ekspertyza_zewn` -> `ekspertyza-zewn`) — czyli naprawiajac zapis nowych
		// statusow, zepsulbym istniejace. Zlapal to istniejacy test statusow.
		$z_lacznikiem = (string) preg_replace( '/\s+/u', '-', $bez_ogonkow );

		return sanitize_key( $z_lacznikiem );
	}

	/**
	 * Zwraca wszystkie definicje statusow wlasnych (znormalizowane).
	 *
	 * @return array<string, array{label: string, active: bool, terminal: bool, sla_hours: int, warning_hours: int}>
	 */
	public static function all(): array {
		$raw = get_option( self::OPTION, array() );

		if ( ! is_array( $raw ) ) {
			return array();
		}

		$out = array();

		foreach ( $raw as $slug => $def ) {
			// Odczyt zostaje na `sanitize_key`: identyfikatory zapisane WCZESNIEJ
			// (po staremu) musza dalej dzialac. Nowa regula obowiazuje przy zapisie.
			$slug = sanitize_key( (string) $slug );

			// Defensywa: pomijamy puste i przekraczajace szerokosc kolumny C
			// (upsert i tak nie wpuszcza takich — to pas na wypadek recznego wpisu).
			if ( '' === $slug || strlen( $slug ) > self::SLUG_MAX || ! is_array( $def ) ) {
				continue;
			}

			$out[ $slug ] = self::sanitize_def( $def );
		}

		return $out;
	}

	/**
	 * Callback filtra `mp_registered_statuses` — dokłada AKTYWNE statusy wlasne
	 * w ksztalcie kontraktu C: slug => {label, terminal}. Statusy nieaktywne NIE
	 * sa publikowane (C ich nie zwaliduje). Rdzenia 7 D nie dotyka.
	 *
	 * @param mixed $statuses Dotychczasowa mapa (od innych; zwykle pusta).
	 * @return array<string, array{label: string, terminal: bool}>
	 */
	public static function register_statuses( $statuses ): array {
		$out = is_array( $statuses ) ? $statuses : array();

		foreach ( self::all() as $slug => $def ) {
			if ( ! $def['active'] ) {
				continue;
			}

			$out[ $slug ] = array(
				'label'    => $def['label'],
				'terminal' => $def['terminal'],
			);
		}

		return $out;
	}

	/**
	 * Dodaje/aktualizuje status wlasny. Slug przez sanitize_key (bez kolizji
	 * z rdzeniem C). Loguje CONFIG_CHANGED (kto/kiedy). Zwraca uzyty slug albo ''
	 * gdy slug pusty po sanityzacji.
	 *
	 * @param string               $slug Surowy slug (zostanie zsanityzowany).
	 * @param array<string, mixed> $def  Surowe pola definicji.
	 * @return string Slug uzyty do zapisu ('' = odrzucone).
	 */
	public static function upsert( string $slug, array $def ): string {
		// 2.26: identyfikator POWSTAJE z tego, co wpisal czlowiek, a nie zostaje
		// po nim okrojony — „W realizacji" daje `w-realizacji`, nie `wrealizacji`.
		$slug = self::slug_from_input( $slug );

		// Pusty po sanityzacji LUB dluzszy niz kolumna statusu C = ODMOWA
		// (D nie publikuje statusu, ktorego walidator/baza C nie obsluzy).
		if ( '' === $slug || strlen( $slug ) > self::SLUG_MAX ) {
			return '';
		}

		$defs          = self::all();
		$defs[ $slug ] = self::sanitize_def( $def );

		update_option( self::OPTION, $defs, false );

		WorkflowEvents::log(
			WorkflowEvents::CONFIG_CHANGED,
			array(
				'object' => 'status',
				'id'     => $slug,
				'action' => 'upsert',
			),
			null,
			self::current_actor()
		);

		return $slug;
	}

	/**
	 * Usuwa status wlasny (rdzenia 7 nie dotyczy — nie ma go tu). Loguje CONFIG_CHANGED.
	 *
	 * @param string $slug Slug statusu wlasnego.
	 * @return void
	 */
	public static function delete( string $slug ): void {
		$slug = sanitize_key( $slug );
		$defs = self::all();

		if ( '' === $slug || ! isset( $defs[ $slug ] ) ) {
			return;
		}

		unset( $defs[ $slug ] );
		update_option( self::OPTION, $defs, false );

		WorkflowEvents::log(
			WorkflowEvents::CONFIG_CHANGED,
			array(
				'object' => 'status',
				'id'     => $slug,
				'action' => 'delete',
			),
			null,
			self::current_actor()
		);
	}

	/**
	 * Rejestruje handler zapisu z ekranu ustawien. `nopriv` swiadomie TEZ —
	 * zeby niezalogowany dostal jawne 403 z bramki capability, a nie ciche „0"
	 * z admin-post.php (ten sam uklad co ResponseTemplates).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
		add_action( 'admin_post_nopriv_' . self::ACTION_CONFIG, array( self::class, 'handle_config' ) );
	}

	/**
	 * Odcisk biezacej konfiguracji (blokada optymistyczna formularza — audyt #9).
	 *
	 * @return string
	 */
	public static function config_rev(): string {
		return md5( (string) wp_json_encode( self::all() ) );
	}

	/**
	 * Handler ekranu ustawien: capability PIERWSZA => 403; nonce; blokada
	 * optymistyczna; potem wiersze formularza => upsert/delete.
	 *
	 * Wiersz niesie `orig` (slug z chwili otwarcia). Zmiana sluga = delete starego
	 * + upsert nowego, bo slug jest KLUCZEM definicji, nie jej polem.
	 *
	 * Slug odrzucony przez upsert() (pusty albo dluzszy niz kolumna statusu C)
	 * NIE ginie po cichu — wraca do czlowieka nazwany po imieniu. Cicha odmowa
	 * zapisu jest gorsza niz brak ekranu: admin widzi „zapisano" i pusta liste.
	 *
	 * @return void
	 */
	public static function handle_config(): void {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			wp_die(
				esc_html__( 'Brak uprawnień do konfiguracji statusów.', 'mp-workflow-automator' ),
				'',
				array( 'response' => 403 )
			);
		}

		check_admin_referer( self::ACTION_CONFIG );

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$rev = isset( $_POST['mp_config_rev'] ) ? sanitize_text_field( wp_unslash( $_POST['mp_config_rev'] ) ) : '';

		if ( self::config_rev() !== $rev ) {
			self::back( 'konflikt-statusy' );
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Missing -- check_admin_referer() wyzej.
		$rows = isset( $_POST['mp_status'] ) && is_array( $_POST['mp_status'] )
			// phpcs:ignore WordPress.Security.NonceVerification.Missing, WordPress.Security.ValidatedSanitizedInput.InputNotSanitized -- kazde pole sanityzowane pojedynczo nizej.
			? (array) wp_unslash( $_POST['mp_status'] )
			: array();

		$odrzucone = array();

		foreach ( $rows as $row ) {
			if ( ! is_array( $row ) ) {
				continue;
			}

			$orig = isset( $row['orig'] ) ? sanitize_key( (string) $row['orig'] ) : '';
			$slug = isset( $row['slug'] ) ? sanitize_key( (string) $row['slug'] ) : '';

			// Wiersz zaznaczony do usuniecia albo wyczyszczony do zera = kasujemy
			// (o ile w ogole istnial). Nowy pusty wiersz po prostu pomijamy.
			if ( ! empty( $row['delete'] ) || '' === $slug ) {
				if ( '' !== $orig ) {
					self::delete( $orig );
					continue;
				}

				if ( '' === $slug && '' !== trim( (string) ( $row['label'] ?? '' ) ) ) {
					// Etykieta wpisana, slug pusty — czlowiek chcial dodac status
					// i nie dowiedzialby sie, czemu go nie ma.
					$odrzucone[] = sanitize_text_field( (string) $row['label'] );
				}

				continue;
			}

			$zapisany = self::upsert(
				$slug,
				array(
					'label'         => (string) ( $row['label'] ?? '' ),
					'active'        => ! empty( $row['active'] ),
					'terminal'      => ! empty( $row['terminal'] ),
					'sla_hours'     => (int) ( $row['sla_hours'] ?? 0 ),
					'warning_hours' => (int) ( $row['warning_hours'] ?? 0 ),
				)
			);

			if ( '' === $zapisany ) {
				$odrzucone[] = $slug;
				continue;
			}

			// Slug zmieniony => stara definicja przestaje istniec.
			if ( '' !== $orig && $orig !== $zapisany ) {
				self::delete( $orig );
			}
		}

		if ( array() !== $odrzucone ) {
			self::back( 'statusy-odrzucone', implode( ', ', array_slice( $odrzucone, 0, 5 ) ) );
		}

		self::back( '' );
	}

	/**
	 * Powrot na ekran ustawien z ewentualnym kodem bledu. Zawsze konczy zadanie.
	 *
	 * @param string $kod   Kod bledu ('' = sukces).
	 * @param string $detal Doprecyzowanie dla czlowieka (np. odrzucone slugi).
	 * @return void
	 */
	private static function back( string $kod, string $detal = '' ): void {
		$ref  = wp_get_referer();
		$cel  = false !== $ref ? $ref : admin_url();
		$args = array();

		if ( '' !== $kod ) {
			$args['mp_settings_error'] = $kod;
		} else {
			$args['mp_settings_ok'] = 'statusy';
		}

		if ( '' !== $detal ) {
			$args['mp_settings_detal'] = rawurlencode( $detal );
		}

		wp_safe_redirect( add_query_arg( $args, $cel ) );
		exit;
	}

	/**
	 * Normalizuje jedna definicje statusu (czysta — sanityzacja pol). Etykieta
	 * pusta => fallback na slug NIE tutaj (slug znamy dopiero w upsert); pusta
	 * etykieta zostaje pusta i UI ja podmieni. sla_hours/warning_hours >= 0
	 * (0 = brak pilnowania SLA dla tego statusu).
	 *
	 * @param array<string, mixed> $def Surowe pola.
	 * @return array{label: string, active: bool, terminal: bool, sla_hours: int, warning_hours: int}
	 */
	public static function sanitize_def( array $def ): array {
		$label = isset( $def['label'] ) ? sanitize_text_field( (string) $def['label'] ) : '';

		if ( mb_strlen( $label ) > self::LABEL_MAX ) {
			$label = mb_substr( $label, 0, self::LABEL_MAX );
		}

		return array(
			'label'         => $label,
			'active'        => ! empty( $def['active'] ),
			'terminal'      => ! empty( $def['terminal'] ),
			'sla_hours'     => max( 0, (int) ( $def['sla_hours'] ?? 0 ) ),
			'warning_hours' => max( 0, (int) ( $def['warning_hours'] ?? 0 ) ),
		);
	}

	/**
	 * Biezacy uzytkownik jako actor (0/brak => null = system).
	 *
	 * @return int|null
	 */
	private static function current_actor(): ?int {
		$uid = function_exists( 'get_current_user_id' ) ? (int) get_current_user_id() : 0;

		return $uid > 0 ? $uid : null;
	}
}
