# EVENT_MODEL.md — model zdarzeń (ZAMROŻONY)

> Trzy tabele APPEND‑ONLY (zero metod UPDATE/DELETE, bez wyjątków): `wp_mp_case_events` (C),
> `wp_mp_product_events` (B), `wp_mp_workflow_events` (D). Spec: „każda zmiana statusu, komentarz,
> powiadomienie i decyzja tworzy nieusuwalny wpis w osi czasu sprawy" + „rejestr operacji istotnych"
> per plugin.

## 1. ŻELAZNA ZASADA NO‑PII‑IN‑LOG

Zdarzenia są **W 100% STRUKTURALNE**: referencje (`customer_id`, `message_id`), fakty (status
z→na), kody decyzji. **ZERO pól wolnotekstowych w events.** Komentarze/notatki żyją w
`wp_mp_messages` (redagowalnej), event trzyma wskaźnik. Maile w events wyłącznie jako
`{template_id, recipient_ref}` — nigdy adres ani wyrenderowana treść. Diffy produktu: pola
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

Zapis eventu i mutacja stanu = JEDNA transakcja (status bez eventu NIGDY); akcje `mp_*` po commit.

## 3. Typy zdarzeń — `wp_mp_case_events` (C)

| Typ | Payload (strukturalny) |
|---|---|
| CASE_CREATED | {case_number, rodzaj, product_registry_id\|null} |
| STATUS_CHANGED | {from, to, actor, rejection_reason_code?} |
| CASE_ASSIGNED | {from, to, actor} (auto i ręczny — każdy przydział) |
| PRIORITY_CHANGED | {from, to, actor} |
| VALIDATION_FAILED | {field, reason_code} — nigdy surowe stringi z danymi |
| CHECKLIST_ITEM_TOGGLED | {step_key, completed, actor_id} |
| EXCEPTION_APPLIED / EXCEPTION_REVOKED | {exception_id} (listener `mp_warranty_exception_changed`; case_id=NULL → no‑op) |
| SLA_REMINDER_SENT / SLA_ESCALATED | {kind, recipient_ref} (listener `mp_sla_notified`) |
| CONSENT_RECORDED / CONSENT_WITHDRAWN | {consent_id, wersja} |
| CUSTOMER_ANONYMIZED | {customer_id} |
| PII_REDACTION | {target_id, fields: [lista zredagowanych pól]} — bez wartości |
| RATE_LIMIT | {hash-klucza} — bez PII |

## 4. Typy zdarzeń — `wp_mp_product_events` (B)

| Typ | Payload |
|---|---|
| zmiany danych produktu | diff before/after; pii_sensitive → {field, changed:true} |
| EXCEPTION_CREATED / EXCEPTION_REVOKED | {exception_id, typ, actor_id} — NIGDY kopia tekstu `reason` |
| PRODUCT_RESTORED | {actor} (przywrócenie z archiwum — jawne, nigdy ciche w imporcie) |
| PRODUCT_FORCE_DELETED | {actor, reason?} (notatka techniczna, NO‑PII) |
| przebiegi importu | {import_job_id, statystyki} |

## 5. Typy zdarzeń — `wp_mp_workflow_events` (D)

| Typ | Payload |
|---|---|
| wykonanie reguły | {rule_id, case_id, trigger, akcja, wynik, depth} — audyt „czemu automat to zrobił" |
| RULE_LOOP_BLOCKED / RULE_LIMIT_HIT | {rule_id, case_id, depth} |
| ASSIGNMENT_UNMATCHED | {case_id, trigger} (żadna reguła/pusta pula — świadomy stan) |
| MAIL_FAILED / MAIL_FAILED_FINAL | {rule_id?, template_key, case_id, error_code} |
| MAIL_SKIPPED_NO_RECIPIENT | {case_id, template_key} (klient zanonimizowany = stan legalny) |
| EXPORT_GENERATED | {user_id, liczba wierszy, hash filtrów} — bez PII |
| CRUD konfiguracji | {obiekt, id, actor} (reguły/szablony/statusy/SLA) |
| przebiegi sweepa / resync / „Przelicz SLA" | {statystyki przebiegu} |

`wp_mp_workflow_events` przy uninstallu C (sygnał `mp_cases_data_erased`) ZOSTAJE — rejestr
operacji D jest historyczny, nie wskazuje „na żywo".

## 6. Snapshot‑wzorzec (spokrewniony z eventami)

Dane, które muszą pokazywać ÓWCZESNĄ prawdę, są zamrażane w wierszu przy zdarzeniu:
`form_data` (etykiety pól z chwili złożenia) · `warranty_snapshot` (gwarancja z chwili zgłoszenia) ·
`step_label` w odhaczeniu checklisty · pełny tekst zgody w consents. Zmiana definicji/konfiguracji
NIGDY nie przepisuje historii.
