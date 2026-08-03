<?php
/**
 * Zapis wpisu do dziennika zdarzen — Z KONTROLA WYNIKU (wspolny dla 3 pluginow).
 *
 * ⛔ Po co ta klasa istnieje. Trzy dzienniki (sprawy, produkty, automat) miały
 * metode `log()` zadeklarowana jako `: void` i wykonywaly GOLE `$wpdb->insert()`,
 * bez odczytania wyniku. Nieudane wstawienie do bazy **zwraca wartosc falszywa,
 * a nie przerywa wykonania** — wiec proces szedl dalej tak, jakby wpis powstal:
 * status sie zmienial, decyzja gwarancyjna zapadala, dane osobowe znikaly,
 * a slad, ktory ma byc DOWODEM, cicho gubil zdarzenia.
 *
 * Kontrakt zamowienia mowi: „kazda zmiana statusu, komentarz, powiadomienie
 * i decyzja tworzy NIEUSUWALNY wpis w osi czasu sprawy", a dokumentacja stawia
 * to jeszcze mocniej: „status bez eventu NIGDY". Reguly „NIGDY" nie da sie
 * dotrzymac, jesli nikt nie sprawdza, czy zapis sie udal.
 *
 * Zwracamy `bool` (a nie wyjatek), bo wolajacy sa rozni: przy decyzji
 * gwarancyjnej wynik ma wycofac transakcje, a przy zwyklym powiadomieniu ma
 * tylko podniesc alarm. Alarm jest ZAWSZE — zeby awaria nie byla cicha nawet
 * wtedy, gdy wolajacy wyniku nie uzyje.
 *
 * @package MP\Common
 */

namespace MP\Common;

/**
 * Zapis do dziennika z kontrola wyniku i alarmem przy awarii.
 */
final class EventWrite {

	/**
	 * Opcja z ostatnia awaria zapisu dziennika (czytana przez Stan witryny).
	 */
	public const ALERT_OPTION = 'mp_event_write_alert';

	/**
	 * Wstawia wiersz dziennika i MOWI, czy sie udalo.
	 *
	 * @param string               $table Pelna nazwa tabeli dziennika.
	 * @param array<string, mixed> $row   Wiersz do zapisania.
	 * @return bool True gdy wpis powstal.
	 */
	public static function insert( string $table, array $row ): bool {
		global $wpdb;

		// phpcs:disable WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching -- tabela wlasna, dziennik append-only.
		$wynik = $wpdb->insert( $table, $row );
		// phpcs:enable

		if ( 1 === (int) $wynik ) {
			return true;
		}

		self::alert( $table, (string) ( $row['event_type'] ?? '' ) );

		return false;
	}

	/**
	 * Podnosi alarm widoczny w „Narzedzia → Stan witryny".
	 *
	 * Ten sam wzorzec, ktorym produkt sygnalizuje awarie poczty: opcja bez
	 * autoladowania, czytana przez test diagnostyczny. Bez tego administrator
	 * nie ma jak sie dowiedziec, ze dziennik gubi wpisy — a to jest dokladnie
	 * ta klasa awarii, ktora nie daje o sobie znac na ekranie.
	 *
	 * Wolane takze SPOZA dziennikow — tam, gdzie nieudany zapis ma taki sam
	 * ciezar (np. rejestr zgod: RODO art. 7 wymaga wykazania zgody).
	 *
	 * @param string $table      Tabela, ktorej dotyczy awaria.
	 * @param string $event_type Typ zdarzenia albo nazwa operacji.
	 * @return void
	 */
	public static function alert( string $table, string $event_type ): void {
		global $wpdb;

		// ⚠️ Czyscimy pamiec podreczna PRZED zapisem — i to nie jest ostroznosc
		// na wyrost. Gdy alarm powstal wewnatrz transakcji, ktora potem zostala
		// wycofana, wiersz w bazie znika, ale pamiec procesu trzyma nowa wartosc.
		// `update_option()` porownuje wtedy „stare" z „nowym", nie widzi roznicy
		// i NIC NIE ZAPISUJE. Samo `delete_option()` tu nie wystarcza: przy braku
		// wiersza w bazie konczy sie wczesniej i pamieci podrecznej NIE czysci.
		// Alarm gubil sie dokladnie w tym przypadku, dla ktorego powstal —
		// zlapane zywym testem (wycofanie decyzji gwarancyjnej).
		wp_cache_delete( self::ALERT_OPTION, 'options' );
		delete_option( self::ALERT_OPTION );

		update_option(
			self::ALERT_OPTION,
			array(
				'table'      => $table,
				'event_type' => $event_type,
				// Komunikat bazy bywa dlugi i techniczny — obcinamy, zero danych osobowych.
				'error'      => substr( (string) $wpdb->last_error, 0, 200 ),
				'time'       => gmdate( 'Y-m-d H:i:s' ),
			),
			false
		);
	}

	/**
	 * Ostatnia awaria zapisu dziennika (null = brak).
	 *
	 * @return array<string, mixed>|null
	 */
	public static function last_alert(): ?array {
		$alert = get_option( self::ALERT_OPTION, null );

		return is_array( $alert ) && array() !== $alert ? $alert : null;
	}

	/**
	 * Kasuje alarm (po potwierdzeniu przez administratora albo w testach).
	 *
	 * @return void
	 */
	public static function clear_alert(): void {
		delete_option( self::ALERT_OPTION );
	}
}
