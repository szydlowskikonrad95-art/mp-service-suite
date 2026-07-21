# OWNERSHIP.md — własność danych i granice zapisu (ZAMROŻONE)

> Matryca: dane → właściciel → kto może pisać CZYM. Zasada nadrzędna: **kod pluginu NIE dotyka
> cudzych tabel — ani zapisem, ani odczytem (SELECT też zakazany).** Jedyna droga = hooki
> z API‑KONTRAKT.md. Pilnuje tego MASZYNA: linter cudzych tabel w CI (tokenowy) + testy.

## 1. Matryca własności

| Dane | Tabele | Właściciel | Inni piszą przez | Inni czytają przez |
|---|---|---|---|---|
| Klienci, zgody | customers, consents | **C** | — (tylko C) | erasery/eksportery C |
| Sprawy | service_cases | **C** | `mp_case_change_status` · `mp_case_assign` · `mp_case_set_priority` · `mp_case_add_system_message` | `mp_case_get_context` · `mp_cases_query` |
| Oś czasu sprawy | case_events (append‑only) | **C** | pośrednio: funkcje kontraktowe C + listenery C (`mp_warranty_exception_changed`, `mp_sla_notified`) | — (UI C) |
| Wiadomości, załączniki | messages, attachments | **C** | `mp_case_add_system_message` (D: raport końcowy) | konto klienta / karta sprawy C |
| Licznik SRV | srv_counters (techniczna) | **C** | — | — |
| Rejestr produktów | product_registry, product_events | **B** | — | `mp_warranty_check` · `mp_serial_usage_count` |
| Wyjątki gwarancyjne | warranty_exceptions | **B** | — (zatwierdza WYŁĄCZNIE `mp_system_admin` w UI B) | pola exception_* w zwrotce `mp_warranty_check` |
| Przebiegi importu | import_jobs | **B** | — | ekran importu B |
| Reguły automatora | workflow_rules | **D** | — | — |
| Księgowość SLA, checklisty (stan) | case_sla, case_checklists | **D** | — (stan checklisty: NAJPIERW `mp_case_checklist_authorize` w C, po OK zapis w D) | sekcje karty sprawy (filter `mp_case_card_sections`) |
| Rejestr operacji D | workflow_events (append‑only) | **D** | — | podgląd w adminie D |

## 2. Wspólne zasoby (nie mają jednego właściciela‑pluginu)

- **Role `mp_*` (4 ze spec)**: współdzielone. Każdy plugin przy aktywacji odtwarza je idempotentnie
  (`Common\Roles::ensure`). Zdejmuje je **OSTATNI ODINSTALOWYWANY** plugin: detekcja przez osobne
  opcje‑markery `mp_module_intake` / `mp_module_registry` / `mp_module_automator` (każdy pisze
  WYŁĄCZNIE swój; NIE file_exists, NIE wspólna tablica). Marker = ZAINSTALOWANY, nie aktywny:
  kasowany wyłącznie w uninstall.php (deaktywacja NIE dotyka). W uninstall markery braci czytane
  BEZPOŚREDNIO `$wpdb` (pominięcie cache — dwa równoległe uninstalle). Kolejność odporna na
  przerwanie: remap userów partiami PRZED zdjęciem roli; WŁASNY marker kasowany na SAMYM KOŃCU.
  Kierunek błędu bezpieczny: FTP‑delete/`wp plugin delete --skip-plugins` → marker‑sierota → role
  ZOSTAJĄ (wentyl: `wp mp cleanup --roles` + nota README). Przy zdjęciu ról: user bez innej roli →
  `subscriber`. Multisite: poza zakresem v1 (README „czego system NIE robi").
- **Wspólny kod `lib/mp-common`**: jedyne źródło w repo; kopie w pluginach GENEROWANE przez build
  (stempel namespace), gitignorowane; edycja kopii = błąd; release ZIP wyłącznie artefaktem CI
  (BUILD‑INFO w każdym ZIP).
- **Stała `MP_CONTRACT_VERSION`**: definiuje pierwszy załadowany plugin (guard `defined()`);
  niezgodność oczekiwań = notice + degraded.

## 3. Orkiestracja RODO (proces międzypluginowy)

**Właścicielem PROCESU anonimizacji jest C** (eraser natywny WP):
1. C czyści/redaguje swoje dane (MAPA‑PII w DATABASE.md),
2. C woła filter `mp_privacy_redact_for_customer($customer_id, $case_ids)` → **B** redaguje
   `warranty_exceptions.reason` powiązane ze sprawami klienta → `{success, redacted_count}`,
3. B nieaktywne/błąd → eraser raportuje `items_retained` z powodem (natywny mechanizm WP;
   retry = ponowne uruchomienie erasera) + wpis w audit‑logu,
4. **D nie ma nic do redakcji** (NO‑PII z konstrukcji),
5. sprawa aktywna / okno roszczeń → odroczenie **EN BLOC** (wstrzymuje też wywołanie do B —
   jedna operacja, jeden raport).

## 4. Sprzątanie i cykl życia danych

- **Uninstall dwuwarstwowy**: warstwa (i) ZAWSZE — opcje techniczne, transienty, crony, pliki
  techniczne, auto‑strona formularza (tylko nieedytowana, po zapisanym ID); warstwa (ii) default
  OFF — dane biznesowe wg JAWNEJ listy per plugin (w tym opcje‑TREŚCI D: szablony, definicje
  checklist, statusy własne — przeżywają RAZEM z regułami; `srv_counters` = warstwa ii RAZEM ze
  sprawami). uninstall.php IDEMPOTENTNY (przerwany → dokańcza).
- **Sygnał `mp_cases_data_erased`** (uninstall C ścieżką ON): D robi wipe case_sla + case_checklists
  (workflow_events zostaje — rejestr historyczny); B rewokuje wyjątki per‑sprawa (globalne zostają).
  C skasowany BEZ sygnału → sieroty sprząta defensywa sweepa D (`not_found` → wiersz sla czyszczony).
- **Integralność międzytabelowa w KODZIE (bez FK)**: usunięcie produktu z aktywną sprawą = odmowa
  (pyta `mp_product_active_cases_count`; **FAIL‑CLOSED**: C nieaktywne → też odmowa); usuwanie z UI =
  SOFT DELETE (archived); hard delete tylko WP‑CLI z `--confirm=<SERIAL>`.

## 5. Egzekwowanie (maszyny, nie umowy)

1. `build/lint-cudze-tabele.php` w CI: literał nazwy cudzej tabeli w kodzie pluginu = czerwone.
2. Standard kodu: nazwy tabel wyłącznie ze stałych/centralnej metody (zakaz dynamicznego składania).
3. Testy DoD per klocek: „uninstall JEDNEGO przy dwóch aktywnych → permission checks sąsiadów
   działają" + test 3‑etapowy sekwencyjny z asercją TREŚCI markerów.
4. Testy negatywne uprawnień dla 4 ról na kluczowych operacjach.
