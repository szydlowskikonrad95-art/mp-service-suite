<?php
/**
 * Nazwy tabel wlasnych Intake (C) — WYLACZNIE przez stale tej klasy.
 *
 * Zakaz dynamicznego skladania nazw w SQL; linter cudzych tabel pilnuje,
 * zeby inne pluginy tych nazw nie dotykaly.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Rejestr nazw tabel C (7 wg DATABASE.md).
 */
final class Tables {

	/**
	 * Klienci (dane kontaktowe; anonimizacja zostawia wiersz).
	 */
	public const CUSTOMERS = 'mp_customers';

	/**
	 * Sprawy serwisowe (status NULL = nieporwierdzona).
	 */
	public const CASES = 'mp_service_cases';

	/**
	 * Os czasu sprawy (APPEND-ONLY BEZ WYJATKOW).
	 */
	public const CASE_EVENTS = 'mp_case_events';

	/**
	 * Wiadomosci klient<->serwis (redagowalne przy RODO).
	 */
	public const MESSAGES = 'mp_messages';

	/**
	 * Metadane zalacznikow (cron retencji chodzi po tej tabeli).
	 */
	public const ATTACHMENTS = 'mp_attachments';

	/**
	 * Rejestr zgod RODO (pelny tekst zamrozony w wierszu).
	 */
	public const CONSENTS = 'mp_consents';

	/**
	 * Licznik atomowy SRV per rok (techniczna).
	 */
	public const SRV_COUNTERS = 'mp_srv_counters';

	/**
	 * Pelna nazwa tabeli z prefiksem instalacji.
	 *
	 * @param string $table Stala z tej klasy.
	 * @return string
	 */
	public static function full( string $table ): string {
		global $wpdb;

		return $wpdb->prefix . $table;
	}
}
