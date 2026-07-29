<?php
/**
 * Cykl zycia pluginu MP Workflow Automator (aktywacja/deaktywacja).
 *
 * @package MP\Automator
 */

namespace MP\Automator;

use MP\Automator\Common\Roles;

/**
 * Aktywacja i deaktywacja pluginu.
 */
final class Lifecycle {

	/**
	 * Marker obecnosci modulu (wspolna mechanika uninstall — patrz Common\Uninstall).
	 */
	public const MODULE_MARKER = 'mp_module_automator';

	/**
	 * Opcja wersji schematu bazy (migracje startuja w D2).
	 */
	public const SCHEMA_OPTION = 'mp_automator_schema_version';

	/**
	 * Haki cron pluginu (czyszczone przy deaktywacji; lista rosnie z kodem).
	 *
	 * @var string[]
	 */
	public const CRON_HOOKS = array( Sweep::CRON_HOOK, Sla::RECALC_CONTINUE_HOOK );

	/**
	 * Aktywacja: role wspolne (idempotentnie), marker modulu, migracje schematu.
	 *
	 * @return void
	 */
	public static function activate(): void {
		Roles::ensure();

		if ( false === get_option( self::MODULE_MARKER, false ) ) {
			add_option( self::MODULE_MARKER, 1, '', false );
		}

		if ( false === get_option( self::SCHEMA_OPTION, false ) ) {
			add_option( self::SCHEMA_OPTION, '0', '', false );
		}

		Schema::migrate();
		Rules::maybe_seed_defaults();
		Sweep::schedule();
		Sla::recompute_open();
	}

	/**
	 * Upgrade bez reaktywacji (WP updater podmienia pliki, NIE reaktywuje).
	 *
	 * Wolane na admin_init; gated wersja schematu => odpala zalegle migracje
	 * RAZ po podniesieniu wtyczki, potem no-op. Idempotentne (Migrations::run
	 * i Roles::ensure same sie pilnuja). Bez tego update nie utworzylby tabel D
	 * (schemat pojawil sie dopiero teraz, po v0.1.0-szkielecie).
	 *
	 * @return void
	 */
	public static function maybe_upgrade(): void {
		// Cron POZA bramka wersji schematu. Powod z realnego przebiegu (27.07):
		// aktualizacja 0.4.0 -> nowsza zostawiala system BEZ zaplanowanego sweepa,
		// bo schemat D sie nie zmienil, wiec cala funkcja wychodzila w pierwszej
		// linii. Klient, ktory zainstalowal wersje z zdjetym cronem (blad #103),
		// po aktualizacji NADAL nie mial pilnowania terminow — a system wyglada
		// na sprawny. `schedule()` jest idempotentne (sprawdza wp_next_scheduled),
		// wiec wolanie go przy kazdym wejsciu do panelu nic nie kosztuje.
		Sweep::schedule();

		if ( (int) get_option( Schema::VERSION_OPTION, 0 ) >= Schema::LATEST ) {
			return;
		}

		Roles::ensure();
		Schema::migrate();
		Rules::maybe_seed_defaults();

		// Przeliczenie terminow PO migracji — ZA bramka wersji, wiec raz na aktualizacje.
		//
		// Audyt 29.07: `migration_2_warning_at()` dokladalo kolumne `warning_at` golym
		// dbDelta, bez przeliczenia istniejacych wierszy. Sweep przypomnien wymaga
		// `warning_at IS NOT NULL` (Sweep.php), wiec KAZDA sprawa otwarta w chwili
		// aktualizacji nie dostawala juz przypomnienia PRZED terminem — tylko eskalacje
		// PO. Dotyczylo to dokladnie spraw stojacych w miejscu, czyli tych, dla ktorych
		// ten mechanizm powstal. Samo sie naprawialo dopiero przy zmianie statusu
		// (on_status_changed re-provisionuje) albo po recznym „Przelicz SLA".
		//
		// Wolamy ISTNIEJACY mechanizm, nie wlasna petle: `recompute_open()` bierze paczke
		// 200 spraw, sam planuje dokonczenie w tle (RECALC_CONTINUE_HOOK jest w CRON_HOOKS,
		// wiec sprzata sie przy odinstalowaniu) i jest idempotentny — markery wysylki sa
		// poza setem UPDATE, wiec NIE wyjda ponownie stare powiadomienia.
		//
		// ⚠️ To wywolanie MUSI zostac ZA bramka wersji. Przed nia stoi tylko
		// `Sweep::schedule()` i to celowo (blad #103) — przeliczanie 200 spraw przy
		// KAZDYM wejsciu do panelu byloby zupelnie czym innym niz idempotentny schedule().
		Sla::recompute_open();
	}

	/**
	 * Deaktywacja: wylacza crony pluginu; NICZEGO nie kasuje.
	 *
	 * @return void
	 */
	public static function deactivate(): void {
		foreach ( self::CRON_HOOKS as $hook ) {
			wp_clear_scheduled_hook( $hook );
		}
	}
}
