# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/pl/1.1.0/) · wersjonowanie: [SemVer](https://semver.org/lang/pl/).

## [Unreleased]

### Fixed
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
