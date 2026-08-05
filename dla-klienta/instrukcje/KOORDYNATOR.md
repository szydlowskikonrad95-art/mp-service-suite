# Instrukcja: KOORDYNATOR SERWISU

> Dla kierownika zespołu z rolą **Koordynator serwisu MP**. Widzisz wszystkie sprawy, rozdzielasz
> pracę, konfigurujesz automatyzację i pilnujesz terminów zespołu.

## 1. Wszystkie sprawy zespołu

**MP: Sprawy** — pełna lista z filtrami (status / rodzaj / przydzielony) i wyszukiwarką po numerze
sprawy lub kliencie. Czerwony termin SLA = wymaga uwagi. „Nieprzydzielona" na czerwono = sprawa,
której automat nie umiał przydzielić (najczęściej pusta pula — patrz §3).

> **SLA** to umówiony czas na zajęcie się sprawą (np. 24 godziny na pierwszą reakcję). System
> pilnuje go sam: przypomina pracownikowi przed upływem, a po terminie eskaluje do Ciebie —
> szczegóły w §4.

![Lista spraw](zdjecia/admin-01-sprawy.png)

Na karcie sprawy możesz: **przydzielić / prze-przydzielić** pracownika, zmienić status,
pisać do klienta. Ponowne przydzielenie tej samej osobie nic nie wysyła (bez spamu).
Priorytet widzisz w nagłówku karty — nadaje go automat według reguł, z karty się go nie zmienia.

Wynik sprawdzenia gwarancji ma cztery statusy: aktywna / wygasła / brak danych / **wymagana
weryfikacja**. Ten ostatni znaczy, że numer dokumentu zakupu albo data zakupu od klienta nie
zgadzają się z rejestrem — sprawa NIE jest automatycznie odrzucana. Poproś pracownika o
sprawdzenie dokumentu zakupu z klientem; jeśli sprawa jest zasadna mimo niezgodności w
rejestrze, poproś **administratora systemu** o nadanie wyjątku gwarancyjnego. Wyjątki zatwierdza
wyłącznie administrator — koordynator ich nie nadaje.

Uwaga przy przydzielaniu: na liście „Przydziel do" są **tylko pracownicy serwisu**. Koordynatorzy
i administratorzy nie prowadzą spraw, więc nie da się im przydzielić sprawy.

## 2. Zgłoszenia niepotwierdzone

**MP: Niepotwierdzone** — zgłoszenia, których klient jeszcze nie potwierdził mailem. Nie obsługuje
się ich (mogą być pomyłką lub spamem). Pojedynczy link potwierdzający jest ważny **24 godziny**,
ale **okno potwierdzenia zgłoszenia trwa 72 godziny** — w tym czasie możesz wysłać klientowi
świeży link akcją **„Wyślij ponownie"** na tej liście. Po upływie okna zgłoszenie nie może już
ruszyć, a **po 30 dniach znika razem z danymi**.

Kolumna **„Poczta"** pokazuje, czy link potwierdzający w ogóle wyszedł. Oznaczenie
**„⚠ Link NIE doszedł"** znaczy, że wysyłka maila padła po stronie serwera — klient nie dostał
nic i nie ma czego potwierdzić, więc **samo czekanie nic nie da**. W takim wypadku sprawdź
**Narzędzia → Stan witryny** (sekcja poczty), a po naprawie użyj przy zgłoszeniu akcji
**„popraw e-mail i wyślij ponownie"** — przy okazji poprawisz literówkę w adresie. Ponowną
wysyłkę dla tej samej sprawy można wywołać **raz na 5 minut**.

![Niepotwierdzone zgłoszenia](zdjecia/admin-03-niepotwierdzone.png)

## 3. Automatyzacja — Twój panel sterowania

**Automatyzacje MP** (menu boczne):

![Panel Automatyzacje MP](zdjecia/admin-07-automatyzacje.png)

- **Reguły przydziału** — tabela pokazuje, co automat robi i kiedy (tylko do odczytu). **Pusta lista
  pracowników = sprawy zostają nieprzydzielone**, a tabela reguł mówi o tym wprost. Jeśli widzisz to
  ostrzeżenie, poproś administratora: sekcję **„Kto dostaje zgłoszenia"** z listą pracowników do
  zaznaczenia widzi i ustawia **wyłącznie administrator systemu** — w Twoim panelu jej nie ma.
- **Akcje**: u Ciebie jest **„Eksport CSV"** (zestawienie: liczba spraw, czas obsługi, powody odrzuceń).
  Przycisk **„Przelicz terminy obsługi"** (uruchamiany po zmianie konfiguracji terminów; nie wysyła
  ponownie starych powiadomień) **widzi wyłącznie administrator systemu** — to, że go nie masz, nie jest błędem.

### ⏱️ Dwie kolumny czasu w eksporcie — i dlaczego dwie

Eksport podaje **dwie różne wielkości**, każdą z podstawą wypisaną w nagłówku:

