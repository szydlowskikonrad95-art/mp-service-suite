=== MP Workflow Automator ===
Requires at least: 6.0
Tested up to: 7.0
Requires PHP: 8.1
Stable tag: 1.3.12
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Rules engine for service cases: automatic assignment, statuses, e-mail notifications, SLA deadlines, checklists, reports.

== Description ==

Automates the service workflow: assigns cases to staff based on product category or priority, manages configurable case statuses, sends e-mail notifications to customers and staff on every relevant change, tracks SLA deadlines with reminders before and escalations after the deadline, provides per-type checklists and response templates, and exports CSV reports.

Part of the MP Service Suite (three cooperating plugins; each one also works standalone in a reduced mode, never causing fatal errors). The plugin UI and e-mails are in Polish (source language); every string is internationalized via the text domain, so the plugin can be translated to other languages. No separate .po/.mo is bundled because Polish is the base language.

== Requirements ==

* WordPress 6.x (6.0 or newer)
* PHP 8.1 or newer
* MySQL 8.0+ or MariaDB 10.6+
* HTTPS -- the suite handles passwordless (magic-link) login and customer personal data.
* WP-Cron enabled -- scheduled tasks rely on it: SLA deadlines, reminders and escalations (Workflow Automator), background CSV imports (Registry) and data-retention cleanup (Intake).

Developed and tested on WordPress 6.9.4, PHP 8.1-8.5, MariaDB 11.8. Additionally, on 2026-07-27 the release package passed a from-scratch control installation on WordPress 7.0.2 (PHP 8.2).

== Changelog ==

= 1.3.13 =
Poprawki po przeglądzie kontrolnym. Numer wydania podbije osobny krok — poniżej zmiany w TYM module.

Reguły i powiadomienia:
* **Reguła powiadomienia utworzona dokładnie tak, jak podpowiada ekran, nie wyśle już wewnętrznej
  wiadomości do klienta.** Podpowiedź w polu „Szczegóły akcji" uczy jednego zapisu odbiorcy,
  a silnik reguł rozumiał wyłącznie drugi — i cicho wysyłał klientowi treść napisaną dla pracownika.
  Oba zapisy działają teraz tak samo; reguły już istniejące zachowują się bez zmian.
* **Rejestr zdarzeń nie odsyła do reguły, której nie ma.** Wpisy z mechanizmów wbudowanych
  (powiadomienie o przydziale, cykliczny przegląd terminów) pokazywały „reguła nr: 0", a tabela
  reguł numeruje od jedynki — czytelnik szukał reguły-widma. Teraz piszą wprost: wbudowana.

Opis wtyczki:
* **Opis modułu nie obiecuje już przydziału według kraju ani języka.** Produkt tych danych nigdzie
  nie zbiera, więc reguła oparta na nich nie dopasowałaby żadnej sprawy — działają kategoria
  produktu i priorytet. Ekran ustawień i instrukcje mówiły to od dawna, opis wtyczki nie.

= 1.3.12 =
Wydanie po zewnętrznym audycie całego pakietu. Poniżej to, co zmieniło się w TYM module.

Powiadomienia i terminy:
* **Powiadomienia z reguł mają ponowienie i alarm** — tak samo jak przypomnienia o terminach obok.
  Dotąd nieudana wysyłka z reguły cichła bez śladu.
* **Ochrona przed podwójnym mailem działa tak samo, jak ochrona przed podwójnym zgłoszeniem** —
  jeden mechanizm rezerwacji zamiast dwóch różnych.
* **Wiersze-sieroty w tabeli terminów są naprawdę sprzątane.** Dotąd obiecywały to cztery komentarze
  w kodzie, a nie robił tego nikt.
* **Wykrywanie sprawy krążącej między statusami** — sprawa, która bez końca wraca do tego samego
  stanu, przestaje być niewidoczna. ⚠️ Terminy obsługi (SLA) nadal liczą się od ostatniej zmiany
  statusu; krążenie wykrywamy nową, osobną miarą wieku sprawy, a nie zmianą podstawy terminów.
* **Powiadomienie o przekroczonym terminie ma pierwszeństwo przed przypomnieniem.** Cykliczny
  przegląd liczy teraz, ile wiadomości będzie kosztować eskalacja, ZANIM wyda budżet wysyłki na
  przypomnienia — dotąd pilniejsza wiadomość (termin już minął) mogła zostać bez pokrycia.
* Mechanizm ratunkowy przydziału sięga spraw czekających najdłużej, a nie najnowszych.

