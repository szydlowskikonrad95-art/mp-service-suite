# EVENT_MODEL.md — model zdarzeń (ZAMROŻONY)

> Trzy tabele APPEND‑ONLY (zero metod UPDATE/DELETE, bez wyjątków): `wp_mp_case_events` (C),
> `wp_mp_product_events` (B), `wp_mp_workflow_events` (D). Spec: „każda zmiana statusu, komentarz,
> powiadomienie i decyzja tworzy nieusuwalny wpis w osi czasu sprawy" + „rejestr operacji istotnych"
> per plugin.

## 1. ŻELAZNA ZASADA NO‑PII‑IN‑LOG

Zdarzenia są **W 100% STRUKTURALNE**: referencje (`customer_id`, `message_id`), fakty (status
z→na), kody decyzji. **ZERO pól wolnotekstowych w events.** Komentarze/notatki żyją w
`wp_mp_messages` (redagowalnej), event trzyma wskaźnik. Maile w events wyłącznie jako **rodzaj
wiadomości i referencja adresata** (w C: `{kind}` / `{kind, error_code}`; w D: `{template_key,
recipient_ref}`) — **nigdy adres ani wyrenderowana treść**. Diffy produktu: pola
`pii_sensitive` TYLKO jako `{field, changed: true}`. Efekt: **events NIETYKALNE BEZ WYJĄTKÓW** —
redakcja RODO ich nie dotyka, a w historii ląduje nowy event `PII_REDACTION`.

Interpretacja „nieusuwalna historia": oś czasu, typy zdarzeń, daty i decyzje NIGDY nie znikają;
audit log ≠ application log. Sprawa unverified nie pisze ŻADNYCH eventów (events startują przy
weryfikacji, z referencjami do już istniejących rekordów).

## 2. Wpis zdarzenia (wspólny kształt)

| Pole | Zasada |
|---|---|
| `case_id` / `product_registry_id` | referencja obiektu |
| typ | zamknięta lista per tabela (niżej) — każdy typ w systemie MA NAZWĘ |
| `payload` | LONGTEXT, JSON walidowany w PHP przy zapisie |
| `schema_version` | wersja kształtu payloadu (w payloadzie) |
| actor | user_id / `system` |
| `created_at` | UTC |

Zapis eventu i mutacja stanu = JEDNA transakcja; akcje `mp_*` po commit.

