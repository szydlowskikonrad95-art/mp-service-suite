=== MP Warranty & Serial Registry ===
Requires at least: 6.0
Tested up to: 7.0
Requires PHP: 8.1
Stable tag: 1.3.12
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Product, serial number, production batch and warranty registry with CSV import, warranty status and admin search.

== Description ==

Stores products, serial numbers, production batches and warranty periods in dedicated database tables. Imports registry data from CSV files (resilient to regional encodings and separators), determines warranty status automatically (active, expired, no data, verification required), detects serial number reuse across cases, supports admin-approved warranty exceptions and provides an administrative search by serial, customer, invoice or model.

Part of the MP Service Suite (three cooperating plugins; each one also works standalone in a reduced mode, never causing fatal errors). The plugin UI and e-mails are in Polish (source language); every string is internationalized via the text domain, so the plugin can be translated to other languages. No separate .po/.mo is bundled because Polish is the base language.

== Requirements ==

* WordPress 6.x (6.0 or newer)
* PHP 8.1 or newer
* MySQL 8.0+ or MariaDB 10.6+
* HTTPS -- the suite handles passwordless (magic-link) login and customer personal data.
* WP-Cron enabled -- scheduled tasks rely on it: SLA deadlines, reminders and escalations (Workflow Automator), background CSV imports (Registry) and data-retention cleanup (Intake).

Developed and tested on WordPress 6.9.4, PHP 8.1-8.5, MariaDB 11.8. Additionally, on 2026-07-27 the release package passed a from-scratch control installation on WordPress 7.0.2 (PHP 8.2).

== Frequently Asked Questions ==

= What should the CSV import file look like? =

A ready-to-use sample ships with the plugin: `przyklady/przyklad-import-produktow.csv`. The import screen also links to it ("Pobierz przykładowy plik CSV").

Only the serial column is required (header `serial`, `numer_seryjny` or `sn`). Optional columns: `model`, `partia` (`batch`), `faktura` (`dokument_zakupu`), `data_zakupu`, `gwarancja_do` (`warranty_until`), `kategoria`. Without `gwarancja_do` the warranty status cannot be computed and the product shows "no data".

Dates: `2026-04-12` or `12.04.2026` (Polish Excel). Separator: `;` or `,`, detected automatically. Encoding: UTF-8 or Windows-1250 (the latter needs the iconv or intl extension; otherwise the file is rejected instead of silently mangling Polish characters). Maximum file size: 8 MB -- split larger registries, imports are resumable.

= Does re-importing a file update existing products? =

No. The import ADDS products. A serial number already present in the registry is reported in the error report as a duplicate and the existing entry is left untouched. Serial comparison ignores spaces, dashes and letter case, so `SN-AUD-1001` and `sn aud 1001` are the same product.

== Changelog ==

= 1.3.13 =
Poprawki po przeglądzie kontrolnym. Numer wydania podbije osobny krok — poniżej zmiany w TYM module.

Ekran importu:
* **Tabela „Ostatnie importy" nadąża za banerem.** Po zakończeniu importu baner mówił
  „zakończony 8 z 8", a tabela tuż pod nim dalej „w trakcie, 0/8" — aż do ręcznego odświeżenia
  strony. Wiersz importu odświeża się teraz sam, razem z liczbami i odnośnikiem do raportu błędów.

Menu:
* **„Rejestr MP" stoi w menu bocznym obok pozostałych ekranów MP**, a nie na samym dole, pod
  ustawieniami WordPressa — instrukcja wymienia cztery ekrany jednym tchem i teraz tak też wyglądają.

= 1.3.12 =
Wydanie po zewnętrznym audycie całego pakietu. Poniżej to, co zmieniło się w TYM module.

Bezpieczeństwo danych:
* **Raport błędów importu nie wypuszcza już formuły do arkusza kalkulacyjnego.** Wartość z pliku
  zaczynająca się od znaku formuły trafiała do raportu tak, jak stała — a arkusz wykonuje ją przy
  otwarciu. Waga: krytyczna.
* **Nieudany zapis do dziennika rejestru zatrzymuje operację** zamiast przepuścić ją dalej.
  Wcześniej zmiana danych mogła zostać zatwierdzona bez wpisu, który ma być jej dowodem.

Dostępność (WCAG 2.1 AA):
* **Ekran importu ogłasza postęp, zakończenie i błąd także czytnikowi ekranu.** Dotąd pasek postępu
  zmieniał się w ciszy — osoba niewidoma nie wiedziała, czy import jeszcze trwa.

Ekrany i praca administratora:
* **Administrator widzi wszystkie udzielone wyjątki gwarancyjne** na jednym ekranie, a nie tylko
  wyjątek produktu, który akurat otworzył.
* **Historia egzemplarza jest widoczna, a nie tylko zapisywana** — nowy ekran pokazuje, co się
  z danym produktem działo, kto i kiedy zmienił dane. ⚠️ Domknięta jest strona rejestru: **lista
  spraw danego egzemplarza i wskazanie, z którą sprawą coś jest duplikatem, nadal nie istnieją**
  — kontrakt między wtyczkami oddaje w tym miejscu wyłącznie liczbę.
