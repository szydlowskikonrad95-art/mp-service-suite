<?php
/**
 * Archiwum produktu (soft delete: archived + deleted_at/by; DATABASE.md).
 *
 * FAIL-CLOSED (kontrakt mp_product_active_cases_count): bez dzialajacego
 * modulu spraw (C) NIE DA SIE potwierdzic braku aktywnych spraw, wiec
 * archiwizacja jest ODMAWIANA — nigdy "na slowo".
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * Archiwizacja i przywracanie produktow.
 */
final class Archive {

	/**
	 * Archiwizuje produkt (soft delete).
	 *
	 * @param int $product_registry_id ID produktu.
	 * @return true|array{error: string}
	 */
	public static function archive( int $product_registry_id ) {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			return array( 'error' => __( 'Archiwizować produkty może wyłącznie administrator systemu MP.', 'mp-warranty-registry' ) );
		}

		$row = self::get_product( $product_registry_id );

		if ( null === $row ) {
			return array( 'error' => __( 'Produkt o tym ID nie istnieje.', 'mp-warranty-registry' ) );
		}

		if ( '1' === (string) $row['archived'] ) {
			return array( 'error' => __( 'Ten produkt jest już w archiwum.', 'mp-warranty-registry' ) );
		}

		if ( ! has_filter( 'mp_product_active_cases_count' ) ) {
			return array( 'error' => __( 'Nie można potwierdzić braku aktywnych spraw (moduł spraw nieaktywny) — archiwizacja odmówiona.', 'mp-warranty-registry' ) );
		}

		$count = apply_filters( 'mp_product_active_cases_count', null, $product_registry_id );

		if ( ! is_numeric( $count ) ) {
			return array( 'error' => __( 'Moduł spraw nie odpowiedział jednoznacznie — archiwizacja odmówiona (FAIL-CLOSED).', 'mp-warranty-registry' ) );
		}

		if ( (int) $count > 0 ) {
			return array( 'error' => self::aktywne_sprawy_komunikat( (int) $count ) );
		}

		// M3: odczyt wyzej jest dla KOMUNIKATU, nie dla decyzji. Rozstrzyga zapis
		// nizej — liczy pod zamkiem, we wlasnej transakcji. Gdy w tym oknie powstala
		// sprawa, `set_archived()` odmawia i produkt zostaje nietkniety; wtedy
		// mowimy o tym czlowiekowi TYM SAMYM zdaniem co przy zwyklej odmowie,
		// zamiast melodwac „zarchiwizowano".
		if ( ! self::set_archived( $product_registry_id, true ) ) {
			$swiezy = apply_filters( 'mp_product_active_cases_count', null, $product_registry_id );

			return array(
				'error' => is_numeric( $swiezy ) && (int) $swiezy > 0
					? self::aktywne_sprawy_komunikat( (int) $swiezy )
					: __( 'Nie można potwierdzić braku aktywnych spraw — archiwizacja odmówiona (FAIL-CLOSED).', 'mp-warranty-registry' ),
			);
		}

