# MP Service Suite — zasady pracy w tym repo

System serwisowy MP: **dokladnie 3 pluginy WordPress** (intake / warranty-registry / workflow-automator),
dedykowane tabele `wp_mp_*`, WP 6.9.4 / PHP 8.1+ / MariaDB 10.6+ (demo: 11.8). Spec klienta = swieta;
kontrakt (dokumenty w `dokumentacja-techniczna/`) = zamrozony; zmiany kontraktu tylko swiadoma decyzja.

## Zlote zasady skladni (twarde)
1. **NIE zgadujemy skladni WP/PHP** — kazde niepewne API sprawdzone w developer.wordpress.org;
   literowki w nazwach funkcji lapie PHPStan + wordpress-stubs (stubs pinowane na ~6.9 = wersja TARGETU).
2. **Pre-commit lokalny**: php -l na kazdym zmienionym pliku + linter cudzych tabel + skan sekretow
   (gitleaks; gdy brak lokalnie — pilnuje CI). Commit ze zlamana skladnia fizycznie nie wchodzi.
3. **PR dopiero przy lokalnie zielonym** PHPCS + PHPStan (branch protection i tak nie wpusci czerwonego).
4. **dbDelta WYLACZNIE wg rygoru DATABASE.md**: 2 spacje po PRIMARY KEY, `KEY` nie `INDEX`, bez FOREIGN KEY,
   LONGTEXT (walidacja JSON w PHP) nie typ JSON, `utf8mb4` z `get_charset_collate()`.
5. **i18n i kazdy niepewny wzorzec z AKTUALNYCH docs**, nie z pamieci.
6. **Skrypty w repo = bash** z shebang `#!/usr/bin/env bash` — NIGDY fish.
7. **ZERO placeholderow // TODO** — commitujemy tylko kompletny kod.

## Architektura (nie lam tego)
- **Komunikacja miedzy pluginami WYLACZNIE hookami `mp_*`** przenoszacymi skalary/tablice (nigdy obiekty).
  Kod pluginu NIE MOZE zawierac nazw tabel innego pluginu — pilnuje `build/lint-cudze-tabele.php` (CI).
- **Nazwy tabel tylko ze stalych klasy / centralnej metody** — zakaz dynamicznego skladania nazw w SQL.
- **Wspolny kod = `lib/mp-common` (JEDYNE zrodlo).** Kopie `includes/Common/` sa GENEROWANE przez
  `build/build.sh` (stempel namespace) i gitignorowane — edycja kopii = blad. Release ZIP zawsze
  artefaktem z CI (BUILD-INFO w kazdym ZIP), nigdy budowany recznie.
- **Degraded mode**: plugin bez braci dziala z ograniczeniem, NIGDY fatal. Niezgodnosc wersji kontraktu
  = admin notice + tryb ograniczony.
- **Uprawnienia wylacznie `current_user_can( 'mp_*' )`** (capability, nie nazwa roli). Nonce + capability
  ZAWSZE w parze. `$wpdb->prepare()` do kazdego SQL.
- **Append-only tylko tabele `*_events`** (zero UPDATE/DELETE); zadnych PII w eventach (NO-PII-IN-LOG).
- **Lock ZAWSZE przez INSERT-pod-UNIQUE**, nigdy add_option. Licznik SRV = `wp_mp_srv_counters`.

## Proces
- Kazda zmiana pelnym cyklem **branch → test → commit → PR → squash-merge → kasuj branch**.
  Commity po polsku wg Conventional Commits (feat/fix/docs/chore/test/ci).
- Zmiana JS/CSS = bump `Version` pluginu (nowy `?ver`).
- Docs = kod: zdanie w dokumentacji/diagramie musi miec pokrycie w kodzie (sweep przed wydaniem).
- Testy przed merge: `composer lint && composer phpcs && composer phpstan && composer test && composer tabele`.