* **Koordynator serwisu ma dostęp do Rejestru produktów** (wcześniej ekran wpuszczał pracownika,
  a odbijał jego przełożonego).
* **Import mówi, które pole jest za długie i jaki jest limit**, zamiast odrzucać wiersz bez powodu.
  ⚠️ To jest część zarzutu: komunikaty przy pozostałych regułach importu zostają bez zmian.
* Wpis w dzienniku rejestru i odpowiedzi kontraktowe **niosą wersję swojego kształtu** — moduł,
  który je czyta, wie, z jaką wersją danych rozmawia.
* Poprawka stylu albo skryptu dociera do przeglądarek, zamiast zostać w pamięci podręcznej.
* Nagłówki przy blokach ekranu, wersja schematu i zbędna praca przy wczytywaniu — porządki.
* Wspólna dla pakietu warstwa ustawień: administrator ustawia statusy, terminy i reguły bez
  programisty.

Z kontroli na działającej instalacji (dwie dotyczą tego modułu):
* **Koordynator widział w menu pozycję „Rejestr MP", która go nie wpuszczała.** Jest ukryta
  temu, kto nie ma do niej prawa, zamiast otwierać drzwi i odsyłać z kwitkiem. ⚠️ Po aktualizacji
  koordynator, który tej pozycji nie miał używać, przestanie ją widzieć — to zmiana zamierzona.
* **Ekrany wyjątków gwarancyjnych i importu rozjeżdżały się na wąskim oknie.** Tabele przewijają
  się teraz w swoim obszarze, z zaczepem klawiatury, i mieszczą się na telefonie i na monitorze.
  Kolumn nie schowaliśmy: schowanie dałoby w pomiarze identyczny wynik co poprawne przewijanie,
  a kasowałoby kolumny na zawsze.

= 1.3.11 =
* Ekran „Wyjatki gwarancyjne" otwarty z menu (bez wybranego produktu) mowil tylko „wybierz produkt
  z listy Rejestru" i zostawial uzytkownika bez wyjscia. Teraz tlumaczy, czym jest wyjatek
  gwarancyjny i dlaczego ekran jest pusty, oraz daje przycisk „Przejdz do Rejestru MP".
* Dzialanie bez zmian — poprawka wygody obslugi.

= 1.3.10 =
* Wydanie zbiorcze pakietu: bez zmian w kodzie tego modułu, numer wersji podniesiony razem
  z pozostałymi. Poprawki językowe tego wydania (cytowana nazwa roli, etykieta przycisku
  w Rejestrze zdarzeń, nagłówek kolumny w tabeli statusów) dotyczą modułów Zgłoszenia MP
  i Automatyzacja MP.

= 1.3.9 =
* Instrukcja wdrozenia: nowy krok „schowaj formularz na czas przygotowan". Strona zgloszenia jest
  publiczna od chwili wlaczenia wtyczki, a instrukcja nie mowila, jak ja tymczasowo ukryc — przez
  co zgloszenie moglo trafic do systemu, zanim rejestr gwarancji i pula pracownikow byly gotowe.
* Dokumentacja: poprawiona sprzeczna liczba testow diagnostyki (bylo „42 testy" w jednym akapicie
  README, jest czternascie — tyle, ile wtyczki realnie rejestruja w Stanie witryny).
* Kontrola dokumentow w CI sprawdza teraz SPOJNOSC liczb w calym pliku, a nie tylko obecnosc
  poprawnej liczby w jednym miejscu (poprzednia wersja przepuszczala blad opisany wyzej).
* Dzialanie wtyczek bez zmian — wydanie dokumentacyjne.

= 1.3.8 =
* Poprawki języka na ekranach tego modułu: nagłówek kolumny „Job" zamieniony na „Import",
  komunikaty błędów importu mówią „ten import" zamiast „job", a „Niepełne dane batcha" —
  „Niepełne dane porcji importu".
* Godziny podawane w czasie UTC (tabela importów, wyjątki gwarancyjne) są teraz opisane zdaniem
  wyjaśniającym różnicę względem zegara w Polsce.
* Instrukcje (materiał wspólny dla pakietu): poprawione nazwy pozycji menu i filtrów (były
  nieaktualne względem panelu) oraz prawidłowa droga do wyjątków gwarancyjnych. Odświeżone
  zdjęcia w instrukcji administratora — w tym zdjęcie wyjątków gwarancyjnych, które wcześniej
  pokazywało pusty ekran zamiast działającej funkcji.

= 1.3.7 =
* Zmiana wylacznie w dokumentacji: raport dostepnosci (WCAG 2.1 AA) zostal powtorzony na
  paczce 1.3.6 pobranej z wydania, na WordPressie 7.0 i innym motywie. Wynik ten sam: zero
  naruszen na wszystkich trzech ekranach klienta. W kodzie wtyczki bez zmian.