		return true;
	}

	/**
	 * Zdanie odmowy z liczba aktywnych spraw.
	 *
	 * Trzy formy polskiej odmiany — bez tego klient widzial „ma 1 aktywnych spraw"
	 * (audyt 27.07, soczewka jezykowa). Przypadek n=1 jest tu NORMALNY, nie skrajny:
	 * wystarczy jedna otwarta sprawa, zeby blokada zadzialala. JEDNO ZRODLO dla obu
	 * odmow (przed zamkiem i spod zamka) — inaczej rozjada sie slowo w slowo.
	 *
	 * @param int $count Liczba aktywnych spraw (>0).
	 * @return string
	 */
	private static function aktywne_sprawy_komunikat( int $count ): string {
		$fraza = Common\Str::odmiana(
			$count,
			__( 'Produkt ma 1 aktywną sprawę — najpierw ją zamknij.', 'mp-warranty-registry' ),
			/* translators: %d: liczba aktywnych spraw (2-4). */
			__( 'Produkt ma %d aktywne sprawy — najpierw je zamknij.', 'mp-warranty-registry' ),
			/* translators: %d: liczba aktywnych spraw (5 i wiecej). */
			__( 'Produkt ma %d aktywnych spraw — najpierw je zamknij.', 'mp-warranty-registry' )
		);

		return sprintf( $fraza, $count );
	}

	/**
	 * Przywraca produkt z archiwum (komunikat importu: "przywroc jawnie").
	 *
	 * @param int $product_registry_id ID produktu.
	 * @return true|array{error: string}
	 */
	public static function restore( int $product_registry_id ) {
		if ( ! current_user_can( 'mp_system_admin' ) ) {
			return array( 'error' => __( 'Przywracać produkty może wyłącznie administrator systemu MP.', 'mp-warranty-registry' ) );
		}

		$row = self::get_product( $product_registry_id );

		if ( null === $row ) {
			return array( 'error' => __( 'Produkt o tym ID nie istnieje.', 'mp-warranty-registry' ) );
		}

		if ( '1' !== (string) $row['archived'] ) {
			return array( 'error' => __( 'Ten produkt nie jest w archiwum.', 'mp-warranty-registry' ) );
		}

		self::set_archived( $product_registry_id, false );

		return true;
	}

	/**
	 * Zapis flagi archiwum + wpis historii (diff before/after).
	 *
	 * @param int  $product_registry_id ID produktu.
	 * @param bool $archived            Docelowy stan.
	 * @return bool True = zapisano; false = odmowa (stan produktu nietkniety).
	 */
	private static function set_archived( int $product_registry_id, bool $archived ): bool {
		global $wpdb;

		// Audyt #18: bramka "aktywna sprawa blokuje archiwizacje" na NAJNIZSZYM
		// mutatorze — kazda przyszla sciezka zapisu przechodzi przez ten sam
		// punkt (dotad pilnowal tylko Archive::archive, wiec nowy caller moglby
		// bramke ominac). FAIL-CLOSED: brak odpowiedzi modulu spraw = odmowa.
		//
		// ⛔ M3 (recenzja zewnetrzna 1.3.12): liczenie i zapis byly DWOMA osobnymi
		// krokami bez wspolnego zamka. Sprawa zalozona w oknie miedzy nimi (milisekundy)
		// nie mogla juz zatrzymac archiwizacji: produkt szedl do archiwum z aktywna
		// sprawa, wbrew instrukcji i wbrew samej bramce. Teraz OBA kroki siedza w jednej
		// transakcji, a liczenie idzie POD ZAMKIEM (trzeci argument haka => FOR UPDATE
		// po stronie C). Zalozenie sprawy temu produktowi czeka wtedy na nasz COMMIT,
		// wiec albo zdazy przed liczeniem (i my odmawiamy), albo po zapisie (i wtedy
		// bramka juz obowiazuje). Zamka nie zaklada Registry — prosi o niego wlasciciela
		// tabeli hakiem, wiec granica wlasnosci danych zostaje nienaruszona.
		$transakcja = false;

		if ( $archived ) {
			// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- sterowanie transakcja, nie zapytanie do tabeli.
			$wpdb->query( 'START TRANSACTION' );
			$transakcja = true;

			$count = has_filter( 'mp_product_active_cases_count' )
				? apply_filters( 'mp_product_active_cases_count', null, $product_registry_id, true )
				: null;

			if ( ! is_numeric( $count ) || (int) $count > 0 ) {
				// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- sterowanie transakcja, nie zapytanie do tabeli.
				$wpdb->query( 'ROLLBACK' );

				return false; // Odmowa — stan produktu nietkniety (archive() melduje blad wyzej).
			}
		}

		$table    = Tables::full( Tables::REGISTRY );
		$actor_id = get_current_user_id();
		$now      = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytania przygotowane.
		if ( $archived ) {
			$wpdb->query(
				$wpdb->prepare(
					"UPDATE {$table} SET archived = 1, deleted_at = %s, deleted_by = %d, updated_at = %s WHERE id = %d",
					$now,
					$actor_id,
					$now,
					$product_registry_id
				)
			);
		} else {
			$wpdb->query(
				$wpdb->prepare(
					"UPDATE {$table} SET archived = 0, deleted_at = NULL, deleted_by = NULL, updated_at = %s WHERE id = %d",
					$now,
					$product_registry_id
				)
			);
		}
		// phpcs:enable

		ProductEvents::log(
			$product_registry_id,
			'PRODUCT_UPDATED',
			array(
				'archived' => array(
					'before' => $archived ? 0 : 1,
					'after'  => $archived ? 1 : 0,
				),
			),
			$actor_id
		);

		if ( $transakcja ) {
			// Wpis historii siedzi w TEJ SAMEJ transakcji co flaga — archiwum bez
			// sladu w historii produktu bylo dotad mozliwe przy padzie miedzy zapisami.
			// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- sterowanie transakcja, nie zapytanie do tabeli.
			$wpdb->query( 'COMMIT' );
		}

		return true;
	}

	/**
	 * Odczyt produktu po ID.
	 *
	 * @param int $product_registry_id ID produktu.
	 * @return array<string, mixed>|null
	 */
	private static function get_product( int $product_registry_id ): ?array {
		global $wpdb;

		$table = Tables::full( Tables::REGISTRY );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT id, archived FROM {$table} WHERE id = %d", $product_registry_id ),
			ARRAY_A
		);
		// phpcs:enable

		return is_array( $row ) ? $row : null;
	}
}
