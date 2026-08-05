=== MP Service Intake ===
Requires at least: 6.0
Tested up to: 7.0
Requires PHP: 8.1
Stable tag: 1.3.12
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Przyjmowanie zgłoszeń serwisowych i reklamacyjnych: dynamiczny formularz, numery spraw SRV, konto klienta, narzędzia RODO, ochrona przed spamem.

== Description ==

Przyjmuje zgłoszenia serwisowe i reklamacyjne przez formularz osadzony na stronie WordPressa. Pola formularza i wymagane załączniki dopasowują się do rodzaju zgłoszenia (reklamacja, naprawa, zapytanie techniczne, zwrot) oraz kategorii produktu. Każda sprawa dostaje odporny na wyścigi numer SRV/RRRR/NNNN.

Najważniejsze funkcje:

* Dynamiczny formularz frontowy (blok Gutenberga + shortcode `[mp_intake_form]`) z walidacją zależną od rodzaju zgłoszenia.
* Weryfikacja mailowa każdego zgłoszenia (jednorazowy magic-link, potwierdzenie przyciskiem — sam podgląd odnośnika nigdy nie potwierdza sprawy).
* Konto klienta (`mp_client`) z logowaniem bez hasła: bieżący status sprawy, historia wiadomości, edycja danych kontaktowych (art. 16 RODO) oraz samoobsługowe wycofanie zgody i usunięcie danych (art. 7 ust. 3 / art. 17 RODO).
* Utwardzone załączniki: typ MIME wykrywany po treści pliku (`finfo`), limity rozmiaru i liczby, usuwanie EXIF z obrazów, kontrola własności pliku przy każdym pobraniu.
* Ochrona przed spamem: honeypot, pułapka czasowa, warstwowy limit zgłoszeń (IP / e-mail / numer seryjny) i twarda 15-minutowa blokada duplikatów.
* Ekran personelu do zgłoszeń niepotwierdzonych (poprawa adresu e-mail + ponowna wysyłka świeżego linku, z ograniczeniem częstotliwości) wraz z rejestrem operacji.
* Eraser i eksporter RODO wpięte w narzędzia prywatności WordPressa; treść zgody jest mrożona per wiersz dla rozliczalności.

Część pakietu MP Service Suite (trzy współpracujące wtyczki; każda działa też samodzielnie w trybie ograniczonym i nigdy nie powoduje błędów krytycznych). Interfejs i e-maile wtyczki są po polsku (język źródłowy); każdy napis jest umiędzynarodowiony przez text domain, więc wtyczkę można przetłumaczyć na inne języki. Osobnych plików .po/.mo nie dołączamy, bo polski jest językiem bazowym.

== Requirements ==

* WordPress 6.x (6.0 lub nowszy)
* PHP 8.1 lub nowszy
* MySQL 8.0+ lub MariaDB 10.6+
* HTTPS -- pakiet obsługuje logowanie bez hasła (magic-link) i dane osobowe klientów.
* Włączony WP-Cron -- na zadaniach cyklicznych stoją: terminy SLA, przypomnienia i eskalacje (Workflow Automator), importy CSV w tle (Registry) oraz retencyjne sprzątanie danych (Intake).

Rozwijane i testowane na WordPressie 6.9.4, PHP 8.1-8.5, MariaDB 11.8; dodatkowo 27.07.2026 paczka przeszła kontrolną instalację od zera na WordPressie 7.0.2 (PHP 8.2).

== Installation ==

1. Wgraj ZIP wtyczki w **Wtyczki → Dodaj nową → Wyślij wtyczkę na serwer**, a potem ją aktywuj.
2. Aktywacja tworzy automatycznie dwie strony: formularz zgłoszenia („Zgłoszenie serwisowe") i panel klienta („Panel zgłoszeń"). Można je przenosić i zmieniać ich nazwy.
3. Ustaw **Ustawienia → Ogólne → Język witryny** na polski, a strefę czasową na `Europe/Warsaw`, żeby daty i komunikaty wyświetlały się poprawnie.
4. Upewnij się, że hosting wysyła pocztę (patrz FAQ) — linki weryfikacyjne i logowania wychodzą przez `wp_mail()`.
5. Do załączników wymagane jest rozszerzenie PHP `fileinfo` (przy jego braku wtyczka pokazuje ostrzeżenie w panelu).

== Frequently Asked Questions ==

= Maile weryfikacyjne / logowania nie dochodzą =

Wtyczka wysyła pocztę przez WordPressowe `wp_mail()`. Za niezawodne doręczanie odpowiada hosting / wtyczka SMTP — zainstaluj i skonfiguruj wtyczkę SMTP (np. wskazującą serwer SMTP Twojego dostawcy). Bez działającej poczty wychodzącej klienci nie potwierdzą zgłoszeń ani się nie zalogują.

