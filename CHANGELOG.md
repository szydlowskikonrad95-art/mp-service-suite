# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/pl/1.1.0/) · wersjonowanie: [SemVer](https://semver.org/lang/pl/).

## [Unreleased]

## [1.3.13] — w przygotowaniu

> Numer wydania nie jest jeszcze wycięty: nagłówki wtyczek, `Stable tag` w `readme.txt`
> i pliki tłumaczeń nadal mówią 1.3.12 i podbije je osobny krok wydania. Poniżej jest komplet
> zmian scalonych do gałęzi głównej po wydaniu 1.3.12.

### Naprawione — bezpieczeństwo danych klienta
- 🔴 **Załącznik cudzej sprawy przestał być boczną furtką.** Pracownik serwisu widział na liście
  i na karcie **wyłącznie swoje** sprawy, ale załącznik — zdjęcie usterki, skan dokumentu zakupu —
  pobierał z **dowolnej** sprawy, także takiej, której nie obsługuje. Bramka załącznika pyta teraz
  o to samo, o co pyta karta: pracownik wchodzi tylko do spraw przydzielonych jemu, koordynator
  i administrator systemu — do wszystkich, klient — do swoich. Nikt uprawniony nie stracił dostępu.

### Naprawione — historia sprawy i powiadomienia
- 🔴 **Żadnej zmiany sprawy bez śladu na osi zdarzeń już nie będzie.** Gdy zapis wpisu do historii
  się nie udał, zmiana i tak wchodziła — sprawa dostawała nowy stan, a oś czasu o tym milczała,
  choć produkt obiecuje historię nieusuwalną i kompletną. Dotyczyło to **zmiany statusu, przydziału
  pracownika i zmiany priorytetu**. Teraz nieudany zapis **wycofuje całą zmianę**: personel widzi,
  że operacja się nie powiodła, a administrator dostaje sygnał w **Narzędzia → Stan witryny**.
  Lepiej odmówić zmiany, niż zmienić stan po cichu.
- 🔴 **Reguła powiadomienia utworzona dokładnie tak, jak podpowiada ekran, nie wyśle już
  wewnętrznej wiadomości do klienta.** Podpowiedź w polu „Szczegóły akcji" uczy jednego zapisu
  odbiorcy, a silnik reguł rozumiał tylko drugi — i cicho wysyłał **klientowi** treść napisaną dla
  pracownika. Oba zapisy działają teraz tak samo; reguły już istniejące zachowują się bez zmian.
- **Komunikat po zmianie statusu mówi tylko o mailach, które naprawdę wyszły.** Dotąd zawsze
  twierdził, że powiadomiono klienta **i** przypisanego pracownika — także wtedy, gdy status zmieniał
  sam przypisany pracownik (nie wysyłamy komu maila o jego własnej akcji) albo gdy sprawa nie miała
  przypisanego. W tych przypadkach pisze teraz po prostu: powiadomiono klienta.

### Naprawione — RODO
- 🔴 **Obietnica „dane usuniemy po zakończeniu zgłoszenia" wykonuje się sama.** Klient, który
  wycofał zgodę przy aktywnej sprawie, dostawał tę odpowiedź — i na tym się kończyło: po zamknięciu
  sprawy dane leżały w bazie bezterminowo, dopóki ktoś nie kliknął drugi raz. O tym nie wiedział ani
  klient, ani administrator. Teraz odroczone żądanie kończy **dobowy przebieg porządkowy**, zaraz po
  zamknięciu sprawy. Nowe zgłoszenie tej samej osoby przed wykonaniem anuluje odroczenie.

### Naprawione — współbieżność i niezawodność (recenzja zewnętrzna 1.3.12: M1, M3, M4)
- **Dobowy limit zgłoszeń trzyma także przy dwóch zgłoszeniach naraz.** Sprawdzenie limitu tylko
  CZYTAŁO licznik, a doliczenie zgłoszenia szło dopiero po założeniu sprawy — dwa żądania wysłane
  w tej samej chwili widziały ten sam stan i **oba przechodziły**, więc limit „3 na dobę" kończył się
  czterema sprawami (przy sześciu równoległych — sześcioma; zmierzone). Teraz miejsce w limicie
  rezerwuje się jednym, niepodzielnym zapisem, zanim sprawa powstanie. Komunikaty odmowy bez zmian:
  nadal mówią, KTÓRY limit blokuje i KIEDY można wrócić, i nie czyszczą formularza. Zgłoszenie
  odrzucone przy walidacji **oddaje** zajęte miejsce — literówka nadal nie zjada limitu na dobę.
- **Produktu z aktywną sprawą nie da się zarchiwizować także wtedy, gdy sprawa powstaje w tej samej
  sekundzie.** Liczenie spraw i zapis flagi archiwum były dwoma osobnymi krokami — sprawa założona
  między nimi nie zatrzymywała już archiwizacji, a ekran meldował sukces. Teraz oba kroki dzieją się
  w jednej transakcji, a liczenie odbywa się pod zamkiem po stronie modułu spraw (właściciela danych);
  odmowa mówi człowiekowi to samo zdanie co zwykle: „Produkt ma 1 aktywną sprawę — najpierw ją zamknij".
- **Chwilowa awaria poczty nie kasuje już przypomnienia SLA na stałe.** Przy większej liczbie zaległości
  jeden przebieg zamiatarki nadrabia je pętlą rund — a każda runda brała te same sprawy, więc komplet
  trzech prób wysyłki palił się w kilka sekund: powiadomienie było spisywane na straty, choć poczta
  wracała minutę później. Zmierzone: 55 zaległych przypomnień, jeden przebieg z padniętą pocztą →
  **20 przypomnień przepadło**. Teraz próby są rozsunięte w czasie (kolejna dopiero w następnym
  przebiegu), więc po powrocie poczty wychodzą wszystkie.

#### Zmiany techniczne
- Schemat Automatora **v3**: kolumny `reminder_attempt_at` / `escalation_attempt_at` w `wp_mp_case_sla`
  (migracja dokłada je automatycznie; nowa instalacja dostaje je od razu).
- Hak `mp_product_active_cases_count` przyjmuje trzeci argument `$for_update` (odczyt pod zamkiem);
  starsi słuchacze z dwoma argumentami działają bez zmian.
- Nowe żywe dowody: `testy/e2e/c-m1-limit-dobowy-wyscig.sh`, `testy/e2e/b-m3-archiwizacja-wyscig.sh`,
  `testy/e2e/d-m4-proby-sla-rozsuniete.sh` — każdy skalibrowany (pada na kodzie sprzed naprawy).

### Zmienione — komunikaty i ekrany
- **Odmowa przy zbyt wielu zgłoszeniach mówi, czego naprawdę dotyczy limit.** Klient słyszał
  zawsze „z tego adresu wysłano zbyt wiele zgłoszeń" — także wtedy, gdy blokada wynikała z limitu
  **numeru seryjnego** albo **łącza internetowego**. Człowiek z zupełnie nowym adresem zmieniał go
  wtedy bez skutku albo uznawał system za zepsuty. Każdy zakres ma teraz własne zdanie.
- **Tabela „Ostatnie importy" nadąża za banerem.** Po imporcie baner mówił „zakończony 8 z 8",
  a tabela tuż pod nim dalej „w trakcie, 0/8" — aż do ręcznego odświeżenia strony. Wiersz importu
  odświeża się teraz sam.
- **Rejestr zdarzeń automatu nie odsyła do reguły, której nie ma.** Wpisy pochodzące z mechanizmów
  wbudowanych (powiadomienie o przydziale, cykliczny przegląd terminów) pokazywały „reguła nr: 0",
  a tabela reguł numeruje od jedynki — czytelnik szukał reguły-widma. Teraz piszą wprost: wbudowana.
- **„Rejestr MP" stoi w menu bocznym obok pozostałych ekranów MP**, a nie na samym dole, pod
  ustawieniami WordPressa.

### Naprawione — dokumenty dla klienta
- **Instrukcje i diagramy mówią to, co produkt naprawdę robi** po powyższych naprawach: realny limit
  importu CSV (mniejsza z dwóch wartości — wtyczki i serwera; ekran zawsze pokazuje właściwą),
  panel koordynatora bez przycisków, które widzi wyłącznie administrator, aktualny numer telefonu na
  karcie sprawy, załączniki przy odinstalowaniu (znikają tylko za zgodą), raport końcowy wysyłany
  przy zamknięciu sprawy, własny status mogący kończyć sprawę, brak zmiany priorytetu z karty
  i brak maila do klienta przy samym przydziale.
- **Korekta językowa całego kompletu instrukcji** — format przykładowego numeru sprawy, nazwy
  rodzajów zgłoszeń zgodne z etykietami formularza, poprawiona odmiana i interpunkcja.
- **Dokumentacja techniczna** (kontrakt programistyczny, model zdarzeń, maszyna stanów, model
  bezpieczeństwa, własność danych) opisuje stan po tych naprawach — łącznie z granicami gwarancji,
  które kod egzekwuje, i tymi, których nie egzekwuje.

## [1.3.12] — 2026-08-04

### Naprawione — dane osobowe (wydanie 1.3.12, grupa 0) — żądanie usunięcia sięga głębiej
- 🔴 **Żądanie usunięcia danych obejmuje teraz „Powód zwrotu" i NAZWĘ PLIKU nadaną przez klienta.**
  Powód zwrotu to pole, w którym człowiek pisze własnymi słowami — potrafi tam trafić nazwisko,
  adres albo numer telefonu — a redakcja danych go pomijała. Osobno: kasowanie załącznika
  zostawiało w bazie **nazwę pliku**, a skany dowodów zakupu ludzie nazywają swoim imieniem
  i nazwiskiem. Jedno i drugie znika teraz razem z resztą danych.
- ⛔ **Poprawka obejmuje także zgłoszenia LEŻĄCE JUŻ W BAZIE**, nie tylko nowe. Bez tego kroku
  chroniłaby wyłącznie klientów, którzy zgłoszą się po aktualizacji.
- **Nowe pole tekstowe dokładane przez administratora jest domyślnie traktowane jako wrażliwe.**
  Wcześniej każde nowo dołożone pole z automatu wypadało z usuwania danych.

### Naprawione — bezpieczeństwo (wydanie 1.3.12, grupa 1)
- **Dobowego limitu zgłoszeń nie da się obejść „plus-adresowaniem".** Adresy w rodzaju
  `jan+1@poczta.pl` i `jan+2@poczta.pl` to ta sama skrzynka, a produkt liczył je jako różne
  osoby — wystarczyło dopisać znak plus, żeby wysyłać bez ograniczeń.

### Zmienione — terminy obsługi (wydanie 1.3.12, grupa 2)
- **Licznik terminu STOI, gdy sprawa czeka na klienta.** Dotąd zegar biegł także wtedy, gdy
  serwis nie mógł nic zrobić, bo czekał na zdjęcie albo odpowiedź — i sprawa robiła się
  „po terminie" z winy klienta. To standard branżowy, nie nasz wymysł.
- **Na liście spraw taka sprawa pokazuje napis „czeka na klienta"** zamiast pustego terminu.
  Puste miejsce miało w produkcie kilka różnych znaczeń i nie dało się ich odróżnić.
- **Reguła zmiany statusu działa tak, jak podpowiada ekran** — wcześniej podpowiedź i zachowanie
  rozjeżdżały się przy statusach dokładanych przez administratora.

### Naprawione — kontrakt programistyczny i bramki (wydanie 1.3.12, grupa 3)
- **Zwrotki niosą wersję kształtu danych w KAŻDEJ gałęzi zwrotu**, także tam, gdzie zwracana jest
  wartość pusta. Kto podpina się do produktu czwartym modułem, wie, z jakim kształtem rozmawia.
- **Tłumaczenia nie zostają wersję w tyle za wtyczką** — i pilnuje tego bramka, więc nie zdarzy się
  to po cichu przy kolejnym wydaniu.
- **Druga bramka dokumentów wykrywa, że któraś z jej własnych kontroli w ogóle nie wystartowała.**
  Kontrola, która cicho nie rusza, świeci na zielono i wygląda jak porządek.

### Naprawione — paczka i dokumenty dla klienta (wydanie 1.3.12, grupa 4)
- **Paczka zawiera plik licencji**, którego wcześniej w niej nie było, choć każdy `readme.txt`
  deklarował GPLv2 — to jeden z najczęstszych powodów odrzucenia wtyczki przez recenzentów.
- **Zniknęły martwe odsyłacze** do dokumentu, którego w paczce nie ma, **poprawione wersje plików
  tłumaczeń** oraz **nasze wewnętrzne ślady** (numery robocze i notatki z budowy), które nie
  powinny trafiać do klienta.
- **Instrukcje dla klienta, koordynatora i pracownika mówią to, co produkt naprawdę robi** po
  wszystkich powyższych naprawach — łącznie z ważnością linku potwierdzającego, obsługą powodów
  odrzucenia i ekranem ustawień.
- **Zrzuty ekranu w instrukcji pokazują formularz, który klient widzi dzisiaj**, a nie sprzed napraw.
- **Dokumentacja techniczna** (kontrakt, model zdarzeń, opis bazy, model bezpieczeństwa) opisuje
  stan po tych naprawach, a nie zamiar sprzed nich.
- **Raport z audytu mówi wprost, co zostało sprawdzone na działającym systemie, a co tylko od
  zaplecza** — razem z rzeczami, których ta runda nie objęła.

### Naprawione — odinstalowanie (wydanie 1.3.12, grupa 5)
- **Własne powody odrzucenia znikają przy odinstalowaniu ZA ZGODĄ, a bez zgody zostają.**
  Dotąd zachowywały się inaczej niż reszta konfiguracji, więc odinstalowanie zostawiało po
  produkcie ślad albo kasowało za dużo — zależnie od tego, czego administrator się spodziewał.

### Naprawione — dostęp ról (wydanie 1.3.12, grupa 1)
- **Koordynator serwisu przestaje mieć dostęp do MNIEJ ekranów niż podległy mu pracownik.**
  Role MP nie mają hierarchii (to projekt: kod sprawdza wyłącznie uprawnienia, nigdy nazwy roli),
  a ekran „Zgłoszenia niepotwierdzone" miał uprawnienie pracownika **wpisane na sztywno**, więc
  odbijał przełożonego osoby, która na nim pracuje. Dwa inne ekrany rozwiązały to samo poprawnie
  już wcześniej; **rozciągnęliśmy ten wzorzec**, zamiast dokładać uprawnienia rolom (to ruszyłoby
  wszystkie bramki naraz).
- **„Rejestr MP" znika koordynatorowi z menu — i to jest naprawa, nie odebranie dostępu.**
  Wcześniej widział tę pozycję, klikał i dostawał odmowę, nie wiedząc, czy to awaria, czy tak ma
  być. Menu i bramka ekranu pytają teraz o **tę samą listę uprawnień**, więc pozycji nie widzi ten,
  kogo ekran i tak nie wpuści. **Rejestr produktów zostaje przy pracowniku serwisu i administratorze
  systemu** — zgodnie z zamówieniem, w którym wyjątki gwarancyjne zatwierdza uprawniony
  administrator. Nikt nie stracił dostępu, który miał.
- Bramka „czy to personel" i wybór uprawnienia do menu są teraz **jedną funkcją we wspólnej
  bibliotece**, a nie kopią warunku w każdym ekranie z osobna.