| Kolumna | Liczy od | Co mierzy |
|---|---|---|
| **Czas obsługi od potwierdzenia (godz.)** | od potwierdzenia zgłoszenia przez klienta | pracę serwisu — odcinek, na który serwis ma wpływ |
| **Wiek sprawy od złożenia (godz.)** | od wysłania formularza przez klienta | ile sprawa trwała łącznie, z czekaniem na potwierdzenie |

Różnica między nimi to **czas, przez który zgłoszenie czekało na potwierdzenie przez klienta —
do 72 godzin** (tyle trwa okno potwierdzenia zgłoszenia; pojedynczy link żyje krócej, ale w oknie
można wysłać świeży — patrz §2). Przy sprawie potwierdzonej po dwóch dniach
jedna liczba będzie o kilkadziesiąt godzin większa od drugiej, mimo że serwis pracował tyle samo.

**Czas obsługi liczony od potwierdzenia to ta sama liczba, którą klient widzi we wpisie
zamykającym sprawę** — obie strony mówią o tym samym.

> ⚠️ **To jest nasza interpretacja i czeka na Twoje potwierdzenie.** Zamówienie mówi o eksporcie
> z czasem obsługi, ale **nie rozstrzyga, którą z tych dwóch wielkości nazwać „czasem obsługi"**.
> Dlatego produkt podaje **obie** i nie wybiera za Ciebie. Do wersji 1.3.11 eksport podawał pod
> nazwą „Czas obsługi (godz.)" wielkość liczoną **od złożenia** — czyli tę, która dziś nazywa się
> **wiekiem sprawy**. Stara liczba nie zniknęła: jest w tej właśnie kolumnie i w zestawieniu.
> Jeśli powiesz, że „czas obsługi" ma znaczyć co innego, zmienimy nazwy — liczby są policzone i tak.
- **Statusy spraw** — 7 wbudowanych i nieusuwalnych. **Własne statusy dokłada administrator**
  w **Automatyzacje MP → Ustawienia** (sekcja „Statusy własne"); tam też ustawia się **godziny
  terminów** dla każdego statusu. Programista nie jest do tego potrzebny.
- **Rejestr zdarzeń** — co automat zrobił i dlaczego (np. `ASSIGNMENT_UNMATCHED` = nie umiał
  przydzielić). Przycisk „Pokaż wpisy automatycznego przeglądu" odsłania też wpisy cyklicznego sprawdzania.
- **Checklisty i szablony odpowiedzi** — kroki obsługi dla każdego rodzaju sprawy i gotowe treści maili;
  w treściach działają wyłącznie markery z listy pod edytorem (np. `{{numer_sprawy}}`,
  `{{status}}`) — inne są pomijane.

## 3a. Notatki wewnętrzne — co zespół musi o nich wiedzieć

Notatka wewnętrzna przy sprawie jest niewidoczna w panelu klienta i **nie idzie do niego mailem** —
służy do uwag dla innego pracownika serwisu (podejrzenie ingerencji, ustalenia co do wyceny, kontekst rozmowy).

🔴 **Ale klient może ją przeczytać.** Wniosek o dostęp do danych (art. 15 RODO) obejmuje także
**opinie o osobie**, więc notatka o kliencie jest jego daną i **wchodzi do paczki**, którą
administrator wydaje na taki wniosek. **Powiedz to zespołowi wprost:** notatka ma być rzeczowa
i dotyczyć sprawy, a nie zawierać ocen, których nie dałoby się powtórzyć klientowi w oczy.

## 4. Terminy zespołu (SLA)

- Przypomnienia przed terminem idą do przypisanego pracownika; **eskalacje po terminie — do
  Ciebie**.
- Sprawy nieprzydzielone też eskalują do Ciebie (nic nie ginie w próżni).
- **Przy większej liczbie zaległości dostajesz jedną zbiorczą wiadomość**, a nie osobny mail
  od każdej sprawy — np. po dłuższej przerwie w pracy serwera. Lista spraw jest w treści.
- Wznowienie **zamkniętej** sprawy to wyłącznie Twoja decyzja (Ty albo administrator; zawsze
  do statusu „w analizie", z czystym terminem).
- ⏸️ **Sprawa w statusie „do uzupełnienia" nie ma terminu — i tak ma być.** Zegar zatrzymuje się
  na czas, gdy czekamy na ruch klienta (dosłanie zdjęcia, dokumentu, odpowiedzi), więc serwis nie
  dostaje przekroczenia za cudzą zwłokę i **nie idzie z tego eskalacja**. W kolumnie terminu
  i na karcie sprawy zobaczysz wtedy napis **„czeka na klienta"** zamiast daty — puste pole
  znaczyłoby co innego. Zegar rusza od nowa, gdy przestawisz sprawę na kolejny status.

## 5. Kondycja systemu

**Narzędzia → Stan witryny** — testy systemu mówią m.in.: czy przydział ma pracowników w puli,
czy sprawdzanie terminów **naprawdę się wykonuje** (nie tylko jest zaplanowane), czy żadna
potwierdzona sprawa nie utknęła poza automatyzacją. Czerwone = do działania, każda pozycja ma
instrukcję naprawy.
