<?php
/**
 * Wspolna "skorupa" samodzielnych stron klienta (weryfikacja, potwierdzenie,
 * logowanie, bledy). Te strony CELOWO stoja poza motywem (bezpieczenstwo:
 * no-store, noindex, no-referrer, nosniff, SAMEORIGIN) — ale maja spojny,
 * profesjonalny wyglad: karta na jasnym tle, akcent przez --mp-accent
 * (ten sam co formularz). Jedno zrodlo stylu = wszystkie ekrany graja.
 *
 * @package MP\Intake\Front
 */

namespace MP\Intake\Front;

/**
 * Renderer skorupy stron samodzielnych.
 */
final class Landing {

	/**
	 * Naglowki bezpieczenstwa + <head> + otwarcie karty. Wolaj przed tresc.
	 *
	 * @param string $title  Tytul strony (i meta title).
	 * @param int    $status Kod HTTP (200 domyslnie; 403/410 dla bledow).
	 * @return void
	 */
	public static function open( string $title, int $status = 200 ): void {
		if ( ! headers_sent() ) {
			status_header( $status );
			header( 'Cache-Control: no-store, max-age=0' );
			header( 'Referrer-Policy: no-referrer' );
			header( 'X-Content-Type-Options: nosniff' );
			header( 'X-Frame-Options: SAMEORIGIN' );
			header( 'Content-Type: text/html; charset=utf-8' );
		}

		echo '<!doctype html><html lang="pl"><head><meta charset="utf-8" />';
		echo '<meta name="viewport" content="width=device-width, initial-scale=1" />';
		echo '<meta name="robots" content="noindex, nofollow" />';
		echo '<title>' . esc_html( $title ) . '</title>';
		// phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped -- staly wewnetrzny CSS (self::css), zero danych uzytkownika.
		echo '<style>' . self::css() . '</style>';
		echo '</head><body><main class="mp-card">';
	}

	/**
	 * Zamkniecie karty i dokumentu.
	 *
	 * @return void
	 */
	public static function close(): void {
		echo '</main></body></html>';
	}

	/**
	 * Spojny styl skorupy (system font — brak zewnetrznych zapytan; akcent
	 * --mp-accent taki jak formularz wtyczki).
	 *
	 * @return string
	 */
	private static function css(): string {
		return ':root{--mp-accent:#14161c;--mp-ink:#1a1d26;--mp-muted:#5c6472}'
			. '*{box-sizing:border-box}'
			. 'body{font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;background:#f4f5f8;color:var(--mp-ink);line-height:1.6;margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:1.5rem}'
			. '.mp-card{background:#fff;width:100%;max-width:33rem;margin:0 auto;padding:clamp(1.6rem,4vw,2.4rem);border:1px solid #e8eaf0;border-radius:16px;box-shadow:0 12px 34px rgba(16,18,30,.07)}'
			. '.mp-card h1{font-size:1.4rem;line-height:1.2;margin:0 0 .7rem;letter-spacing:-.01em}'
			. '.mp-card p{color:var(--mp-muted);margin:0 0 .4rem}'
			. '.mp-card form{margin-top:1.3rem}'
			. '.mp-card button,.mp-card .mp-cta{display:inline-flex;align-items:center;justify-content:center;gap:.4rem;padding:.85rem 1.6rem;background:var(--mp-accent);color:#fff;font:inherit;font-weight:600;text-decoration:none;border:0;border-radius:999px;cursor:pointer;transition:transform .15s ease,box-shadow .15s ease}'
			. '.mp-card button:hover,.mp-card .mp-cta:hover{transform:translateY(-1px);box-shadow:0 8px 20px rgba(20,22,28,.25)}'
			. '.mp-card button:focus-visible,.mp-card .mp-cta:focus-visible{outline:2px solid var(--mp-accent);outline-offset:3px}';
	}
}