= Czy pliki załączników są chronione przed bezpośrednim dostępem po adresie URL? =

Tak na **Apache / LiteSpeed** (do katalogu wgrywek zapisywany jest `.htaccess` z regułą `deny`). **nginx ignoruje `.htaccess`** — na nginksie dodaj regułę serwera:
`location ^~ /wp-content/uploads/mp-attachments/ { deny all; return 403; }`
Niezależnie od serwera WWW pliki zawsze są serwowane przez końcówkę PHP sprawdzającą własność, więc bezpośredni adres to tylko warstwa zapasowa. Patrz `dokumentacja-techniczna/SECURITY.md`.

= Czego ta wtyczka NIE robi? =

* **Nie** doręcza poczty sama z siebie — to zależy od hostingu/SMTP.
* **Nie** usuwa metadanych z załączników PDF (czyszczone i przekodowywane są tylko obrazy).
* **Nie** prowadzi automatyzacji obiegu (auto-przydział, SLA, maile statusowe) — to osobna wtyczka *MP Workflow Automator*.
* Limit częstotliwości zgłoszeń stoi na transientach; przy trwałej pamięci podręcznej obiektów liczniki żyją w tej pamięci, a nie w bazie.

== Changelog ==

= 1.3.12 =
Wydanie po zewnętrznym audycie całego pakietu. Poniżej to, co zmieniło się w TYM module.

Dane osobowe i RODO:
* **Konto klienta przestało nosić dane osobowe.** Konto zakładane przy potwierdzeniu zgłoszenia
  brało nazwę wyświetlaną z adresu e-mail, a WordPress publikuje ją na stronie autora — jawnej
  i indeksowalnej. Teraz nazwa, login i adres strony autora są neutralne, a imię i nazwisko żyje
  wyłącznie w tabeli klientów, gdzie sięga po nie mechanizm RODO. Konta założone wcześniej
  poprawia jednorazowa migracja — bez niej osoby już ujawnione pozostałyby ujawnione.
* **Żądanie usunięcia i wydania danych obejmuje zgłoszenia niepotwierdzone.** Leżą w nich adres,
  telefon, opis usterki i zdjęcia osoby, która nigdy nie została klientem — a procedura chodziła
  wyłącznie po klientach i mimo to meldowała „usunięto".
* **Formularz pyta o imię i nazwisko.** Bez tego ochrona przed sklejeniem dwóch osób pod wspólną
  skrzynką (recepcja, sekretariat) nigdy się nie włączała.
* Notatka wewnętrzna personelu: klient jej nie widzi i nie dostaje o niej powiadomienia, ale
  wchodzi do paczki wydawanej na żądanie RODO.
* Powód wyjątku gwarancyjnego znika z migawki sprawy przy żądaniu usunięcia danych.
* Sprzątanie po terminie retencji **nie zabiera już załączników sprawie, która żyje** albo wróciła
  ze stanu zamkniętego; termin jest przeliczany, a nie wyliczany raz przy wgraniu pliku.

Dostępność (WCAG 2.1 AA):
* **Błąd formularza prowadzi do konkretnego pola:** podsumowanie błędów jest listą odnośników,
  a pole z błędem jest oznaczone dla czytnika ekranu.
* **Wysyłka ogłasza, że trwa** — przycisk zmienia napis i nie da się kliknąć drugi raz; kontrolka
  nie jest przy tym wyłączana, bo to wycinałoby ją z przesyłanych danych.
* Ekran „Zgłoszenia niepotwierdzone" mieści się w oknie przy powiększeniu 200%.

Praca personelu, statusy i terminy:
* **Administrator ustawia statusy, terminy i reguły bez programisty** — nowa warstwa ustawień.
* **Status „odrzucone" da się nie tylko wybrać, ale i zapisać**, a lista powodów odrzucenia jest
  ustawieniem administratora, nie listą w kodzie.
* Pracownik widzi na liście **tylko swoje sprawy**; koordynator ma dostęp do tych samych ekranów,
  co podległy mu pracownik (wcześniej miał do mniejszej liczby).
* Jedna sprawa **nazywa się wszędzie tak samo** — rodzaj i status nie mają już trzech nazw.
* „Czas obsługi" znaczy to samo w panelu i w eksporcie, a **wiek sprawy jest liczony osobno**,
  od złożenia. ⚠️ Terminy obsługi (SLA) nadal liczą się od ostatniej zmiany statusu — zostawiliśmy
  to świadomie, a wykrywanie sprawy krążącej między statusami oparliśmy na nowej, osobnej mierze
  wieku sprawy.