- ⛔ **Granica naprawy pilnowana testem:** import i wyjątki gwarancyjne **zostają** za administratorem
  systemu — tak wymaga zamówienie („wyjątki zatwierdzane przez uprawnionego administratora").

### Naprawione — dane osobowe (wydanie 1.3.12, grupa 0)
- 🔴 **Żądanie usunięcia i żądanie wydania danych obejmuje ZGŁOSZENIA NIEPOTWIERDZONE.** Zgłoszenie,
  którego nikt nie potwierdził, nie ma rekordu klienta — a spis żądań RODO chodził wyłącznie po
  klientach. W takim zgłoszeniu leżą: adres, telefon, opis usterki i **załączone zdjęcia** osoby,
  która nigdy klientem nie została, i **nie było żadnej drogi**, żeby je usunąć przed upływem
  30 dni. Gorzej: procedura meldowała „usunięto", a przycisk w panelu klienta pisał wprost
  **„Twoje dane osobowe zostały usunięte"** — czyli produkt składał nieprawdziwe oświadczenie
  osobie, której dane dotyczą, w odpowiedzi na jej żądanie.
- Adres zgłaszającego stoi teraz w **indeksowanej kolumnie** (`pending_email`, migracja schematu 5)
  i **znika w chwili weryfikacji**, żeby nie zostawał jako druga kopia danych. Migracja uzupełnia
  go dla zgłoszeń **już leżących w bazie** — inaczej poprawka nie objęłaby nikogo, kto złożył
  zgłoszenie przed aktualizacją.
- Kasowanie zgłoszeń niepotwierdzonych ma **jeden mechanizm dla dwóch powodów**: upływu czasu
  (retencja) i żądania osoby. Wcześniej istniał tylko pierwszy.

### Naprawione — dane osobowe (wydanie 1.3.12, grupa 0) — konto klienta
- 🔴 **Adres e-mail klienta przestaje być widoczny publicznie.** Konto WordPressa zakładane przy
  potwierdzeniu zgłoszenia brało nazwę wyświetlaną z nazwiska, a gdy nazwiska nie było — z adresu
  e-mail. Formularz o nazwisko **nie pytał**, więc w normalnym torze zgłoszenia nazwa konta była
  adresem, a WordPress publikuje ją na stronie autora (jawnej i indeksowalnej). Teraz konto WP
  **z założenia nie nosi danych osobowych**: nazwa wyświetlana, login i człon adresu strony autora
  są neutralne (`Klient serwisu #N`, `mp-klient-N`), a imię i nazwisko żyje wyłącznie w tabeli
  klientów wtyczki, gdzie obsługuje je eraser RODO. Strona autora konta klienta dostaje `noindex`.
- 🔴 **Konta założone WCZEŚNIEJ są poprawiane jednorazowo** (migracja schematu 4). Bez tego kroku
  poprawka chroniłaby tylko nowych klientów: nazwa wyświetlana zapisywana jest **raz w życiu konta**
  i nic jej nigdy nie aktualizowało, więc osoby już ujawnione pozostałyby ujawnione. Kont personelu
  i administratora migracja nie tyka.
- **Formularz publiczny pyta o imię i nazwisko.** To korzeń obu powyższych wad i trzeciej:
  ochrona przed sklejeniem dwóch osób pod wspólną skrzynką (recepcja, sekretariat) wymagała dwóch
  niepustych nazwisk, więc **nigdy się nie włączała**. Teraz dwie osoby pod jednym adresem dostają
  osobne rekordy klienta, a ta sama osoba (inna pisownia) nadal jeden.
- **Brak zgody i brak imienia wracają do człowieka RAZEM**, jedna bramka zamiast dwóch — poprawianie
  formularza nie wymaga kolejnego okrążenia.

### Dowody
- Test przeglądarkowy `testy/e2e/c-tozsamosc-konta-klienta.sh` (w CI): 20 kontroli, w tym próby
  kontrolne detektora, odtworzenie stanu sprzed poprawki i sprawdzenie anonimowym żądaniem HTTP,
  że strona autora nie zdradza ani adresu, ani nazwiska.
- Testy jednostkowe `TozsamoscKlientaTest` (granica długości liczona w znakach, nie bajtach).

### Naprawione — sześć wad z kontroli na działającej instalacji (wydanie 1.3.12, grupa 6)

Ostatnia kontrola przed wydaniem polegała na obejrzeniu **działającego systemu oczami
użytkownika**, ekran po ekranie, zamiast czytania kodu. Wykryła sześć rzeczy, których nie było
na liście audytu. Wszystkie zamknięte w tym wydaniu.

- 🔴 **Pracownik serwisu docierał do spraw spoza swojego przydziału — razem z danymi klienta.**
  Lista pokazywała mu wyłącznie jego sprawy, ale **karta sprawy otwierała się po samym numerze
  w adresie**. Ta sama luka pozwalała **zmienić cudzą sprawę**: status, odpowiedź wysyłaną do
  klienta, notatkę. Karta i każde działanie na niej pytają teraz o prawo do **tej konkretnej
  sprawy**, dokładnie tak jak lista. Przydzielanie spraw zostaje u koordynatora i administratora,
  zgodnie z zamówieniem.
  ⚠️ **Wada jest obecna w 1.3.11 i wcześniejszych** — kto ma którąś z nich postawioną, zamyka
  ją samą aktualizacją; nic poza tym nie jest potrzebne.
- **Zbyt duży załącznik kończył się pustą białą stroną** — zgłaszający nie wiedział, czy wysłał,
  a wpisane dane znikały. Teraz dostaje czytelny komunikat i wraca na formularz.
- **Przekroczenie dobowego limitu zgłoszeń czyściło cały formularz** — opis usterki i załącznik
  trzeba było wpisywać od nowa. Wartości zostają, a komunikat mówi, **kiedy** będzie można
  wysłać ponownie.
- **Treść z adresu strony trafiała na ekran jako komunikat panelu.** Spreparowanym odnośnikiem
  dało się pokazać na prawdziwej stronie serwisu dowolne zdanie — np. o odrzuceniu sprawy
  i numerze premium. Skryptu uruchomić się nie dało; ciężar polegał na wiarygodności, jakiej
  taki odnośnik użyczał od domeny serwisu. Ekran przyjmuje teraz **wyłącznie znane komunikaty**.
- **Koordynator widział w menu pozycję, która go nie wpuszczała.** Jest ukryta temu, kto nie ma
  do niej prawa, zamiast otwierać drzwi i odsyłać z kwitkiem.
- **Ekrany ustawień i Rejestru rozjeżdżały się na wąskim oknie** — z tabeli statusów widać było
  jedną kolumnę. Tabele **przewijają się** w swoim obszarze (z zaczepem klawiatury) i mieszczą
  się na telefonie i na monitorze. ⛔ Nie schowaliśmy kolumn: schowanie dałoby w pomiarze
  identyczny wynik co poprawne przewijanie, a kasowałoby kolumny na zawsze.

### Dowody — sześć wad
- Kontrola prowadzona na **żywej instalacji pod adresem, którym wchodzi klient**, nie przez
  `localhost`, i w tempie człowieka — formularz ma pułapkę czasową, więc automat klikający
  natychmiast mierzy tę pułapkę, a nie produkt.
- Naprawa dostępu do spraw sprawdzona **w obie strony**: przed poprawką wszystkie cztery próby
  (odczyt karty, zmiana statusu, wysyłka maila do cudzego klienta, notatka) przechodziły;
  po poprawce „Sprawa niedostępna" i trzykrotna odmowa, żaden mail nie wyszedł — a **własną
  sprawę** pracownik obsługuje bez zmian i koordynator robi wszystko, co robił.
- Testy przeglądarkowe układu tabel (w CI) mierzą także, czy tabela jest **dostępna, a nie tylko
  schowana**, i kończą się „pomiar nieważny" tam, gdzie ekran nie ma danych do pokazania.

### Naprawione — cztery rzeczy z ostatniego przeglądu ekranów personelu (wydanie 1.3.12, grupa 7, #273)

Ostatnia kontrola przed wysyłką przeszła jeszcze raz przez ekrany personelu na działającej
instalacji. Trzy z tych napraw pilnuje test w CI (`testy/e2e/c-wyglad-rejestr-zdarzen.sh`):

- **Rejestr zdarzeń automatyzacji mówi, której sprawy dotyczy wpis.** Wcześniej osiemnaście
  z dwudziestu wpisów pokazywało wewnętrzny numer wiersza bazy zamiast numeru sprawy —
  człowiek nie wiedział, co czyta.
- **Kolumna „Szczegóły" w rejestrze zdarzeń jest po ludzku.** Wcześniej pokazywała surowy
  zapis techniczny, przycięty w połowie słowa — wyglądał jak uszkodzone dane, a nie jak skrót.
- **Przycisk „Wyślij ponownie" na liście zgłoszeń niepotwierdzonych przestał być niewidzialny.**
  Przy typowym oknie stał poza ekranem we wszystkich wierszach; dojechać przewinięciem się dało,
  ale nic nie sygnalizowało, że dalej cokolwiek jest. Krawędź tabeli pokazuje teraz cień
  przewijania — wyłącznie wtedy, gdy rzeczywiście jest co przewijać.
- **Podsumowanie importu przestało samo sobie przeczyć** — ten sam import potrafił pokazać
  naraz „8 / 8 wierszy" i „8 błędów", bo nagłówek obiecywał wynik, a kolumna liczyła postęp.
  Tabela pokazuje teraz „Zaimportowane / wszystkie", czyli zdanie prawdziwe na każdym etapie.

### Naprawione — dostępność (WCAG 2.1 AA)
- **Błąd formularza prowadzi do konkretnego pola.** Podsumowanie błędów jest listą odnośników,
  a pole z błędem dostaje `aria-invalid`; komunikat i pole są spięte `aria-describedby`. Dotąd
  osoba z czytnikiem ekranu słyszała, że coś jest nie tak, ale nie dowiadywała się, **co**.
- **Wysyłka zgłoszenia ogłasza, że trwa** — formularz dostaje `aria-busy`, przycisk zmienia napis
  i blokuje powtórne kliknięcie. ⛔ Kontrolki **nie wyłączamy** przez `disabled`: wyłączona wypada
  z przesyłanych danych, a część przeglądarek przerywa przez to samą wysyłkę.
- **Ekran importu CSV ogłasza postęp, zakończenie i błąd także czytnikowi ekranu** (`role="status"`
  dla postępu, komunikat błędu asertywnie). Dotąd pasek postępu zmieniał się w ciszy.
- **Dwa ekrany personelu mieszczą się w oknie przy powiększeniu 200%** na szerokości typowego
  monitora: panel automatyzacji i „Zgłoszenia niepotwierdzone" (dotąd wychodziły poza okno o 184
  i 165 pikseli przy 1280 px). ⚠️ **Część zarzutu zostaje otwarta** — patrz pomiar niżej.
- **Pole listy powodów odrzucenia na ekranie „Ustawienia zgłoszeń" dostało nazwę dla czytnika
  ekranu.** Naruszenie reguły `label` (waga krytyczna): pole nie miało ani `id`, ani etykiety
  spiętej z kontrolką, więc czytnik czytał je jako pole bez nazwy — nagłówek i opis nad nim są
  wyłącznie wizualne. **Znalezione własnym pomiarem na tym wydaniu**, wyszło dopiero dzięki
  rozszerzeniu narzędzia na ekrany personelu. Zmiana obejmuje jedną linię, zachowanie bez zmian.
- **Narzędzie badające dostępność sięga ekranów personelu i drukuje zakres badania.** Zawężenie
  siedziało w samym przyrządzie: badał wyłącznie trzy powierzchnie klienta, więc każde wydanie
  wychodziło „zielone", opisując część systemu i nie mówiąc, że to część.

### Dowody — dostępność
- **Badanie axe-core powtórzone na wydaniu 1.3.12**, na czystej instalacji postawionej z paczki dla
  klienta (WordPress 6.9 / PHP 8.1 / MySQL 8), po HTTPS-owej ścieżce klienta z odczytem poczty.
  Zbadane **11 powierzchni, zero pominiętych**: trzy ekrany klienta i osiem ekranów personelu.
  - **Trzy ekrany klienta: zero naruszeń** (13, 7 i 7 zdanych reguł). Poprzednie badanie
    (1.3.6) też dawało zero, ale nie obejmowało zmian z tego wydania.
  - **Osiem ekranów personelu: zero naruszeń.**
  - Pierwszy przebieg (przed naprawą) pokazał **jedno naruszenie** — regułę `label` na ekranie
    „Ustawienia zgłoszeń". Poprawka opisana wyżej weszła w tym samym wydaniu, a **przebieg po niej
    kończy się wynikiem „zero naruszeń w naszych powierzchniach"** i kodem powodzenia. Oba wydruki,
    sprzed i po, zostają w repozytorium — żeby dało się je porównać, a nie tylko uwierzyć.
    Ekran „Ustawienia zgłoszeń" ma po naprawie 10 zdanych reguł zamiast 5: brakująca etykieta
    sprawiała, że część reguł nie miała czego badać.
  - Naruszenie w bloku nawigacji motywu WordPressa występuje na stronach publicznych i **nie
    pochodzi z naszego kodu** — tak samo jak w poprzednim badaniu.
- **Pomiar mieszczenia się w oknie przy powiększeniu** (`testy/a11y/zoom200-panel.py`, z próbą
  kontrolną na sąsiednim ekranie):
  - **„Zgłoszenia niepotwierdzone" — czysto.** Nigdzie nie wychodzi poza okno tam, gdzie próba
    kontrolna się mieści. ⚠️ Ten ekran **nie był wcześniej mierzony w ogóle** — narzędzie zna
    tylko panel automatyzacji, więc zmierzyliśmy go osobno, tą samą metodą.
  - 🔴 **Panel automatyzacji — otwarte.** Przy 1280 px i 200% zero nadmiaru, ale przy 768 px
    z powiększeniem 200% nadmiar **167 px**, a przy 390 px bez powiększenia **78 px** — w obu
    punktach próba kontrolna ma zero, więc to wada tego ekranu, nie stanowiska. **Pozycja 2.6
    jest zamknięta w części, nie w całości**, i tak stoi też w raporcie dla klienta.
  - ⚠️ Osobno: przy 1024 px i 200% poza okno wychodzą **wszystkie** mierzone ekrany, łącznie
    z próbą kontrolną — to szersza sprawa układu panelu, nie tej pozycji.
- Surowe wydruki obu przebiegów leżą w repozytorium: `audyt/pomiary-a11y-1312/` (katalog `audyt/`
  nie wchodzi do paczki dla klienta — jest dla osoby, która chce zweryfikować te liczby).

## [1.3.11] - 2026-08-01

> Zgloszone przez zamawiajacego przy klikaniu po panelu — **nie znalazla tego zadna kontrola
> automatyczna**. Ekran spelnial wymog specyfikacji (S-10) i dlatego przeszedl kontrole zgodnosci;
> zawodzil dopiero wtedy, gdy ktos wszedl na niego pierwszy raz i nie wiedzial, co dalej.

### Naprawione
- **Ekran „Wyjatki gwarancyjne" otwarty z menu byl slepym zaulkiem.** Bez wybranego produktu
  pokazywal wylacznie zdanie „wybierz produkt z listy Rejestru MP" — uzytkownik wiedzial, ze ma
  isc gdzie indziej, ale musial sam szukac tego miejsca. Teraz ekran: (1) tlumaczy, czym jest
  wyjatek gwarancyjny, (2) wyjasnia, dlaczego jest pusty (wyjatek nadaje sie zawsze dla
  konkretnego produktu), (3) daje przycisk **„Przejdz do Rejestru MP"**.

### Uwagi
- Sprawdzono pozostale ekrany panelu pod katem tej samej klasy bledu — **to bylo jedyne miejsce
  bez wyjscia**; karta sprawy i ekran poprawiania produktu maja odnosniki powrotne.
- Docelowe rozwiazanie (lista wszystkich aktywnych wyjatkow na tym ekranie) zostaje w planie 1.4
  — swiadomie nie dokladamy nowej funkcji w dniu przekazania.

## [1.3.10] - 2026-07-31

> Wydanie **jezykowe**: dzialanie wtyczek bez zmian. Znalezione przy KALIBRACJI audytora —
> podlozone bledy mialy sprawdzic czulosc kontroli, a kontrole przy okazji wykryly trzy prawdziwe
> usterki jezyka tej samej klasy, ktora naprawialo wydanie 1.3.8. Dowod, ze tamta naprawa objela
> CZESC miejsc, nie wszystkie.

### Naprawione
- **Komunikaty kazaly nadac role „Pracownik serwisu", a na liscie rol jest „Pracownik serwisu MP".**
  Dwa miejsca (`CaseCard.php`, `PanelScreen.php`); trzecie, w Stanie witryny, cytowalo poprawnie
  — system przeczyl sam sobie. Administrator szukajacy dokladnie cytowanej nazwy jej nie widzial.
- **Przycisk w Rejestrze zdarzen pokazywal nazwe stalej z kodu**: „Pokaz techniczne (SWEEP_RUN)".
  Teraz: „Pokaz wpisy automatycznego przegladu". Nazwy stalych sa dla programisty, nie dla serwisanta.
- **Naglowek kolumny „Terminalny"** (zargon maszyn stanow, obok zwyklych „Status" i „Etykieta")
  zamieniony na **„Konczy sprawe"**.

### Zmienione
- **Bramka nazw rol obejmuje teraz takze napisy w kodzie, nie tylko dokumenty.** Kontrola powstala
  29.07 patrzyla wylacznie na `dla-klienta/*.md`, wiec poprawka dokumentow przeszla, a te same
  bledne cytaty zostaly w PHP i dozyly do dzis. Dolozona tez kontrola wykrywajaca surowe nazwy
  stalych w napisach dla uzytkownika. **Obie skalibrowane podlozonymi bledami — obie je zlapaly.**
