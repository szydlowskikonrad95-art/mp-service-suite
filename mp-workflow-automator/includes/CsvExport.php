<?php
/**
 * Eksport CSV spraw + zestawienie (P3.6) — BACKEND-HANDLER-ONLY (bez menu/ekranu;
 * przycisk podepnie osobne zadanie „panel admina D", decyzja straznika 23.07).
 *
 * Bezpieczenstwo (bulk egress danych osobowych): capability `mp_coordinator` /
 * `mp_system_admin` PIERWSZA => jawne 403 dla anon/subscriber/klient/pracownik;
 * nonce (check_admin_referer); audyt append-only `EXPORT_GENERATED` w rejestrze D.
 * Dane wychodza ZMINIMALIZOWANE — hook `mp_cases_query` (C) nie oddaje kontaktu.
 * Kazde pole CSV chronione przed CSV-formula-injection (prefiks apostrofu).
 *
 * @package MP\Automator
 */

namespace MP\Automator;

/**
 * Handler admin-post eksportu CSV spraw.
 */
final class CsvExport {

	/**
	 * Nazwa akcji admin-post (i klucz nonce).
	 */
	public const ACTION = 'mp_automator_export_csv';

	/**
	 * Rozmiar strony pobierania z mp_cases_query (chunk kontraktu).
	 */
	private const CHUNK = 500;

	/**
	 * Twardy limit stron (pas bezpieczenstwa przed petla — 500k spraw).
	 */
	private const MAX_PAGES = 1000;

	/**
	 * Separator CSV — srednik (Excel PL domyslnie czyta listy po sredniku).
	 */
	private const SEP = ';';

	/**
	 * Rejestruje handler (priv I nopriv => ten sam handler; capability PIERWSZA,
	 * wiec subscriber/anon dostaja JAWNE 403, nie 400 z braku handlera).
	 *
	 * @return void
	 */
	public static function register(): void {
		add_action( 'admin_post_' . self::ACTION, array( self::class, 'handle' ) );
		add_action( 'admin_post_nopriv_' . self::ACTION, array( self::class, 'handle' ) );
	}

	/**
	 * Czy biezacy uzytkownik moze eksportowac (koordynator lub administrator systemu).
	 *
	 * @return bool
	 */
	private static function can_export(): bool {
		return current_user_can( 'mp_coordinator' ) || current_user_can( 'mp_system_admin' );
	}

	/**
	 * Obsluga eksportu: capability => nonce => zbierz => audyt => stream CSV.
	 *
	 * @return void
	 */
	public static function handle(): void {
		if ( ! self::can_export() ) {
			wp_die(
				esc_html__( 'Brak uprawnień do eksportu spraw.', 'mp-workflow-automator' ),
				'',
				array( 'response' => 403 )
			);
		}

		check_admin_referer( self::ACTION );

		$filters = self::read_filters();

		// Liczba wierszy BEZ sciagania ich do pamieci: kontrakt `mp_cases_query` zwraca
		// `total` obok `rows`, wiec jedna strona o rozmiarze 1 wystarczy do audytu.
		// Audyt zostaje PRZED wysylka — slad wyniesienia danych ma powstac takze wtedy,
		// gdy pobieranie urwie sie w polowie.
		$sonda = apply_filters( 'mp_cases_query', null, $filters, 1, 1 );
		$total = is_array( $sonda ) && isset( $sonda['total'] ) ? (int) $sonda['total'] : 0;

		// Audyt bulk-egress (append-only, NO-PII: tylko referencje/liczby/hash filtra).
		WorkflowEvents::log(
			WorkflowEvents::EXPORT_GENERATED,
			array(
				'user_id'      => get_current_user_id(),
				'rows'         => $total,
				'filters_hash' => md5( (string) wp_json_encode( $filters ) ),
			),
			null,
			get_current_user_id()
		);

		self::stream( $filters );
	}

	/**
	 * Czyta i sanityzuje filtry z requestu (nonce zweryfikowany wyzej).
	 *
	 * @return array<string, string>
	 */
	private static function read_filters(): array {
		$filters = array();

		foreach ( array( 'status', 'kind', 'date_from', 'date_to' ) as $key ) {
			// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- check_admin_referer() juz wywolany w handle().
			$raw = isset( $_GET[ $key ] ) ? sanitize_text_field( wp_unslash( $_GET[ $key ] ) ) : '';

			if ( '' !== $raw ) {
				$filters[ $key ] = $raw;
			}
		}

		return $filters;
	}

