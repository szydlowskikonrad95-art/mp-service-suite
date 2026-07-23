# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/pl/1.1.0/) · wersjonowanie: [SemVer](https://semver.org/lang/pl/).

## [Unreleased]

### Added
- Registry (B): **kategoria produktu** (domkniecie kartki P1.2/P3.1 po stronie danych) — kolumna `category`
  (migracja v2 `maybe_upgrade`, BEZ reaktywacji; istniejace wiersze => `inne`), slownik 4 kategorii
  (audio / agd / elektronarzedzia / inne; konfigurowalny filtrem `mp_product_categories`), import CSV z kolumna
  `kategoria` (WSTECZNIE ZGODNY — stary CSV bez niej => `inne`; nieznana => `inne`, bez przerwania importu),
  oraz hak kontraktowy `mp_product_category` (Intake `get_context.kategoria` => os przydzialu w Automatorze).
  Test e2e `b-kategoria`. Przydzial wg kategorii udowodniony end-to-end (test `d-p31-kategoria`).
- Intake (C): **formularz P1.2 — pola wg kategorii produktu**. Dropdown kategorii na formularzu; dodatkowe pola per
  kategoria (sensowne domyslne + konfigurowalne filtrem `mp_intake_category_fields`); `fields_for($kind, $category)`
  ADDYTYWNIE (bez kategorii = pola rodzaju, ZERO regresji #15); zapis pol kategorii do `form_data`; walidacja serwera
  + JS-dynamika (pokazuje pola wg rodzaju ORAZ kategorii). Test e2e `c-kategoria-formularz`.
- Intake (C): **listener `mp_product_active_cases_count`** — domkniecie kartki l.50 (B5: „brak mozliwosci
  usuniecia produktu powiazanego z aktywna sprawa"). Registry (B) mial juz blokade (`Archive.php`) + akcje
  w adminie, ale brakowalo strony C odpowiadajacej liczba spraw => archiwizacja ODMAWIALA ZAWSZE (fail-closed
  bez listenera, nawet dla produktu bez spraw). Teraz Intake liczy sprawy NIE-TERMINALNE produktu
  (`CaseRepo::active_cases_count_for_product`); >0 => Registry odmawia z komunikatem, 0 => archiwizuje
  (soft-delete: `archived=1` + `deleted_at`). Test e2e `b5-usuwanie-produktu` (blok / OK / fail-closed).

### Fixed
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
  `RuleEngine` dedupuje po `dedup_key`, nie po `body`. Mail do wysłania dalej niesie prawdziwą datę. Asercja-strażnik
  w `d-p33d-dedup`.

- Intake (C): **kolumna „Sprawy" i wyszukiwarka po kliencie w Rejestrze** — Intake nie rejestrował listenerów
  kontraktowych `mp_case_count_by_product` i `mp_customer_find_products` → kolumna „Sprawy" pokazywała „moduł
  spraw nieaktywny" mimo aktywnego Intake, a wyszukiwarka po kliencie (kartka **P2.6**) była WYŁĄCZONA. Dodane
  `CaseRepo::case_count_by_product` (`{total,active,closed,rejected}`, unverified wykluczone) +
  `find_products_for_customer` (`{ids,truncated,limit}`) + rejestracja obu filtrów. Test `c-count-search-hooki`.
  Znalezione KLIKACZEM admina (bramka) — automaty testowały haki osobno, nie zintegrowany panel.

## [0.4.0] - 2026-07-23

Klocek D (Automator) kompletny: silnik reguł + auto-przydział, statusy, maile, SLA (1–4),
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
- Intake (C): formularz zgłoszenia dynamiczny wg rodzaju po stronie klienta (kartka wymóg #1). Render
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
  eraser odraczał anonimizację klienta w nieskończoność, łamiąc §4 kartki). Realny slug to `zamknięte`
  (z ę, jedyna droga zapisu = `change_status`). Testy c5-rodo/c6b/c6b2b przepięte na REALNĄ
  `change_status` (seed literówki maskował błąd — zielone kłamały). Flaga #14. (pre-release v0.3.0)

### Added
- Automator (D): schemat D — 4 tabele (`wp_mp_workflow_rules`, `wp_mp_case_sla`,
  `wp_mp_case_checklists`, `wp_mp_workflow_events` = rejestr operacji APPEND-ONLY, NO-PII);
  migracje bez reaktywacji (`maybe_upgrade`), uninstall opt-in kasuje wszystkie artefakty D
  i nic cudzego (kanarki + role współdzielone nietknięte). Test d1-schema + DoD D.
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
- Testy klocka D w CI: seria `d-*` (schemat, hooki, P3.1–P3.6), DoD D (uninstall zero-śladu +
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
  SRV/RRRR/NNNN (`INSERT ... VALUES(year, LAST_INSERT_ID(1)) ON DUPLICATE KEY UPDATE ...` +
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
  mechanika co "Wznow" w UI) oraz testy DoD klocka B w CI (job e2e-import na zywym WP 6.9.4
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
  linter cudzych tabel, gitleaks), testy jednostkowe smoke, poligon Docker (WP 6.9.4, MariaDB 11.8,
  Mailpit) z realnym cronem i SMTP dev.
