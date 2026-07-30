=== MP Workflow Automator ===
Requires at least: 6.0
Tested up to: 7.0
Requires PHP: 8.1
Stable tag: 1.3.2
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Rules engine for service cases: automatic assignment, statuses, e-mail notifications, SLA deadlines, checklists, reports.

== Description ==

Automates the service workflow: assigns cases to staff based on product category, country, language or priority, manages configurable case statuses, sends e-mail notifications to customers and staff on every relevant change, tracks SLA deadlines with reminders before and escalations after the deadline, provides per-type checklists and response templates, and exports CSV reports.

Part of the MP Service Suite (three cooperating plugins; each one also works standalone in a reduced mode, never causing fatal errors). The plugin UI and e-mails are in Polish (source language); every string is internationalized via the text domain, so the plugin can be translated to other languages. No separate .po/.mo is bundled because Polish is the base language.

== Requirements ==

* WordPress 6.x (6.0 or newer)
* PHP 8.1 or newer
* MySQL 8.0+ or MariaDB 10.6+
* HTTPS -- the suite handles passwordless (magic-link) login and customer personal data.
* WP-Cron enabled -- scheduled tasks rely on it: SLA deadlines, reminders and escalations (Workflow Automator), background CSV imports (Registry) and data-retention cleanup (Intake).

Developed and tested on WordPress 6.9.4, PHP 8.1-8.5, MariaDB 11.8.

== Changelog ==

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