	/**
	 * Wysyla CSV (naglowki + BOM + sekcja danych + sekcja zestawienia) i konczy.
	 *
	 * STRUMIENIOWO — wiersze leca do przegladarki strona po stronie, a nie po zebraniu
	 * calosci do pamieci PHP (audyt 29.07). Dotad `collect()` sciagalo WSZYSTKIE sprawy
	 * do jednej tablicy przed wyslaniem czegokolwiek: przy kilkudziesieciu tysiacach
	 * spraw koordynator klikal „Eksport" i dostawal biala strone albo blad limitu czasu,
	 * bez zadnej podpowiedzi, ze chodzi o rozmiar. Teraz pamiec nie rosnie z liczba spraw
	 * (jedna strona naraz), a przegladarka dostaje pierwsze bajty od razu.
	 *
	 * Zestawienie na koncu pliku liczymy AKUMULACYJNIE (liczniki sa sumowalne), wiec
	 * nie wymaga drugiego przebiegu ani trzymania danych.
	 *
	 * @param array<string, string> $filters Filtry z requestu (jak w mp_cases_query).
	 * @return never
	 */
	private static function stream( array $filters ): void {
		$reasons = apply_filters( 'mp_rejection_reasons', array() );
		$reasons = is_array( $reasons ) ? $reasons : array();

		$filename = 'mp-eksport-spraw-' . gmdate( 'Ymd-Hi' ) . '.csv';

		nocache_headers();
		header( 'Content-Type: text/csv; charset=UTF-8' );
		header( 'X-Content-Type-Options: nosniff' );
		header( 'Content-Disposition: attachment; filename="' . $filename . '"' );

		// BOM UTF-8 => Excel PL czyta polskie ogonki poprawnie.
		echo "\xEF\xBB\xBF";

		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fopen -- stream odpowiedzi HTTP (download generowany w locie, nie plik dyskowy).
		$out = fopen( 'php://output', 'w' );

		if ( false === $out ) {
			exit;
		}

		// ── Sekcja danych ──────────────────────────────────────────────────
		self::put_row(
			$out,
			array(
				__( 'Nr sprawy', 'mp-workflow-automator' ),
				__( 'Status', 'mp-workflow-automator' ),
				__( 'Rodzaj', 'mp-workflow-automator' ),
				__( 'Kraj', 'mp-workflow-automator' ),
				__( 'Język', 'mp-workflow-automator' ),
				__( 'Data utworzenia (UTC)', 'mp-workflow-automator' ),
				__( 'Data zamknięcia (UTC)', 'mp-workflow-automator' ),
				__( 'Czas obsługi (godz.)', 'mp-workflow-automator' ),
				__( 'Powód odrzucenia (kod)', 'mp-workflow-automator' ),
				__( 'Powód odrzucenia', 'mp-workflow-automator' ),
			)
		);

		// Akumulator zestawienia — rosnie o STALA wielkosc, nie o liczbe spraw.
		$acc  = array(
			'total'     => 0,
			'by_status' => array(),
			'by_reason' => array(),
			'closed'    => 0,
			'sum_sec'   => 0,
		);
		$page = 1;

		do {
			$res  = apply_filters( 'mp_cases_query', null, $filters, $page, self::CHUNK );
			$rows = is_array( $res ) && isset( $res['rows'] ) && is_array( $res['rows'] ) ? $res['rows'] : array();

			foreach ( $rows as $c ) {
				$code  = isset( $c['rejection_reason_code'] ) && null !== $c['rejection_reason_code']
					? (string) $c['rejection_reason_code']
					: '';
				$label = '' !== $code && isset( $reasons[ $code ] ) ? (string) $reasons[ $code ] : $code;

				self::put_row(
					$out,
					array(
						(string) ( $c['case_number'] ?? '' ),
						(string) ( $c['status'] ?? '' ),
						(string) ( $c['kind'] ?? '' ),
						(string) ( $c['country'] ?? '' ),
						(string) ( $c['lang'] ?? '' ),
						(string) ( $c['created_at'] ?? '' ),
						(string) ( $c['closed_at'] ?? '' ),
						self::hours( $c['handling_seconds'] ?? null ),
						$code,
						$label,
					)
				);

				self::accumulate( $acc, $c, $code );
			}

			// Wypychamy to, co juz powstalo — inaczej bufor PHP i tak trzymalby caly
			// plik w pamieci i cala ta zmiana nic by nie dala.
			if ( 0 !== ob_get_level() ) {
				ob_flush();
			}
			flush();

			$got = count( $rows );
			++$page;
		} while ( self::CHUNK === $got && $page <= self::MAX_PAGES );

		// ── Sekcja zestawienia ─────────────────────────────────────────────
		$summary = self::summary_finish( $acc );

		self::put_row( $out, array( '' ) );
		self::put_row( $out, array( __( 'ZESTAWIENIE', 'mp-workflow-automator' ) ) );
		self::put_row( $out, array( __( 'Łączna liczba spraw', 'mp-workflow-automator' ), (string) $summary['total'] ) );

		self::put_row( $out, array( '' ) );
		self::put_row( $out, array( __( 'Liczba spraw wg statusu', 'mp-workflow-automator' ) ) );
		foreach ( $summary['by_status'] as $status => $count ) {
			self::put_row( $out, array( (string) $status, (string) $count ) );
		}

		self::put_row( $out, array( '' ) );
		self::put_row( $out, array( __( 'Czas obsługi (sprawy zamknięte)', 'mp-workflow-automator' ) ) );
		self::put_row( $out, array( __( 'Liczba spraw zamkniętych', 'mp-workflow-automator' ), (string) $summary['closed_count'] ) );
		self::put_row( $out, array( __( 'Średni czas obsługi (godz.)', 'mp-workflow-automator' ), $summary['avg_hours'] ) );
		self::put_row( $out, array( __( 'Łączny czas obsługi (godz.)', 'mp-workflow-automator' ), $summary['total_hours'] ) );

		self::put_row( $out, array( '' ) );
		self::put_row( $out, array( __( 'Rozkład powodów odrzuceń', 'mp-workflow-automator' ) ) );
		if ( array() === $summary['by_reason'] ) {
			self::put_row( $out, array( __( '(brak spraw odrzuconych)', 'mp-workflow-automator' ) ) );
		}
		foreach ( $summary['by_reason'] as $code => $count ) {
			$label = isset( $reasons[ $code ] ) ? (string) $reasons[ $code ] : (string) $code;
			self::put_row( $out, array( $label, (string) $count ) );
		}

		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fclose -- para do fopen(php://output).
		fclose( $out );
		exit;
	}

	/**
	 * Dokłada JEDNĄ sprawe do zestawienia (liczniki per status, czas obslugi,
	 * rozklad powodow odrzucen).
	 *
	 * Liczby sa sumowalne, wiec zestawienie powstaje w trakcie wysylki — bez
	 * trzymania spraw w pamieci i bez drugiego przebiegu po danych.
	 *
	 * @param array<string, mixed> $acc    Akumulator (modyfikowany przez referencje).
	 * @param array<string, mixed> $sprawa Jedna sprawa z mp_cases_query.
	 * @param string               $code   Kod powodu odrzucenia ('' gdy brak).
	 * @return void
	 */
	private static function accumulate( array &$acc, array $sprawa, string $code ): void {
		++$acc['total'];

		$status = (string) ( $sprawa['status'] ?? '' );

		if ( ! isset( $acc['by_status'][ $status ] ) ) {
			$acc['by_status'][ $status ] = 0;
		}
		++$acc['by_status'][ $status ];

		$handling = $sprawa['handling_seconds'] ?? null;
		if ( null !== $handling ) {
			++$acc['closed'];
			$acc['sum_sec'] += (int) $handling;
		}

		if ( '' !== $code ) {
			if ( ! isset( $acc['by_reason'][ $code ] ) ) {
				$acc['by_reason'][ $code ] = 0;
			}
			++$acc['by_reason'][ $code ];
		}
	}

	/**
	 * Domyka zestawienie z akumulatora (te same pola co dawne `summarize`).
	 *
	 * @param array<string, mixed> $acc Akumulator z `accumulate()`.
	 * @return array<string, mixed>
	 */
	private static function summary_finish( array $acc ): array {
		$closed  = (int) $acc['closed'];
		$sum_sec = (int) $acc['sum_sec'];

		return array(
			'total'        => (int) $acc['total'],
			'by_status'    => (array) $acc['by_status'],
			'closed_count' => $closed,
			'avg_hours'    => $closed > 0 ? self::hours( (int) round( $sum_sec / $closed ) ) : '',
			'total_hours'  => self::hours( $sum_sec ),
			'by_reason'    => (array) $acc['by_reason'],
		);
	}

	/**
	 * Sekundy => godziny (2 miejsca), '' dla NULL.
	 *
	 * @param mixed $seconds Sekundy lub null.
	 * @return string
	 */
	private static function hours( $seconds ): string {
		if ( null === $seconds ) {
			return '';
		}

		return number_format_i18n( (int) $seconds / HOUR_IN_SECONDS, 2 );
	}

	/**
	 * Zapisuje wiersz CSV z anti-formula-injection na KAZDYM polu.
	 *
	 * @param resource           $handle Uchwyt strumienia.
	 * @param array<int, string> $cells  Komorki (surowe).
	 * @return void
	 */
	private static function put_row( $handle, array $cells ): void {
		$safe = array_map( array( self::class, 'harden' ), $cells );

		// $escape PUSTY = RFC-4180 (jak Excel). Jawnie, bo PHP 8.4+ deprecuje
		// pominiecie argumentu, a jego domyslna wartosc ma sie zmienic.
		// phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_fwrite, WordPress.WP.AlternativeFunctions.file_system_operations_fputcsv -- zapis wiersza do strumienia odpowiedzi (download w locie).
		fputcsv( $handle, $safe, self::SEP, '"', '' );
	}

	/**
	 * CSV-formula-injection: pole zaczynajace sie od = + - @ TAB CR => prefiks
	 * apostrofu (Excel/Sheets nie wykona jako formuly). OBOWIAZKOWE (RCE u klienta).
	 *
	 * @param string $value Wartosc.
	 * @return string
	 */
	private static function harden( string $value ): string {
		if ( '' === $value ) {
			return $value;
		}

		$first = $value[0];

		if ( in_array( $first, array( '=', '+', '-', '@', "\t", "\r" ), true ) ) {
			return "'" . $value;
		}

		return $value;
	}
}
