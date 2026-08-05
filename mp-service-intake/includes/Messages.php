<?php
/**
 * Wiadomosci sprawy — wp_mp_messages ( historia wiadomosci klient<->serwis).
 *
 * Komunikacja NIE JEST audit-logiem: wiadomosci sa REDAGOWALNE przy RODO
 * (kwazi-identyfikatory), a events zostaja nietkniete. Event `mp_case_message_added`
 * niesie TYLKO wskazniki (case_id, message_id, author_type) — bez tresci.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Repozytorium wiadomosci spraw.
 */
final class Messages {

	/**
	 * Marker wartosci po redakcji RODO.
	 */
	public const REDACTED = '[ZREDAGOWANO-RODO]';

	/**
	 * Typ autora: NOTATKA WEWNETRZNA personelu (audyt 2.15).
	 *
	 * Produkt mial trzy typy — klient, personel, system — i zaden z nich nie byl
	 * niewidoczny dla klienta. Serwisant nie mial gdzie zapisac uwagi dla kolegi:
	 * o podejrzeniu ingerencji, o wycenie, o kliencie. Interfejs nie wprowadzal
	 * w blad (pole nazywa sie „odpowiedz"), wiec nie bylo tu pulapki „notatka,
	 * ktora wycieka" — brakowalo po prostu miejsca na notatke.
	 *
	 * ⛔ NIEWIDOCZNOSC JEST EGZEKWOWANA W ZAPYTANIU, nie w szablonie. Ukrycie
	 * na poziomie wygladu przecieka przy pierwszym nowym widoku, eksporcie
	 * albo kanale API.
	 */
	public const INTERNAL = 'internal';

	/**
	 * Dodaje wiadomosc do sprawy i emituje mp_case_message_added (bez tresci).
	 *
	 * @param int      $case_id     ID sprawy.
	 * @param string   $author_type client|staff|system|internal.
	 * @param int|null $author_id   ID autora (WP user; null dla system).
	 * @param string   $body        Tresc wiadomosci.
	 * @return int ID wiadomosci.
	 */
	public static function add( int $case_id, string $author_type, ?int $author_id, string $body ): int {
		global $wpdb;

		// Audyt #5: podwojny POST tej samej wiadomosci (dwuklik/refresh) dawal
		// dwa identyczne wpisy na osi i dwa maile. Rezerwacja 60 s na odcisku
		// tresci: duplikat w oknie zwraca ISTNIEJACY wpis bez drugiego zdarzenia.
		// Ta sama tresc wyslana ponownie PO oknie jest legalna (klient moze
		// sie powtorzyc celowo).
		$odcisk = 'mp_rl_msg_' . md5( $case_id . '|' . $author_type . '|' . (string) ( $author_id ?? 0 ) . '|' . sha1( $body ) );

		if ( ! RateLimit::claim_window( $odcisk, MINUTE_IN_SECONDS ) ) {
			$table = Tables::full( Tables::MESSAGES );

			// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
			$existing = $wpdb->get_var(
				$wpdb->prepare(
					"SELECT id FROM {$table} WHERE case_id = %d AND author_type = %s AND body = %s ORDER BY id DESC LIMIT 1",
					$case_id,
					$author_type,
					$body
				)
			);
			// phpcs:enable

			if ( null !== $existing ) {
				return (int) $existing;
			}
		}

		$now = gmdate( 'Y-m-d H:i:s' );

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna.
		$wpdb->insert(
			Tables::full( Tables::MESSAGES ),
			array(
				'case_id'     => $case_id,
				'author_type' => in_array( $author_type, array( 'client', 'staff', 'system', self::INTERNAL ), true ) ? $author_type : 'system',
				'author_id'   => $author_id,
				'body'        => $body,
				'created_at'  => $now,
			)
		);
		// phpcs:enable

		$message_id = (int) $wpdb->insert_id;

		/**
		 * Sygnal dla D: dopisano wiadomosc (BEZ tresci — tylko wskazniki).
		 *
		 * @param int    $case_id     ID sprawy.
		 * @param int    $message_id  ID wiadomosci.
		 * @param string $author_type Typ autora.
		 */
		// ⛔ NOTATKA WEWNETRZNA NIE EMITUJE ZDARZENIA. Zdarzenie uruchamia reguly
		// powiadomien, a te wysylaja mail do klienta — notatka „dla kolegi" nie moze
		// wywolac maila do osoby, przed ktora jest ukryta. Ukrycie w odczycie bez
		// tego byloby polowiczne: tresci klient by nie zobaczyl, ale dostalby
		// wiadomosc, ze „jest nowa odpowiedz".
		if ( self::INTERNAL !== $author_type ) {
			do_action( 'mp_case_message_added', $case_id, $message_id, $author_type );
		}

		return $message_id;
	}

