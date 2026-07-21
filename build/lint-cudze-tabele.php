<?php
/**
 * Linter-straznik cudzych tabel (CI + pre-commit).
 *
 * Zasada kontraktu (OWNERSHIP): kod pluginu NIE MOZE zawierac nazw tabel
 * INNEGO pluginu — komunikacja wylacznie hookami mp_*. Skan po tokenach
 * (token_get_all), NIE grep: sprawdzane sa WYLACZNIE literaly stringow
 * w kodzie (lapie tez sprintf/define), komentarze i dokumentacja ignorowane.
 * Kopie includes/Common/ (generowane) pominiete. Runda W, zbieznosc 4x.
 *
 * @package MP\Build
 */

declare(strict_types=1);

$mp_ownership = array(
	'mp-service-intake'     => array(
		'wp_mp_customers',
		'wp_mp_service_cases',
		'wp_mp_case_events',
		'wp_mp_messages',
		'wp_mp_attachments',
		'wp_mp_consents',
		'wp_mp_srv_counters',
	),
	'mp-warranty-registry'  => array(
		'wp_mp_product_registry',
		'wp_mp_product_events',
		'wp_mp_warranty_exceptions',
		'wp_mp_import_jobs',
	),
	'mp-workflow-automator' => array(
		'wp_mp_workflow_rules',
		'wp_mp_case_sla',
		'wp_mp_case_checklists',
		'wp_mp_workflow_events',
	),
);

$mp_all_tables = array_merge( ...array_values( $mp_ownership ) );
$mp_root       = dirname( __DIR__ );
$mp_failures   = 0;

foreach ( $mp_ownership as $mp_plugin => $mp_own_tables ) {
	$mp_foreign = array_diff( $mp_all_tables, $mp_own_tables );
	$mp_dir     = $mp_root . '/' . $mp_plugin;

	if ( ! is_dir( $mp_dir ) ) {
		continue;
	}

	$mp_iterator = new RecursiveIteratorIterator(
		new RecursiveDirectoryIterator( $mp_dir, FilesystemIterator::SKIP_DOTS )
	);

	foreach ( $mp_iterator as $mp_file ) {
		if ( ! $mp_file->isFile() || 'php' !== $mp_file->getExtension() ) {
			continue;
		}

		$mp_path = $mp_file->getPathname();

		if ( str_contains( $mp_path, '/includes/Common/' ) ) {
			continue;
		}

		$mp_tokens = token_get_all( (string) file_get_contents( $mp_path ) );

		foreach ( $mp_tokens as $mp_token ) {
			if ( ! is_array( $mp_token ) ) {
				continue;
			}

			list( $mp_id, $mp_text, $mp_line ) = $mp_token;

			if ( T_CONSTANT_ENCAPSED_STRING !== $mp_id && T_ENCAPSED_AND_WHITESPACE !== $mp_id ) {
				continue;
			}

			foreach ( $mp_foreign as $mp_table ) {
				if ( false !== stripos( $mp_text, $mp_table ) ) {
					fwrite( STDERR, "CUDZA TABELA: {$mp_table} w {$mp_path}:{$mp_line}\n" );
					$mp_failures = 1;
				}
			}
		}
	}
}

if ( 1 === $mp_failures ) {
	fwrite( STDERR, "BLAD: kod pluginu odwoluje sie do tabel innego pluginu — uzyj hookow mp_* (API-KONTRAKT.md).\n" );
	exit( 1 );
}

echo "Linter cudzych tabel: CZYSTO.\n";
