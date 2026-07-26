<?php
/**
 * Diagnostyka wdrozenia w natywnym ekranie WP: Narzedzia -> Stan witryny.
 *
 * PO CO: wtyczki jada na CUDZYM hostingu, ktorego nie widzimy. Zamiast zgadywac,
 * kazda wtyczka zglasza wlasne testy przez oficjalny filtr `site_status_tests`
 * (WP 5.2+, `class-wp-site-health.php`). Klient otwiera ekran i widzi KONKRET:
 * co nie dziala, dlaczego i co poprawic na hostingu.
 *
 * ZASADA DOBORU TESTU: zglaszamy TYLKO to, czego awaria realnie psuje funkcje
 * I co klient moze naprawic. Reszta to halas.
 *
 * WYDAJNOSC: wylacznie testy `direct` — Site Health odpala je przy KAZDYM
 * wejsciu na ekran oraz cronem. Zero sieci, zero wysylki maila, zero ciezkich
 * zapytan. Testowa wysylka poczty = osobna akcja na zadanie, nie automat.
 *
 * @package MP\Common
 */

namespace MP\Common;

/**
 * Rejestrator testow Stanu witryny (wspolny dla 3 wtyczek MP).
 */
final class SiteHealth {

	/**
	 * Rejestruje zestaw testow danej wtyczki.
	 *
	 * @param string                                          $prefix Unikalny prefiks testow (np. `mp_intake`).
	 * @param array<string, callable(): array<string, mixed>> $tests  Klucz => funkcja zwracajaca wynik z `wynik()`.
	 * @return void
	 */
	public static function register( string $prefix, array $tests ): void {
		add_filter(
			'site_status_tests',
			static function ( array $wszystkie ) use ( $prefix, $tests ): array {
				foreach ( $tests as $klucz => $funkcja ) {
					$wszystkie['direct'][ $prefix . '_' . $klucz ] = array(
						'label' => 'MP',
						'test'  => $funkcja,
					);
				}

				return $wszystkie;
			}
		);
	}

	/**
	 * Buduje wynik testu w formacie, ktorego oczekuje Stan witryny.
	 *
	 * Format wg rdzenia WP: label, status (good|recommended|critical), badge,
	 * description (HTML), actions (HTML), test (identyfikator).
	 *
	 * @param string $id       Identyfikator testu.
	 * @param string $status   `good`, `recommended` albo `critical`.
	 * @param string $tytul    Naglowek widoczny na liscie.
	 * @param string $opis     Co to znaczy (zdanie po ludzku, bez zargonu).
	 * @param string $naprawa  Co konkretnie zrobic (pusty gdy status `good`).
	 * @return array<string, mixed>
	 */
	public static function wynik( string $id, string $status, string $tytul, string $opis, string $naprawa = '' ): array {
		$kolor = 'good' === $status ? 'green' : ( 'critical' === $status ? 'red' : 'orange' );

		return array(
			'label'       => $tytul,
			'status'      => $status,
			'badge'       => array(
				'label' => 'MP Service Suite',
				'color' => $kolor,
			),
			'description' => '<p>' . $opis . '</p>',
			'actions'     => '' !== $naprawa ? '<p>' . $naprawa . '</p>' : '',
			'test'        => $id,
		);
	}

	/**
	 * Czy WP-Cron jest wylaczony stala `DISABLE_WP_CRON`.
	 *
	 * Wydzielone, bo to CZYSTA logika — testowalna bez WordPressa.
	 *
	 * @param bool $stala_zdefiniowana Czy stala istnieje.
	 * @param bool $wartosc_stalej     Jej wartosc.
	 * @return bool True gdy cron wylaczony.
	 */
	public static function cron_wylaczony( bool $stala_zdefiniowana, bool $wartosc_stalej ): bool {
		return $stala_zdefiniowana && $wartosc_stalej;
	}

	/**
	 * Czy limit uploadu serwera wystarcza na nasz limit zalacznika.
	 *
	 * @param int $limit_serwera Bajty (z `wp_max_upload_size`).
	 * @param int $nasz_limit    Bajty (limit wtyczki).
	 * @return bool True gdy serwer ma zbyt maly limit.
	 */
	public static function upload_za_maly( int $limit_serwera, int $nasz_limit ): bool {
		return $limit_serwera > 0 && $limit_serwera < $nasz_limit;
	}

	/**
	 * Czy adres nadawcy to domyslny WordPressowy `wordpress@domena`.
	 *
	 * Rdzen WP (`pluggable.php`) przy braku naglowka From wysyla z adresu
	 * `wordpress@` + domena strony. Taka skrzynka zwykle NIE ISTNIEJE, wiec
	 * poczta oblewa weryfikacje domeny i laduje w spamie, a odbicia gina.
	 *
	 * @param string $adres Adres nadawcy uzyty przez WP.
	 * @return bool True gdy to domyslny adres rdzenia.
	 */
	public static function nadawca_domyslny( string $adres ): bool {
		return 1 === preg_match( '/^wordpress@/i', trim( $adres ) );
	}

	/**
	 * Ilu REALNYCH pracownikow obsluzy pula auto-przydzialu.
	 *
	 * Liczymy tak samo jak silnik regul: pusty/zepsuty JSON = zero, a kazdy
	 * wskazany user musi jeszcze miec uprawnienie agenta (ktos mogl zmienic mu
	 * role po zapisaniu reguly — wtedy pula jest formalnie niepusta, a przydzial
	 * i tak nie ma komu oddac sprawy). Zwracamy liczbe UNIKALNYCH pracownikow:
	 * ten sam user wpisany dwa razy to dalej jeden czlowiek.
	 *
	 * @param array<int, string|null> $konfiguracje_json Kolumny action_config_json regul przydzialu.
	 * @param callable                $czy_agent         fn(int $user_id): bool — czy user ma cap agenta.
	 * @return int Liczba unikalnych pracownikow w puli.
	 */
	public static function pracownikow_w_puli( array $konfiguracje_json, callable $czy_agent ): int {
		$pracownicy = array();

		foreach ( $konfiguracje_json as $json ) {
			$config = json_decode( (string) $json, true );

			if ( ! is_array( $config ) || ! isset( $config['pool'] ) || ! is_array( $config['pool'] ) ) {
				continue;
			}

			foreach ( $config['pool'] as $uid ) {
				$uid = (int) $uid;

				if ( $uid > 0 && $czy_agent( $uid ) ) {
					$pracownicy[ $uid ] = true;
				}
			}
		}

		return count( $pracownicy );
	}
}
