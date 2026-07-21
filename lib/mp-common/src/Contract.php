<?php
/**
 * Kontrola wersji kontraktu miedzy pluginami MP.
 *
 * Kontrakt (hooki, tabele, role) jest wersjonowany stala MP_CONTRACT_VERSION.
 * Niezgodnosc wersji = admin notice + tryb ograniczony, NIGDY fatal error.
 *
 * @package MP\Common
 */

namespace MP\Common;

/**
 * Sprawdzenie zgodnosci wersji kontraktu.
 */
final class Contract {

	/**
	 * Czy zaladowany kontrakt zgadza sie z oczekiwanym przez plugin.
	 *
	 * @param int $expected Wersja kontraktu, na ktora zbudowano plugin.
	 * @return bool True gdy zgodny.
	 */
	public static function is_compatible( int $expected ): bool {
		return defined( 'MP_CONTRACT_VERSION' ) && MP_CONTRACT_VERSION === $expected;
	}

	/**
	 * Rejestruje admin notice o niezgodnosci kontraktu (tryb ograniczony).
	 *
	 * @param string $plugin_label Czytelna nazwa pluginu do komunikatu.
	 * @return void
	 */
	public static function register_mismatch_notice( string $plugin_label ): void {
		add_action(
			'admin_notices',
			static function () use ( $plugin_label ): void {
				printf(
					'<div class="notice notice-warning"><p>%s</p></div>',
					esc_html(
						sprintf(
							/* translators: %s: nazwa pluginu MP. */
							'%s: niezgodna wersja kontraktu MP — plugin dziala w trybie ograniczonym. Zaktualizuj wszystkie 3 pluginy MP do tego samego wydania.',
							$plugin_label
						)
					)
				);
			}
		);
	}
}
