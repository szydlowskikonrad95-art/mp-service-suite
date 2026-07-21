<?php
/**
 * Plugin Name: MP Dev — Mailpit SMTP
 * Description: WYLACZNIE poligon dev/demo: kieruje wp_mail() do Mailpit (SMTP mailpit:1025). Kontener WP nie ma sendmaila — bez tego zaden mail nie wychodzi. NIE trafia do paczek klienta.
 *
 * @package MP\Dev
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

add_action(
	'phpmailer_init',
	static function ( $phpmailer ): void {
		$phpmailer->isSMTP();
		$phpmailer->Host     = 'mailpit';
		$phpmailer->Port     = 1025;
		$phpmailer->SMTPAuth = false;
	}
);