= 1.3.6 =
* Zmiany wylacznie w instrukcjach dla klienta: wyjasnione SLA, anonimizacja, blokada
  integralnosci i link do zalogowania; §7.1 (SMTP) dostal gotowa tresc wiadomosci do dostawcy
  poczty. Poprawiony jeden zrzut ekranu (data po polsku). W kodzie wtyczki bez zmian.

= 1.3.5 =
* Listy w panelu (sprawy, produkty) pobieraja dane jednym zapytaniem na strone zamiast
  jednego na kazdy wiersz. Ekran spraw zszedl z 43 do 4 zapytan do bazy. Wyglad i dzialanie
  ekranow bez zmian.
* Poprawki w instrukcji: nazwa ekranu w menu (MP: Sprawy), opis ekranu MP: Niepotwierdzone,
  ostrzezenie przy poleceniu kopii bazy dla PIERWSZEJ instalacji.

= 1.3.4 =
* Wydanie porzadkowe dokumentacji: dwa zdania w dokumentacji technicznej opisywaly
  zabezpieczenia szerzej, niz robi to kod (automatyczne generowanie testow z kontraktu
  oraz test wspolbieznosci na 20 procesach). Zdania poprawiono tak, by opisywaly stan
  faktyczny. **Zero zmian w kodzie wtyczek.**

= 1.3.3 =
* Wydanie porzadkowe: dokument opisujacy kontrole jakosci deklarowal numer poprzedniej wersji.
  Kontrola wersji w skrypcie pakujacym obejmuje teraz WSZYSTKIE dokumenty dla klienta (wczesniej
  dwa wpisane z nazwy) i liczy, ile plikow objela.

= 1.3.2 =
* Import CSV: wiersz z niepełną liczbą kolumn trafia do raportu błędów, a nie do bazy z uciętymi
  danymi (wcześniej produkt wchodził bez daty zakupu i gwarancji).
* Import CSV: jeden nieprawidłowy bajt nie niszczy już polskich znaków w całym pliku.
* Import CSV: komórka z Enterem w cudzysłowach nie rozjeżdża wiersza.
* Raport błędów importu poprawnie cytuje wartości i nie ginie przy awarii w trakcie partii.
* Ekran importu: przyciski „Wznów" blokowane na czas operacji (dwa kliknięcia osierocały import).

= 1.3.1 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.3.0 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.5 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.4 =
* Import CSV odrzuca teraz wiersz, w którym gwarancja kończy się przed datą zakupu (najczęstsza literówka przy ręcznym uzupełnianiu). Wiersz trafia do raportu błędów z powodem, reszta pliku importuje się normalnie. Ta sama reguła obowiązywała już przy poprawianiu danych w panelu.

= 1.2.3 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.2 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.1 =
* Odinstalowanie kasuje teraz katalog roboczy importów (uploads/mp-imports/) razem z plikami wsadowymi i raportami błędnych wierszy. Wcześniej zostawały one na serwerze na zawsze, mimo że zawierają dane z rejestru (numery seryjne, faktury, daty zakupu).

= 1.2.0 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.1.0 =
* Nowość: ekran „popraw dane" przy produkcie — można poprawić model, partię, kategorię, dokument i daty (np. błędną datę gwarancji z importu). Każda zmiana zapisuje się w historii produktu: kto, kiedy, wartość przed i po. Numeru seryjnego nie da się zmienić, bo wiążą się z nim sprawy klientów.

= 1.0.3 =
* Paczka zawiera teraz część techniczną dla programisty (układ bazy, kontrakt między modułami, model zdarzeń, maszyna statusów, bezpieczeństwo) oraz źródła diagramów do edycji. Bez zmian w kodzie tego modułu.

= 1.0.2 =
* Wydanie porządkujące paczkę dla klienta: ujednolicona wersja w dokumentach i przegenerowany zrzut ekranu. Bez zmian w kodzie tego modułu.

= 1.0.1 =
* Nazwa czwartego statusu gwarancji ujednolicona z modułem zgłoszeń („wymagana weryfikacja") — ten sam stan nie nazywa się już różnie na dwóch ekranach.
* Wydanie zbiorcze pakietu: numer wersji podniesiony razem z pozostałymi modułami.

= 1.0.0 =
* Pierwsze wydanie dla klienta.
* Poprawna odmiana liczb w komunikatach („Produkt ma 1 aktywną sprawę" zamiast „1 aktywnych spraw").
* Sprzątanie plików importu odtwarza się samo, gdy zadanie cykliczne zniknie z WordPressa; Stan witryny ostrzega, gdy go brakuje.
* Po odinstalowaniu modułu zgłoszeń wyjątki gwarancyjne przypięte do spraw są cofane (sygnał kontraktowy zaczął realnie działać).

= 0.5.0 =
* Kontrakt mp_product_details (detale produktu + status gwarancji dla karty sprawy w Intake). Bez zmian w danych rejestru.

= 0.4.0 =
* Version aligned to MP Service Suite v0.4.0. No functional changes in this release (Registry unchanged; the release adds the Workflow Automator — see the suite CHANGELOG).

= 0.1.0 =
* Plugin skeleton: OOP bootstrap, lifecycle (activation/deactivation/uninstall), shared mp_* roles, i18n.