Dostępność (WCAG 2.1 AA):
* **Panel automatyzacji mieści się w oknie przy powiększeniu 200%** na szerokości typowego
  monitora. ⚠️ **Zamknięta jest część zarzutu:** przy węższym oknie ekran nadal wychodzi poza nie
  (zmierzone: 167 pikseli przy szerokości 768 z powiększeniem 200%, 78 pikseli przy szerokości 390
  bez powiększenia). To zostaje otwarte i mówimy o tym wprost.

Ekrany i ustawienia:
* **Administrator ustawia statusy, terminy i reguły bez programisty** — nowa warstwa ustawień.
  Identyfikator statusu własnego powstaje z tego, co wpisał człowiek, a nie z kolejnego numeru.
* **Ekran puli pokazuje pracowników także wtedy, gdy kont klientów przybywa** — dotąd przy dużej
  liczbie kont lista personelu potrafiła zniknąć.
* Ekran ustawień odsyła do przycisku, który naprawdę tak się nazywa.
* Pole „priorytet" ma wreszcie jedną, zdefiniowaną nazwę — ta sama stoi w nagłówku kolumny
  i w regułach; dotąd produkt nie nazywał go nigdzie wprost.

Rzetelność liczb i zapisu:
* **„Liczba spraw zamkniętych" w eksporcie liczy sprawy zamknięte** — wcześniej liczyła co innego.
* **„Czas obsługi" znaczy to samo w eksporcie i w tym, co widzi klient**, a wiek sprawy jest liczony
  osobno, od złożenia.
* **Rejestr zdarzeń przestaje puchnąć od własnego ruchu produktu** — wpisy techniczne z cyklicznego
  przeglądu nie przykrywają już zdarzeń biznesowych.
