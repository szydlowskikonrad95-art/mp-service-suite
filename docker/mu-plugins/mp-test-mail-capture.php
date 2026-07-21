<?php
/**
 * DEV/TEST: przechwyt wp_mail do pliku (token magic-linka dla testow E2E).
 *
 * Zapisuje KAZDY wychodzacy mail jako linia JSON do /tmp/mp-mail-capture.jsonl
 * i PRZEPUSZCZA go dalej (na poligonie leci do Mailpita). Dziala tylko w dev:
 * plik jest w /tmp, nie rusza tresci maila. Nie wchodzi do artefaktu pluginu.
 *
 * @package MP\Test
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

add_filter(
	'wp_mail',
	static function ( array $args ): array {
		$line = wp_json_encode(
			array(
				'to'      => $args['to'] ?? '',
				'subject' => $args['subject'] ?? '',
				'body'    => $args['message'] ?? '',
			),
			JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
		);

		// Zapis do WP_CONTENT_DIR (zawsze istnieje, na poligonie wspoldzielony
		// wolumen wp_data) — front biegnie w innym kontenerze niz test, a /tmp
		// jest per-kontener.
		if ( is_string( $line ) ) {
			file_put_contents( WP_CONTENT_DIR . '/mp-mail-capture.jsonl', $line . "\n", FILE_APPEND | LOCK_EX );
		}

		return $args;
	},
	5
);
