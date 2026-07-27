<?php
/**
 * Odinstalowanie MP Service Intake.
 *
 * Warstwa (i): opcje techniczne + wspolna mechanika rol (Common\Uninstall).
 * Warstwa (ii): dane biznesowe — domyslnie ZOSTAJA (default OFF); kasowanie
 * tabel dochodzi wraz z migracjami (D2) pod jawna lista tabel wlasnych.
 *
 * @package MP\Intake
 */

if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}

require_once __DIR__ . '/includes/Autoloader.php';

MP\Intake\Autoloader::register();

// Warstwa (i) — auto-strona formularza: kasowana TYLKO gdy tresc nietknieta
// (odcisk palca == oryginal). Recznie zredagowana strona ZOSTAJE (blad #5 kolegi).
$mp_intake_page_id = (int) get_option( MP\Intake\Front\Frontend::PAGE_OPTION, 0 );

if ( $mp_intake_page_id > 0 ) {
	$mp_intake_page = get_post( $mp_intake_page_id );

	if ( $mp_intake_page instanceof WP_Post
		&& md5( (string) $mp_intake_page->post_content ) === MP\Intake\Front\Frontend::original_fingerprint()
	) {
		wp_delete_post( $mp_intake_page_id, true );
	}
}

delete_option( MP\Intake\Front\Frontend::PAGE_OPTION );
delete_option( MP\Intake\Front\Frontend::FINGERPRINT_OPTION );

// Warstwa (i) — auto-strona panelu klienta: ta sama zasada (kasuj tylko gdy nietknieta).
$mp_account_page_id = (int) get_option( MP\Intake\Front\AccountPage::PAGE_OPTION, 0 );

if ( $mp_account_page_id > 0 ) {
	$mp_account_page = get_post( $mp_account_page_id );

	if ( $mp_account_page instanceof WP_Post
		&& md5( (string) $mp_account_page->post_content ) === MP\Intake\Front\AccountPage::original_fingerprint()
	) {
		wp_delete_post( $mp_account_page_id, true );
	}
}

delete_option( MP\Intake\Front\AccountPage::PAGE_OPTION );
delete_option( MP\Intake\Front\AccountPage::FINGERPRINT_OPTION );

// Audit-log operacji personelu (metadane operacyjne — kasowane zawsze).
delete_option( MP\Intake\Audit::OPTION );

// Warstwa (i) — katalog zalacznikow (PLIKI techniczne) sprzatany ZAWSZE.
$mp_intake_uploads = wp_upload_dir();
$mp_intake_att_dir = rtrim( (string) $mp_intake_uploads['basedir'], '/' ) . '/mp-attachments';

if ( is_dir( $mp_intake_att_dir ) ) {
	$mp_intake_files = glob( $mp_intake_att_dir . '/*' );

	foreach ( ( false === $mp_intake_files ? array() : $mp_intake_files ) as $mp_intake_file ) {
		if ( is_file( $mp_intake_file ) ) {
			wp_delete_file( $mp_intake_file );
		}
	}

	// Zostaja tylko .htaccess/index.php (guardy) — skasuj i zdejmij katalog.
	foreach ( array( '/.htaccess', '/index.php' ) as $mp_intake_guard ) {
		if ( is_file( $mp_intake_att_dir . $mp_intake_guard ) ) {
			wp_delete_file( $mp_intake_att_dir . $mp_intake_guard );
		}
	}

	// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_rmdir -- uninstall: pusty katalog techniczny zalacznikow.
	rmdir( $mp_intake_att_dir );
}

// Warstwa (ii) — dane biznesowe C — kasowane WYLACZNIE za jawna zgoda admina.
// srv_counters czyszczone RAZEM ze sprawami: skasowanie licznika przy zostawionych
// sprawach => duplikaty SRV po reinstalacji w tym samym roku (DATABASE.md sekcja 4).
$mp_intake_delete_data = ( '1' === get_option( 'mp_intake_delete_data', '0' ) );

