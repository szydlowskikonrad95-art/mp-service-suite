<?php
/**
 * READ-API D->C dla karty sprawy personelu (ekran w Intake C). Wystawia stan
 * checklisty, szablony odpowiedzi i termin SLA jako FILTRY kontraktowe — C
 * renderuje kartę bez sięgania w tabele/klasy D (luźne wiązanie 3 pluginów).
 *
 * Kontrakt (API-KONTRAKT):
 *  - `mp_case_checklist_state($case_id)` => lista {step_key,label,completed,completed_by,completed_at}
 *    (PEŁNA definicja kroków rodzaju + nałożony stan odhaczeń; zapis/toggle dalej przez
 *    `mp_automator_checklist_toggle` + `mp_case_checklist_authorize`).
 *  - `mp_response_templates($kind)` => lista {key,label,body} (dropdown odpowiedzi).
 *  - `mp_render_response_template($key,$case_id)` => string (body z podmienionymi markerami; '' gdy brak).
 *  - `mp_case_deadline($case_id)` => {deadline_at,warning_at,status}|null (termin z tabeli case_sla D).
 *
 * NO-PII: żaden z tych odczytów nie loguje. Kontekst sprawy bierzemy przez
 * `mp_case_get_context` (kontrakt C) — D nie czyta tabel C literałem.
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Filtry read-only zasilające kartę sprawy w C.
 */
final class CaseCardApi {

	/**
	 * Rejestruje filtry kontraktowe (wołane z Plugin::boot, addytywnie).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_filter( 'mp_case_checklist_state', array( self::class, 'checklist_state' ), 10, 2 );
		add_filter( 'mp_response_templates', array( self::class, 'response_templates' ), 10, 2 );
		add_filter( 'mp_render_response_template', array( self::class, 'render_template' ), 10, 3 );
		add_filter( 'mp_case_deadline', array( self::class, 'sla_deadline' ), 10, 2 );
	}

	/**
	 * Stan checklisty sprawy = DEFINICJA kroków rodzaju (ChecklistTemplates) z
	 * nałożonym stanem odhaczeń (Checklists::get_state). Pełna lista, żeby karta
	 * pokazała też kroki jeszcze nieodhaczone. Pusta gdy sprawa/rodzaj nieznany.
	 *
	 * @param mixed $result   Wartość domyślna filtra (ignorowana).
	 * @param int   $case_id  ID sprawy.
	 * @return array<int, array{step_key: string, label: string, completed: bool, completed_by: int|null, completed_at: string|null}>
	 */
	public static function checklist_state( $result, $case_id ): array {
		unset( $result );

		$case_id = (int) $case_id;
		$ctx     = apply_filters( 'mp_case_get_context', null, $case_id );

		if ( ! is_array( $ctx ) ) {
			return array();
		}

		$kind  = (string) ( $ctx['rodzaj'] ?? '' );
		$steps = ChecklistTemplates::for_kind( $kind );
		$state = Checklists::get_state( $case_id );
		$out   = array();

		foreach ( $steps as $step ) {
			$key = (string) $step['key'];
			$st  = $state[ $key ] ?? null;

			$out[] = array(
				'step_key'     => $key,
				'label'        => (string) $step['label'],
				'completed'    => is_array( $st ) ? (bool) $st['completed'] : false,
				'completed_by' => is_array( $st ) ? $st['completed_by'] : null,
				'completed_at' => is_array( $st ) ? $st['completed_at'] : null,
			);
		}

		return $out;
	}

	/**
	 * Szablony odpowiedzi dla rodzaju (dropdown). Pusta lista gdy nieznany.
	 *
	 * @param mixed  $result Wartość domyślna (ignorowana).
	 * @param string $kind   Rodzaj sprawy.
	 * @return array<int, array{key: string, label: string, body: string}>
	 */
	public static function response_templates( $result, $kind ): array {
		unset( $result );

		return ResponseTemplates::for_kind( (string) $kind );
	}

	/**
	 * Renderuje szablon odpowiedzi dla sprawy (markery z mp_case_get_context).
	 * '' gdy sprawy/szablonu brak (karta pokaże puste pole do wpisania).
	 *
	 * @param mixed  $result  Wartość domyślna (ignorowana).
	 * @param string $key     Klucz szablonu.
	 * @param int    $case_id ID sprawy.
	 * @return string
	 */
	public static function render_template( $result, $key, $case_id ): string {
		unset( $result );

		$ctx = apply_filters( 'mp_case_get_context', null, (int) $case_id );

		if ( ! is_array( $ctx ) ) {
			return '';
		}

		$kind = (string) ( $ctx['rodzaj'] ?? '' );
		$body = ResponseTemplates::render( $kind, (string) $key, $ctx );

		return is_string( $body ) ? $body : '';
	}

	/**
	 * Termin SLA sprawy (deadline/warning/status) z tabeli case_sla (własna D).
	 * Null gdy brak wiersza (sprawa bez SLA / terminalna z deadline NULL).
	 *
	 * @param mixed $result  Wartość domyślna (ignorowana).
	 * @param int   $case_id ID sprawy.
	 * @return array{deadline_at: string|null, warning_at: string|null, status: string}|null
	 */
	public static function sla_deadline( $result, $case_id ): ?array {
		unset( $result );

		global $wpdb;

		$table = Tables::full( Tables::CASE_SLA );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela własna D, zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT deadline_at, warning_at, status FROM {$table} WHERE case_id = %d",
				(int) $case_id
			),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $row ) ? $row : null;
	}
}