- Zrzut ekranu panelu automatyzacji przerenderowany (pokazywal stare napisy).

## [1.3.9] - 2026-07-31

> Wydanie **dokumentacyjne**: dzialanie wtyczek bez zmian. Powstalo z audytu koncowego przed
> oddaniem — szesc niezaleznych kontroli (zgodnosc ze zrodlem, klikanie na zywej stronie, paczka
> i repozytorium, bezpieczenstwo, kompletnosc, czytelnik nietechniczny) plus kalibracja audytora
> podlozonymi bledami.

### Dodane
- **Instrukcja wdrozenia: krok „schowaj formularz na czas przygotowan" (§4).** Strona zgloszenia
  jest publiczna od chwili wlaczenia wtyczki, a instrukcja nie mowila, jak ja tymczasowo ukryc.
  Klient mogl zebrac zgloszenia, zanim rejestr gwarancji i pula pracownikow byly gotowe — sprawa
  utknelaby bez rozpoznanej gwarancji i bez przydzialu. Opisane jako cztery kliki, z zapewnieniem,
  ze wtyczka nie utworzy drugiej strony (kod pomija odtworzenie, gdy strona istnieje jako szkic).

### Naprawione
- **README podawal dwie rozne liczby testow diagnostyki w tym samym pliku** — „czternascie" w §3
  i „42 testy" w sekcji o jakosci. Prawidlowa liczba to **14** (9 Intake + 2 Registry + 3 Automator,
  policzone w kodzie). Liczba 42 byla pomylona z liczba kontroli bramki dokumentow.
- **Bramka `testy/dokumenty/liczby-zgodne-z-kodem.sh` sprawdzala ISTNIENIE poprawnej liczby, nie jej
  SPOJNOSC.** Jedno trafienie w pliku wystarczalo do zaliczenia, wiec poprawna liczba w jednym
  akapicie maskowala bledna w drugim — dlatego blad wyzej przechodzil przez CI. Dodana kontrola
  `sprawdz_bez_sprzecznych`, skalibrowana podlozonym bledem (zlapala go, exit 1).

