# API-KONTRAKT.md — hooki między pluginami (ZAMROŻONY)

> Jedyny dozwolony kanał komunikacji między pluginami MP. **Zakaz dotykania cudzych tabel
> (czytanie I pisanie)** — pilnuje linter w CI. Przez hooki przechodzą WYŁĄCZNIE **skalary
> i tablice** (nigdy obiekty — stemplowane namespace Common = obce typy = TypeError).

## Zasady twarde

1. **Wersjonowanie**: kontrakt = `MP_CONTRACT_VERSION` (obecnie **1**). Zmiana łamiąca = NOWA nazwa
   hooka, stara żyje do wycofania. Zwrotki niosą `schema_version`.
2. **Niezgodność wersji** przy aktywacji/plugins_loaded = admin notice + tryb ograniczony
   (`MP\{Ns}\Common\Contract`) — NIGDY fatal.
3. **Rejestracja nasłuchów najpóźniej na `init`; emisje WYŁĄCZNIE w runtime żądań/crona** (nigdy
   przy ładowaniu plików).
4. **Detekcja braci przez `has_filter()`** — nie `is_plugin_active()`. Filter niepodpięty → wartość
   domyślna → degraded mode (nigdy fatal).
5. **Akcje mutujące emitowane PO COMMIT transakcji.**
6. Z przykładowych payloadów niżej **generowane są mocki i testy kontraktowe** (spec bez przykładu =
   każdy plugin „zgodny" inaczej).

## A. Akcje (zdarzenia) — emitent → słuchacze

### `mp_case_created( $case_id )` — C → D
Po weryfikacji mailowej sprawy (narodziny sprawy; przejście NULL→'nowe' NIE emituje status_changed).
D: zakłada wiersz `wp_mp_case_sla`, odpala reguły przydziału.
```php
do_action( 'mp_case_created', 123 );
```

### `mp_case_status_changed( $case_id, $old_status, $new_status, $actor_id )` — C → D
Emitowana PO COMMIT przez `mp_case_change_status()` przy KAŻDEJ późniejszej zmianie statusu
(także wykonanej przez D). JAWNA SEMANTYKA: wyłącznie zmiany PO narodzinach.
```php
do_action( 'mp_case_status_changed', 123, 'nowe', 'w analizie', 7 );
```

### `mp_case_message_added( $case_id, $message_id, $author_type )` — C → D
`$author_type` ∈ {client, staff, system} (zamknięta lista).
```php
do_action( 'mp_case_message_added', 123, 456, 'client' );
```

### `mp_warranty_exception_changed( $exception_id, $product_registry_id, $case_id, $status, $schema_version )` — B → C, D
Po przyznaniu/cofnięciu wyjątku (PO COMMIT). `$case_id` NULL = wyjątek globalny na produkt.
C: dopisuje case_event EXCEPTION_APPLIED/REVOKED (case_id=NULL → jawny no‑op).
D: trigger reguł (condition_key `exception_status`).
```php
do_action( 'mp_warranty_exception_changed', 11, 42, 123, 'active', 1 );
```

### `mp_sla_notified( $case_id, $kind, $recipient_ref )` — D → C
Po skutecznej wysyłce przypomnienia/eskalacji SLA. `$kind` ∈ {reminder, escalation};
`$recipient_ref` = referencja adresata (user_id / 'customer'), NIGDY adres e‑mail.
C: dopisuje event SLA_REMINDER_SENT / SLA_ESCALATED do osi sprawy (spec, relacja 3).
```php
do_action( 'mp_sla_notified', 123, 'escalation', 'role:mp_coordinator' );
```

### `mp_cases_data_erased()` — C → B, D (bez argumentów)
Sygnał GLOBALNY z uninstalla C ścieżką ON: „tabele spraw przestały istnieć".
D: pełny wipe SWOICH tabel per‑sprawa (case_sla, case_checklists; workflow_events zostaje —
rejestr historyczny). B: wyjątki z `case_id NOT NULL` → revoked + event (globalne zostają).
```php
do_action( 'mp_cases_data_erased' );
```

## B. Filtry — pytania o dane (właściciel odpowiada)

### `mp_warranty_check( $result, $serial, $case_id = null, $verify = null )` — pyta C (i inni), odpowiada B
`$verify` opcjonalnie `{purchase_doc, purchase_date}` — B porównuje U SIEBIE (dokument nie wychodzi
przez hook — minimalizacja PII). Wyjątek z `case_id` honorowany TYLKO gdy `$case_id` się zgadza.
Status = stan FAKTYCZNY gwarancji (wyjątek i archived to NIE statusy). Bez B → default →
snapshot „brak danych/wymagana weryfikacja".
```php
$check = apply_filters( 'mp_warranty_check', null, 'ABC123', 123, array(
    'purchase_doc'  => 'FV/2026/0017',
    'purchase_date' => '2026-03-01',
) );
// Zwrotka:
array(
    'found'               => true,
    'archived'            => false,   // Intake blokuje NOWE zgłoszenia na produkt archiwalny
    'purchase_doc_match'  => true,    // true|false|null (null = brak danych w rejestrze)
    'purchase_date_match' => false,
    'product_id'          => 42,
    'serial_normalized'   => 'ABC123',
    'model'               => 'XJ-500',
    'batch'               => 'B-2026-03',
    'status'              => 'aktywna', // aktywna|wygasla|brak_danych|weryfikacja (4 ze spec)
    'warranty_until'      => '2028-03-01',
    'is_overridden'       => false,
    'exception_id'        => null,    // pola exception_* = null gdy is_overridden=false
    'override_until'      => null,
    'override_reason'     => null,    // notatka WEWNĘTRZNA — nigdy do klienta
    'checked_at'          => '2026-07-21T18:00:00Z',
    'registry_updated_at' => '2026-07-20T09:00:00Z',
    'schema_version'      => 1,
);
```

### `mp_serial_usage_count( $count, $serial )` — odpowiada B
Ile spraw używa serialu (zasilany przez `mp_case_count_by_product` z C; bez C → „brak danych",
nie zero).

### `mp_customer_find_products( $result, $query )` — pyta B, odpowiada C
Wyszukiwarka „po kliencie" w B mechaniką odwróconą (C zna mapping klient→sprawy→produkty).
```php
array( 'ids' => array( 42, 57 ), 'truncated' => false, 'limit' => 200 );
```

### `mp_product_active_cases_count( $count, $product_registry_id )` — pyta B, odpowiada C → int
Blokada usunięcia I archiwizacji produktu z aktywną sprawą. **FAIL‑CLOSED**: brak słuchacza →
B odmawia operacji z komunikatem.

### `mp_case_count_by_product( $result, $product_registry_id )` — pyta B, odpowiada C
```php
array( 'total' => 5, 'active' => 1, 'closed' => 3, 'rejected' => 1 );
```
Sprawy unverified NIE wliczają się (anty‑wektor „spamer blokuje produkty").

### `mp_privacy_redact_for_customer( $result, $customer_id, $case_ids )` — woła C (eraser), odpowiada B
Orkiestracja RODO: C = właściciel procesu anonimizacji; B redaguje `warranty_exceptions.reason`
powiązane ze sprawami klienta. B nieaktywne/błąd → eraser raportuje `items_retained` z powodem.
```php
array( 'success' => true, 'redacted_count' => 2 );
```

### `mp_rejection_reasons( $reasons )` — oddaje D
Słownik powodów odrzuceń (kod→etykieta; opcja‑treść, edycja w adminie D). Bez D → C używa
awaryjnego mini‑słownika (DUPLICATE / NO_RESPONSE / OTHER) + ręczny kod ≤64.
```php
array( 'gwarancja_wygasla' => 'Gwarancja wygasła', 'duplikat' => 'Zgłoszenie zduplikowane', /* … */ );
```

### `mp_registered_statuses( $statuses )` — oddaje D
Definicje statusów WŁASNYCH (D = źródło definicji, C = walidator przejść). Bez D → rdzeń 7.
```php
array( 'ekspertyza_zew' => array( 'label' => 'Ekspertyza zewnętrzna', 'terminal' => false ) );
```
**Limit sluga: ≤ 20 znaków** — `wp_mp_service_cases.status` = `VARCHAR(20)`. Slug to KLUCZ MASZYNOWY (po `sanitize_key`); długą nazwę ludzką niesie `label` (bez limitu). Slug > 20 znaków jest **odrzucany przy rejestracji** (`StatusDefs::SLUG_MAX=20` → `continue`/`return ''`, NIE ucina — zero kolizji). C jest chroniony **przechodnio**: `mp_case_change_status` puszcza tylko `Statuses::exists()`, a slug > 20 nigdy się nie zarejestruje → dostałby `INVALID_STATUS`; dlatego osobny check długości w C jest zbędny. *(Poprzednia wersja przykładu — `ekspertyza_zewnetrzna`, 21 zn — łamała ten limit i była cicho ucinana; złapane samo-kontrolą buildera + strażnik, 22.07.)*

### `mp_case_card_sections( $sections, $case_id )` — renderuje C, dokłada D
```php
$sections[] = array( 'title' => 'Checklista', 'content' => $html, 'order' => 30 );
```

### `mp_intake_captcha_html( $html )` — pusty slot C (captcha nie od startu).

## C. Funkcje kontraktowe C (operacje na sprawach — jedyna droga zapisu dla D)

Wszystkie: walidacja + event w historii + kody błędów wg ERROR_MODEL. UPDATE + event w JEDNEJ
transakcji, akcje PO commit. `mp_cases_query` respektuje ROLĘ wołającego (mp_agent → tylko swoje).

| Funkcja | Kontrakt |
|---|---|
| `mp_case_get_context( $case_id )` | → `{status, rodzaj, priority, assigned_to, kategoria, kraj, język, verified_at, status_changed_at, case_number, rejection_reason_code, kontakt}`; kontakt = runtime do maili, NIGDY do logów; nieistniejąca sprawa → `'not_found'` |
| `mp_case_change_status( $case_id, $new_status, $expected_status, $actor_id, $rejection_reason_code = null )` | optimistic‑lock (`WHERE status = expected`); „odrzucone" WYMAGA kodu; emituje `mp_case_status_changed` PO commit |
| `mp_case_assign( $case_id, $user_id, $actor_id )` | walidacja (istnienie, verified, rola przydzielanego) + event `CASE_ASSIGNED {from, to, actor}` |
| `mp_case_set_priority( $case_id, $priority, $actor_id )` | + event `PRIORITY_CHANGED` |
| `mp_case_checklist_authorize( $case_id, $step_key, $completed, $actor_id )` | walidacja własności/roli + event `CHECKLIST_ITEM_TOGGLED`; KOLEJNOŚĆ: najpierw ta funkcja, po OK → D zapisuje stan u siebie |
| `mp_case_add_system_message( $case_id, $content )` | wiadomość systemowa (author_type=system) — m.in. RAPORT KOŃCOWY sprawy od D |
| `mp_cases_query( $filters, $page, $per_page )` | paginowane (chunk 500) — raporty/eksport/resync D |

## D. Kto co emituje / słucha (mapa skrótowa)

| Hook | Emituje/oddaje | Słucha/woła |
|---|---|---|
| mp_case_created · mp_case_status_changed · mp_case_message_added | C | D |
| mp_warranty_exception_changed | B | C, D |
| mp_sla_notified | D | C |
| mp_cases_data_erased | C | B, D |
| mp_warranty_check · mp_serial_usage_count | B | C (i inni) |
| mp_customer_find_products · mp_product_active_cases_count · mp_case_count_by_product | C | B |
| mp_privacy_redact_for_customer | B (listener) | C (eraser) |
| mp_rejection_reasons · mp_registered_statuses · sekcje karty | D | C |
| funkcje kontraktowe spraw (§C) | C | D |