⛔ **„Status bez eventu NIGDY" — od 1.3.13 EGZEKWOWANE, nie tylko deklarowane (D2).** Sama transakcja
tego nie załatwia: nieudany INSERT eventu jej nie przerywa, więc do 1.3.12 COMMIT szedł mimo braku
wpisu i status zmieniał się po cichu, bez śladu na osi, którą README obiecuje jako nieusuwalną
i kompletną. `CaseRepo::change_status` sprawdza teraz wynik `CaseEvents::log()` i przy porażce
**wycofuje całą transakcję** (zwrotka `EVENT_LOG_FAILED`) — lepiej odmówić zmiany, niż zmienić stan
bez śladu. **Zakres:** gwarancja obowiązuje dla `STATUS_CHANGED`. `CASE_ASSIGNED` i `PRIORITY_CHANGED`
mają event w tej samej transakcji, ale wyniku zapisu nie sprawdzają — przy nieudanym INSERT mutacja
zostaje, a alarm podnosi `Common\EventWrite` („Stan witryny"). `wp_mp_workflow_events` (D) nigdy nie
idzie w transakcji z mutacją C: to dziennik operacji automatu zapisywany PO commit C, z założenia
best‑effort.

## 3. Typy zdarzeń — `wp_mp_case_events` (C)

Lista jest ZAMKNIĘTA i odpowiada stałym w `MP\Intake\CaseEvents` — 15 typów, jeden do jednego.

| Typ | Payload (strukturalny) |
|---|---|
| CASE_CREATED | {case_number, rodzaj, product_registry_id\|null} |
| STATUS_CHANGED | {from, to, actor, rejection_reason_code?} |
| CASE_ASSIGNED | {from, to, actor} (auto i ręczny — każdy przydział) |
| PRIORITY_CHANGED | {from, to, actor} |
| CHECKLIST_ITEM_TOGGLED | {step_key, completed, actor_id} |
| EXCEPTION_APPLIED / EXCEPTION_REVOKED | {exception_id} (listener `mp_warranty_exception_changed`; case_id=NULL → no‑op) |
| SLA_REMINDER_SENT / SLA_ESCALATED | {kind, recipient_ref} (listener `mp_sla_notified`) |
| CONSENT_RECORDED / CONSENT_WITHDRAWN | {consent_id, wersja} |
| PII_REDACTION | {target} — `'customer'` przy anonimizacji klienta; przy redakcji pól sprawy lista zredagowanych POL, nigdy wartości |
| **MAIL_SENT** | {kind} — ⚠️ **dopisywany TYLKO wtedy, gdy jest co odwoływać**: gdy wcześniejsza wysyłka na tej sprawie padła. Zwykła, udana wysyłka NIE puchnie osi ani o wiersz (`Front\Mailer.php:153-159`) |
| **MAIL_FAILED** | {kind, error_code} — wysyłka odbita przez serwer poczty; z tego wpisu bierze się oznaczenie „⚠ Link NIE doszedł” na ekranie „Niepotwierdzone” (`Front\Mailer.php:164-175`) |
| **CONTACT_UPDATED** | {fields: [nazwy zmienionych pól], actor: 'client'} — **nigdy wartości** (numer telefonu jest daną osobową); klient poprawił dane kontaktowe w panelu (2.49). Wpis ląduje na KAŻDEJ sprawie tego klienta, bo tam patrzy pracownik, zanim zadzwoni; zapis bez faktycznej zmiany nie tworzy wpisu (`Front\AccountPage.php:327-334`) |

⚠️ **Czego tu NIE MA, choć bywało opisywane:** `VALIDATION_FAILED`, `CUSTOMER_ANONYMIZED`
i `RATE_LIMIT` **nie istnieją w kodzie** — to były typy‑widma tego dokumentu. Odrzucenie walidacji
nie zostawia eventu (sprawa jeszcze nie istnieje), anonimizacja pisze `PII_REDACTION {target:'customer'}`
(`Privacy.php:155`), a odmowy ogranicznika żyją w tabeli `wp_mp_rate_counters`, nie na osi sprawy.
**Kto pisał integrację pod te nazwy, nasłuchiwał na coś, co nigdy nie padnie.**

## 4. Typy zdarzeń — `wp_mp_product_events` (B)

Lista ZAMKNIĘTA — **trzy typy**, wszystkie mają wywołanie w kodzie.

| Typ | Payload |
|---|---|
| PRODUCT_UPDATED | diff `{pole: {before, after}}`; pola z `ProductEvents::PII_FIELDS` (dokument zakupu) → sam fakt zmiany, bez wartości. Emitowane przez `Repo::update()` (ekran „popraw dane", `Repo.php:471`) **oraz przez `Archive` przy zmianie flagi `archived` w OBIE strony** (`Archive.php:149` — archiwizacja i przywrócenie to ten sam typ z diffem `archived`). Brak realnej zmiany = brak wpisu |
| EXCEPTION_CREATED / EXCEPTION_REVOKED | {exception_id, typ, actor_id} — NIGDY kopia tekstu `reason` (`WarrantyExceptions.php:132`, `:225`) |

⚠️ **Czego tu NIE MA, choć bywało opisywane:**
- `PRODUCT_RESTORED` — **nie istnieje**. Przywrócenie z archiwum zapisuje `PRODUCT_UPDATED`
  z diffem `archived: {before:1, after:0}`; ten sam wiersz tabeli wyżej sam to mówił, więc
  dokument przeczył sobie o dwie linie.
- `PRODUCT_FORCE_DELETED` — **nie istnieje, bo nie istnieje operacja**. `OWNERSHIP.md` §4 stwierdza
  wprost: „twardego usuwania produktu **nie ma w ogóle** — ani z panelu, ani z WP‑CLI"; usuwanie
  z UI to soft delete (`archived`). **Dwa ZAMROŻONE dokumenty mówiły coś przeciwnego** — ten opisywał
  zdarzenie operacji, której drugi zabrania.
- **„przebiegi importu"** — import **nie pisze do `product_events`**. Statystyki przebiegu żyją
  w tabeli `wp_mp_import_jobs` (`total/processed/success/error_rows` + raport błędów), i to jest
  właściwe miejsce: to stan zadania, nie zdarzenie produktu.

## 5. Typy zdarzeń — `wp_mp_workflow_events` (D)

| Typ | Payload |
|---|---|
| wykonanie reguły | {rule_id, case_id, trigger, akcja, wynik, depth} — audyt „czemu automat to zrobił" |
| RULE_LOOP_BLOCKED / RULE_LIMIT_HIT | {rule_id, case_id, depth} |
| ASSIGNMENT_UNMATCHED | {case_id, trigger} (żadna reguła/pusta pula — świadomy stan) |
| MAIL_FAILED / MAIL_FAILED_FINAL | {rule_id?, template_key, case_id, error_code} |
| MAIL_SKIPPED_NO_RECIPIENT | {case_id, template_key} (klient zanonimizowany = stan legalny) |
| EXPORT_GENERATED | {user_id, liczba wierszy, hash filtrów} — bez PII |
| CRUD konfiguracji | {obiekt, id, actor} (reguły/szablony/statusy/SLA/**pula pracowników** — `object=assignment_pool` z `rule_id` i liczbą osób, bez identyfikatorów w treści) |
| CLOSING_REPORT_GENERATED | {case_id} — raport końcowy po zamknięciu sprawy |
| MAIL_DEDUPED | {case_id, template_key} — identyczna wiadomość w oknie dedupu |
| przebiegi sweepa / resync / „Przelicz terminy obsługi" | {statystyki przebiegu; przy przerwaniu budżetem maili także `budzet_maili` i `przerwany_budzetem`} |

`wp_mp_workflow_events` przy uninstallu C (sygnał `mp_cases_data_erased`) ZOSTAJE — rejestr
operacji D jest historyczny, nie wskazuje „na żywo".

## 6. Snapshot‑wzorzec (spokrewniony z eventami)

Dane, które muszą pokazywać ÓWCZESNĄ prawdę, są zamrażane w wierszu przy zdarzeniu:
`form_data` (etykiety pól z chwili złożenia) · `warranty_snapshot` (gwarancja z chwili zgłoszenia) ·
`step_label` w odhaczeniu checklisty · pełny tekst zgody w consents. Zmiana definicji/konfiguracji
NIGDY nie przepisuje historii.
