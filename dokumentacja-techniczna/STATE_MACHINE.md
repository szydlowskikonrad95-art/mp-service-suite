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
- 72 h to okno POTWIERDZENIA sprawy; sam LINK wygasa wcześniej, po 24 h (`CaseRepo::TOKEN_TTL_HOURS`). Sieroty pending kasuje cron dopiero po
  **30 dniach** (`mp_intake_pending_retention_days`, czysty DELETE + unlink plików; spraw verified NIGDY nie dotyka).

## 1. Rdzeń 7 statusów

| Status | Terminalny? | SLA |
|---|---|---|
| nowe | nie | tak (default 24 h) |
| do uzupełnienia | nie | **NIE — licznik STOI** (deadline NULL) |
| w analizie | nie | tak (48 h) |
| zaakceptowane | nie | tak (24 h) |
| w naprawie | nie | tak (120 h) |
| odrzucone | **TAK** | bez SLA (deadline NULL) |
| zamknięte | **TAK** | bez SLA (deadline NULL) |

⏸️ **„Do uzupełnienia" od 1.3.12 nie ma terminu — to jedyny NIETERMINALNY status bez SLA.**
Zapisane jako `'do uzupełnienia' => 0` w `SlaConfig::CORE_HOURS` (`SlaConfig.php:69`); ścieżka
`sla_hours <= 0 => deadline NULL` istniała już wcześniej, więc zero nie wymaga osobnej obsługi,
a zamiatarka bierze wyłącznie wiersze z `deadline_at IS NOT NULL`. **Powód:** w tym statusie piłka
jest po stronie KLIENTA — do 1.3.11 status miał własne okno 72 h, które biegło przez cały czas
oczekiwania, więc po trzech dobach sprawa **eskalowała do koordynatora za to, że klient nie odpisał**,
i zafałszowywała średni czas obsługi w eksporcie. Zegar rusza od nowa przy powrocie do statusu
roboczego (każda zmiana statusu liczy termin od zera). ⛔ **Sprawa nie znika z radaru**: zaparkowaną
tu na stałe łapie osobna miara wieku (`Sla::stale_cases`), niezależna od terminów.
⚠️ **Nie mylić z 72 h z §0** — tamto to okno POTWIERDZENIA sprawy (`CaseRepo::CONFIRM_WINDOW_HOURS`),
zupełnie inny mechanizm; ta sama liczba w dwóch znaczeniach kosztowała już jedno nieporozumienie.

Czasy = godziny kalendarzowe 24/7/365 × modyfikator priorytetu (wysoki ×0,5 / normalny ×1 /
niski ×2). **Godziny terminów statusów WBUDOWANYCH ustawia administrator** w panelu
(Automatyzacje MP → Ustawienia, sekcja „Godziny terminów (statusy wbudowane)"); termin statusu
WŁASNEGO ustawia się przy nim samym, w sekcji „Statusy własne". ⚠️ **Modyfikator priorytetu
konfigurowalny NIE jest** — siedzi w kodzie jako stała `SlaConfig::PRIORITY_MODIFIER`.

## 2. Dozwolone przejścia

- **Między statusami NIETERMINALNYMI: przejścia liberalne** (każdy → każdy). Walidacja C pilnuje:
  status istnieje na liście, optimistic‑lock (`expected_status` się zgadza), wymogi specjalne niżej.
  NIE budujemy edytora grafu przejść.
- **Wejście w „odrzucone" WYMAGA `rejection_reason_code`** (kolumna + kod w evencie + w
  `mp_cases_query`). **Słownik powodów oddaje C** — `MP\Intake\RejectionReasons` jest jedynym
  dostawcą filtra `mp_rejection_reasons` (`RejectionReasons.php:86`), a czytają go karta sprawy C
  i eksport CSV D. **Domyślny słownik jest NIEPUSTY** (6 powodów, `RejectionReasons::defaults()`)
  i pustej listy nie da się zapisać — inaczej świeża instalacja miałaby ślepy zaułek: karta pokazuje
  pole powodu tylko przy niepustej liście, a bez powodu `change_status` odbija `REJECTION_REASON_REQUIRED`.
  Listę edytuje admin w **MP: Sprawy → Ustawienia**, sekcja „Powody odrzucenia sprawy".
  *(Do 1.3.11 filtr nie miał ŻADNEGO dostawcy — stąd wcześniejszy zapis „słownik od D, degraded:
  mini‑słownik C" opisywał zamiar, nie stan: D go nie rejestrowało, a mini‑słownika C nie było.)*
- **Wejście w „zamknięte"** → D generuje RAPORT KOŃCOWY sprawy (wiadomość systemowa przez
  `mp_case_add_system_message` + mail do klienta — krok 8 spec).
- **REOPEN (z terminalnych): „zamknięte" → „w analizie" oraz „odrzucone" → „w analizie"** — wykonuje
  personel (koordynator/admin). *Ślad decyzji: spec i karty przesądziły reopen dla „zamknięte"
  (tabletop S5); symetryczny reopen dla „odrzucone" tą samą pojedynczą ścieżką = decyzja redakcyjna
  kontraktu (jedna droga powrotu, zero specjalnych przypadków).* Reopen emituje normalny
  `mp_case_status_changed` — sprawa dostaje świeży termin SLA jak przy każdej zmianie statusu.
- Wiadomości na sprawie ZAMKNIĘTEJ są dozwolone (nie zmieniają statusu; panel pokazuje notę,
  notyfikacja D działa normalnie).

## 3. Statusy własne ( „konfigurowalne")

- Definiuje D — **podstrona w menu: Automatyzacje MP → Ustawienia, sekcja „Statusy własne"**
  (kolumny na ekranie: klucz techniczny / nazwa widoczna / aktywny / kończy sprawę / termin
  w godzinach / ostrzeż na — czyli `warning_hours`); rdzeń 7 NIEUSUWALNY; definicje =
  opcja‑treść (warstwa ii uninstalla).
  ⚠️ To NIE jest zakładka wewnątrz panelu — to osobna pozycja w menu bocznym. Nazwa w dokumencie
  ma się zgadzać z tym, co człowiek widzi na ekranie.
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