### Uwagi
- Kontrola spojnosci celowo obejmuje **tylko liczbe testow diagnostyki**, a nie kazda liczbe
  w dokumentach: ta sama liczba potrafi poprawnie znaczyc co innego w dwoch akapitach (DATABASE.md
  cytuje „4 tabele" ze specyfikacji klienta, a system ma ich 16 — obie liczby sa prawdziwe).
  Uniwersalna bramka dawalaby falszywe alarmy i zostalaby wylaczona.

## [1.3.8] - 2026-07-31

### Zmienione (jezyk ekranow)
- **Naglowek kolumny „Job" na ekranie importu zamieniony na „Import".** Bylo to jedyne angielskie
  slowo posrod polskich naglowkow tej samej tabeli („Status", „Wiersze", „Bledy").
- **Komunikaty bledow importu przestaly mowic „job".** „Job importu nie istnieje" → „Ten import nie
  istnieje"; „Nie mozna wznowic: job nie istnieje…" → „…ten import nie istnieje…". Te komunikaty
  widzi pracownik, gdy import sie przerwie.
- **„Niepelne dane batcha" → „Niepelne dane porcji importu"** — ta sama wtyczka w innym miejscu
  uzywa polskiego slowa „Partia" na to samo pojecie.
- **Lista markerow szablonow podpisana „(lista dozwolonych)" zamiast „(whitelist)".**
- **Przycisk „Przelicz SLA" → „Przelicz terminy obslugi"**, a testy Stanu witryny mowia
  „Terminy obslugi zgloszen (SLA)" — skrot jest rozwiniety przy pierwszym uzyciu.
- **Godziny w czasie UTC opisane po ludzku.** Kolumny „Utworzony (UTC)" i „Wazny do (UTC)" stracily
  techniczny dopisek, a pod tabelami stoi zdanie: czas uniwersalny, w Polsce zegar jest o 1 godzine
  (zima) lub 2 godziny (latem) do przodu.

### Poprawione (materialy dla klienta)
- **Zdjecie wyjatkow gwarancyjnych pokazywalo PUSTY ekran** z podpowiedzia „Wybierz produkt",
  wklejone pod opisem dzialajacej funkcji. Przyczyna siedziala w narzedziu generujacym zdjecia:
  wchodzilo na ekran wyjatkow bez wskazania produktu, wiec blad wracalby przy kazdym odswiezeniu.
  Narzedzie wchodzi teraz tak jak administrator — z listy produktow, odnosnikiem „wyjatki" — i wybiera
  produkt, ktory JUZ MA wyjatek, zeby zdjecie pokazywalo tresc.
- **Instrukcja administratora podawala droge prowadzaca do tego pustego ekranu.** Teraz opisuje
  wlasciwa (Rejestr MP → produkt → kolumna Akcje → „wyjatki") i tlumaczy, czemu pozycja w menu
  bocznym pokazuje sama podpowiedz.
- **Nazwy w instrukcjach niezgodne z panelem:** filtr „Przydzielony: ja" → **„Moje sprawy"**,
  „Rejestr MP → Import" → **„Import CSV"** (2 miejsca).
- **Instrukcja glowna nie pokazywala zapisu pol podstawianych** w szablonach odpowiedzi. Doszedl
  przyklad `{{numer_sprawy}}` z wyjasnieniem, gdzie znalezc pelna liste i co sie dzieje z polem
  spoza niej.
- Odswiezone zdjecia w instrukcji administratora: import produktow, automatyzacje, wyjatki gwarancyjne.

## [1.3.7] - 2026-07-31

### Zmienione (dokumentacja)
- **Raport dostepnosci (WCAG 2.1 AA) zostal powtorzony na wydanej wersji.** Dotad badanie
  pochodzilo z paczki **1.3.0** i dokument mowil to wprost, zamiast podmieniac numer w naglowku.
  Badanie powtorzono **31.07 na paczce 1.3.6 pobranej z wydania**, w prawdziwej przegladarce,
  po HTTPS, na **WordPressie 7.0 / PHP 8.2 / MariaDB 11.8** i na innym motywie niz za pierwszym
  razem. **Wynik ten sam: zero naruszen na wszystkich trzech ekranach klienta** (formularz
  zgloszenia, panel przed zalogowaniem i po zalogowaniu).
- **Raport pokazuje teraz oba badania obok siebie** — z wersjami, srodowiskiem i motywem kazdego
  z nich. Czesc wyniku liczona dla calej strony razem z motywem rozni sie miedzy badaniami, bo
  zalezy od motywu, a nie od naszych wtyczek: na motywie demonstracyjnym wyszlo zero naruszen,
  na domyslnym Twenty Twenty-Five jedno, w bloku nawigacji WordPressa.
- Dopisane wyjasnienie, czym jest „regul zdanych", zeby liczba w tabeli nie byla brana za ocene.

**W kodzie wtyczek nie zmieniono ani jednej linii** — podbite wylacznie numery wersji (9 miejsc).

## [1.3.6] - 2026-07-30

### Zmienione (dokumentacja)
- **Slowa, ktorych czytelnik nie musi znac, sa teraz wyjasnione.** Do slowniczka doszly **SLA**,
  **link do zalogowania (magic-link)** i **anonimizacja**; skrot SLA jest tez rozwiniety przy
  pierwszym uzyciu w instrukcjach **pracownika** i **koordynatora** (te dokumenty czyta sie
  osobno, bez slowniczka z instrukcji glownej).
- **RODO: instrukcja mowi wprost, co znika przy anonimizacji, a co zostaje** — zamiast ogolnego
  „dane osobowe znikaja". Wymienione pola zgodne z tym, co robi kod.
- **„Blokada integralnosci" wyjasniona po ludzku** — dlaczego produktu z aktywna sprawa nie da
  sie usunac.
- **§7.1 (SMTP) przestal byc sprzeczny z naglowkiem rozdzialu 7.** Rozdzial jest oznaczony jako
  „nie do samodzielnego wykonania", a ten podpunkt kazal dzialac samemu. Teraz jest zaznaczone,
  ze akurat ten krok robi sie w panelu, i doszla **gotowa tresc wiadomosci do dostawcy poczty**
  (trzecia taka, obok dwoch do hostingu).

### Poprawione
- **Zdjecie pustego formularza pokazywalo date po amerykansku** (`mm/dd/yyyy`), podczas gdy
  sasiednie zdjecie tego samego formularza pokazywalo `14.03.2026`. Zrzut powstal bez wymuszonego
  jezyka przegladarki. Klient w polskiej przegladarce widzi format polski — zdjecie zostalo
  zrobione ponownie.
- **Brakowalo wpisu dla wydania 1.3.5** — jego tresc lezala w „Unreleased", wiec CHANGELOG
  sugerowal, ze ostatnim wydaniem jest 1.3.4.

## [1.3.5] - 2026-07-30

### Poprawione
- **Lista spraw pobiera terminy SLA jednym zapytaniem.** Kolumna terminu pytala o kazdy wiersz
  osobno; razem z poprzednia poprawka ekran „MP: Sprawy" zszedl z **43 do 4 zapytan**.
  Modul automatyzacji wystawia na to nowy, hurtowy punkt kontraktu — **stary zostaje nietkniety**,
  wiec karta pojedynczej sprawy i starsze wersje modulu dzialaja bez zmian.
- **Lista spraw i lista produktow robily nadmiarowe zapytania do bazy (N+1).** Ekran „MP: Sprawy"
  dowolywal sie opisu zgloszenia osobno dla kazdego wiersza (20 zapytan na strone), a „Rejestr MP"
  tak samo sprawdzal wyjatki gwarancyjne. Teraz oba pobieraja te dane **jednym zapytaniem na cala
  strone**: lista spraw **43 → 23 zapytania**, rejestr **64 → 45**. Zachowanie ekranow bez zmian —
  opisy i plakietka „wyjatek" wyswietlaja sie jak dotad.

### Zmienione (dokumentacja)
- **Instrukcja podawala nazwe ekranu, ktorej nie ma w menu.** Bylo „Zgloszenia / sprawy", jest
  **„MP: Sprawy"** — plus dopisany brakujacy ekran **„MP: Niepotwierdzone"**, ktory administrator
  widzi w menu, a instrukcja go nie opisywala.
- W tabeli wtyczek doszla kolumna **„Nazwa na liscie wtyczek"** (nazwy techniczne sa po angielsku,
  instrukcja uzywa polskich — teraz widac, co czemu odpowiada).
- `MIGRATION_POLICY.md`: przy poleceniu kopii **tylko tabel MP** dopisane ostrzezenie, ze przy
  PIERWSZEJ instalacji tych tabel jeszcze nie ma i polecenie zwroci blad — wtedy uzywa sie
  pelnego eksportu.
- Doprecyzowane dwa zdania: terminy SLA „licza sie same" (zamiast „dzialaja od razu" — pierwszy
  wpis powstaje przy najblizszym przebiegu zadania cyklicznego) oraz uzasadnienie ograniczenia
  eksportu CSV (zestawienie opisuje prace nad sprawami; nie zawiera danych kontaktowych klientow).
- `DATABASE.md`: test wspolbieznosci licznika numerow **zostal wykonany** (20 rownoleglych procesow,
  20 unikalnych numerow, zero duplikatow) — wczesniejsze zdanie „testu NIE MA" bylo nieaktualne.

## [1.3.4] - 2026-07-30

### Poprawione
- **Dwa zdania w dokumentacji technicznej opisywaly zabezpieczenia szerzej, niz robi to kod.**
  `API-KONTRAKT.md` mowil, ze z przykladowych danych **generowane sa** mocki i testy kontraktowe —
  w rzeczywistosci testy sa pisane recznie na podstawie tych przykladow i zadnego generatora nie ma.
  `DATABASE.md` powolywal sie na test wspolbieznosci na **20 rownoleglych procesach i 1000 numerach**
  — taki test nie istnieje; realny sprawdzian to 6 rownoleglych zadan (`testy/e2e/c21-dedup-wyscig.sh`),
  a atomowosc samego przydzialu numeru sprawy opiera sie na gwarancji bazy danych, nie na naszym
  tescie obciazeniowym. Oba zdania opisuja teraz stan faktyczny i wskazuja testy, ktore naprawde chodza.
- Dokumentacja, ktora **obiecuje wiecej niz kod**, jest grozniejsza od jej braku: informatyk klienta
  planuje prace, ufajac opisowi. Poprawka weszla na `main` godzine PO wydaniu 1.3.3, wiec **paczka
  1.3.3 miala jeszcze stara tresc** — to wydanie ja domyka.

**Zero zmian w kodzie wtyczek.** Numery wersji podniesione w calym pakiecie, zeby paczka
i repozytorium mowily jednym glosem.

## [1.3.3] - 2026-07-30

### Poprawione
- **Dokument `JAKOSC-I-AUDYTY.md` deklarowal wersje 1.3.1, gdy paczka miala 1.3.2.** Blad w jednej
  linii, ale w dokumencie, ktory opisuje wlasnie kontrole jakosci.
- **Wazniejsze: bramka kontrolujaca wersje w dokumentach miala dziure.** Lista sprawdzanych plikow
  byla wpisana na sztywno (dwa dokumenty z nazwy), wiec nowy dokument dolozony do paczki nie byl
  kontrolowany wcale. **To dokladnie ta klasa bledu, ktorej ta bramka miala pilnowac.**
  Teraz kontrola przechodzi WSZYSTKIE dokumenty dla klienta (`dla-klienta/*.md` oraz
  `dokumentacja-techniczna/*.md`) i **liczy, ile plikow objela** — kontrola, ktora cicho nie
  objelaby niczego, wywala budowanie paczki.
  Skalibrowana podlozonym bledem: dokument z wersja 1.2.9 przy paczce 1.3.2 zostal zatrzymany.

Zero zmian w kodzie wtyczek.

## [1.3.2] - 2026-07-30

Efekt dwóch soczewek kontroli użytych po raz pierwszy: **czytania kodu linia po linii** (parser
i importer CSV, silnik reguł, cały JavaScript) oraz **oceny instrukcji przez czytelnika
nietechnicznego**. Poprzednie audyty tych rzeczy nie widziały, bo szukały wzorcami zamiast czytać
całość.

### Poprawione — przyjmowanie plików CSV
- **Wiersz z niepełną liczbą kolumn wchodził do bazy z uciętymi danymi.** Brakujące kolumny stawały
  się cichymi pustymi wartościami, nieodróżnialnymi od pól celowo pustych — produkt trafiał do
  rejestru **bez daty zakupu i gwarancji**, a system liczył potem klientowi status gwarancji
  z niepełnych danych. Teraz taki wiersz idzie do raportu błędów z podaniem brakujących kolumn.
- **Jeden nieprawidłowy bajt niszczył polskie znaki w całym pliku.** Sprawdzenie kodowania
  obejmowało plik jako całość, więc pojedynczy znak wklejony np. z Worda kierował **cały** plik do
  konwersji z Windows-1250 i zamieniał poprawne polskie znaki w krzaki, bez ostrzeżenia. Teraz
  decyduje proporcja poprawnych sekwencji: plik uszkodzony jest czyszczony, a plik z polskiego
  Excela nadal konwertowany jak dotąd.
- **Komórka z Enterem w cudzysłowach rozjeżdżała wiersz.** Plik był dzielony na linie przed
  parsowaniem, więc wieloliniowa wartość stawała się dwoma „wierszami": kolumny przesuwały się,
  licznik postępu był zawyżony, a dane trafiały w złe pola bez żadnego błędu. Rekordy wydziela
  teraz czytnik rozumiejący cudzysłowy.
- **Raport błędów rozjeżdżał kolumny**, gdy numer seryjny zawierał średnik — wartości są cytowane
  zgodnie z regułami CSV.
- **Raport błędów mógł przepaść przy awarii** w wąskim okienku po zatwierdzeniu partii; zapis
  raportu wykonuje się teraz przed zatwierdzeniem.

### Poprawione — automat i panel
- **Reguła wykonana po zmianie statusu widziała stary stan sprawy.** Dane sprawy pobierane były raz
  przed przetwarzaniem reguł, więc kolejna reguła (np. powiadomienie mailowe) mogła wysłać do
  klienta wiadomość o statusie, którego sprawa już nie miała. Dane są odświeżane po zmianie.
- **Dwa szybkie kliknięcia „Wznów" osierocały jeden import.** Zadanie było rezerwowane na serwerze,
  ale pętla ruszała tylko dla jednego. Przyciski są blokowane na czas operacji.

### Instrukcje — po ocenie czytelnika nietechnicznego (62/100 przed poprawkami)
- **Rozdział o konfiguracji serwera zaczyna się ostrzeżeniem, że nie jest do samodzielnego
  wykonania**, z gotową treścią wiadomości do pomocy technicznej hostingu. Wcześniej instrukcja
  podawała fragmenty kodu bez informacji, kto ma je wprowadzić — a pominięcie zadania cyklicznego
  zatrzymuje pilnowanie terminów w nocy, choć system wygląda na sprawny.
- **Nowy rozdział „Gdy coś nie działa — do kogo się zwrócić"** z podziałem na hosting, osobę
  wdrażającą i utrzymanie systemu, oraz miejscem na wpisanie kontaktu.
- **Słowniczek dziesięciu pojęć** używanych dalej w instrukcji.
- **Powiedziane wprost, że trzeba mieć już działającą stronę na WordPressie**, jak sprawdzić
  wymagania hostingu (z gotowym pytaniem) i co zrobić, gdy nie są spełnione.
- Szacowany czas wdrożenia, informacja, że dokument polityki kopii jest dla osoby technicznej,
  oraz dwa nowe wpisy w tabeli najczęstszych kłopotów.

### Testy
Trzy nowe testy jednostkowe pilnujące, żeby naprawione klasy błędów nie wróciły: wiersz urwany,
plik UTF-8 z uszkodzonym bajtem, plik z polskiego Excela. Razem **155 testów, 456 sprawdzeń**.

## [1.3.1] - 2026-07-29

### Poprawione
- **Opcja alarmu poczty zostawała w bazie po odinstalowaniu wtyczki.** `mp-service-intake`
  zapisywał `mp_intake_mail_alert` (flaga awarii wysyłki, czytana przez Stan witryny), ale
  `uninstall.php` jej nie kasował — po pełnym odinstalowaniu opcja zostawała osierocona
  w `wp_options`. Bliźniacza opcja w `mp-workflow-automator` była kasowana poprawnie, czyli
  ten sam wzorzec naprawiono wcześniej tylko w jednym egzemplarzu. `OWNERSHIP.md` obiecuje
  „warstwa (i) ZAWSZE — opcje techniczne" i teraz kod tę obietnicę spełnia.
- **Komentarz w `SlaConfig` obiecywał funkcję, której nie ma.** Twierdził, że godziny SLA
  siedmiu statusów rdzenia są „admin-edytowalne w panelu" — takiego ekranu nie ma. Opis
  poprawiony na stan faktyczny: rdzeń zmienia się kodem/WP-CLI, a godziny statusów **własnych**
  są edytowalne w panelu (i to właśnie wymaga zamówienie: „konfigurowalne statusy").

Znalezione audytem kompletności (soczewka „czy coś czegoś nie robi"). Zero zmian w logice
biznesowej i w interfejsie — raport dostępności z 1.3.0 obowiązuje bez zmian.

## [1.3.0] - 2026-07-29

### Narzędzia kontrolne i dokumenty (bez zmian w kodzie wtyczek)

### Poprawione
- **Audyt dostępności badał stronę główną zamiast naszych ekranów.** `testy/a11y/audyt-axe.py`
  miał zaszyte adresy `/zgloszenie/` i `/moje-sprawy/` — takie strony istniały tylko na ręcznie
  ustawionym środowisku deweloperskim. Na instalacji **z paczki** wtyczka zakłada
  `zgloszenie-serwisowe` i `panel-zgloszen`, a oba stare adresy oddają **stronę główną z kodem
  200**. Skrypt nie sprawdzał, czy widzi to, co ma badać, więc axe badał nagłówek motywu
  i meldował zero naruszeń — bramka świeciła na zielono, nie startując.
  Teraz adresy **pobieramy z samej witryny** (REST `?rest_route=`, po slugu — działa też przy
  „prostych" odnośnikach `?page_id=N`), a przed badaniem sprawdzamy obecność formularza i pola
  logowania: brak = błąd, nie cichy sukces. Ręczne wskazanie: `MP_URL_FORMULARZ` / `MP_URL_PANEL`.
- Ten sam zaszyty adres siedział w teście zgodności przeglądarek
  (`testy/przegladarki/sciezka-klienta-w-przegladarkach.py`) — poprawiony tak samo. Tam skutek był
  łagodniejszy: test ma twarde asercje, więc na stronie głównej po prostu nie przechodził.

### Zmienione
- Audyt dostępności liczy teraz **osobno naszą część strony i całą stronę z motywem**. O kodzie
  wyjścia decyduje tylko nasza część — za motyw, którego nie dostarczamy, nie odpowiadamy —
  ale naruszenia motywu są wypisywane z dopiskiem `[motyw]`, bo klient i tak je u siebie zobaczy.
- `dla-klienta/RAPORT-A11Y-WCAG.md` przebadany na nowo **na wersji 1.3.0**, na instalacji
  postawionej z paczki na czystym WP 6.9 / PHP 8.1 / MySQL 8. Nasze ekrany: **0 naruszeń**
  (12 / 7 / 7 reguł zdanych). Cała strona z domyślnym motywem Twenty Twenty-Five 1.4:
  **1 naruszenie** reguły `list` w bloku nawigacji WordPressa (nagłówek motywu, nie nasz kod —
  wtyczki nie tworzą na stronie żadnej nawigacji). Poprzednie liczby (20/15/16 reguł, 0 naruszeń)
  pochodziły z pomiaru na nieistniejącym już środowisku i nie dało się ich odtworzyć.
- **Raport kazał uruchomić narzędzie, którego paczka nie zawierała.** Odsyłał do
  `testy/a11y/audyt-axe.py`, a katalogu `testy/` w paczce nie ma wcale — to było jedyne
  polecenie w całej paczce wskazujące poza nią. Skrypt trafia teraz do
  `dla-informatyka/audyt-dostepnosci/`, a bramka pakowania pilnuje dwóch rzeczy: że plik
  w paczce **jest** i że **żaden dokument** nie każe uruchamiać niczego ze ścieżki `testy/`.
  Obie kontrole skalibrowane podłożonym błędem. Kontrola śladów wewnętrznych objęła też
  pliki `*.py` (skoro `.py` idzie do klienta) — i od razu złapała nazwę serwera poczty
  w komentarzach.
- Trzeci badany ekran (panel po zalogowaniu) wymaga linku z maila, czyli dostępu do skrzynki,
  którego klient u siebie nie ma. Brak `MP_MAILPIT` = ekran **pominięty z komunikatem**,
  nie błąd. `MP_BASE` straciło wartość domyślną — wskazywała nieistniejące środowisko,
  a w paczce u klienta byłaby po prostu fałszem.
- `MP_PACZKA` ze ścieżką **względną** (tak brzmią nasze notatki) kończyło się `BLAD: nie ma
  pliku` — skrypt robi `cd` do własnego katalogu. Ścieżkę rozwijamy teraz przed zmianą katalogu.
- Dane testowe: `przyklad.pl` → `example.com` (RFC 2606). `przyklad.pl` wygląda na przykładową,
  a jest prawdziwą, cudzą domeną.

### Kod wtyczek

### Zmienione
- **Eksport CSV nie trzyma już wszystkich spraw w pamięci.** Dotąd zbierał całość do jednej
  tablicy PHP, zanim cokolwiek poszło do przeglądarki — przy kilkudziesięciu tysiącach spraw
  koordynator klikał „Eksport" i dostawał białą stronę albo błąd limitu czasu, bez podpowiedzi,
  że chodzi o rozmiar. Teraz wiersze lecą **strona po stronie**, a zestawienie na końcu pliku
  liczy się **w trakcie wysyłki** (liczniki są sumowalne, więc nie trzeba drugiego przebiegu).
  Pomiar na 20 000 spraw: **15,8 MB → 1,9 kB** zużytej pamięci, i nie rośnie dalej z liczbą spraw.
- Ślad w rejestrze o wyniesieniu danych powstaje nadal **przed** wysyłką (liczbę spraw bierzemy
  z kontraktu, nie z policzenia zebranej tablicy) — dzięki temu wpis istnieje także wtedy, gdy
  pobieranie urwie się w połowie.
- Nowy żywy test `testy/e2e/d-eksport-strumieniowy.sh` (10 kontroli) wpięty w CI: mierzy pamięć
  obiema drogami, sprawdza zgodność wszystkich pozycji zestawienia i to, że pamięciożerna metoda
  została usunięta. Skalibrowany kodem sprzed przebudowy — złapał.

## [1.2.5] - 2026-07-29

### Poprawione
- **Po dłuższym przestoju koordynator dostawał lawinę „zbiorczych" maili.** Sprawdzanie terminów
  brało eskalacje tą samą paczką co przypomnienia (50 spraw), a próg zbiorczego powiadomienia
  liczy się **na przekazanej liście** — więc 500 zaległych eskalacji dawało 10 rund po 50, czyli
  **dziesięć osobnych „zbiorczych" maili w ciągu jednego przebiegu**. Dokładnie ta lawina, przed
  którą zbiorcze powiadomienie miało chronić. Eskalacje mają teraz własny, większy limit paczki;
  przypomnienia zostały przy swoim, bo to jeden mail **na sprawę**, a eskalacja powyżej progu —
  jeden mail **na całą listę**, więc większy limit zmniejsza liczbę wiadomości, a nie zwiększa.
- **Przy okazji: jałowe kręcenie się w kółko.** Gdy eskalacja nie mogła zostać wysłana, przebieg
  powtarzał dziesięć rund po tych samych sprawach i liczył je wielokrotnie — licznik w rejestrze
  pokazywał 500 przy realnych 120. Dowód wykonaniem na tej samej instalacji: stary kod
  `rounds: 10, escalations: 500`, poprawiony `rounds: 1, escalations: 120`.
- Nowy żywy test `testy/e2e/d-jeden-digest-na-przebieg.sh` (5 kontroli) wpięty w CI. Kalibracja
  wykryła **dziurę w samym teście**: wzorzec `"rounds":1` pasował także do `"rounds":10`, więc
  kluczowa kontrola przechodziła na wadliwym kodzie — poprawione na dopasowanie z granicą pola.

## [1.2.4] - 2026-07-29

### Poprawione
- **Import CSV omijał regułę, której pilnowała ręczna edycja.** „Gwarancja nie może kończyć się
  przed datą zakupu" było egzekwowane tylko przy poprawianiu danych produktu w panelu (od 1.1.0),
  a **nie przy imporcie — czyli przy głównej drodze wejścia danych**. Parser sprawdzał każdą datę
  z osobna (czy jest poprawna kalendarzowo), ale nie porównywał ich ze sobą: wiersz z zakupem
  2026-08-01 i gwarancją do 2026-01-01 wjeżdżał bez słowa i dostawał normalny status, bo status
  liczy się wyłącznie z daty końca. Pilnowaliśmy reguły tam, gdzie prawie nikt nie wchodzi.
  Teraz taki wiersz trafia do raportu błędów z powodem, a reszta pliku importuje się normalnie.
  Puste daty pozostają legalne — kolumny są opcjonalne.
- Nowy żywy test `testy/e2e/b-import-waliduje-daty.sh` (7 kontroli) wpięty w CI: sprawdza nie tylko
  odrzucenie złego wiersza, ale też że dobry wchodzi, puste daty dalej działają i że raport podaje
  powód. Skalibrowany kodem sprzed poprawki — złapał.
- `INSTRUKCJA-KLIENTA.md`: reguła dopisana do zasad pliku CSV.

## [1.2.3] - 2026-07-29

### Poprawione
- **Awaria wysyłki przypomnień i eskalacji była niewidoczna.** Automator zapisywał flagę alarmu
  i **nikt jej nigdy nie odczytywał** — komentarz w kodzie obiecywał „panel pokaże notice",
  a panel nie pokazywał nic. Po trzech nieudanych próbach sprawa dostaje trwały znacznik
  „wysłano" i nie dostanie już przypomnienia ani eskalacji tego rodzaju, a system wygląda zdrowo.
  Typowy scenariusz: hosting przycina wysyłkę na godzinę, sweep trafia w to okno trzy razy pod
  rząd i cichnie na stałe. Moduł zgłoszeń miał ten sam wzorzec zrobiony w komplecie — poprawka
  przenosi go 1:1: kształt flagi `{rodzaj, czas}`, gaszenie po udanej wysyłce i **czternasty test
  w Narzędzia → Stan witryny**, który mówi, KTÓRE powiadomienie nie wyszło i KIEDY.
- Nowy żywy test `testy/e2e/d-mail-awaria-widoczna.sh` (8 kontroli) wpięty w CI, skalibrowany
  kodem sprzed poprawki — złapał. Liczba testów diagnostycznych w `README.md` i `ADMIN.md`
  podniesiona z 13 na 14 (pilnuje tego bramka `liczby-zgodne-z-kodem.sh`).

## [1.2.2] - 2026-07-29

### Poprawione
- **Aktualizacja wtyczki gubiła przypomnienia dla spraw już otwartych.** Kolumna z terminem
  ostrzeżenia została kiedyś dodana migracją jako pusta, bez przeliczenia istniejących wierszy,
  a zapytanie wysyłające przypomnienia pomija wiersze puste. Skutek: sprawa otwarta w chwili
  podniesienia wersji **nigdy nie dostawała przypomnienia PRZED terminem** — tylko eskalację po
  nim. Dotyczyło to dokładnie spraw stojących w miejscu, czyli tych, dla których ten mechanizm
  powstał; naprawiało się samo dopiero przy zmianie statusu albo po ręcznym „Przelicz SLA".
  Ścieżka aktualizacji woła teraz **istniejący** mechanizm przeliczania (paczki po 200
  z dokańczaniem w tle), za bramką wersji — czyli raz na aktualizację, nie przy każdym wejściu
  do panelu. Markery wysyłki zostają nietknięte, więc stare powiadomienia nie wychodzą drugi raz.
  Dowód wykonaniem: na tej samej instalacji stary kod zostawiał termin pusty, nowy go przelicza.
- Nowy żywy test `testy/e2e/d-upgrade-przelicza-terminy.sh` (6 kontroli) wpięty w CI: odtwarza
  stan tuż po podmianie plików i sprawdza przeliczenie, nietykalność markerów wysyłki oraz to,
  że bramka wersji zamyka temat po jednym przebiegu. Skalibrowany kodem sprzed poprawki — złapał.

## [1.2.1] - 2026-07-29

### Poprawione
- **Odinstalowanie rejestru zostawiało pliki na serwerze.** Katalog `uploads/mp-imports/` — pliki
  wsadowe importu i raporty odrzuconych wierszy (numery seryjne, faktury, daty zakupu) — nie był
  kasowany przy odinstalowaniu wtyczki, a cron retencji, który sprzątał je po dobie, znikał razem
  z nią. Katalog zostawał więc na dysku na zawsze. Wtyczka zgłoszeń robiła to poprawnie od początku;
  poprawka kopiuje jej układ 1:1. `OWNERSHIP.md` obiecywał takie zachowanie („warstwa (i) ZAWSZE:
  … pliki techniczne") — kod łamał regułę własnego projektu.
  Dowód wykonaniem: na tej samej instalacji stara wersja zostawiała katalog z plikami, poprawiona
  go usuwa razem z guardami.
- `testy/e2e/uninstall-crony.sh` pilnuje teraz obu katalogów roboczych. Test **najpierw zakłada
  w nich próbki**, żeby pusty katalog nie udawał posprzątanego; skalibrowany podłożonym błędem
  (stara wersja pliku odinstalowującego) — złapał.
- `OWNERSHIP.md` wymienia oba katalogi z nazwy, zamiast ogólnego „pliki techniczne".

## [1.2.0] - 2026-07-29

Domknięcie kroku 5 przebiegu ze specyfikacji: **„silnik reguł nadaje priorytet i przydziela sprawę
do właściwego pracownika"**. Silnik działał od początku, ale **pula pracowników wychodziła
z instalacji pusta i nie było jej jak wypełnić** — ani ekranem, ani komendą wiersza poleceń.
Świeżo wdrożony system przyjmował zgłoszenia i zostawiał je nieprzydzielone, a instrukcja
kazała „wskazać pracowników w regule" jako pierwszy krok wdrożenia.

### Dodane
- **Sekcja „Kto dostaje zgłoszenia"** w panelu Automatyzacje MP (pod tabelą reguł): lista
  pracowników serwisu do zaznaczenia + zapis. Wymaga uprawnienia administratora systemu —
  tak samo jak pozostałe konfiguracje. Zapis jest chroniony tokenem, sprawdzeniem uprawnień
  i blokadą przed nadpisaniem cudzej zmiany; zostawia wpis w rejestrze zdarzeń.
- Nowy żywy test `testy/e2e/d-pula-pracownikow.sh` (14 kontroli) wpięty w CI: pilnuje całej
  drogi — pusta pula = brak przydziału, zapis z panelu = sprawa trafia do człowieka.
  Endpoint dopisany także do testu macierzy bezpieczeństwa (403 dla nieuprawnionych).

### Poprawione
- **Instrukcje mówiły o ekranach ustawień, których nie ma.** Sprawdzone w kodzie i poprawione
  w czterech miejscach: kategorie zgłoszeń, terminy SLA, dodawanie własnych statusów oraz
  ustawianie puli (to ostatnie stało się prawdą wraz z tym wydaniem). Dokumenty podają teraz
  wartości wbudowane i wprost mówią, co wymaga programisty.
- Instrukcja koordynatora kazała mu ustawić pulę, do czego nie ma uprawnień — wskazuje teraz
  administratora systemu.

## [1.1.0] - 2026-07-28

Domknięcie wymogu ze specyfikacji: **„historia zmian danych produktu i decyzji gwarancyjnych"**.
Decyzje gwarancyjne były zapisywane od początku, ale danych produktu **nie dało się zmienić** —
wchodziły wyłącznie importem, a ponowny import odrzucał ten sam numer seryjny jako duplikat.
Historia zmian danych nie miała więc czego zapisywać, a błąd w pliku (np. zła data gwarancji)
był nie do poprawienia bez ręcznej ingerencji w bazę.

### Added
- **Ekran „popraw dane" w rejestrze produktów** (`?page=mp-registry&edit=ID`, wymaga
  `mp_system_admin`): model, partia, kategoria, dokument zakupu, data zakupu, data końca gwarancji.
  Daty przyjmowane w obu formatach obsługiwanych przez import (`RRRR-MM-DD` i `DD.MM.RRRR`).
- **Zapis każdej poprawki do historii produktu** jako `PRODUCT_UPDATED` z różnicą przed/po —
  ten sam typ zdarzenia i kształt danych, którego używa archiwizacja, więc historia czyta się
  jednym wzorcem.

### Security
- Numer seryjny **wyłączony z edycji** (`Repo::EDITABLE_FIELDS`). Jest kluczem relacji
  sprawa → produkt ze specyfikacji; podmiana przepisałaby cudzą historię serwisową na inny egzemplarz.
- Dokument zakupu trafia do historii **bez wartości** (lista PII w `ProductEvents::PII_FIELDS`) —
  zapisujemy sam fakt zmiany.
- Zapis chroniony tokenem `nonce` per produkt i sprawdzeniem uprawnień; produkt archiwalny
  odrzucany; gwarancja kończąca się przed datą zakupu odrzucana z czytelnym komunikatem.

### Tests
- `testy/e2e/b-edycja-produktu.sh` wpięty w CI: zapis i wpis w historii, brak PII w historii,
  nietykalność numeru seryjnego, odrzucenie błędnej daty i odwróconych dat, brak wpisu przy
  braku realnej zmiany, blokada archiwalnego oraz **realna zmiana statusu gwarancji po poprawce
  daty** (bez tego edycja byłaby ozdobna).

## [1.0.3] - 2026-07-28

Wydanie uzupełniające paczkę — **bez zmian w kodzie wtyczek**. Domyka to, czego brakowało
osobie technicznej po stronie klienta, i zamyka ostatnią uwagę recenzenta dotyczącą CI.

### Added (paczka dla klienta)
- `dla-informatyka/` — komplet dokumentacji technicznej w paczce: układ bazy, kontrakt
  między wtyczkami, model zdarzeń, maszyna statusów, własność danych, zasady bezpieczeństwa,
  polityka migracji. Wcześniej te dokumenty istniały wyłącznie w repozytorium, więc kto
  dostawał samą paczkę, nie dostawał nic dla programisty.
- `diagramy/zrodla/` — źródła diagramów (HTML + CSS), żeby dało się je poprawić, a nie
  tylko obejrzeć gotowy obrazek.

### Security (łańcuch dostaw CI)
- Wszystkie akcje w `quality.yml` przypięte do **skrótu commita (SHA)** zamiast ruchomych
  tagów `@v1`/`@v2`/`@v4`/`@v7`. Przejęcie repozytorium akcji nie podmieni nam już tego,
  co uruchamia się z dostępem do sekretów. Wersja pozostaje w komentarzu przy każdym wpisie.

### Changed (skrypt pakujący — bramka, nie komentarz)
- Samokontrola paczki sprawdza teraz, czy **każdy** dokument techniczny z repozytorium
  faktycznie znalazł się w paczce i czy liczba źródeł diagramów zgadza się z liczbą obrazków.

## [1.0.2] - 2026-07-28

Wydanie porządkujące paczkę — **bez zmian w kodzie wtyczek**. Powstało po pełnym sprawdzeniu
1.0.1 przed przekazaniem (kalibracja audytu + testy na żywym systemie); żadnej wady działania
nie znaleziono, poprawki dotyczą wyłącznie spójności materiałów dla klienta.

### Fixed (spójność paczki)
- Dwa dokumenty (`INSTRUKCJA-KLIENTA.md`, `RAPORT-A11Y-WCAG.md`) deklarowały wersję 1.0.0 mimo
  wydania 1.0.1 — ujednolicone do wersji wydania.
- Zrzut ekranu potwierdzenia e-mail pokazywał tymczasowy adres środowiska demonstracyjnego —
  przegenerowany na neutralny.

### Changed (skrypt pakujący — naprawa wzorca, nie objawu)
- `build/pakuj-dla-klienta.sh` kontroluje teraz zgodność wersji także w TREŚCI dokumentów
  (wcześniej tylko w nagłówkach wtyczek i `readme.txt` — stąd rozjazd wersji przeszedł niezauważony).
- Wykrywanie śladów wewnętrznych rozszerzone o adresy tuneli demonstracyjnych.

## [1.0.1] - 2026-07-28

Wydanie po przeglądzie na **żywym systemie** — każda pozycja niżej została złapana przez przejście
ścieżki klienta i pracownika w przeglądarce, nie przez czytanie kodu.

### Fixed (gwarancja — czwarty status naprawdę działa)
- **Dokument zakupu i data zakupu są wreszcie porównywane z rejestrem.** Zgłoszenie z cudzym
  numerem seryjnym i zmyśloną fakturą dostawało status **„gwarancja aktywna"**, bo moduł zgłoszeń
  pytał rejestr o gwarancję, ale nie przekazywał mu tego, co wpisał klient. Czwarty status
  z zamówienia („wymagana weryfikacja") był przez to **nieosiągalny**. Teraz niezgodność dokumentu
  albo daty oznacza sprawę do ręcznego sprawdzenia.
- **Karta sprawy pokazywała inny status, niż sprawa ma zapisany.** Sprawa z niezgodną fakturą
  miała w bazie „wymagana weryfikacja", a pracownik widział zielone „aktywna" — karta czytała
  bieżący stan produktu w rejestrze zamiast decyzji z chwili zgłoszenia. Pod plakietką jest teraz
  **powód**: „Niezgodne z rejestrem: dokument zakupu. Sprawdź dokument u klienta przed decyzją."
- **Ten sam status nazywał się różnie na dwóch ekranach** („do weryfikacji" na karcie sprawy,
  „wymagana weryfikacja" w rejestrze) — czytało się to jak dwa różne stany.

### Added (formularz zgłoszenia)
- **Załącznik zależny od kategorii produktu** (wymóg z zamówienia, wcześniej niedomknięty): dla
  **AGD drobnego** i **elektronarzędzi** trzeba dołączyć zdjęcie tabliczki znamionowej — bez niego
  serwis nie ustali modelu ani mocy. Audio i „inne" bez zmian. Wymóg spełnia wyłącznie plik, który
  **przejdzie kontrolę** — zdjęcie za duże albo w złym formacie nie „zalicza" go po cichu. Regułę
  można zmienić bez ruszania kodu (filtr `mp_intake_category_attachments`).

### Fixed (praca z systemem)
- **Kategoria wracała pusta po każdym błędzie formularza** — klient poprawiał jedno pole
  i dostawał formularz o innym kształcie niż wysłał (znikały pola kategorii).
- **Lista „Przydziel do" pokazywała osoby, których nie da się wybrać.** Wybranie koordynatora
  kończyło się zawsze komunikatem „Nie udało się przydzielić sprawy." bez wyjaśnienia. Teraz lista
  zawiera wyłącznie pracowników serwisu, a komunikat mówi powód.
- **Komunikat o zbyt dużym pliku radził „spróbuj ponownie"**, choć druga próba też się nie udawała.
  Teraz podaje limit **obowiązujący na tym serwerze** (mniejszy z: limit wtyczki i limit hostingu).
- **Uszkodzone zdjęcie zostawiało ostrzeżenia PHP w dzienniku strony.** Plik ucięty przy wysyłce
  przechodził kontrolę typu, ale nie dawał się odczytać przy usuwaniu danych EXIF — wtyczka radziła
  sobie z tym poprawnie, tylko po drodze wpisywała do `debug.log` trzy ostrzeżenia ze swoją nazwą.
  Teraz dziennik zostaje czysty, zgodnie z obietnicą z `PRZECZYTAJ-MNIE`.

### Changed (dokumentacja dla klienta)
- **Polityka kopii i cofania zmian w bazie trafia do paczki** (`MIGRATION_POLICY.md`), a kopia bazy
  przed instalacją jest **krokiem pierwszym** w `PRZECZYTAJ-MNIE` i w instrukcji wdrożenia.
- **Ryzyko za pośrednikiem (Cloudflare/nginx) opisane po polsku** w instrukcji — wcześniej wisiało
  tylko po angielsku w pliku technicznym wewnątrz wtyczki. Wszystkie zgłoszenia wyglądają wtedy jak
  z jednego adresu IP, więc ochrona przed spamem potrafi zablokować prawdziwych klientów.
- **Instrukcja administratora mówi prawdę o odinstalowaniu.** Obiecywała skasowanie tabel i kont
  klientów; kod świadomie ich **nie kasuje** (żeby przypadkowe kliknięcie nie skasowało firmie
  danych). Doszło ostrzeżenie: narzędzie RODO znika razem z wtyczką, więc dane trzeba usunąć PRZED.
- **Czwarty status gwarancji opisany** w instrukcji wdrożenia oraz w instrukcjach pracownika
  i koordynatora — co znaczy i co z taką sprawą zrobić. Wyjątek gwarancyjny przypisany właściwej
  roli: zatwierdza go **administrator systemu**, nie koordynator.
- **Wszystkie 21 zrzutów ekranu odświeżone.** Dwa różne podpisy pokazywały wcześniej ten sam
  obrazek, a zdjęcie „skrzynki mailowej" przedstawiało narzędzie testowe zamiast wiadomości.

## [1.0.0] - 2026-07-27

### Security (panel klienta — nieodwracalna akcja z potwierdzeniem)
- **Usunięcie danych osobowych wymaga teraz dwóch świadomych kliknięć.** Przycisk „Wycofaj zgodę
  i usuń moje dane" wysyłał formularz od razu: jedno kliknięcie wycofywało zgodę na **wszystkich**
  sprawach i uruchamiało usuwanie — a przycisk sąsiadował z niewinnym „Zapisz dane". Na telefonie
  pudło kciukiem kończyło się nieodwracalną utratą danych. Teraz pierwsze kliknięcie prowadzi na
  ekran, który mówi wprost **co zniknie** (imię, telefon, e-mail), **co zostaje** (historia zdarzeń
  i statystyki, bez danych identyfikujących) i że operacji **nie da się cofnąć**; dopiero przycisk
  na tym ekranie ją wykonuje — z osobnym nonce. Ten sam wzorzec, co przy potwierdzaniu zgłoszenia
  i logowaniu linkiem z maila.
- **Blok RODO przeniesiony pod listę spraw.** Rozdzielał dane kontaktowe od zgłoszeń, przez co
  klient wchodzący sprawdzić status naprawy w pierwszej kolejności widział czerwony przycisk
  kasowania konta.

### Changed (sprawdzenie na najnowszym WordPressie)
- **`Tested up to: 7.0`** we wszystkich trzech wtyczkach — paczka przeszła **instalację od zera na
  WordPressie 7.0.2** (PHP 8.2, MySQL 8): ścieżka klienta 19/0, wgranie wtyczki przez panel 6/0,
  zero PHP notice z naszego kodu. Wcześniej deklarowaliśmy 6.9, a oficjalny Plugin Check miał
  **wyciszone** ostrzeżenie o nieaktualnym nagłówku — wyciszenie zdjęte, nagłówek pilnuje się sam.
  Harness `testy/paczka-od-zera` przyjmuje teraz wersję WP przez `MP_WP_OBRAZ`, więc obie
  kombinacje (minimum 6.9/PHP 8.1 i najnowsza 7.0/PHP 8.2) da się powtórzyć jednym poleceniem.

### Fixed (poprawki z przeglądu ekranów przed wydaniem)
- **Zwrot przestał wyglądać na puste zgłoszenie.** Kolumna „Czego dotyczy" na liście spraw czytała
  wyłącznie opis usterki, a formularz zwrotu zbiera **powód zwrotu** — więc każdy zwrot pokazywał
  koordynatorowi „— bez opisu", mimo że klient napisał, dlaczego oddaje produkt. Teraz kolumna bierze
  opis usterki, a gdy go nie ma — powód zwrotu (pierwszeństwo opisu bez zmian).
- **Koniec surowego `CASE_CREATED` w historii sprawy.** Mapa etykiet nie miała wpisu dla zdarzenia
  narodzin sprawy, więc **każda karta** zaczynała się technicznym kodem w otoczeniu polskich wpisów.
  Uzupełniono komplet typów z `CaseEvents` (zgody RODO, usunięcie danych, przypomnienia i eskalacja SLA,
  nieudana wysyłka e-maila).
- **Priorytet po polsku** — karta sprawy pokazywała wartość z bazy (`normal`) zamiast „normalny".
- Dokumentacja klienta: jawne ostrzeżenie, że **bazę produktów trzeba wgrać przed udostępnieniem
  formularza** — powiązanie sprawy z produktem powstaje w chwili przyjęcia i nie jest uzupełniane wstecz.

**Pierwsze wydanie dla klienta.** Kompletny system obsługi zgłoszeń serwisowych i reklamacyjnych:
przyjmowanie zgłoszeń z weryfikacją mailową i kontem klienta bez hasła, rejestr produktów
i gwarancji z importem CSV, automatyczny przydział spraw, pilnowanie terminów SLA z przypomnieniami
i eskalacją, raporty. Poniżej pełna lista zmian od wersji 0.5.0.

### Added
- Registry (B) — **przykładowy plik importu w paczce + opis kolumn na ekranie.** Wtyczka wozi
  `przyklady/przyklad-import-produktow.csv` (8 wierszy pokazujących WSZYSTKIE obsługiwane kolumny, oba formaty
  daty, kategorię slugiem i etykietą, wiersz minimalny „tylko serial", jedną gwarancję już wygasłą), a ekran
  importu linkuje do niego („Pobierz przykładowy plik CSV"). Ekran wymienia teraz też **kolumny opcjonalne**
  (dotąd tylko wymaganą `serial`), formaty dat, listę kategorii **czytaną z `Categories::slugs()`** (nie
  przepisaną ręcznie — nie może się rozjechać) oraz jawnie mówi, że import DODAJE produkty i nie nadpisuje
  duplikatu serialu. Test pilnujący `test_dolaczony_przyklad_csv_importuje_sie_bez_bledow` przepuszcza dołączony
  plik przez realny parser — przykład nie może cicho przestać się importować.

### Changed
- **Numer sprawy ma format ze specyfikacji: `SRV/RRRR/NNNN` (cztery cyfry).** Dotąd kod nadawał
  pięć cyfr (`SRV/2026/00001`), mimo że specyfikacja zamawiającego mówi `SRV/RRRR/NNNN`. Rozjazd
  utrwalił się, bo wcześniej „poprawiono literówkę" **w dokumentacji, dopasowując ją do kodu**
  zamiast odwrotnie — a komentarz w kodzie twierdził, że pięć cyfr to „spec klienta". Wyszło
  w audycie odbiorczym czytającym surową specyfikację. Po zmianie: pierwsza sprawa roku to
  `SRV/2026/0001`; po przekroczeniu 9999 spraw numer rośnie naturalnie do pięciu cyfr, więc
  licznik się nie zapętli ani nie zdubluje.

### Fixed
- **Poczta: awaria wysyłki przestała być niewidoczna (audyt 27.07).** Cztery miejsca w Intake
  (magic-link, ponowna wysyłka, potwierdzenie z numerem SRV, link logowania) ignorowały wynik
  `wp_mail()`. Gdy hosting odmawiał wysyłki, klient nie dostawał linku, formularz i tak pokazywał
  „sprawdź skrzynkę", a w bazie **nie zostawał żaden ślad** — nikt nie odkrywał, czemu zgłoszenia
  przestały się potwierdzać. Poprawny wzorzec istniał obok, w Automatorze. Teraz: jedno gardło
  wysyłki, zdarzenie `MAIL_FAILED` na osi sprawy, alert w Narzędzia → Stan witryny (gaśnie po
  pierwszej udanej wysyłce) i nowy test diagnostyczny „Poczta NIE WYCHODZI" z instrukcją naprawy.
- **Sprawa potwierdzona przy wyłączonym Automatorze nie zostaje sierotą (audyt 27.07).** Naprawa
  sierot z #1 rozpoznawała je po BRAKU zdarzenia narodzin — więc nie widziała przypadku, gdy Intake
  zapisał wszystko poprawnie, tylko Automator był wyłączony i nikt akcji nie usłyszał. Taka sprawa
  nigdy nie dostawała przydziału ani terminu. Sweep porównuje teraz swój stan z listą spraw
  (kontrakt `mp_cases_verified_ids` — same ID, zero danych osobowych) i doszywa różnicę.
- **Kontrakt `mp_cases_data_erased` ożył.** Sygnał był opisany w API-KONTRAKT.md, OWNERSHIP.md,
  EVENT_MODEL.md i na diagramie architektury, Rejestr miał gotowego słuchacza — a **nikt go nigdy
  nie emitował**. Po odinstalowaniu Intake w pozostałych wtyczkach zostawały wiersze wiszące na
  nieistniejących sprawach. Uninstall emituje sygnał, Automator dostał brakującego słuchacza
  (czyści terminy i checklisty; rejestr operacji zostaje jako historia).
- **Sweep SLA nie zaleje hostingu.** Paczki ograniczały liczbę spraw, nie maili: do 500 wiadomości
  sekwencyjnie w jednym żądaniu PHP (typowy hosting przepuszcza 200–500/godzinę). Dodany budżet
  120 maili na przebieg (filtr `mp_sla_mail_budget`); reszta czeka na kolejny przebieg z nietkniętym
  markerem, a przerwanie jest jawnie zapisane w rejestrze.
- **„Przelicz SLA" nie wywróci się na dużej bazie.** Zapytanie szło bez limitu, a potem pętla robiła
  zapytanie i UPDATE na każdy wiersz — przy 15 tys. spraw ~30 tys. zapytań w jednym żądaniu. Teraz
  paczki po 200 z dokańczaniem w tle (hak sprzątany przy deaktywacji i odinstalowaniu).
- **RODO: porzucone zgłoszenia znikają razem z danymi.** Kto wypełnił formularz i nie kliknął linku,
  zostawiał sprawę wraz z e-mailem i telefonem **na zawsze** (okno potwierdzenia to 72 h, więc taka
  sprawa i tak nie może ruszyć). Dzienny cron kasuje porzucone starsze niż 30 dni razem z plikami
  załączników; próg zmienia filtr `mp_intake_pending_retention_days`.
- **Zamknięta sprawa nie przyjmuje już przydziału ani zmiany pilności.** Bramka terminalna chroniła
  wyłącznie kolumnę statusu — przydział zamkniętej sprawy wysyłał maila do pracownika i dopisywał
  zdarzenie na jej osi. Do pracy sprawa wraca przez wznowienie, nie bocznymi drzwiami.
- **Formularz publiczny nie wywali się na hostingu bez `mbstring`.** Walidator używał gołego
  `mb_strlen()` — brak rozszerzenia oznaczał błąd krytyczny na każdym zgłoszeniu, a nie degradację.
- **Polska odmiana liczb w komunikatach.** Rejestr pokazywał „Produkt ma 1 aktywnych spraw";
  formy dobierane są teraz wg reguł języka (z wyjątkiem 12–14).
- **Panel: teksty i czytelność (audyt ekranów 27.07).** Diagnostyka odsyłała do edycji reguły w
  panelu, który jest tylko do odczytu — teraz podaje prawdziwą drogę (rola „Pracownik serwisu MP"
  w Użytkownikach). Rejestr zdarzeń mówi po polsku („Brak pasującej reguły przydziału" zamiast
  `ASSIGNMENT_UNMATCHED`), pokazuje numer sprawy zamiast wewnętrznego ID i czas lokalny zamiast UTC.
  Pole e-mail przy ponownej wysyłce dostało nazwę dla czytników ekranu, a tekst pomocniczy
  „nieprzydzielona" — kontrast zgodny z WCAG AA.
- **Teksty dodawane JavaScriptem przechodzą przez tłumaczenia** (wiersze konfiguracji dodawane
  przyciskiem miały etykiety i opisy dla czytników ekranu wpisane na sztywno).
- Intake (C) — **nagłówki bezpieczeństwa docierały TYLKO na auto-stronę wtyczki.** Warunek brzmiał
  „jeśli to strona o ID zapisanym w opcji" — a dokumentowany sposób użycia to **wstawienie shortcode'u
  na własną podstronę**. Takie strony (czyli te, które realnie robi klient) szły **bez żadnego nagłówka**:
  zmierzone na żywym WP — auto-strona miała `Cache-Control: no-store`, ręcznie założona `/moje-sprawy/`
  nie miała nic. Teraz decyduje obecność shortcode'u (`PageDetect::is_plugin_page`), a zestawy są
  filtrowalne (`mp_intake_security_headers`) — strona klienta może je dostosować albo wyłączyć.
  Formularz dostaje `X-Frame-Options`, `X-Content-Type-Options`, `CSP: frame-ancestors 'self'`,
  `Referrer-Policy`. **Panel klienta dodatkowo `X-Robots-Tag: noindex, nofollow`, `Cache-Control:
  no-store` i `Referrer-Policy: no-referrer`** — pokazuje dane osobowe, więc nie ma prawa trafić do
  wyszukiwarki ani zostać w cache; plus `<meta name="robots" noindex>` jako pas zapasowy, gdy hosting
  utnie nagłówki. Strony BEZ naszego shortcode'u zostają nietknięte (sprawdzane osobną asercją: zero
  ingerencji poza własnym terenem). Regresję pilnuje `testy/e2e/c3-front.sh` §8.
- Intake (C) — **panel klienta: 20 inline-style'i usuniętych, własne odstępy zamiast liczenia na motyw.**
  Objaw: na motywie, który zeruje marginesy `<p>` (a robi tak wiele motywów), przycisk „Wyślij"/„Zapisz dane"
  **przyklejał się do pola** — 0 px odstępu; na motywie domyślnym WP wychodziło 22 px, czyli poprawnie tylko
  przez przypadek. Przyczyna: `Front/AccountPage.php` budował formularze `<br>`-ami i inline-style'ami, które
  **przebijały własny CSS wtyczki** (pola dostawały `padding:.5rem` zamiast zaprojektowanego `.7rem/.85rem`,
  przycisk RODO czerwoną łatę zamiast obrysu). Teraz: klasy `mp-account__field` / `__actions` / `__meta` /
  `__message*` / `__note-closed` + reguły w `intake.css`, a zaszyte kolory (`#555`, `#666`, `#2e7d32`, `#a33`,
  `#fff`, `#f6f6f6`) zamienione na zmienne (`--mp-muted`, `--mp-ok` — nowa, `--mp-err`, `--mp-soft-bg`).
  Skutek: **ten sam wygląd na dowolnym motywie** i możliwość dopasowania kolorów bez tykania kodu wtyczki.
  Zmierzone po naprawie: odstęp pole→przycisk **18 px na motywie strony demonstracyjnej i 18 px na Twenty Twenty-Five**, kontrast
  przycisku „Wycofaj zgodę" **5.12:1** (AA). Zero zmian logiki i treści. Honeypot w `FormRenderer` zostaje
  inline świadomie — gdyby arkusz się nie wczytał, pułapka na boty stałaby się widoczna dla ludzi.
- Registry (B) + Automator (D) — **`str_getcsv`/`fputcsv` bez jawnego `$escape` = deprecated na PHP 8.4+.**
  Import 10 tys. wierszy potrafił wygenerować 10 tys. wpisów „deprecated" przy `WP_DEBUG` (łamie kontrakt
  dirty-env „zero notice z naszego kodu"), a **domyślna wartość ma się w przyszłym PHP zmienić** — czyli
  parsowanie zmieniłoby się samo. Teraz `$escape` podawany jawnie jako PUSTY = semantyka RFC-4180, taka jaką
  pisze Excel (cudzysłów podwajany, backslash literalny). Efekt uboczny naprawiony przy okazji: model typu
  `Kabel 3\4` i ścieżka `D:\dane\` parsują się poprawnie (z dotychczasowym domyślnym `\` psuły podział pola).
  Zabezpieczone testem `test_backslash_jest_zwyklym_znakiem`.

### Changed
- Admin — **kolorowe plakietki statusów w listach personelu (czytelność).** Intake (C): status sprawy
  (nowe=niebieski, w naprawie=pomarańczowy, zamknięte=szary…). Registry (B): status gwarancji
  (aktywna=zielony, wygasła=czerwony, weryfikacja=żółty, brak danych=szary) — reuse istniejącego
  `admin-registry.css`/`mp-badge`. **Bonus fix:** mapa etykiet statusu gwarancji miała klucze angielskie,
  a `WarrantyStatus::compute` zwraca polskie — lista pokazywała surowe „wygasla"/„brak_danych"; teraz
  poprawne „wygasła"/„brak danych". Styl natywny WP-admin, zero zmian logiki.
- Intake (C) — **spójny wygląd WSZYSTKICH ekranów klienta.** Strony samodzielne (weryfikacja „Potwierdź
  zgłoszenie", potwierdzenie/błędy, logowanie „Zaloguj się", „Link nieaktualny") stały poza motywem z gołym
  systemowym stylem — teraz wspólna skorupa `Front\Landing` (jedno źródło stylu: karta na jasnym tle, akcent
  `--mp-accent` jak formularz). Bezpieczeństwo bez zmian (no-store/no-referrer/nosniff/SAMEORIGIN/noindex).
  Karty spraw / kontakt / prywatność w panelu klienta dostały wygląd z `intake.css` (ładniejsze karty,
  subtelny warm-akcent na „wycofanie zgody"). Zero zmian logiki.
  <!-- SPROSTOWANIE 2026-07-26: pierwotnie stało tu „Usunięte inline-style'e z panelu klienta" — to było
       NIEPRAWDĄ, `AccountPage.php` miał ich dalej 20. Faktyczne usunięcie: wpis w „Fixed" niżej. -->

- Intake (C) — **dopracowany wygląd frontu (formularz zgłoszenia + panel klienta).** Dotąd CSS był surowy
  („techniczne" pola). Teraz profesjonalny, ale **neutralny motywowo** (wąski zakres `.mp-intake`/`.mp-account`,
  dziedziczy font motywu): pola z zaokrągleniem i wyraźnym focus, **własny chevron selecta**, **własny checkbox
  RODO**, przyciski-pigułki, sprawy w panelu jako karty, czytelne błędy/notki. Akcent przez zmienną
  **`--mp-accent`** (domyślnie ciemny neutral — ładnie na każdym motywie klienta; strona/motyw może nadpisać).
  Zero zmian logiki. Dostępność: `focus-visible`, kontrast AA.

### Fixed
- Intake (C) — **rate-limit zgłoszeń liczy tylko UDANE próby** (#D5). Dotąd `RateLimit::check()`
  inkrementował liczniki e-mail/serial PRZED walidacją (zgoda/serial/data), więc klient z literówką
  wyczerpywał limit 3/dobę i nie mógł złożyć reklamacji. Teraz `check()` **tylko czyta** liczniki
  e-mail/serial (blokada gdy już wyczerpane), a inkrement (`record_submission`) następuje dopiero po
  utworzeniu sprawy. Limit **IP (anty-flood)** dalej liczy każdą próbę atomowo. Anti-spam zachowany
  (3 udane zgłoszenia → 4. blok). Test `c6c`: 3 nieudane (bez zgody) nie zjadają limitu, ważne przechodzi.
- Registry (B) — **limit importu 20 MB → 8 MB (ochrona przed OOM)** (#D10). `create_job_from_file` wczytuje
  cały plik do pamięci (`file_get_contents` + `to_utf8` + `preg_split` w tablicę), co przy ~20 MB mogło
  przekroczyć domyślny `memory_limit` 128 MB. Limit obniżony do 8 MB (bezpieczny zapas); większe importy
  klient dzieli na części. Właściwe przetwarzanie (`process_batch`) i tak streamuje przez `fgetcsv`.
  Test `ImportEndpointsTest::test_import_limit_is_memory_safe` (test pilnujący przed przyszłym bumpem).
- Intake (C) — **honeypot czasowy: brak/za stary `mp_ts` też odrzucany** (#D11). Wcześniej pominięcie pola
  `mp_ts` omijało pułapkę czasu (warunek `$started > 0`) — bot mógł nie wysyłać znacznika. Teraz brak,
  zbyt szybkie (<2 s) i zbyt stare (>3 h, replay) znaczniki wpadają w cichy odrzut. Warstwa bonusowa —
  realna ochrona to nonce + rate-limit. Test `c3-front`: submit bez `mp_ts` → zero spraw.
- Intake (C) — **załączniki WebP bez `imagewebp()` nie są kaleczone** (#D8). Przy GD bez obsługi zapisu
  WebP (i bez Imagick) strip metadanych zapisywał JPEG do pliku z mime `image/webp` w bazie → `serve()`
  dawał błędny `Content-Type` (plik się nie otwierał). Teraz taki plik zostaje oryginalny (spójny).
- Intake (C) — **admin notice gdy brak biblioteki obrazów** (#D9). Bez Imagick i bez GD metadane EXIF/GPS
  ze zdjęć nie były usuwane po cichu — teraz admin dostaje ostrzeżenie (`Attachments::has_image_library`).
- Intake (C) — **licznik SRV i rate-limit czytają `$wpdb->insert_id`** zamiast osobnego `SELECT
  LAST_INSERT_ID()` (#D7, tylko ścieżki `INSERT … ON DUPLICATE KEY UPDATE` — zweryfikowane, że insert_id
  się tam odświeża). Bezpieczniejsze na HyperDB (bare SELECT mógłby trafić na replikę) + jedno zapytanie
  mniej. Round-robin automatora (plain UPDATE) świadomie zostaje przy `SELECT LAST_INSERT_ID()` — tam
  `insert_id` się NIE odświeża (potwierdzone empirycznie).
- Registry (B) — **pliki importu CSV kasowane (retencja RODO + dysk)** (poprawka #D2 z audytu kod-based).
  Znormalizowany plik importu (`uploads/mp-imports/{uuid}.csv`, PII: serial/faktura/nazwisko) nigdy nie
  był usuwany — `ImportJobs::finish()` robił tylko UPDATE statusu, a plugin B nie miał żadnego crona
  (`CRON_HOOKS` puste). Pliki rosły bez końca (art. 5 ust. 1 lit. e). Teraz `finish()` **kasuje źródłowy
  CSV** po zaksięgowaniu (raport błędów `.bledy.csv` ZOSTAJE — admin pobiera przez `handle_report`), a nowy
  **dobowy cron `mp_registry_imports_sweep`** (`Importer::sweep_import_files`) sprząta sieroty starsze niż
  24 h (joby przerwane w połowie + stare raporty), chroniąc guardy katalogu. Test `import-dod`: po `finish`
  źródłowy CSV zniknął, raport przetrwał, sweep skasował sierotę >24 h.
- Intake (C) — **rate-limit atomowy (odporny na współbieżność)** (poprawka #D3 z audytu kod-based).
  Liczniki rate-limitu (formularz zgłoszeń i żądania magic-linku) używały transientowego
  read-modify-write (`get_transient` + `set_transient`) — pod równoległymi żądaniami wszystkie czytały
  tę samą wartość i nadpisywały +1, przez co **limit dało się obejść** (repro: 20 równoległych → licznik
  spadał do ~2, zgubione ~18 inkrementów). Zastąpione **atomową tabelą `mp_rate_counters`** (migracja v2)
  z jedną kwerendą `INSERT … ON DUPLICATE KEY UPDATE … LAST_INSERT_ID` (wzorzec `SrvCounter`, okno
  przesuwane); wygasłe wiersze sprząta cron retencji (`cleanup_expired`). Test `c17`: 20 równoległych żądań
  → licznik dokładnie 20 (zero zgubionych) + reset okna. Dedup pozostaje transientem (bez zmian).
- Intake (C) — **załączniki: pominięte pliki są MELDOWANE klientowi** (poprawka #D4 z audytu kod-based).
  Dotąd `SubmissionHandler::handle_submit()` wywoływał `Attachments::store_for_case()` i **ignorował wynik**
  (`{stored, errors}`) — klient, którego pliki odpadły (zły typ, za duży, limit 5/sprawę, brak miejsca),
  widział neutralny „sukces", a serwis dostawał reklamację **bez dowodów**. Teraz wynik jest przechwytywany,
  a gotowe (istniejące server-side) teksty błędów doklejane do komunikatu PRG. Anty-enumeracja zachowana
  (błędy dotyczą plików, które klient sam wgrał — nie zdradzają istnienia konta). Test `c4-zalaczniki`:
  realny POST z plikiem złego typu → sprawa powstaje, plik odrzucony, notice niesie tekst błędu.
- Intake (C) — **RODO art. 17: eraser USUWA konto WP klienta** (poprawka #D1 z audytu kod-based).
  Dotąd anonimizacja tylko odpinała konto (`customers.wp_user_id = NULL`), a rekord `wp_users` z realnym
  e-mailem/loginem/nazwiskiem zostawał bezterminowo — mimo że panel raportował „dane zanonimizowane"
  (naruszenie art. 17 + art. 5 ust. 1 lit. a). Teraz `Privacy::erase()` łapie `wp_user_id` **przed**
  anonimizacją i woła nową `Accounts::purge_client_account()`, która **usuwa konto** (unieważnia sesje +
  `wp_delete_user`, e-mail/login/nazwisko znikają z `wp_users`). Kasuje **wyłącznie czyste konto klienta**
  (`mp_client`); konta personelu/admina podpięte po e-mailu (EDGE `ensure_for_customer`) oraz konta wciąż
  spięte z innym nieanonimizowanym klientem są nietknięte. Test `c5-rodo`: asercja skasowania z `wp_users`
  + asercja ochrony konta personelu (21/0).

### Added
- Intake (C) — **rate-limit żądań magic-linku (logowanie)** (`RateLimit::check_login`, osobne liczniki od
  formularza zgłoszeń): domyślnie 5 żądań/15 min na IP + 5/godz. na e-mail. Chroni skrzynki klientów przed
  zalewem linkami i endpoint przed nadużyciem (OWASP anti-automation — hardening poza specyfikacją, standard
  bezpieczeństwa). Komunikat neutralny (zero enumeracji kont), progi nadpisywalne filtrem
  `mp_intake_login_rate_limits`, źródło IP przez `mp_intake_client_ip`. Test `c17-rate-limit-login` (5/5).

### Changed
- Automator (D) — **konfiguracja checklist i szablonów: surowy JSON → formularz** (poprawka #2 z audytu:
  UX/profeska, poza specyfikacją — specyfikacja wymaga funkcji, nie sposobu konfiguracji). Panel „Automatyzacje MP"
  renderuje **builder per rodzaj sprawy** (pola klucz/etykieta[/treść] + „+ dodaj" / „×" usuń) zamiast
  wklejania JSON. **Kontrakt backendu NIETKNIĘTY** — JS składa te same dane do ukrytego pola `payload`,
  ten sam handler + walidacja (zero regresji: `d-p35` 20/0). Surowy JSON zostaje jako fallback w sekcji
  „Zaawansowane: edytuj jako JSON" (działa też bez JS). Testy: `c18-config-form-render` (14/0) + żywy test
  serializacji JS (Playwright: edycja+dodanie wiersza → poprawny JSON, 4 rodzaje).
- Wymagania środowiska doprecyzowane wg specyfikacji klienta: `Requires at least` obniżone **6.9 → 6.0**
  (specyfikacja: „WordPress 6.x" = 6.0 i nowsze; kod używa tylko stabilnych API). Dodana sekcja **Requirements**
  w readme (WordPress 6.x, PHP 8.1+, MySQL 8.0+/MariaDB 10.6+, **HTTPS** — passwordless login + dane klienta,
  **WP-Cron** — SLA/przypomnienia/eskalacje, importy, retencja). `Tested up to` bez zmian (6.9).
  Poprawka literówki formatu numeru w readme intake: `SRV/YYYY/NNNNN` (5 cyfr, spójnie z v0.5.0).

### Added
- Automator (D) — **przebieg krok 5: silnik reguł NADAJE priorytet.** Nowa akcja reguły
  `set_priority` (na `case_created`) ustawia priorytet sprawy wg warunku (np. kategoria/rodzaj)
  przez kontrakt C `mp_case_set_priority` (low/normal/high). Priorytet nadawany PRZED wierszem SLA
  (RuleEngine hook 10 < Sla 20) → pierwszy termin liczy się z nadanego priorytetu (high = krótszy).
  Idempotentny (ten sam priorytet = bez zdarzenia), waliduje (INVALID_PRIORITY), loguje `PRIORITY_CHANGED`.
  Domyślnie brak reguły → priorytet `normal` (politykę konfiguruje admin, jak pulę auto-przydziału).
  Test `d-p31-priorytet`.
- Automator (D) — **przebieg krok 8: raport końcowy przy zamknięciu.** Przy przejściu sprawy w status
  `zamknięte` D składa podsumowanie (numer SRV, rodzaj, data zamknięcia, czas obsługi, podziękowanie —
  klient-friendly, NO-PII) i dopisuje **wpis systemowy** przez `mp_case_add_system_message` (widoczny w
  panelu klienta i na karcie). Zdarzenie `CLOSING_REPORT_GENERATED` w rejestrze D. Zmiana nie-końcowa
  nie generuje raportu. Zachowanie strukturalne (gwarancja, nie reguła). Test `d-raport-koncowy`.

## [0.5.0] - 2026-07-24

Checkpoint „3 pluginy spec-complete" (pre-release). Weryfikacja specyfikacji klienta 1:1
dla wszystkich 3 pluginów (6/6 każdy) + karta pracy personelu, drobne poprawki i domknięcia
z audytu. Projekt NADAL w rozwoju — kolejne poprawki przed v1.0.0 (oddanie).

### Added
- Automator (D): **powiadomienie PRACOWNIKA przy zmianie statusu** (spec „powiadomienia dla klienta
  i pracownika po każdej ważnej zmianie") — dotąd zmiana statusu mailowała tylko klienta. Nowa domyślna
  reguła `status_changed → agent` (szablon `status_changed_staff`) informuje **przypisanego** pracownika.
  **SELF-SKIP:** gdy status zmienił SAM przypisany pracownik, nie dostaje maila o własnej akcji
  (`recipient_ref=agent_self`); zmiana przez koordynatora/innego → mail dochodzi. Seed **idempotentny per
  `system_key`** (bump `SEED_VERSION`→2 DOSIEWA nową regułę bez duplikowania na upgrade — bez reaktywacji).
  Testy `d-p33e-mail-pracownik` + idempotencja w `d-seed-regul`.
- Karta sprawy (C): **sekcja „Produkt i gwarancja"** — kontrakt B->C `mp_product_details` (Registry
  wystawia detale produktu po ID: model, nr seryjny, dokument+data zakupu, gwarancja do, **status
  gwarancji liczony z daty** aktywna/wygasła/brak-danych, flaga zarchiwizowany). Karta nie siega w
  tabele B (luzne wiazanie). `mp_case_get_context` wystawia teraz `product_registry_id` (bylo czytane
  wewnetrznie, nie zwracane). Degraduje gdy modul B nieaktywny / sprawa bez produktu. Test `b-product-details`.
- Intake (C): **ekran pracy personelu „MP: Sprawy" — karta sprawy (specyfikacja krok 7)**. Domkniecie luki #1
  audytu adwersaryjnego (2026-07-24): personel nie mial GDZIE obslugiwac potwierdzonej sprawy. Teraz:
  **lista spraw** (`WP_List_Table`, kolumny nr/klient/rodzaj/status/przydzielony/termin-SLA/utworzono,
  filtry status/rodzaj/przydzielony + „moje"/„nieprzydzielone", wyszukiwarka po nr/kliencie, sortowanie,
  paginacja; model B — caly personel widzi wszystkie zweryfikowane sprawy) oraz **karta sprawy**
  (opis zgloszenia z `form_data` · dane klienta · zalaczniki · wiadomosci · **oS czasu zdarzen** ·
  **checklista interaktywna**). **Akcje personelu** (admin-post, KAZDA z capability + nonce): zmiana
  statusu (optimistic-lock `expected_status` => `STATUS_CONFLICT`, powod przy odrzuceniu), odpowiedz do
  klienta (szablony D wypelniaja pole), przydzial — **TYLKO koordynator/administrator** (pracownik `mp_agent`
  nie przydziela: 403). Kazda decyzja ląduje na osi (`case_events`) + maile P3.3. Nowe kontraktowe filtry
  **D->C** (`CaseCardApi`): `mp_case_checklist_state` / `mp_response_templates` / `mp_render_response_template`
  / `mp_case_deadline` (karta nie siega w tabele D). Nowe metody read C: `CaseRepo::query_for_staff` /
  `form_data_for_case`, `CaseEvents::for_case`. Testy e2e `c-case-card` (19) + `c-case-actions` (16, macierz
  capability+nonce). Zweryfikowane na zywo: klikacz admin + `mp_agent` (panel przydzialu ukryty pracownikowi).
- Registry (B): **kategoria produktu** (domkniecie specyfikacji P1.2/P3.1 po stronie danych) — kolumna `category`
  (migracja v2 `maybe_upgrade`, BEZ reaktywacji; istniejace wiersze => `inne`), slownik 4 kategorii
  (audio / agd / elektronarzedzia / inne; konfigurowalny filtrem `mp_product_categories`), import CSV z kolumna
  `kategoria` (WSTECZNIE ZGODNY — stary CSV bez niej => `inne`; nieznana => `inne`, bez przerwania importu),
  oraz hak kontraktowy `mp_product_category` (Intake `get_context.kategoria` => os przydzialu w Automatorze).
  Test e2e `b-kategoria`. Przydzial wg kategorii udowodniony end-to-end (test `d-p31-kategoria`).
- Intake (C): **formularz P1.2 — pola wg kategorii produktu**. Dropdown kategorii na formularzu; dodatkowe pola per
  kategoria (sensowne domyslne + konfigurowalne filtrem `mp_intake_category_fields`); `fields_for($kind, $category)`
  ADDYTYWNIE (bez kategorii = pola rodzaju, ZERO regresji #15); zapis pol kategorii do `form_data`; walidacja serwera
  + JS-dynamika (pokazuje pola wg rodzaju ORAZ kategorii). Test e2e `c-kategoria-formularz`.
- Intake (C): **listener `mp_product_active_cases_count`** — domkniecie specyfikacji l.50 (B5: „brak mozliwosci
  usuniecia produktu powiazanego z aktywna sprawa"). Registry (B) mial juz blokade (`Archive.php`) + akcje
  w adminie, ale brakowalo strony C odpowiadajacej liczba spraw => archiwizacja ODMAWIALA ZAWSZE (fail-closed
  bez listenera, nawet dla produktu bez spraw). Teraz Intake liczy sprawy NIE-TERMINALNE produktu
  (`CaseRepo::active_cases_count_for_product`); >0 => Registry odmawia z komunikatem, 0 => archiwizuje
  (soft-delete: `archived=1` + `deleted_at`). Test e2e `b5-usuwanie-produktu` (blok / OK / fail-closed).

### Fixed
- Automator (D): **cicha utrata konfiguracji przy błędnym JSON** (znalezisko audytu 24.07) — panel zapisywał
  config checklist/szablonów z surowego `<textarea>`; błędny JSON → `json_decode` null → zapis PUSTEGO
  configu bez ostrzeżenia. Teraz błędny JSON (składnia albo nie-obiekt) przy niepustej treści NIE nadpisuje
  (poprzednia konfiguracja zachowana) + komunikat błędu na panelu; puste pole = świadome wyczyszczenie.
  Dotyczy `ChecklistTemplates`/`ResponseTemplates`. Test `d-config-json-guard`.
- Automator (D): **rejestr zdarzeń zalewany `SWEEP_RUN`** (znalezisko audytu 24.07) — cron SLA co 5 min
  logował `SWEEP_RUN`, przez co zdarzenia biznesowe tonęły. Domyślny widok panelu ukrywa teraz `SWEEP_RUN`
  (`WHERE event_type <> 'SWEEP_RUN'`), a link „Pokaż techniczne" odsłania pełny log (toggle zachowany w paginacji).
- Registry (B): **brak auto-migracji przy AKTUALIZACJI** — `mp-warranty-registry` nie miał `maybe_upgrade`
  na `admin_init` (wzorzec obecny w Intake i Automator), więc update dodający migrację (v1→v2 kolumna
  `category`) NIE stosował jej bez deaktywacji+aktywacji → schemat zostawał stary → `SELECT category`
  sypał błędem DB. Dodano `Lifecycle::maybe_upgrade` (gated `Schema::LATEST`) + hook `admin_init` +
  `Schema::LATEST` — spójność 3 wtyczek. Regresja: `testy/e2e/registry-maybe-upgrade.sh` (migracja
  bez reaktywacji). Złapane audytem adwersaryjnym 2026-07-24.
- Automator (D): **flaky dedup maili `d-p33d`** — `MailDedup` kluczował po WYRENDEROWANYM body, a body niesie
  `{{data}}` (`wp_date('Y-m-d H:i')`, granica minuty). Dwie IDENTYCZNE notyfikacje sekundy od siebie na granicy
  minuty → różny body → różny hash → dedup gubił duplikat (~1/60 runów). Fix W PRZYCZYNIE: `MailTemplates::render`
  zwraca dodatkowo `dedup_key` = treść BEZ zmiennego `{{data}}` (numer/status/rodzaj podstawione, data pominięta);
  `RuleEngine` dedupuje po `dedup_key`, nie po `body`. Mail do wysłania dalej niesie prawdziwą datę. Asercja-test pilnujący
  w `d-p33d-dedup`.

- Intake (C): **kolumna „Sprawy" i wyszukiwarka po kliencie w Rejestrze** — Intake nie rejestrował listenerów
  kontraktowych `mp_case_count_by_product` i `mp_customer_find_products` → kolumna „Sprawy" pokazywała „moduł
  spraw nieaktywny" mimo aktywnego Intake, a wyszukiwarka po kliencie (specyfikacja **P2.6**) była WYŁĄCZONA. Dodane
  `CaseRepo::case_count_by_product` (`{total,active,closed,rejected}`, unverified wykluczone) +
  `find_products_for_customer` (`{ids,truncated,limit}`) + rejestracja obu filtrów. Test `c-count-search-hooki`.
  Znalezione KLIKACZEM admina (bramka) — automaty testowały haki osobno, nie zintegrowany panel.

## [0.4.0] - 2026-07-23

Moduł D (Automator) kompletny: silnik reguł + auto-przydział, statusy, maile, SLA (1–4),
checklisty + szablony, eksport CSV, panel admina — spięte z Intake (C) i Registry (B)
kontraktem hooków. Plus szlif i naprawy Intake (C) z fazy pre-release.

### Fixed
- Automator (D): flaga #8 SLA (retroaktywność sweepa) — pierwszy przebieg po reaktywacji /
  instalacji nie zalewa lawiną: sprawy już po terminie dostają JEDNO powiadomienie (eskalacja),
  przypomnienie tłumione = marker `reminder_sent_at` zajęty BEZ maila i BEZ `mp_sla_notified`
  (zero `SLA_REMINDER_SENT` na osi C); przy masie po terminie — 1 zbiorczy digest. Test d-p34b/c.
- Intake (C): kontrast WCAG panelu klienta #13 (`AccountPage`) — kolory podniesione do ≥ 4.5:1.
- Intake (C): szlif frontu klienta (polerka, bez zmian logiki). (1) Pasek admina WP **ukryty** klientowi
  `mp_client` (filtr `show_admin_bar` + `Accounts::is_client_only`), personel/admin widzą go dalej.
  (2) Arkusz `assets/css/intake.css` (enqueue wersjonowany) — etykiety nad polami, pola pełnej szerokości,
  czytelne karty panelu (koniec „etykieta[pole]"). (3) CTA „Przejdź do panelu zgłoszeń" na stronie
  potwierdzenia (URL panelu dynamicznie z `AccountPage::url()`, nie hardkod). Test c16. Flaga #16.
- Intake (C): formularz zgłoszenia dynamiczny wg rodzaju po stronie klienta (specyfikacja wymóg #1). Render
  UNII pól wszystkich rodzajów (każde pole raz, `data-mp-field`) — m.in. `return_reason` (zwrot) jest w
  DOM od razu, więc zwrot składa się za 1. razem (wcześniej pole renderowane dopiero PO błędzie). Nowy
  skrypt `assets/js/intake-form.js` (enqueue wersjonowany, config przez `wp_localize_script`) pokazuje/
  ukrywa pola i toggluje `required` przy zmianie „Rodzaj". Serwer pozostaje źródłem prawdy —
  `FormConfig::fields_for(kind)` waliduje na submit bez zmian (JS = progressive enhancement; no-JS też
  wyśle). Test c-form-dynamic + dowód w przeglądarce. Flaga #15.
- Intake (C): wyjątki gwarancyjne na osi zdarzeń sprawy — listener `mp_warranty_exception_changed`
  (B→C) zapisuje `EXCEPTION_APPLIED` (stan `active`) / `EXCEPTION_REVOKED` (stan `revoked`) do
  `wp_mp_case_events`; payload strukturalny `{exception_id}` (NO-PII, bez `reason`), `case_id=NULL`
  (wyjątek globalny) → no-op (EVENT_MODEL.md). Wcześniej decyzja gwarancyjna nie zostawiała śladu na
  osi czasu sprawy. Test c11 + blok-S S4. Flaga #11.
- Intake (C): rate-limit po REALNYM IP klienta — nowy filtr `mp_intake_client_ip`
  (`RateLimit::client_ip()`, domyślnie `REMOTE_ADDR`). Za reverse-proxy/Cloudflare wszyscy klienci
  mieli IP proxy = 1 adres → rate-limit blokował wszystkich; wdrożeniowiec podpina zaufane źródło IP
  (nota: SECURITY.md §7). Nie ufamy ślepo `X-Forwarded-For` (spoofowalny). Test c6c §4. Flaga #10.
- Intake (C): RODO — poprawny terminalny status „zamknięte" (był bez ogonka `zamkniete` w
  `TERMINAL_STATUSES` → `has_active_case()` nigdy nie widziała zamkniętej sprawy jako terminalnej →
  eraser odraczał anonimizację klienta w nieskończoność, łamiąc §4 specyfikacji). Realny slug to `zamknięte`
  (z ę, jedyna droga zapisu = `change_status`). Testy c5-rodo/c6b/c6b2b przepięte na REALNĄ
  `change_status` (seed literówki maskował błąd — zielone kłamały). Flaga #14. (pre-release v0.3.0)

### Added
- Automator (D): schemat D — 4 tabele (`wp_mp_workflow_rules`, `wp_mp_case_sla`,
  `wp_mp_case_checklists`, `wp_mp_workflow_events` = rejestr operacji APPEND-ONLY, NO-PII);
  migracje bez reaktywacji (`maybe_upgrade`), uninstall opt-in kasuje wszystkie artefakty D
  i nic cudzego (kanarki + role współdzielone nietknięte). Test d1-schema + kryteria odbioru D.
- Automator (D): P3.1 silnik reguł + auto-przydział round-robin — reguły STRUKTURALNE
  (trigger/warunek/akcja, zero eval), kursor RR per reguła, nasłuch `mp_case_created`;
  seed reguły domyślnej przydziału przy aktywacji (jednorazowo, skasowana nie wraca).
- Automator (D): P3.2 statusy własne D — provider `mp_registered_statuses` (rdzeń 7 + własne,
  guard długości sluga ≤20 = `VARCHAR(20)`), akcja `change_status` przez kontrakt C oraz
  **guard pętli reguł** (`RULE_LOOP_BLOCKED`, mutacja przy depth≥1 zablokowana, zero lawiny).
- Automator (D): P3.3 maile powiadomień — `Mailer` (bezpieczny egress: strip CRLF, sanityzacja
  odbiorcy, NO-PII w rejestrze), szablony `MailTemplates` z markerami, powiadomienia klient/
  pracownik po ważnej zmianie; notyfikacja przydziału (`mp_case_assigned` → mail agenta),
  reguły `message_added` (klient→agent, staff→klient, guard `from===to`), dedup-okno
  identycznych maili zdarzeniowych (best-effort, per typ).
- Automator (D): P3.4 SLA — księgowość `wp_mp_case_sla` (termin liczony od `status_changed_at`)
  + `SlaConfig` + notify send-then-claim (SLA-1); sweep cron 5-min (`GET_LOCK`, przypomnienia
  przed / eskalacje po terminie, SLA-2); resync po reaktywacji + digest bez lawiny
  (>próg = 1 zbiorczy mail do koordynatora, SLA-3); akcja admina „Przelicz SLA"
  (backend-handler-only, nieretroaktywność, audyt `SLA_RECALCULATED`, SLA-4).
- Automator (D): P3.5 checklisty per typ + szablony odpowiedzi (backend-handler-only) —
  checklisty konfigurowalne per rodzaj, **toggle przez hook `mp_case_checklist_authorize`**
  (własność/rolę egzekwuje C), stan w `wp_mp_case_checklists` (`step_label` zamrożony);
  szablony odpowiedzi per typ z markerami i WHITELIST markerów widoczną adminowi;
  konfiguracja przez `admin_post` (capability system-admin + nonce + audyt `CONFIG_CHANGED`).
- Automator (D): P3.6 eksport CSV spraw + zestawienia (backend-handler-only) — capability
  koordynator/system-admin + nonce + audyt `EXPORT_GENERATED`; **anti-formula-injection**
  (pola `=+-@`/TAB/CR → apostrof), nagłówki `text/csv`+`nosniff`+`Content-Disposition`,
  BOM UTF-8; dane WYŁĄCZNIE przez kontrakt `mp_cases_query` (minimalizacja PII — bez kontaktu);
  zestawienie: liczba per status, czas obsługi, rozkład powodów odrzuceń.
- Automator (D): panel admina D — menu `mp-automator` (widoczne koordynator/system-admin;
  klient/pracownik/anon nie widzą), spina handlery Przelicz SLA + Eksport CSV + konfigurację
  checklist/szablonów, listy read-only (reguły, statusy przez `mp_all_statuses`, rejestr
  zdarzeń paginowany), obrona warstwowa (capability na stronie ORAZ per-przycisk), a11y-lite.
- Kontrakt C↔D: funkcje kontraktowe spraw (jedyna droga D po dane/zapis C — D nigdy nie
  dotyka tabel C, pilnuje linter): `mp_case_get_context`, `mp_case_assign`,
  `mp_case_change_status` (optimistic-lock + STATE_MACHINE), `mp_cases_query` (paginowane
  chunk 500, respekt roli, pola zminimalizowane), `mp_case_checklist_authorize`
  (ownership + event `CHECKLIST_ITEM_TOGGLED`), `mp_all_statuses` (read-only lista statusów
  C→D, degrade gdy Intake OFF).
- Testy modułu D w CI: seria `d-*` (schemat, hooki, P3.1–P3.6), kryteria odbioru D (uninstall zero-śladu +
  kanarki + tryb degraded C/B OFF + macierz uprawnień NEGATYWNA anon/subscriber/klient/agent),
  panel admina (widoczność per rola); odślepione niezmienniki BLOK-S (E2E/tabletop/bug-hunt/
  a11y) na P3.1/P3.2.
- Intake (C): zgody RODO + wiadomości + eraser/exporter (P1.5 + RODO) — `wp_mp_consents` z PEŁNYM
  TEKSTEM zgody zamrożonym przy zbieraniu (rozliczalność art. 7) + wycofanie self-service
  (`CONSENT_WITHDRAWN`, art. 7(3)); zgoda wymagana w formularzu, podpinana do klienta po weryfikacji
  (`CONSENT_RECORDED`); `wp_mp_messages` — historia wiadomości klient↔serwis (redagowalne przy RODO,
  event `mp_case_message_added` bez treści; listener `mp_case_add_system_message` dla D); eraser i
  exporter wpięte w natywne narzędzia WP (Narzędzia → Dane osobowe): eraser szuka PO EMAILU,
  anonimizuje klienta (pola czyszczone, `anonymized_at`, odpięcie konta WP, wiersz zostaje), redaguje
  messages + form_data-PII + `warranty_exceptions.reason` (B przez filter), kasuje załączniki, emituje
  `PII_REDACTION`/`CUSTOMER_ANONYMIZED`; **sprawa aktywna/okno roszczeń → odroczenie EN BLOC**
  (`items_retained`); exporter: dane klienta + sprawy + wiadomości + metadane załączników; test C5 w CI.
- Intake (C): załączniki twardo (spec T5) — MIME PO TREŚCI (finfo; brak ext-fileinfo = admin
  notice + odmowa), limity 8 MB/plik + 5/zgłoszenie + globalny CAP przestrzeni pending 2 GB;
  katalog `uploads/mp-attachments/` z deny-ALL + losowe nazwy UUID BEZ rozszerzenia; strip EXIF/GPS
  (imagick → fallback reenkod GD) dla JPEG/PNG/WebP; `retention_until` liczone z rodzaju sprawy
  (reklamacja 24 / naprawa·zwrot 12 / zapytanie 3 mies.) + cron retencji (kasuje wiersz + PLIK);
  serwowanie przez endpoint PHP z bramką IDOR (personel każdy; klient tylko własna sprawa verified;
  unverified = tylko personel) + Content-Type z finfo + nosniff; kasacja ZAWSZE = wiersz + plik
  z dysku; pole załączników w formularzu; sprzątanie katalogu przy uninstall (warstwa i);
  test C4 w CI (upload z EXIF, deny-ALL, IDOR/ownership, retencja).
- Intake (C): front zgłoszenia (P1.1 + antyspam część) — renderowanie formularza BLOKIEM Gutenberga
  `mp/intake-form` (+ shortcode fallback, lekcja: buildery nie renderują shortcode), WCAG-lite
  (label per pole, aria-describedby, role=alert/status); auto-strona tworzona przy aktywacji
  z ODCISKIEM PALCA (kasowana w uninstall tylko gdy nieedytowana ręcznie); handler zgłoszenia
  (admin-post): nonce + honeypot + pułapka czasu (<2 s = bot, cichy odrzut) → CaseRepo::create
  → mail z magic-linkiem → komunikat NEUTRALNY (bez enumeracji); potwierdzenie magic-linkiem (GET)
  na własnej minimalnej stronie (Cache-Control: no-store, Referrer-Policy: no-referrer, nosniff,
  SAMEORIGIN), neutralnej (SRV tylko mailem) + 2. mail z numerem SRV po weryfikacji; nagłówki
  bezpieczeństwa na stronie formularza; test C3 w CI (wp server + przechwyt wp_mail).
- Intake (C): formularz dynamiczny + walidacje (P1.1/1.2/1.4) — PLASKI schemat pol per RODZAJ
  sprawy (reklamacja/naprawa/zapytanie/zwrot; `FormConfig`, zero logiki warunkowej, admin nadpisze
  opcja autoload=no); walidacja SYNCHRONICZNA PRZED insertem (odmowa = bledy {field, reason_code},
  NIC nie ldauje w bazie): dokument zakupu, serial (ksztalt), data zakupu (format Y-m-d, nie
  z przyszlosci, nie sprzed 1990), email, pola wymagane per rodzaj; form_data buduje etykiety
  i flagi pii_sensitive ZE SCHEMATU z chwili zlozenia (render historyczny); komenda `wp mp
  case-create` rozszerzona (--document/--date/--return-reason); test C2 w CI.
- Intake (C): rdzen sprawy serwisowej — schemat 7 tabel (customers, service_cases, case_events,
  messages, attachments, consents, srv_counters) z migracjami; atomowy licznik numeru sprawy
  SRV/RRRR/NNNNN (`INSERT ... VALUES(year, LAST_INSERT_ID(1)) ON DUPLICATE KEY UPDATE ...` +
  UNIQUE na case_number — zero duplikatow przy zbieznosci); narodziny sprawy wg flow z krytyki:
  zgloszenie -> sprawa `unverified` (status NULL, SRV nadany od razu, snapshot gwarancji z chwili
  zgloszenia NIOSACY PARTIE, token jednorazowy = tylko HASH w bazie, TTL 24h) -> potwierdzenie
  magic-linkiem ATOMOWE (UPDATE-warunkowy: token zywy, w oknie 72h) -> DOPIERO TERAZ event
  CASE_CREATED (append-only, NO-PII) + akcja `mp_case_created` + utworzenie/podpiecie klienta
  (Automator nigdy nie widzi niepotwierdzonych); form_data z etykietami z chwili zlozenia
  (render historyczny) + flaga pii_sensitive per pole; komendy `wp mp case-create` / `case-verify`;
  test C1 w CI (job e2e-import: SRV wspolbiezny 30 procesow + narodziny + snapshot z partia).
- Registry (B): tabele produktow/eventow/wyjatkow/jobow importu z migracjami, silnik statusu
  gwarancji (`mp_warranty_check`), silnik importu CSV odporny na polskiego Excela (Windows-1250,
  separatory `;`/`,`, raport bledow per wiersz, joby z lockiem INSERT-pod-UNIQUE i tokenem UUID,
  batche transakcyjne po 100 z wznowieniem z offsetu), komenda `wp mp import-products`.
- Registry (B): ekran admina "Import produktow z CSV" — upload przez admin-post (PRG),
  pasek postepu i petla batchy przez AJAX (TEN SAM silnik co WP-CLI), przycisk "Wznow"
  (przejecie joba = nowy token, stare batche dostaja odmowe), pobieranie raportu bledow
  przez PHP z capability (nonce + nosniff), stale-detekcja przy renderze, ostrzezenie
  gdy serwer nie ma iconv/intl.
- Registry (B): wyjatki gwarancyjne — CRUD stanu wg precedensu kontraktu (max 1 aktywny per
  zakres, per-sprawa > globalny, wylacznie mp_system_admin, "expired" wyliczane z valid_until
  nigdy zapisywane, valid_until > NOW przy CREATE), emisja `mp_warranty_exception_changed`
  PO COMMIT (5 argumentow), historia produktu `wp_mp_product_events` (append-only, payload bez
  reason, pola PII w diffach jako {field, changed:true}), listenery `mp_cases_data_erased`
  (rewokacja per-sprawa, globalne zostaja) i `mp_privacy_redact_for_customer` (redakcja reason),
  komendy `wp mp exception-add` / `wp mp exception-revoke`.
- Registry (B): wyszukiwarka produktow (serial/model/faktura przez esc_like — `_`/`%` szukaja
  literalnie; "po kliencie" mechanika odwrocona P2.6 przez `mp_customer_find_products` z obsluga
  truncated="doprecyzuj"; degraded bez Intake = pole klienta nieaktywne), archiwum produktu
  (soft delete FAIL-CLOSED: bez `mp_product_active_cases_count` odmowa; wpis w historii),
  ekrany admina: lista produktow (WP_List_Table, status gwarancji wyliczany + badge wyjatku,
  liczba spraw z C albo uczciwe "brak danych") za `mp_agent`, wyjatki gwarancyjne (lista +
  przyznanie + cofniecie) i archiwizacja za `mp_system_admin`; import przeniesiony do submenu
  Rejestru MP; CLI `wp mp product-archive` / `product-restore`.
- Registry (B): `wp mp import-resume <job>` (wznowienie przerwanego importu z CLI — ta sama
  mechanika co "Wznow" w UI) oraz testy kryteria odbioru modułu B w CI (job e2e-import na zywym WP 6.9.4
  + MariaDB 11.8): import 10 000 wierszy, kill -9 klienta w polowie + wznowienie z offsetu
  (ksiegowosc joba == wiersze w bazie, zero duplikatow), partia CSV->mp_warranty_check,
  negatywne uprawnienia, snapshot-uninstall (default OFF: dane zostaja; opt-in: tabele znikaja,
  role i caps zdjete).
- Role mp_* dostaja swoje capabilities (cap-marka per rola) przy aktywacji; wbudowany
  administrator dostaje caps personelu (zdejmowane przy uninstall ostatniego pluginu).
  Pelna macierz uprawnien doprecyzuje SECURITY.md (D2).
- Fundament repo (D1): szkielety 3 pluginow (bootstrap OOP, cykl zycia, wspolne role mp_*, i18n),
  wspolna biblioteka `lib/mp-common` (kopiowana do pluginow przy buildzie ze stemplem namespace),
  build ZIP-ow z BUILD-INFO, CI (php -l matrix 8.1-8.5, PHPCS/WPCS, PHPStan lvl 6, Plugin Check,
  linter cudzych tabel, gitleaks), testy jednostkowe smoke, srodowisko testowe Docker (WP 6.9.4, MariaDB 11.8,
  Mailpit) z realnym cronem i SMTP dev.
