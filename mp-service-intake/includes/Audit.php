<?php
/**
 * Lekki audit-log operacji admina (W3) — NIE eventy sprawy.
 *
 * Operacje na sprawach NIEpotwierdzonych nie moga isc do `wp_mp_case_events`
 * (append-only, tylko sprawy verified). Rejestr operacji personelu (np. resend
 * linku) trzymamy osobno. Wersja proporcjonalna: opcja-ring (ostatnie N wpisow) —
 * wolumen operacji admina maly. Przy duzej skali = dedykowana tabela.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Rejestr operacji personelu (audit-log).
 */
final class Audit {

	/**
	 * Opcja z rejestrem operacji.
	 */
	public const OPTION = 'mp_intake_audit_log';

	/**
	 * Maksymalna liczba trzymanych wpisow (ring).
	 */
	private const MAX = 200;

	/**
	 * Dopisuje operacje do rejestru.
	 *
	 * @param string   $action   Kod operacji (np. 'resend').
	 * @param int      $case_id  ID sprawy.
	 * @param int|null $actor_id ID wykonawcy (personel).
	 * @return void
	 */
	public static function log( string $action, int $case_id, ?int $actor_id ): void {
		$log = get_option( self::OPTION, array() );

		if ( ! is_array( $log ) ) {
			$log = array();
		}

		$log[] = array(
			'action'   => $action,
			'case_id'  => $case_id,
			'actor_id' => $actor_id,
			'at'       => gmdate( 'Y-m-d H:i:s' ),
		);

		if ( count( $log ) > self::MAX ) {
			$log = array_slice( $log, -self::MAX );
		}

		update_option( self::OPTION, $log, false );
	}

	/**
	 * Wpisy rejestru (najnowsze na koncu).
	 *
	 * @return array<int, array<string, mixed>>
	 */
	public static function entries(): array {
		$log = get_option( self::OPTION, array() );

		return is_array( $log ) ? $log : array();
	}
}