	/**
	 * Notatka WEWNETRZNA personelu — widoczna wylacznie w karcie sprawy (2.15).
	 *
	 * @param int    $case_id   ID sprawy.
	 * @param int    $author_id Kto pisze (pracownik).
	 * @param string $body      Tresc.
	 * @return int ID wiadomosci.
	 */
	public static function add_internal_note( int $case_id, int $author_id, string $body ): int {
		return self::add( $case_id, self::INTERNAL, $author_id, $body );
	}

	/**
	 * Listener kontraktowy: wiadomosc systemowa od D (np. raport koncowy).
	 *
	 * @param int    $case_id ID sprawy.
	 * @param string $content Tresc wiadomosci systemowej.
	 * @return int ID wiadomosci.
	 */
	public static function add_system_message( int $case_id, string $content ): int {
		return self::add( $case_id, 'system', null, $content );
	}

	/**
	 * Wiadomosci sprawy (chronologicznie) — panel klienta / eksport.
	 *
	 * @param int  $case_id       ID sprawy.
	 * @param bool $with_internal Czy dolaczyc NOTATKI WEWNETRZNE (tylko karta personelu).
	 * @return array<int, array<string, mixed>>
	 */
	public static function for_case( int $case_id, bool $with_internal = false ): array {
		global $wpdb;

		$table = Tables::full( Tables::MESSAGES );

		// DOMYSLNIE BEZ NOTATEK WEWNETRZNYCH (audyt 2.15). Domyslna wartosc jest
		// tu decyzja o bezpieczenstwie: kto zapomni o parametrze, dostaje wersje
		// BEZPIECZNA dla klienta, a nie wyciek. Notatki widzi tylko ten, kto
		// poprosi o nie WPROST — dzis wylacznie karta sprawy personelu.
		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- tabela wlasna, zapytanie przygotowane.
		$rows = $with_internal
			? $wpdb->get_results(
				$wpdb->prepare( "SELECT * FROM {$table} WHERE case_id = %d ORDER BY id ASC", $case_id ),
				ARRAY_A
			)
			: $wpdb->get_results(
				$wpdb->prepare(
					"SELECT * FROM {$table} WHERE case_id = %d AND author_type != %s ORDER BY id ASC",
					$case_id,
					self::INTERNAL
				),
				ARRAY_A
			);
		// phpcs:enable

		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * Redaguje wiadomosci klienta (RODO) dla podanych spraw.
	 *
	 * @param array<int> $case_ids Sprawy klienta.
	 * @return int Liczba zredagowanych wiadomosci.
	 */
	public static function redact_for_cases( array $case_ids ): int {
		global $wpdb;

		$ids = array_values( array_filter( array_map( 'absint', $case_ids ) ) );

		if ( array() === $ids ) {
			return 0;
		}

		$placeholders = implode( ',', array_fill( 0, count( $ids ), '%d' ) );
		$table        = Tables::full( Tables::MESSAGES );
		$redacted     = self::REDACTED;

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching, WordPress.DB.PreparedSQL.InterpolatedNotPrepared, WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare, WordPress.DB.PreparedSQLPlaceholders.ReplacementsWrongNumber -- tabela wlasna; lista %d w IN() budowana z count($ids) + 2 markery, sniff nie widzi dynamicznego IN.
		$affected = $wpdb->query(
			$wpdb->prepare(
				"UPDATE {$table} SET body = %s WHERE case_id IN ({$placeholders}) AND body <> %s",
				array_merge( array( $redacted ), $ids, array( $redacted ) )
			)
		);
		// phpcs:enable

		return (int) $affected;
	}
}