if ( $mp_intake_delete_data ) {
	global $wpdb;

	// ── Konta klientow zalozone przez wtyczke ────────────────────────────────
	// Bez tego po odinstalowaniu zostawaly w `wp_users` adresy e-mail klientow
	// koncowych — czyli DANE OSOBOWE przezywaly usuniecie systemu, mimo ze admin
	// jawnie wlaczyl „usun wszystkie dane". Dla instytucji publicznej to zarzut
	// wprost z RODO. Zbieramy ID PRZED skasowaniem tabeli `customers`, bo potem
	// nie da sie juz powiazac konta z naszym systemem.
	//
	// Kasujemy WYLACZNIE konta, ktore spelniaja WSZYSTKIE warunki:
	// (1) sa podpiete w NASZEJ tabeli klientow, czyli my je zakladalismy;
	// (2) maja rolę klienta i TYLKO ja — admin/personel z tym samym mailem
	// (Accounts::ensure_for_customer podpina bez zmiany rol) zostaje nietkniety;
	// (3) nie maja zadnych wlasnych tresci w WordPressie.
	// Bo skasowanie cudzego konta jest nieodwracalne, a my mamy sprzatac PO SOBIE,
	// nie po innych.
	$mp_intake_customers = MP\Intake\Tables::full( MP\Intake\Tables::CUSTOMERS );

	// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- uninstall sciezka ON: wlasna tabela, nazwa ze stalych.
	$mp_intake_user_ids = $wpdb->get_col( "SELECT DISTINCT wp_user_id FROM {$mp_intake_customers} WHERE wp_user_id IS NOT NULL AND wp_user_id > 0" );

	if ( ! function_exists( 'wp_delete_user' ) ) {
		require_once ABSPATH . 'wp-admin/includes/user.php';
	}

	foreach ( (array) $mp_intake_user_ids as $mp_intake_uid ) {
		$mp_intake_uid  = (int) $mp_intake_uid;
		$mp_intake_user = get_userdata( $mp_intake_uid );

		if ( ! $mp_intake_user ) {
			continue;
		}

		// Warunek 2: dokladnie jedna rola i to nasza klieńcka.
		if ( array( MP\Intake\Accounts::CLIENT_ROLE ) !== array_values( (array) $mp_intake_user->roles ) ) {
			continue;
		}

		// Warunek 3: zero wlasnych tresci (nie chcemy osierocic cudzych wpisow).
		if ( count_user_posts( $mp_intake_uid, 'any', true ) > 0 ) {
			continue;
		}

		wp_delete_user( $mp_intake_uid );
	}

	$mp_intake_tables = array(
		MP\Intake\Tables::CASE_EVENTS,
		MP\Intake\Tables::MESSAGES,
		MP\Intake\Tables::ATTACHMENTS,
		MP\Intake\Tables::CONSENTS,
		MP\Intake\Tables::CASES,
		MP\Intake\Tables::CUSTOMERS,
		MP\Intake\Tables::SRV_COUNTERS,
		MP\Intake\Tables::RATE_COUNTERS,
	);

	foreach ( $mp_intake_tables as $mp_intake_table ) {
		$mp_intake_full = MP\Intake\Tables::full( $mp_intake_table );
		// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.DirectDatabaseQuery.SchemaChange, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- uninstall sciezka ON: kasowanie WLASNYCH tabel (nazwa ze stalych, nie z inputu).
		$wpdb->query( "DROP TABLE IF EXISTS {$mp_intake_full}" );
	}

	delete_option( MP\Intake\Schema::VERSION_OPTION );

	/**
	 * Sygnal kontraktowy: tabele spraw przestaly istniec (API-KONTRAKT.md §A).
	 *
	 * Audyt 27.07: kontrakt byl OPISANY (API-KONTRAKT, OWNERSHIP, EVENT_MODEL,
	 * diagram architektury) i mial gotowych SLUCHACZY (Rejestr cofa wyjatki
	 * gwarancyjne przypiete do spraw, Automator czysci terminy i checklisty) —
	 * ale NIKT go nie emitowal. Po odinstalowaniu Intake w pozostalych wtyczkach
	 * zostawaly wiersze wiszace na nieistniejacych sprawach, a dokumentacja
	 * obiecywala klientowi cos przeciwnego. Emisja PO skasowaniu tabel: sluchacze
	 * maja nie probowac czytac spraw, ktorych juz nie ma.
	 */
	do_action( 'mp_cases_data_erased' );

	// Osierocone opcje kontaktu (unverified) + transienty (rate-limit/resend) — grep-zero.
	// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- uninstall sciezka ON: sprzatanie WLASNYCH opcji/transientow.
	$wpdb->query(
		"DELETE FROM {$wpdb->options} WHERE option_name LIKE 'mp\\_pending\\_contact\\_%'"
		. " OR option_name LIKE '\\_transient\\_mp\\_rl\\_%' OR option_name LIKE '\\_transient\\_timeout\\_mp\\_rl\\_%'"
		. " OR option_name LIKE '\\_transient\\_mp\\_resend\\_throttle\\_%' OR option_name LIKE '\\_transient\\_timeout\\_mp\\_resend\\_throttle\\_%'"
	);
}

MP\Intake\Common\Uninstall::run(
	'mp_module_intake',
	array( 'mp_intake_schema_version', 'mp_intake_delete_data' ),
	MP\Intake\Lifecycle::CRON_HOOKS
);