* Mechanizm ratunkowy przydziału sięga spraw czekających najdłużej, a nie najnowszych.

Rzetelność zapisu i drobiazgi:
* **Nieudany zapis do dziennika zdarzeń zatrzymuje operację** zamiast przepuścić ją dalej —
  wcześniej zmiana statusu mogła zostać zatwierdzona bez wpisu, który ma być jej dowodem.
* Zmiana danych kontaktowych zostawia ślad w historii sprawy.
* **Duplikat rozpoznawany po numerze sprzętu, nie po sposobie jego zapisania.** ⚠️ Produkt nadal
  oznacza duplikat samą flagą i **nie wskazuje, z którą sprawą** — to zostaje otwarte.
* Oznaczenie „link nie doszedł" rozstrzyga kolejnością wpisów, nie porównaniem czasów.
* Gdy poczta pada, słyszą to i klient, i personel — awaria przestała być niewidoczna.
* Okno wykrywania powtórnego zgłoszenia i okno ogranicznika to ustawienia, nie liczby w kodzie.
* Ważność linku potwierdzającego zgadza się z tym, co piszą materiały dla człowieka.
* Odinstalowanie modułu nie zabiera dowodów sprawom, które zostają.
* Wiersze-sieroty w tabeli terminów są naprawdę sprzątane (dotąd obiecywał to tylko komentarz).
* Poprawka stylu lub skryptu dociera do przeglądarek, zamiast zostać w pamięci podręcznej.

Sześć wad z kontroli na działającej instalacji (cztery dotyczą tego modułu):
* **Pracownik serwisu docierał do spraw spoza swojego przydziału — razem z danymi klienta.**
  Lista pokazywała mu wyłącznie jego sprawy, ale karta sprawy otwierała się po samym numerze
  w adresie. Ta sama luka pozwalała zmienić cudzą sprawę: status, odpowiedź wysyłaną do klienta,
  notatkę. Karta i każde działanie na niej pytają teraz o prawo do TEJ konkretnej sprawy.
  UWAGA: wada jest obecna w 1.3.11 i wcześniejszych — zamyka ją sama aktualizacja.
* **Zbyt duży załącznik kończył się pustą białą stroną** — zgłaszający nie wiedział, czy wysłał,
  a wpisane dane znikały. Teraz dostaje czytelny komunikat i wraca na formularz.
* **Przekroczenie dobowego limitu zgłoszeń czyściło cały formularz.** Wartości zostają,
  a komunikat mówi, kiedy będzie można wysłać ponownie.
* **Treść z adresu strony trafiała na ekran jako komunikat panelu** — spreparowanym odnośnikiem
  dało się pokazać na prawdziwej stronie serwisu dowolne zdanie. Skryptu uruchomić się nie dało;
  ciężar polegał na wiarygodności, jakiej taki odnośnik użyczał od domeny serwisu. Ekran
  przyjmuje teraz wyłącznie znane komunikaty.

= 1.3.11 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.
  Jedyna poprawka tego wydania dotyczy ekranu „Wyjątki gwarancyjne" w module Rejestr MP.

= 1.3.10 =
* Komunikat na karcie sprawy cytuje nazwę roli DOKŁADNIE tak, jak brzmi ona na liście
  użytkowników („Pracownik serwisu MP", nie „Pracownik serwisu") — administrator szukający
  cytowanej nazwy znajdzie ją teraz bez zgadywania.
* Kontrola jakości pilnująca nazw ról obejmuje teraz TAKŻE napisy w kodzie, nie tylko dokumenty
  — poprzednio te same błędne cytaty przeżyły poprawkę dokumentów.
* Działanie wtyczki bez zmian — wydanie językowe. Pozostałe poprawki językowe tego wydania
  (nagłówek kolumny w tabeli statusów, etykieta przycisku w Rejestrze zdarzeń) dotyczą modułu
  Automatyzacja MP.

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
* Wydanie zbiorcze pakietu: bez zmian w kodzie tego modułu, numer wersji podniesiony razem
  z pozostałymi. Poprawki językowe tego wydania dotyczą ekranów importu i wyjątków gwarancyjnych
  w module Rejestr MP oraz ekranów modułu Automatyzacja MP.
* Instrukcje (materiał wspólny dla pakietu): poprawione nazwy pozycji menu i filtrów (były
  nieaktualne względem panelu), dodany opis pól podstawianych w szablonach odpowiedzi oraz
  prawidłowa droga do wyjątków gwarancyjnych. Odświeżone zdjęcia w instrukcji administratora.

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
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.3.1 =
* Odinstalowanie wtyczki kasuje teraz także opcję techniczną z flagą awarii wysyłki poczty
  (`mp_intake_mail_alert`) — wcześniej zostawała w bazie jako osierocony wpis.

