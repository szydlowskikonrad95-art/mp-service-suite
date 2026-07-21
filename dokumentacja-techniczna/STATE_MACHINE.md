# STATE_MACHINE.md — maszyna stanów sprawy (ZAMROŻONA)

> Statusy = zamknięta lista: rdzeń 7 ze specyfikacji + statusy własne (definicje z filtra
> `mp_registered_statuses` od D). Zmiana statusu WYŁĄCZNIE funkcją kontraktową
> `mp_case_change_status()` w C (optimistic‑lock; UPDATE + event w jednej transakcji, akcja po commit).

## 0. Narodziny sprawy: `status = NULL` (unverified)

```
[formularz] → sprawa unverified: status = NULL, identity_status = pending
    (BEZ eventów, BEZ mp_case_created — sprawa-duch niewidoczna dla filtrów/liczników)
        │  mail z magic-linkiem (token jednorazowy, TTL 24h; potwierdzenie przez POST)
        ▼
[weryfikacja mailowa — ATOMOWO]
    UPDATE … SET identity_status='verified', status='nowe', status_changed_at=NOW()
    WHERE id=%d AND identity_status='pending' AND status IS NULL AND created_at >= NOW()-72h
        │  (pierwsze przejście = OSOBNA ścieżka z IS NULL — WHERE status='stary' nie łapie NULL!)
        ▼
status 'nowe' + event CASE_CREATED + akcja mp_case_created + konto klienta + 2. mail (SRV)
```

- **Przejście założycielskie NULL→'nowe' NIE emituje `mp_case_status_changed`** — narodziny niesie
  `mp_case_created`. JAWNA SEMANTYKA: status_changed = wyłącznie zmiany PÓŹNIEJSZE.
- Weryfikacja USTAWIA `status_changed_at` (= `verified_at`, jeden moment) — od tego liczy się
  pierwszy termin SLA (bez tego sprawa nigdy nie dostałaby zegara).
- Sieroty pending >72h kasuje cron (czysty DELETE + unlink plików; spraw verified NIGDY nie dotyka).

## 1. Rdzeń 7 statusów (spec P3.2)

| Status | Terminalny? | SLA |
|---|---|---|
| nowe | nie | tak (default 24 h) |
| do uzupełnienia | nie | tak (72 h) |
| w analizie | nie | tak (48 h) |
| zaakceptowane | nie | tak (24 h) |
| w naprawie | nie | tak (120 h) |
| odrzucone | **TAK** | bez SLA (deadline NULL) |
| zamknięte | **TAK** | bez SLA (deadline NULL) |

Czasy = KLEPNIĘTE defaulty konfiguracji (godziny kalendarzowe 24/7/365 × modyfikator priorytetu:
wysoki ×0,5 / normalny ×1 / niski ×2 — SEMANTYKA‑CZASU.md); wszystko konfigurowalne w adminie.

## 2. Dozwolone przejścia

- **Między statusami NIETERMINALNYMI: przejścia liberalne** (każdy → każdy). Walidacja C pilnuje:
  status istnieje na liście, optimistic‑lock (`expected_status` się zgadza), wymogi specjalne niżej.
  NIE budujemy edytora grafu przejść.
- **Wejście w „odrzucone" WYMAGA `rejection_reason_code`** (kolumna + kod w evencie + w
  `mp_cases_query`; słownik z filtra `mp_rejection_reasons` od D, degraded: mini‑słownik C).
- **Wejście w „zamknięte"** → D generuje RAPORT KOŃCOWY sprawy (wiadomość systemowa przez
  `mp_case_add_system_message` + mail do klienta — krok 8 spec).
- **REOPEN (z terminalnych): „zamknięte" → „w analizie" oraz „odrzucone" → „w analizie"** — wykonuje
  personel (koordynator/admin). *Ślad decyzji: spec i karty przesądziły reopen dla „zamknięte"
  (tabletop S5); symetryczny reopen dla „odrzucone" tą samą pojedynczą ścieżką = decyzja redakcyjna
  kontraktu (jedna droga powrotu, zero specjalnych przypadków).* Reopen emituje normalny
  `mp_case_status_changed` — sprawa dostaje świeży termin SLA jak przy każdej zmianie statusu.
- Wiadomości na sprawie ZAMKNIĘTEJ są dozwolone (nie zmieniają statusu; panel pokazuje notę,
  notyfikacja D działa normalnie).

## 3. Statusy własne (P3.2 „konfigurowalne")

- Definiuje D (zakładka „Statusy": nazwa / aktywny / czy‑końcowy / SLA‑godziny / warning_hours);
  rdzeń 7 NIEUSUWALNY; definicje = opcja‑treść (warstwa ii uninstalla).
- C waliduje przejścia dla rdzenia 7 + statusów z filtra `mp_registered_statuses`; własne statusy:
  przejścia liberalne między nieterminalnymi. Bez D → C zna TYLKO rdzeń 7 (degraded).
- Terminalność wg FLAGI `czy-końcowy` (nie nazwy na sztywno) — sweep SLA pomija terminalne
  (deadline NULL).

## 4. Cykl statusu gwarancji produktu (B — WYLICZANY, nie maszyna stanów w bazie)

`aktywna | wygasła | brak danych | wymagana weryfikacja` — wyliczane z `warranty_until` /
kompletności danych (SARGABLE, wartość z PHP w UTC). Ortogonalne do statusu: `archived` produktu
oraz wyjątek gwarancyjny (active/revoked + `valid_until`; „expired" wyliczane). Sprawa trzyma
SNAPSHOT gwarancji z chwili zgłoszenia (ocena reklamacji wg chwili zgłoszenia); stan „Aktualnie"
personel widzi na żywo z `mp_warranty_check` — bez automatycznej rekoncyliacji snapshotu
(jawny trade‑off, tabletop S8).
