<?php
/**
 * Lista dozwolonych komunikatow przekazywanych przez `?mp_notice=` (S4 #2).
 *
 * Komunikaty po akcjach (zmiana danych, logowanie, zmiana statusu, ponowna
 * wysylka linku) wracaja do uzytkownika przez parametr adresu `mp_notice`.
 * Tresc byla brana z URL WPROST i wyswietlana na prawdziwej stronie serwisu —
 * bez wlamania (wyjscie jest escapowane), ale spreparowanym linkiem dalo sie
 * pokazac pracownikowi albo klientowi DOWOLNE zdanie (np. „Zadzwon pod numer
 * premium"), firmowane domena serwisu. Tu jest zbior zdan, ktore produkt
 * NAPRAWDE wysyla; czytelnik pokazuje wylacznie tresc z tego zbioru, a wszystko
 * spoza niego zamienia na pusty string (zaden komunikat).
 *
 * ⛔ DODAJESZ nowy komunikat w helperze redirectu (AccountPage::redirect_notice,
 * Login::back_with_notice, CaseActions::back, UnverifiedScreen::back)? Dopisz go
 * TU, inaczej ten (legalny) komunikat po prostu sie nie pokaze. Jedno gardlo.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Bramka dozwolonych komunikatow `mp_notice`.
 */
final class Notices {

	/**
	 * Przepuszcza tekst tylko wtedy, gdy jest jednym z komunikatow produktu.
	 *
	 * @param string $raw Surowa tresc z `mp_notice` (juz zsanityzowana z GET).
	 * @return string Ten sam tekst gdy dozwolony; '' gdy spoza listy.
	 */
	public static function filter( string $raw ): string {
		if ( '' === $raw ) {
			return '';
		}

		return in_array( $raw, self::allowed(), true ) ? $raw : '';
	}

	/**
	 * Pelny zbior dozwolonych komunikatow (te same stringi `__()`, co helpery
	 * redirectu — porownanie dziala w kazdym jezyku, bo obie strony tlumacza tak samo).
	 *
	 * @return array<int, string>
	 */
	public static function allowed(): array {
		return array(
			// Front — panel klienta (AccountPage) i logowanie (Login).
			__( 'Sesja wygasła — spróbuj ponownie.', 'mp-service-intake' ),
			__( 'Dane kontaktowe zostały zapisane.', 'mp-service-intake' ),
			__( 'Wiadomość została wysłana do serwisu.', 'mp-service-intake' ),
			__( 'Wiadomość jest pusta.', 'mp-service-intake' ),
			__( 'Nie znaleziono zgłoszenia.', 'mp-service-intake' ),
			__( 'Zgoda została wycofana, a Twoje dane osobowe zostały usunięte.', 'mp-service-intake' ),
			__( 'Zgoda została wycofana. Masz aktywne zgłoszenie — dane usuniemy po jego zakończeniu.', 'mp-service-intake' ),
			__( 'Zgoda została wycofana.', 'mp-service-intake' ),
			__( 'Z tego adresu e-mail korzysta więcej niż jedna osoba, więc samodzielna edycja i usuwanie danych są wyłączone. Napisz wiadomość w swojej sprawie — pracownik serwisu zaktualizuje lub usunie Twoje dane po potwierdzeniu tożsamości.', 'mp-service-intake' ),
			__( 'Zbyt wiele prób logowania — odczekaj kilka minut i spróbuj ponownie.', 'mp-service-intake' ),
			__( 'Jeśli konto istnieje, wysłaliśmy link do logowania na podany adres e-mail.', 'mp-service-intake' ),
			// Panel personelu — karta sprawy (CaseActions → CaseCard).
			__( 'Brak danych zmiany statusu.', 'mp-service-intake' ),
			__( 'Status zmieniony (klient i przypisany pracownik powiadomieni).', 'mp-service-intake' ),
			// W6: wariant, gdy autor zmiany = przypisany pracownik (self-skip
			// automatora) albo sprawa nie ma przypisanego — mail idzie tylko do klienta.
			__( 'Status zmieniony (klient powiadomiony).', 'mp-service-intake' ),
			__( 'Ktoś zmienił status w międzyczasie — odśwież stronę i spróbuj ponownie.', 'mp-service-intake' ),
			__( 'Odrzucenie wymaga podania powodu.', 'mp-service-intake' ),
			__( 'Niedozwolone przejście statusu (sprawę zamkniętą można tylko wznowić do „w analizie").', 'mp-service-intake' ),
			__( 'Sprawa nie istnieje lub niepotwierdzona.', 'mp-service-intake' ),
			__( 'Nie udało się zmienić statusu.', 'mp-service-intake' ),
			__( 'Brak sprawy.', 'mp-service-intake' ),
			__( 'Odpowiedź wysłana do klienta.', 'mp-service-intake' ),
			__( 'Notatka jest pusta.', 'mp-service-intake' ),
			__( 'Notatka zapisana — widzi ją tylko personel.', 'mp-service-intake' ),
			__( 'Wybierz pracownika do przydziału.', 'mp-service-intake' ),
			__( 'Sprawa przydzielona (pracownik powiadomiony).', 'mp-service-intake' ),
			__( 'Sprawy prowadzą pracownicy serwisu — koordynatora ani administratora nie da się na nią przydzielić.', 'mp-service-intake' ),
			__( 'Nie znaleziono sprawy albo klient nie potwierdził jeszcze zgłoszenia.', 'mp-service-intake' ),
			__( 'Nie udało się przydzielić sprawy.', 'mp-service-intake' ),
			// Niepotwierdzone (UnverifiedScreen).
			__( 'Tej sprawy nie można ponowić (nie jest niepotwierdzona).', 'mp-service-intake' ),
			__( 'NIE UDAŁO SIĘ wysłać linku — poczta odmówiła przyjęcia wiadomości. Sprawdź Narzędzia → Stan witryny; sprawa nadal czeka na potwierdzenie. Ponowna próba możliwa za 5 minut.', 'mp-service-intake' ),
			__( 'Link weryfikacyjny wysłany ponownie (świeży token).', 'mp-service-intake' ),
		);
	}
}
