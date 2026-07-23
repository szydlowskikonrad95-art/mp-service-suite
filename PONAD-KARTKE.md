# Co dodaliśmy ponad kartkę — i dlaczego

> **DRAFT do przeglądu.** Ten dokument spisuje rzeczy, które w kodzie **wyglądają jak „więcej niż w specyfikacji"**, i dla każdej pokazuje, **którą literę specyfikacji realizują**. Cel: żeby recenzent nie musiał się domyślać — każda „nadwyżka" ma kotwicę w wymaganiach klienta, a nie jest samowolą programisty.

Format każdego punktu: **CO** (co widać w kodzie) · **KOTWICA W KARTCE** (który wymóg to uzasadnia) · **GDZIE** (plik/klasa).

---

## 1. Weryfikacja mailowa zgłoszenia (magic-link + potwierdzenie POST)

- **CO:** zgłoszenie z formularza nie jest od razu „żywą" sprawą — na e‑mail idzie jednorazowy link (magic‑link), a potwierdzenie następuje przez POST. Dopiero potwierdzenie zakłada konto klienta i wpuszcza sprawę do obiegu.
- **KOTWICA W KARTCE:** P1.6 „ochrona przed spamem i duplikatami zgłoszeń". Weryfikacja adresu to mechanizm realizujący tę literę — bez potwierdzonego maila nie da się masowo zaśmiecić systemu ani podszyć pod cudzy adres.
- **GDZIE:** `mp-service-intake/includes/CaseRepo.php` (token: `verify_token_hash`, `verify_token_expires_at`, `verify_token_used_at`), `Front/SubmissionHandler.php`, potwierdzenie w `Front/AccountPage.php`/`Front/Login.php`.

## 2. Stan techniczny sprawy PRZED „nowe" (bufor weryfikacji)

- **CO:** sprawa niezweryfikowana ma `identity_status = 'pending'` i **nie ma jeszcze żadnego z 7 statusów** kartki — status roboczy pojawia się dopiero przy potwierdzeniu.
- **KOTWICA W KARTCE:** 7 statusów ze specyfikacji jest **nietkniętych** — „pending/przed‑wejściem" to stan techniczny PRZED wejściem na oś statusów, nie ósmy status. To wprost służy P1.6 (nieweryfikowane zgłoszenia nie zajmują kolejki).
- **GDZIE:** `mp-service-intake/includes/CaseRepo.php` (`identity_status`), `mp-service-intake/includes/Statuses.php` (rdzeń 7 statusów `CORE`, nieusuwalny).

## 3. Skala silnika RODO (zgody, eraser, exporter, anonimizacja, retencja)

- **CO:** rozbudowany moduł prywatności — wersjonowane zgody z możliwością wycofania, natywny WP eraser/exporter, prawdziwa anonimizacja klienta i redakcja PII w wiadomościach/danych formularza, retencja załączników z cronem.
- **KOTWICA W KARTCE:** wymagania RODO ze specyfikacji — minimalizacja danych, anonimizacja, rejestr zgód, zdefiniowana retencja. Realizujemy **literę** tych wymagań; „skala" bierze się z tego, że dane osobowe żyją w 3 wtyczkach i każdą trzeba domknąć.
- **GDZIE:** `mp-service-intake/includes/Privacy.php`, `Consents.php`, `CaseRepo.php` (anonimizacja/redakcja), `Attachments.php` (retencja + cron), tabela `wp_mp_consents`.

## 4. 15 tabel bazy zamiast 4 „bazowych"

- **CO:** specyfikacja (sekcja 2 „Trzy zależności baz danych") wylicza **4 tabele bazowe i 3 relacje**; w bazie jest **15 tabel**.
- **KOTWICA W KARTCE:** specyfikacja wylicza **relacje, nie limituje liczby tabel** — a jej wymagania funkcjonalne wymuszają dodatkowe tabele. Każda tabela ponad 4 bazowe ma cytat‑uzasadnienie z konkretnego wymagania. Przykłady: `wp_mp_attachments` (T5/RODO „limity plików + retencja"), `wp_mp_consents` (RODO „rejestr zgód"), `wp_mp_workflow_rules` (P3.1 „automatyczny przydział wg kategorii/kraju/języka/priorytetu"), `wp_mp_case_sla` (P3.4 „przypomnienie przed terminem + eskalacja"), `wp_mp_case_checklists` (P3.5 „checklisty per typ sprawy"), `wp_mp_workflow_events` (sekcja 1 „rejestr operacji istotnych").
- **GDZIE:** pełna mapa 15 tabel z właścicielem i cytatem‑uzasadnieniem per tabela: `dokumentacja-techniczna/DATABASE.md` §1.

## 5. Magic‑linki / tokeny konta klienta (split‑token, jednorazowe, TTL)

- **CO:** logowanie klienta bez hasła (passwordless) — token dzielony na część jawną i sekret (split‑token), jednorazowy, z krótkim czasem życia, porównywany `hash_equals`.
- **KOTWICA W KARTCE:** P1.5 „konto klienta: status na żywo + historia wiadomości" — konto wymaga bezpiecznego wejścia. Passwordless z jednorazowym tokenem to bezpieczna realizacja logowania do tego konta (brak haseł do wycieku).
- **GDZIE:** `mp-service-intake/includes/Front/Login.php`, `CaseRepo.php` (generowanie/weryfikacja tokenu), panel „moje zgłoszenia" IDOR‑safe (ownership z sesji).

## 6. WCAG‑lite formularza i panelu (etykiety, kontrast, klawiatura/fokus, aria)

- **CO:** dostępność — powiązane etykiety, kontrast ≥ 4.5:1, obsługa klawiatury z widocznym fokusem, `aria`/`caption` dla czytników ekranu.
- **KOTWICA W KARTCE:** T7 „widok responsywny/dostępny dla klienta" + wymóg dostępności (EAA). Formularz i panele admina realizują literę „dostępny dla klienta", a nie dokładają funkcji ponad zakres.
- **GDZIE:** `mp-service-intake` (CSS + markup formularza), `mp-workflow-automator/includes/Admin/PanelScreen.php` + `assets/css/admin-automator.css` (kontrast/fokus/caption sr-only).

## 7. Hooki kontraktowe C↔D + linter granic wtyczek

- **CO:** wtyczki nie sięgają w swoje tabele nawzajem — komunikują się przez zestaw hooków kontraktowych (`mp_case_get_context`, `mp_cases_query`, `mp_all_statuses`, `mp_case_checklist_authorize`, `mp_sla_notified`…), a granic pilnuje automatyczny linter w CI.
- **KOTWICA W KARTCE:** specyfikacja wymaga **3 OSOBNYCH pluginów**. Prawdziwa separacja wtyczek wymaga zdefiniowanego styku — hooki są tym stykiem, a linter gwarantuje, że nikt go nie obchodzi literałem cudzej tabeli.
- **GDZIE:** hooki rejestrowane w `mp-service-intake/includes/Plugin.php`; konsumpcja w `mp-workflow-automator` (np. `Sla.php`, `Admin/PanelScreen.php`); linter granic: `build/lint-cudze-tabele.php` (uruchamiany w CI); kontrakt opisany w `dokumentacja-techniczna/API-KONTRAKT.md` i `OWNERSHIP.md`.

---

**Podsumowanie:** wszystkie powyższe to **realizacja litery specyfikacji w skali wynikającej z 3‑wtyczkowej architektury** — nie funkcje ponad zakres. Każdy punkt ma kotwicę w konkretnym wymaganiu klienta i miejsce w kodzie do sprawdzenia.
