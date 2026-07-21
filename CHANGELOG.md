# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/pl/1.1.0/) · wersjonowanie: [SemVer](https://semver.org/lang/pl/).

## [Unreleased]

### Added
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