= 1.3.0 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.5 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.4 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.3 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.2 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.1 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.0 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.1.0 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.0.3 =
* Paczka zawiera teraz część techniczną dla programisty (układ bazy, kontrakt między modułami, model zdarzeń, maszyna statusów, bezpieczeństwo) oraz źródła diagramów do edycji. Bez zmian w kodzie tego modułu.

= 1.0.2 =
* Wydanie porządkujące paczkę dla klienta: ujednolicona wersja w dokumentach i przegenerowany zrzut ekranu. Bez zmian w kodzie tego modułu.

= 1.0.1 =
* Dokument zakupu i data zakupu są porównywane z rejestrem — zgłoszenie z cudzym numerem seryjnym i zmyśloną fakturą nie dostaje już statusu „gwarancja aktywna".
* Karta sprawy pokazuje status TEJ sprawy (decyzję z chwili zgłoszenia) wraz z powodem niezgodności, a nie bieżący stan produktu w rejestrze.
* Załącznik zależny od kategorii: AGD drobne i elektronarzędzia wymagają zdjęcia tabliczki znamionowej. Wymóg spełnia tylko plik, który przejdzie kontrolę.
* Wybrana kategoria wraca do formularza po błędzie — wcześniej znikała razem z polami kategorii.
* Lista „Przydziel do" zawiera wyłącznie pracowników serwisu; nieudany przydział podaje powód.
* Komunikat o zbyt dużym pliku podaje limit obowiązujący na tym serwerze zamiast rady „spróbuj ponownie".
* Uszkodzone zdjęcie nie zostawia już ostrzeżeń PHP w dzienniku strony (plik ucięty przy wysyłce przechodził kontrolę typu, ale nie dawał się odczytać przy usuwaniu danych EXIF).

= 1.0.0 =
* Pierwsze wydanie dla klienta.
* Awaria wysyłki maila zostawia ślad na sprawie i alert w Narzędzia → Stan witryny (dotąd była całkowicie niewidoczna: klient nie dostawał linku, a panel milczał).
* Sprawy potwierdzone przy wyłączonym module automatyzacji są doszywane automatycznie (nie zostają bez przydziału i terminu).
* RODO: porzucone zgłoszenia niepotwierdzone znikają wraz z danymi kontaktowymi i załącznikami po 30 dniach (próg zmienia filtr).
* Zamknięta sprawa nie przyjmuje już przydziału ani zmiany pilności.
* Formularz działa także na hostingu bez rozszerzenia mbstring.
* Numer sprawy w formacie ze specyfikacji: SRV/RRRR/NNNN.
* Sprzątanie starych danych odtwarza się samo, gdy zadanie cykliczne zniknie z WordPressa; Stan witryny ostrzega, gdy go brakuje.

= 0.5.0 =
* Karta pracy personelu „MP: Sprawy" (lista spraw + karta: status/odpowiedź/przydział/checklista/oś czasu), sekcja Produkt i gwarancja. Numer sprawy w formacie SRV/RRRR/NNNN.

= 0.4.0 =
* Contract functions for the Workflow Automator: case context, assignment, status change (optimistic-lock), paginated cases query (role-aware, minimized), checklist authorization (ownership + event), read-only status list.
* Submission form now dynamic by case type client-side (all fields in DOM; return-reason works first time).
* Guarantee exceptions recorded on the case timeline (EXCEPTION_APPLIED/REVOKED, NO-PII).
* Rate-limit by real client IP (mp_intake_client_ip filter) for reverse-proxy/Cloudflare setups.
* GDPR fix: correct terminal status "zamknięte" so erasure is no longer deferred indefinitely.
* Client front polish (admin bar hidden for clients, CSS, panel CTA) + panel WCAG contrast ≥ 4.5:1.

= 0.3.0 =
* Customer account + passwordless login + panel (live status, message history).
* GDPR: contact-data editing (art. 16), self-service consent withdrawal + erasure (art. 7(3)/17), eraser/exporter, consent e-mail redaction on erasure.
* Verification hardened to POST-confirm (mail scanners no longer auto-confirm).
* Spam protection: layered rate-limit + hard duplicate guard.
* Serial reuse flag (`possible_duplicate`) for recent verified cases of the same product.
* Staff screen for unverified submissions: fix e-mail + resend (throttled) + operation audit log.
* Safe upgrade without reactivation (schema migrates on admin load).

= 0.1.0 =
* Plugin skeleton: OOP bootstrap, lifecycle (activation/deactivation/uninstall), shared mp_* roles, i18n.
