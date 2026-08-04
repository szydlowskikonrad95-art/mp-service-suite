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
6. Przykładowe payloady niżej są **wzorcem odniesienia dla testów kontraktowych** (spec bez
   przykładu = każda wtyczka „zgodna" inaczej). ⚠️ Testy są **pisane ręcznie na podstawie tych
   przykładów, nie generowane automatycznie** — nie ma generatora tworzącego je z tego dokumentu.
   Żywe testy filtrów kontraktowych: `testy/e2e/d-hooki-c.sh`,
   `testy/e2e/kontrakt-dane-skasowane.sh`, `testy/e2e/blok-s-tabletop.sh`.
   **Zmieniasz przykład w tym dokumencie → popraw też test.**
7. **Filtry kontraktowe NIE sprawdzają uprawnień użytkownika — i tak ma być.** Autoryzacja siedzi
   o warstwę wyżej, w miejscu wywołania (patrz niżej).

## Gdzie jest autoryzacja (a gdzie jej celowo NIE ma)

Filtry z tego pliku to **wewnętrzne API między wtyczkami**, nie publiczne wejście. Nie wołają
`current_user_can()`, bo najczęstszy wywołujący to **cron** — sweep SLA i silnik reguł działają
bez zalogowanego użytkownika. Gdyby filtr wymagał uprawnień, automatyzacja przestałaby działać
o pierwszej w nocy.

Uprawnienia sprawdza **warstwa, która przyjmuje żądanie od człowieka**:

| Wejście | Kto pilnuje | Czego wymaga |
|---|---|---|
| Ekrany i akcje personelu (`admin_post_*`) | `MP\Intake\Admin\CaseActions` | nonce + `mp_agent` / `mp_coordinator` / `mp_system_admin` |
| Panel klienta (front) | `MP\Intake\Front\AccountPage` | zalogowany `mp_client` + **własność sprawy** (ochrona przed podglądaniem cudzych) |
| Formularz publiczny | `MP\Intake\Front\SubmissionHandler` | nonce + honeypot + pułapka czasowa + limity |
| Reguły i SLA (cron) | — | brak użytkownika z założenia; działanie ograniczone kontraktem |

**Konsekwencja praktyczna:** wywołanie `apply_filters( 'mp_case_change_status', ... )` z kodu PHP
zmieni status **niezależnie od tego, kto jest zalogowany**. To nie jest luka — kto może wykonać PHP
na serwerze, ten i tak ma pełny dostęp do bazy. Ale jeśli dopisujesz **nowy** endpoint (REST, AJAX,
`admin_post`), to **Ty** odpowiadasz za sprawdzenie uprawnień przed wywołaniem filtra; kontrakt tego
za Ciebie nie zrobi.

Sprawdzone praktycznie (27.07.2026): anonimowy `POST` na `admin-post.php` z akcją zmiany statusu
kończy się **HTTP 400 i zerową zmianą w bazie**; zalogowany klient przez kontraktowy
`mp_cases_query` **nie widzi cudzych spraw**, a eksport CSV zwraca mu **zero** rekordów.

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

### `mp_case_assigned( $case_id, $from, $to, $actor_id )` — C → D
Emitowana PO COMMIT przez `mp_case_assign()` przy KAŻDYM przydziale (auto i ręczny; dowolny caller —
`assigned_to` ma jednego writera). Zasada „każdy przydział → notyfikacja nowego pracownika" = gwarancja
struktury, nie call‑site. Wpis na osi (`CASE_ASSIGNED`) powstaje w tej samej transakcji; hook służy
akcjom PO fakcie (mail D). `$from` = poprzedni przypisany (`null` = brak).
```php
do_action( 'mp_case_assigned', 123, null, 7, 0 );
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
`$recipient_ref` = referencja adresata NO‑PII, NIGDY adres e‑mail. Wartości emitowane przez D:
`'user:<id>'` (przypomnienie → przypisany agent) · `'role:mp_coordinator'` (eskalacja i fallback
nieprzydzielonej sprawy → koordynator). SLA NIE powiadamia klienta (odbiorcą jest personel).
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

### `mp_sla_sweep_tick()` — D → C (bez argumentów)
Tick na starcie każdego przebiegu sweepa SLA (co 5 min, pod GET_LOCK). Daje słuchaczom okazję
doszyć zaległości ZANIM przebieg wybierze wymagalne terminy. C: reconcile sierot weryfikacji
(audyt #1 — sprawa potwierdzona, której awaria urwała `CASE_CREATED`, dostaje dosyłkę zdarzenia
i akcji `mp_case_created`; doszyta sprawa prowizjonuje SLA/przydział natychmiast, jej terminy
łapie kolejny przebieg). Bez D nikt nie nasłuchuje `mp_case_created`, więc i tick nie jest
potrzebny — diagnostykę zaległości daje test „Stanu witryny" w C.
```php
do_action( 'mp_sla_sweep_tick' );
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

### `mp_product_category( $default, $product_registry_id )` — odpowiada B
Kategoria produktu po ID (slug ze słownika: audio/agd/elektronarzedzia/inne). Read-only; brak
produktu / brak kategorii → zwraca `$default` (zwykle `null`), nigdy błąd. Zasila
`get_context.kategoria` w C → oś przydziału w D. Implementacja: `MP\Registry\Repo::category_for`.

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

### `mp_cases_verified_ids( $result, $days = 30, $limit = 200 )` — pyta D, odpowiada C

Zwraca **SAME IDENTYFIKATORY** spraw zweryfikowanych w oknie `$days` (bez danych osobowych —
RODO/T5). D porównuje tę listę z własną tabelą terminów i doszywa różnicę: sprawy potwierdzone
w chwili, gdy Automator był WYŁĄCZONY, mają u siebie komplet śladów (C zapisał zdarzenie i
wyemitował akcję), więc reconcile po braku zdarzenia narodzin ich NIE widzi. Wołane z crona,
więc **bez bramki uprawnień** — jak `mp_case_get_context`. Okno i limit trzymają koszt zapytania.

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
**Limit sluga: ≤ 20 znaków** — `wp_mp_service_cases.status` = `VARCHAR(20)`. Slug to KLUCZ MASZYNOWY (po `sanitize_key`); długą nazwę ludzką niesie `label` (bez limitu). Slug > 20 znaków jest **odrzucany przy rejestracji** (`StatusDefs::SLUG_MAX=20` → `continue`/`return ''`, NIE ucina — zero kolizji). C jest chroniony **przechodnio**: `mp_case_change_status` puszcza tylko `Statuses::exists()`, a slug > 20 nigdy się nie zarejestruje → dostałby `INVALID_STATUS`; dlatego osobny check długości w C jest zbędny. *(Uwaga przy dobieraniu slugów: `ekspertyza_zewnetrzna` ma 21 znaków i ten limit przekracza — dlatego przykład wyżej używa krótszej formy.)*

### Karta sprawy — sekcje D przez DEDYKOWANE filtry (renderuje C, odpowiada D)
> *(Audyt #15: wcześniej opisany tu `mp_case_card_sections` NIE istniał w kodzie — hook-widmo;
> ktoś budujący 4. wtyczkę podpiąłby się i nic by się nie stało. Poniżej realny mechanizm.)*

**`mp_case_deadline( $result, $case_id )`** — karta i lista C pytają o terminy SLA sprawy.
Zwrotka `{deadline_at, warning_at, status}` (wiersz `wp_mp_case_sla`) albo `null` gdy brak SLA/D.
```php
$sla = apply_filters( 'mp_case_deadline', null, 123 );
```

**`mp_case_checklist_state( $result, $case_id )`** — karta C pyta o checklistę sprawy.
Zwrotka: PEŁNA lista kroków rodzaju z nałożonym stanem odhaczeń —
`[{step_key, label, completed, completed_by, completed_at}]`; pusta gdy sprawa/rodzaj nieznany.
```php
$steps = apply_filters( 'mp_case_checklist_state', null, 123 );
```

### `mp_intake_captcha_html( $html )` — pusty slot C (captcha nie od startu).

## C. Funkcje kontraktowe C (operacje na sprawach — jedyna droga zapisu dla D)

Wszystkie: walidacja + event w historii + kody błędów wg ERROR_MODEL. UPDATE + event w JEDNEJ
transakcji, akcje PO commit. `mp_cases_query` respektuje ROLĘ wołającego (mp_agent → tylko swoje).

| Funkcja | Kontrakt |
|---|---|
| `mp_case_get_context( $case_id )` | → `{status, rodzaj, priority, assigned_to, kategoria, kraj, język, verified_at, status_changed_at, case_number, rejection_reason_code, kontakt}`; kontakt = runtime do maili, NIGDY do logów; nieistniejąca sprawa → `'not_found'` |
| `mp_case_change_status( $case_id, $new_status, $expected_status, $actor_id, $rejection_reason_code = null )` | optimistic‑lock (`WHERE status = expected`); „odrzucone" WYMAGA kodu; emituje `mp_case_status_changed` PO commit |
| `mp_case_assign( $case_id, $user_id, $actor_id )` | walidacja (istnienie, verified, rola przydzielanego) + event `CASE_ASSIGNED {from, to, actor}`. **Sprawa TERMINALNA (zamknięte/odrzucone) → `error_code: 'CASE_CLOSED'`**, transakcja wycofana, zero eventu i zero maila — do pracy sprawa wraca przez wznowienie |
| `mp_case_set_priority( $case_id, $priority, $actor_id )` | + event `PRIORITY_CHANGED`. **Sprawa TERMINALNA → `error_code: 'CASE_CLOSED'`** (jak przy przydziale) |
| `mp_case_checklist_authorize( $case_id, $step_key, $completed, $actor_id )` | walidacja własności/roli + event `CHECKLIST_ITEM_TOGGLED`; KOLEJNOŚĆ: najpierw ta funkcja, po OK → D zapisuje stan u siebie |
| `mp_case_add_system_message( $case_id, $content )` | wiadomość systemowa (author_type=system) — m.in. RAPORT KOŃCOWY sprawy od D |
| `mp_cases_query( $filters, $page, $per_page )` | paginowane (chunk 500) — raporty/eksport/resync D |

## D. Kto co emituje / słucha (mapa skrótowa)

| Hook | Emituje/oddaje | Słucha/woła |
|---|---|---|
| mp_case_created · mp_case_status_changed · mp_case_message_added · mp_case_assigned | C | D |
| mp_warranty_exception_changed | B | C, D |
| mp_sla_notified | D | C |
| mp_cases_data_erased | C | B, D |
| mp_warranty_check · mp_serial_usage_count | B | C (i inni) |
| mp_customer_find_products · mp_product_active_cases_count · mp_case_count_by_product | C | B |
| mp_privacy_redact_for_customer | B (listener) | C (eraser) |
| mp_rejection_reasons · mp_registered_statuses · sekcje karty | D | C |
| funkcje kontraktowe spraw (§C) | C | D |