* **Nieudany zapis do dziennika zatrzymuje operację** zamiast przepuścić ją dalej.
* Zapis „wstaw albo zaktualizuj" nie używa już funkcji bazy wycofanej w nowszych wersjach MySQL.
* Kontrola w Stanie witryny **nazywa** fabryczne treści WordPressa („Hello world!", „Przykładowa
  strona") widoczne bez logowania — i świadomie ich **nie kasuje**, bo to cudza treść.

Z kontroli na działającej instalacji (dotyczy tego modułu):
* **Ekrany ustawień rozjeżdżały się na wąskim oknie** — z tabeli statusów widać było jedną
  kolumnę. Tabele przewijają się teraz w swoim obszarze, z zaczepem klawiatury. Kolumn nie
  schowaliśmy: schowanie dałoby w pomiarze identyczny wynik co poprawne przewijanie, a kasowałoby
  kolumny na zawsze.

= 1.3.11 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.
  Jedyna poprawka tego wydania dotyczy ekranu „Wyjątki gwarancyjne" w module Rejestr MP.

= 1.3.10 =
* Komunikat na ekranie panelu cytuje nazwę roli DOKŁADNIE tak, jak brzmi ona na liście
  użytkowników („Pracownik serwisu MP", nie „Pracownik serwisu") — administrator szukający
  cytowanej nazwy znajdzie ją teraz bez zgadywania.
* Przycisk w Rejestrze zdarzeń nie pokazuje już nazwy stałej z kodu („SWEEP_RUN") — mówi
  „Pokaż/Ukryj wpisy automatycznego przeglądu".
* Nagłówek kolumny w tabeli statusów: „Terminalny" -> „Kończy sprawę" (bez żargonu maszyn stanów).
* Kontrola jakości pilnująca nazw ról obejmuje teraz TAKŻE napisy w kodzie, nie tylko dokumenty
  — poprzednio te same błędne cytaty przeżyły poprawkę dokumentów.
* Działanie wtyczki bez zmian — wydanie językowe.

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
* Poprawki języka na ekranach tego modułu: przycisk „Przelicz SLA" nazywa się teraz „Przelicz
  terminy obsługi", a lista markerów szablonów jest podpisana „(lista dozwolonych)" zamiast
  „(whitelist)".
* Testy diagnostyki w Stanie witryny mówią „Terminy obsługi zgłoszeń (SLA)" zamiast samego
  skrótu — czytelne także dla osoby, która skrótu nie zna.
* Instrukcje (materiał wspólny dla pakietu): poprawione nazwy pozycji menu i filtrów (były
  nieaktualne względem panelu) oraz dodany opis pól podstawianych w szablonach odpowiedzi.

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
* Reguła wykonana po zmianie statusu widziała stary stan sprawy — mogło to wysłać klientowi
  powiadomienie o statusie, którego sprawa już nie miała. Dane są odświeżane po zmianie.

= 1.3.1 =
* Poprawiony opis w kodzie przy konfiguracji terminów SLA: nadpisania godzin dla siedmiu statusów
  rdzenia to punkt rozszerzenia dla wdrożeniowca, a nie ekran w panelu. Godziny statusów WŁASNYCH
  pozostają edytowalne w panelu.

= 1.3.0 =
* Eksport CSV wysyła dane strumieniowo, zamiast najpierw zbierać wszystkie sprawy do pamięci. Przy dużej bazie eksport nie przerywa się już limitem czasu, a plik zaczyna pobierać się od razu. Zestawienie na końcu pliku liczy się w trakcie wysyłki.

= 1.2.5 =
* Po dłuższym przestoju zaległe eskalacje idą teraz w JEDNYM zbiorczym mailu zamiast w kilku. Wcześniej sprawdzanie terminów dzieliło je na paczki po 50, a próg „zbiorczego maila" liczył się osobno dla każdej paczki — koordynator dostawał do dziesięciu wiadomości w ciągu pięciu minut.

= 1.2.4 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.3 =
* Awaria wysyłki przypomnień i eskalacji jest teraz widoczna w Narzędzia → Stan witryny (z rodzajem powiadomienia i datą). Wcześniej po trzech nieudanych próbach sprawa cichła na stałe, a panel nie mówił o tym nic. Komunikat gaśnie sam po pierwszej udanej wysyłce.

= 1.2.2 =
* Aktualizacja wtyczki przelicza teraz terminy spraw już otwartych. Wcześniej sprawa stojąca w miejscu w chwili podniesienia wersji przestawała dostawać przypomnienie przed terminem — dostawała tylko eskalację po nim.

= 1.2.1 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.0 =
* Nowa sekcja „Kto dostaje zgłoszenia” w panelu Automatyzacje MP: administrator zaznacza pracowników, między których system rozdziela sprawy. Wcześniej lista wychodziła z instalacji pusta i nie było jej jak wypełnić, więc zgłoszenia zostawały nieprzydzielone.

= 1.1.0 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.0.3 =
* Paczka zawiera teraz część techniczną dla programisty (układ bazy, kontrakt między modułami, model zdarzeń, maszyna statusów, bezpieczeństwo) oraz źródła diagramów do edycji. Bez zmian w kodzie tego modułu.

= 1.0.2 =
* Wydanie porządkujące paczkę dla klienta: ujednolicona wersja w dokumentach i przegenerowany zrzut ekranu. Bez zmian w kodzie tego modułu.

= 1.0.1 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.0.0 =
* Pierwsze wydanie dla klienta.
* Budżet wiadomości na jeden przebieg — hosting nie dostaje lawiny maili przy dużej liczbie zaległych terminów; reszta czeka na kolejny przebieg.
* „Przelicz SLA" pracuje paczkami i dokańcza w tle, więc nie przerywa się przy dużej bazie spraw.
* Rejestr zdarzeń mówi po polsku, pokazuje numer sprawy zamiast identyfikatora wewnętrznego i czas lokalny zamiast UTC.
* Diagnostyka podpowiada, jak realnie włączyć automatyczny przydział (nadanie roli), zamiast odsyłać do ekranu tylko do odczytu.
* Po odinstalowaniu modułu zgłoszeń czyszczone są terminy i checklisty; rejestr operacji zostaje jako historia.

= 0.5.0 =
* Powiadomienie e-mail pracownika przy zmianie statusu (self-skip dla autora zmiany). Walidacja JSON konfiguracji (bez cichej utraty), filtr SWEEP_RUN w domyślnym widoku rejestru zdarzeń.

= 0.4.0 =
* Rules engine + round-robin auto-assignment on case creation (structural rules, loop guard).
* Custom case statuses provider + status change action via the C contract.
* Notification e-mails: assignment, status change, client/staff messages (safe egress, per-type dedup).
* SLA: deadline bookkeeping, 5-minute sweep (reminders/escalations), resync + no-avalanche digest, admin "Recalculate SLA".
* Per-type checklists (toggle authorized by Intake, ownership enforced) + per-type response templates with a visible marker whitelist.
* CSV export of cases + summary (capability-gated, audited, anti-formula-injection, minimized data via the cases-query contract).
* Admin panel wiring all backend handlers; all data read from Intake/Registry only through mp_* contract hooks.

= 0.1.0 =
* Plugin skeleton: OOP bootstrap, lifecycle (activation/deactivation/uninstall), shared mp_* roles, i18n.
