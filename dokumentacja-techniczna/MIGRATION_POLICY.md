# MIGRATION_POLICY.md — migracje, kopia zapasowa, cofanie (kartka: „Kopie i odtworzenie")

> Kartka, sekcja 4: **„Backup przed wdrożeniem oraz możliwość cofnięcia migracji bazy na środowisku testowym."**
> Ten dokument opisuje jak działają migracje w 3 wtyczkach, jak zrobić backup PRZED wdrożeniem i jak
> **cofnąć migrację na środowisku testowym**. Odnośnik z `DATABASE.md` §4 i `lib/mp-common/src/Migrations.php`.

## 1. Jak działają migracje (mechanizm w kodzie)
- Każda wtyczka trzyma wersję schematu we **własnej opcji**:
  `mp_intake_schema_version` · `mp_registry_schema_version` · `mp_automator_schema_version`.
- `MP\Common\Migrations::run($opcja, [1 => …, 2 => …])` uruchamia **ponumerowane migracje rosnąco**,
  tylko te powyżej zapisanej wersji. Po KAŻDYM udanym kroku wersja jest zapisywana od razu
  (przerwanie w połowie → ponowny przebieg dokańcza od miejsca — idempotentne).
- Uruchamiane przy aktywacji oraz przez `Lifecycle::maybe_upgrade` na `admin_init`
  (**upgrade BEZ reaktywacji** — podbicie wtyczki dociąga zaległe migracje samo).
- **Zmiany są ADDYTYWNE** (`dbDelta`: dodaje tabele/kolumny, **nigdy nie usuwa**). Zmiany nieaddytywne
  (rename/drop) wolno robić WYŁĄCZNIE pod `.maintenance` lub `LOCK TABLES` — egzekwuje treść migracji (DATABASE.md §4).

## 2. Backup PRZED wdrożeniem (obowiązkowo)
Dane systemu to **tabele `wp_mp_*`** (klienci, sprawy, rejestr produktów, reguły, SLA, zdarzenia…)
+ **opcje `mp_*`** (m.in. 3 wersje schematu). Przed każdą instalacją/aktualizacją:

**A. Baza (wp-cli — zalecane):**
```bash
wp db export backup-przed-wdrozeniem-$(date +%F).sql
# lub tylko tabele MP (mniejszy plik):
wp db export backup-mp-$(date +%F).sql --tables=$(wp db tables 'wp_mp_*' --format=csv)
```
**B. Baza (bez wp-cli):** panel hostingu / phpMyAdmin → eksport bazy do `.sql`.

**C. Pliki:** kopia `wp-content/plugins/mp-service-intake`, `mp-warranty-registry`, `mp-workflow-automator`
(oraz `wp-content/uploads/mp-attachments/` jeśli są załączniki). Zwykle wystarczą 3 wtyczki + baza —
kod wtyczek i tak pochodzi z paczki ZIP.

> ⚠️ Na produkcji rób backup **tuż przed** wdrożeniem i sprawdź że plik `.sql` nie jest pusty
> (`ls -lh backup-*.sql`). Bez świeżego backupu — nie wdrażaj.

## 3. Cofnięcie migracji na ŚRODOWISKU TESTOWYM
Ponieważ migracje są **addytywne**, cofnięcie = przywrócenie stanu sprzed migracji. Dwie drogi:

**Droga A — przywrócenie z backupu (najbezpieczniejsza, też produkcja):**
```bash
wp db import backup-przed-wdrozeniem-2026-07-23.sql
wp db check           # sanity
wp cache flush
```
Weryfikacja test-restore: po imporcie sprawdź że treść i funkcje się zgadzają
(np. `wp db query "SELECT COUNT(*) FROM wp_mp_service_cases;"` = liczba sprzed wdrożenia; formularz się otwiera).

**Droga B — ręczne cofnięcie POJEDYNCZEJ migracji (tylko TEST):**
Odwróć zmianę DDL + cofnij licznik wersji, żeby migracja mogła się przejść ponownie. Przykład dla
**migracji v2 rejestru** (dodała kolumnę `category`):
```bash
wp db query "ALTER TABLE wp_mp_product_registry DROP COLUMN category;"
wp option update mp_registry_schema_version 1     # cofnij z 2 na 1
```
Analogicznie inne migracje: DROP dodanej kolumny/tabeli + `wp option update mp_<plugin>_schema_version <poprzednia>`.
> ⚠️ Drogę B stosuj **wyłącznie na teście** (utrata danych z cofniętej kolumny). Na produkcji → Droga A.

## 4. Szybka ściąga (środowisko testowe)
| Krok | Komenda |
|------|---------|
| Backup | `wp db export backup-$(date +%F).sql` |
| Wdrożenie / test | aktywuj/zaktualizuj wtyczki (migracje idą same przez `maybe_upgrade`) |
| Sprawdź wersje | `wp option get mp_registry_schema_version` (itd. dla intake/automator) |
| Cofnięcie | `wp db import backup-….sql` (Droga A) **lub** DROP + `option update` (Droga B) |
| Weryfikacja | `wp db check` + spot-check liczby wierszy + otwarcie formularza |

## 5. Powiązania
- Rygor DDL migracji: `DATABASE.md` §4. · Uninstall / kasowanie danych (opt-in): patrz `OWNERSHIP.md` + uninstall.php.
- Kontrolowane usuwanie danych w RUNTIME (soft-delete, RODO-erasure, retencja) — to osobny temat od migracji (B4).
