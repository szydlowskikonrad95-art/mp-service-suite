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
		$slug = sanitize_key( $slug );

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
