=== MP Warranty & Serial Registry ===
Requires at least: 6.0
Tested up to: 7.0
Requires PHP: 8.1
Stable tag: 1.2.4
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

Developed and tested on WordPress 6.9.4, PHP 8.1-8.5, MariaDB 11.8.

== Frequently Asked Questions ==

= What should the CSV import file look like? =

A ready-to-use sample ships with the plugin: `przyklady/przyklad-import-produktow.csv`. The import screen also links to it ("Pobierz przykładowy plik CSV").

Only the serial column is required (header `serial`, `numer_seryjny` or `sn`). Optional columns: `model`, `partia` (`batch`), `faktura` (`dokument_zakupu`), `data_zakupu`, `gwarancja_do` (`warranty_until`), `kategoria`. Without `gwarancja_do` the warranty status cannot be computed and the product shows "no data".

Dates: `2026-04-12` or `12.04.2026` (Polish Excel). Separator: `;` or `,`, detected automatically. Encoding: UTF-8 or Windows-1250 (the latter needs the iconv or intl extension; otherwise the file is rejected instead of silently mangling Polish characters). Maximum file size: 8 MB -- split larger registries, imports are resumable.

= Does re-importing a file update existing products? =

No. The import ADDS products. A serial number already present in the registry is reported in the error report as a duplicate and the existing entry is left untouched. Serial comparison ignores spaces, dashes and letter case, so `SN-AUD-1001` and `sn aud 1001` are the same product.

== Changelog ==

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
