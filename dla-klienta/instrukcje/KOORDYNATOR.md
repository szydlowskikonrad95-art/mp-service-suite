# Instrukcja: KOORDYNATOR SERWISU

> Dla kierownika zespołu z rolą **Koordynator serwisu MP**. Widzisz wszystkie sprawy, rozdzielasz
> pracę, konfigurujesz automatyzację i pilnujesz terminów zespołu.

## 1. Wszystkie sprawy zespołu

**MP: Sprawy** — pełna lista z filtrami (status / rodzaj / przydzielony) i wyszukiwarką po numerze
sprawy lub kliencie. Czerwony termin SLA = wymaga uwagi. „Nieprzydzielona" na czerwono = sprawa,
której automat nie umiał przydzielić (najczęściej pusta pula — patrz §3).

![Lista spraw](zdjecia/admin-01-sprawy.png)
> *Zrzut poglądowy — aktualna wersja ma kolorowe plakietki statusów i kolumnę pilności.*

Na karcie sprawy możesz: **przydzielić / prze-przydzielić** pracownika, zmienić status i priorytet,
pisać do klienta. Ponowne przydzielenie tej samej osobie nic nie wysyła (bez spamu).

## 2. Zgłoszenia niepotwierdzone

**MP: Niepotwierdzone** — zgłoszenia, których klient jeszcze nie potwierdził mailem. Nie obsługuje
się ich (mogą być pomyłką lub spamem); po 72 godzinach sprzątają się same.

![Niepotwierdzone zgłoszenia](zdjecia/admin-03-niepotwierdzone.png)

## 3. Automatyzacja — Twój panel sterowania

**Automatyzacje MP** (menu boczne):

![Panel Automatyzacje MP](zdjecia/admin-07-automatyzacje.png)
> *Zrzut poglądowy — w aktualnej wersji tabela reguł opisana jest po polsku
> (KIEDY / JEŚLI / ZRÓB) i ostrzega, gdy pula pracowników jest pusta.*

- **Reguły przydziału** — najważniejsze: w regule automatycznego przydziału ustaw **pulę
  pracowników** (round-robin). **Pusta pula = sprawy zostają nieprzydzielone.**
- **Akcje**: „Przelicz SLA" (po zmianie konfiguracji terminów; nie wysyła ponownie starych
  powiadomień) i „Eksport CSV" (zestawienie: liczba spraw, czas obsługi, powody odrzuceń).
- **Statusy spraw** — 7 wbudowanych + możliwość dodania własnych (własne można też wycofać
  z użycia; wbudowane są nieusuwalne).
- **Rejestr zdarzeń** — co automat zrobił i dlaczego (np. `ASSIGNMENT_UNMATCHED` = nie umiał
  przydzielić). Przycisk „Pokaż techniczne" odsłania też wpisy cyklicznego sprawdzania.
- **Checklisty i szablony odpowiedzi** — kroki obsługi per rodzaj sprawy i gotowe treści maili;
  w treściach działają wyłącznie markery z listy pod edytorem (np. `{{numer_sprawy}}`,
  `{{status}}`) — inne są pomijane.

## 4. Terminy zespołu (SLA)

- Przypomnienia przed terminem idą do przypisanego pracownika; **eskalacje po terminie — do
  Ciebie**.
- Sprawy nieprzydzielone też eskalują do Ciebie (nic nie ginie w próżni).
- Wznowienie **zamkniętej** sprawy to wyłącznie Twoja decyzja (Ty albo administrator; zawsze
  do statusu „w analizie", z czystym terminem).

## 5. Kondycja systemu

**Narzędzia → Stan witryny** — testy systemu mówią m.in.: czy przydział ma pracowników w puli,
czy sprawdzanie terminów **naprawdę się wykonuje** (nie tylko jest zaplanowane), czy żadna
potwierdzona sprawa nie utknęła poza automatyzacją. Czerwone = do działania, każda pozycja ma
instrukcję naprawy.
