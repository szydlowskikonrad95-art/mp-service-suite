# DATABASE.md — kontrakt bazy danych (ZAMROŻONY)

> Część kontraktu MP (`MP_CONTRACT_VERSION = 1`). Zmiana = świadoma decyzja + sweep po dokumentach
> i kodzie. Pełne DDL powstaje w migracjach; TEN dokument ustala tabele, właścicieli, kolumny
> KONTRAKTOWE (te, na których wiszą mechanizmy międzypluginowe) i rygor techniczny.

## 0. Od czego wychodzimy: specyfikacja klienta

Specyfikacja (sekcja 2, „Trzy zależności baz danych") wylicza **4 tabele i 3 relacje**:

| Relacja ze spec | Klucz |
|---|---|
| Klient → zgłoszenia | `wp_mp_customers.id` → `wp_mp_service_cases.customer_id` |
| Produkt/serial → zgłoszenia | `wp_mp_product_registry.id` → `wp_mp_service_cases.product_registry_id` |
| Zgłoszenie → historia zdarzeń | `wp_mp_service_cases.id` → `wp_mp_case_events.case_id` |

Spec wylicza RELACJE, nie limituje liczby tabel — a jej wymagania funkcjonalne (cytaty niżej)
wymuszają dodatkowe tabele. **Każda tabela ponad 4 bazowe ma niżej cytat‑uzasadnienie z konkretnego
wymagania spec.** Razem: **15 tabel (14 biznesowo‑stanowych + 1 techniczna `wp_mp_srv_counters`)**.

## 1. Tabele i właściciele

Właściciel = JEDYNY plugin, który czyta i pisze tę tabelę wprost (reszta wyłącznie hookami —
patrz OWNERSHIP.md; pilnuje tego linter cudzych tabel w CI).

### Własność C — mp-service-intake (7)

| Tabela | Uzasadnienie |
|---|---|
| `wp_mp_customers` | spec, tabela bazowa (relacja 1) |
| `wp_mp_service_cases` | spec, tabela bazowa (relacje 1‑3) |
| `wp_mp_case_events` | spec, tabela bazowa (relacja 3: „nieusuwalny wpis w osi czasu sprawy") |
| `wp_mp_messages` | spec P1.5: „konto klienta z … historią wiadomości" — rozmowa ≠ log audytu, wiadomości są redagowalne (RODO), events nietykalne |
| `wp_mp_attachments` | spec T5/RODO: „limity typów i rozmiaru plików" + „zdefiniowana retencja załączników" — cron retencji chodzi po tej tabeli |
| `wp_mp_consents` | spec RODO: „rejestr zgód" |
| `wp_mp_srv_counters` | techniczna; spec P1.3: „automatyczne generowanie numeru sprawy" + sekcja 2: „unikalny numer sprawy" — licznik atomowy per rok (patrz §4) |

### Własność B — mp-warranty-registry (4)

| Tabela | Uzasadnienie |
|---|---|
| `wp_mp_product_registry` | spec, tabela bazowa (relacja 2) |
| `wp_mp_product_events` | spec P2.5: „historia zmian danych produktu i decyzji gwarancyjnych" |
| `wp_mp_warranty_exceptions` | spec P2.4: „obsługa wyjątków gwarancyjnych zatwierdzanych przez uprawnionego administratora" — wyjątek ma STAN i cykl życia (active/revoked, ważność), stanu nie odczytuje się z event‑logu |
| `wp_mp_import_jobs` | spec P2.1: „import … z pliku CSV" — import asynchroniczny porcjami wymaga trwałego stanu przebiegu (wznowienie po padnięciu) |

### Własność D — mp-workflow-automator (4)

| Tabela | Uzasadnienie |
|---|---|
| `wp_mp_workflow_rules` | spec P3.1: „automatyczny przydział … według kategorii, kraju, języka lub priorytetu" — reguły konfigurowalne przez admina bez zmiany kodu |
| `wp_mp_case_sla` | spec P3.4: „przypomnienie przed przekroczeniem terminu oraz eskalacja po przekroczeniu SLA" — księgowość terminów i markerów wysyłek (idempotencja sweepa) |
| `wp_mp_case_checklists` | spec P3.5: „checklisty dla poszczególnych typów spraw" + krok 7: „pracownik realizuje checklistę" — stan odhaczeń per krok |
| `wp_mp_workflow_events` | spec sekcja 1: „każdy plugin będzie posiadał … rejestr operacji istotnych" — rejestr operacji automatora |

## 2. Kolumny kontraktowe (minimum; pełne DDL w migracjach)

**Każda tabela:** PK `id BIGINT UNSIGNED AUTO_INCREMENT` (wyjątki: `srv_counters.year` PK,
`case_sla.case_id` PK) · `utf8mb4` z `get_charset_collate()` · czasy w **UTC** (konwersja do strefy
witryny wyłącznie przy prezentacji — SEMANTYKA‑CZASU.md).

- **`wp_mp_customers`**: dane kontaktowe klienta · `anonymized_at` (flaga anonimizacji; wiersz
  i relacje ZOSTAJĄ) · powiązanie z kontem WP (odpinane przy anonimizacji).
- **`wp_mp_service_cases`**: `customer_id` · `product_registry_id` **NULL dozwolony** (sprawa bez
  produktu, np. zapytanie bez serialu — wtedy `warranty_snapshot` i jej wersja jawnie NULL) ·
  `case_number` UNIQUE (SRV/RRRR/NNNN) · `status` **NULL = nieporwierdzona (unverified)**, `IS NULL`
  w pierwszym przejściu (patrz STATE_MACHINE.md) · `identity_status` (pending/verified) ·
  `verify_token_hash` UNIQUE + `verify_token_expires_at` + `verify_token_used_at` (NULL=żywy; w bazie
  WYŁĄCZNIE hashe tokenów) · `created_at` (=submit) · `verified_at` · `status_changed_at` ·
  `rejection_reason_code` (NULL poza odrzuconymi) · `possible_duplicate` (flaga, nie blokada) ·
  `form_data` LONGTEXT (klucz→{label z chwili złożenia, value}) + `form_schema_version` ·
  `warranty_snapshot` LONGTEXT (pełna zwrotka `mp_warranty_check` z chwili zgłoszenia) +
  `warranty_snapshot_schema_version` · rodzaj sprawy (reklamacja/naprawa/zapytanie/zwrot) ·
  `priority` · `assigned_to` · kraj (z mapy pól) · język (auto z locale).
- **`wp_mp_case_events`**: `case_id` · typ zdarzenia · `payload` LONGTEXT (JSON walidowany w PHP)
  + `schema_version` · actor · `created_at`. **APPEND‑ONLY BEZ WYJĄTKÓW** (zero metod UPDATE/DELETE);
  zero pól wolnotekstowych — patrz EVENT_MODEL.md.
- **`wp_mp_messages`**: `case_id` · `author_type` (client/staff/system) · treść (redagowalna przy
  RODO) · `created_at`. Wiadomości na sprawie zamkniętej DOZWOLONE.
- **`wp_mp_attachments`**: `case_id` · ścieżka (losowa nazwa bez rozszerzenia) · typ (finfo) ·
  rozmiar · `retention_until` (wyliczane przy tworzeniu z konfiguracji per RODZAJ sprawy) ·
  `deleted_at`. Kasowanie załącznika ZAWSZE = wiersz + PLIK z dysku.
- **`wp_mp_consents`**: klient/e‑mail · `case_id` (zgoda spięta ze sprawą) · `consented_at` ·
  wersja zgody · **PEŁNY TEKST zgody zamrożony w wierszu** (rozliczalność art. 7).
- **`wp_mp_srv_counters`**: `year` PK · `value`.
- **`wp_mp_product_registry`**: `serial_display` + `serial_normalized` UNIQUE (wielkie litery, bez
  spacji/myślników — `MP\Common\Str::normalize_serial()`) · model · partia · `category`
  (VARCHAR(32) NOT NULL DEFAULT 'inne', KEY category; dodana migracją v2 addytywnie — istniejące
  wiersze => 'inne'; słownik audio/agd/elektronarzedzia/inne konfigurowalny filtrem
  `mp_product_categories`; oś przydziału P3.1 przez hak `mp_product_category`) · `warranty_until`
  (INDEKS — filtry statusu SARGABLE: warunek na kolumnie, wartość z PHP w UTC) · `purchase_document`
  (pii_sensitive; indeks „invoice") · `purchase_date` · `source` (csv_import/manual) ·
  `import_job_id` · `archived` + `deleted_at/by` (soft delete; archived ORTOGONALNE do statusu
  gwarancji). Status gwarancji (aktywna/wygasła/brak danych/weryfikacja) = WYLICZANY, nie kolumna.
- **`wp_mp_product_events`**: jak case_events (append‑only; diff before/after; pola pii_sensitive
  w diffie TYLKO `{field, changed:true}` — nigdy wartość).
- **`wp_mp_warranty_exceptions`**: `product_registry_id` · `case_id` **NULL = globalny na produkt;
  NOT NULL = działa TYLKO dla tej sprawy** · `status` **TYLKO active/revoked — „expired" ZAWSZE
  wyliczane z `valid_until`, nigdy zapisywane** · `valid_from` · `valid_until` NULL · `reason` ≤500
  (notatka wewnętrzna; redagowalna przez RODO‑filter) · `created_by/at` · `revoked_by/at` · indeks
  złożony `(product_registry_id, status, case_id, valid_until)`. Precedens: per‑sprawa > globalny;
  max JEDEN aktywny wyjątek per zakres; odczyt deterministyczny (case‑first, valid_until DESC,
  id DESC, LIMIT 1).
- **`wp_mp_import_jobs`**: `file_path` · `status` · `total/processed/success/error_rows` ·
  `error_report_path` · `lock_key` UNIQUE (`'product-import'` żywy / `'done-{id}'` zamknięty —
  lock przez INSERT‑pod‑UNIQUE, NIGDY add_option) · `job_token` UUID · `updated_at` (stale‑detekcja
  >15 min) · `created/finished`.
- **`wp_mp_workflow_rules`**: `trigger_type` · `condition_key` · `condition_operator`
  (equals/not_equals/in_list/is_empty/is_not_empty — zamknięta lista) · `condition_value` ·
  `action_type` · `action_config_json` · `priority` · `enabled` · `rr_cursor` (kursor round‑robin,
  podbijany atomowo wzorcem licznika SRV) · `source` (system/user) · `system_key` UNIQUE NULL ·
  `updated_at` (optimistic‑lock edycji). Kolumny STRUKTURALNE — **ZAKAZ eval / wykonywania tekstu
  z bazy**; indeks `(trigger_type, enabled, priority)`.
- **`wp_mp_case_sla`**: `case_id` PK · `status` (kopia do zapytań) · `sla_policy_version` ·
  `deadline_at` (INDEKS; terminalne → NULL) · `reminder_sent_at` · `escalated_at` ·
  `reminder_attempts` / `escalation_attempts` TINYINT · `updated_at`.
- **`wp_mp_case_checklists`**: `case_id` · `template_id` · `step_key` · `completed` ·
  `completed_by/at` · `step_label` (zamrożony z chwili odhaczenia — wzorzec form_data).
  Wiersz per KROK (atomowy toggle); ZERO pól wolnotekstowych z konstrukcji.
- **`wp_mp_workflow_events`**: jak case_events (append‑only, strukturalne, NO‑PII, payload
  + `schema_version`, `depth` w wykonaniach reguł).

## 3. Rygor techniczny (twardy)

1. **dbDelta WYŁĄCZNIE wg rygoru**: dwie spacje po `PRIMARY KEY`, `KEY` nie `INDEX`, **bez FOREIGN
   KEY** (relacje = klucze LOGICZNE: kolumny+indeksy w SQL, integralność w KODZIE + testach — np.
   blokada usunięcia produktu z aktywną sprawą, w transakcji), `LONGTEXT` z walidacją JSON w PHP
   (typ JSON = fałszywe diffy dbDelta), `utf8mb4` z `get_charset_collate()`.
2. **SQL_MODE**: wszystko działa przy DOMYŚLNYM (strict) trybie MariaDB/MySQL — zero polegania na
   niestandardowych ustawieniach.
3. **Nazwy tabel w kodzie WYŁĄCZNIE ze stałych klasy / centralnej metody** — zakaz dynamicznego
   składania nazw w SQL (pilnuje linter + standard kodu).
4. **Migracje**: wersja schematu w opcji per plugin + ponumerowane migracje; zmiany nieaddytywne
   przez tabelę tymczasową → kopiowanie → RENAME **wyłącznie pod `.maintenance` lub
   `LOCK TABLES … WRITE`** + `DROP … IF EXISTS` osieroconej tabeli tymczasowej na starcie;
   szczegóły i rollback: MIGRATION_POLICY.md.
5. Środowisko: MySQL 8 / MariaDB 10.6+ (spec T1); demo pinowane na MariaDB 11.8 LTS.

## 4. Numer sprawy SRV/RRRR/NNNN — JEDEN algorytm

Licznik ATOMOWY per rok w `wp_mp_srv_counters` (jedna kwerenda = init roku i podbicie):

```sql
INSERT INTO wp_mp_srv_counters (year, value) VALUES (%d, 1)
ON DUPLICATE KEY UPDATE value = LAST_INSERT_ID(value + 1)
```

+ `case_number` UNIQUE jako pas bezpieczeństwa (INSERT pod UNIQUE + retry). Test kontraktowy:
**≥20 równoległych procesów / ≥1000 numerów = zero duplikatów.** Dziury w numeracji po sprzątnięciu
spraw niepotwierdzonych = udokumentowane (unikalność ≠ ciągłość). `wp_mp_srv_counters` = własność C,
czyszczona w warstwie (ii) uninstalla RAZEM ze sprawami (skasowanie licznika przy zostawionych
sprawach → duplikaty SRV po reinstalacji w tym samym roku).

## 5. MAPA‑PII — każda kolumna z danymi osobowymi → kto ją obsługuje przy RODO

| Kolumna | PII | Mechanizm RODO |
|---|---|---|
| `customers.*` (dane kontaktowe) | TAK | eraser C: czyszczenie pól + `anonymized_at` + odpięcie konta WP (wiersz i relacje zostają) |
| `service_cases.form_data` → pola `pii_sensitive` | TAK | eraser C: redakcja WARTOŚCI pól pii_sensitive (struktura/etykiety zostają) |
| `service_cases.rodzaj/status/czasy/numery` | NIE | — (fakty procesowe) |
| opis problemu / notatki w sprawie | TAK | eraser C: redakcja → `[ZREDAGOWANO-RODO]` |
| `messages.tresc` | TAK | eraser C: redakcja wiadomości klienta (kwazi‑identyfikatory) |
| `attachments` (pliki) | TAK | eraser C: kasacja plików (wiersz+PLIK); niezależnie cron retencji `retention_until` |
| `consents` (tekst+meta zgody) | TAK (rozliczalność) | rejestr zgód — art. 7; wycofanie = `CONSENT_WITHDRAWN`; NIE podlega redakcji treści (dowód zgody) |
| `case_events.payload` | **NIE Z KONSTRUKCJI** | ŻELAZNA ZASADA NO‑PII‑IN‑LOG — events nietykalne, redakcja ich nie dotyczy (EVENT_MODEL.md) |
| `product_registry.purchase_document` | TAK (kwazi‑identyfikator) | wartości żyją TYLKO w tabeli stanu; w diffach eventów `{field, changed:true}`; nie wychodzi hookami (weryfikacja `$verify` porównywana po stronie B) |
| `warranty_exceptions.reason` | MOŻE (wolny tekst admina) | filter `mp_privacy_redact_for_customer` od C → B redaguje reason wyjątków powiązanych ze sprawami klienta |
| `case_sla` / `case_checklists` / `workflow_rules` | NIE Z KONSTRUKCJI | zero pól wolnotekstowych przenoszących PII |
| `workflow_events.payload` | NIE Z KONSTRUKCJI | NO‑PII (D „nie ma nic do redakcji") |
| konto WP klienta (`wp_users`) | TAK | odpięcie przy anonimizacji (natywny eraser WP obsługuje resztę) |

Erasery szukają po **EMAILU**, nie user_id (łapią sprawy bez konta). Sprawa aktywna / okno roszczeń →
odroczenie EN BLOC z `items_retained` (żadnej częściowej anonimizacji). Pełna orkiestracja: OWNERSHIP.md.
