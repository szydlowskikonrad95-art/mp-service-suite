# Kontrole automatyczne — co sprawdza się samo, przy każdej zmianie

Ten dokument opisuje **maszynę**, nie ludzkie przeglądy. Wszystko poniżej uruchamia się bez
udziału człowieka i **blokuje wprowadzenie zmiany**, gdy cokolwiek zawiedzie.

Konfiguracja: [`.github/workflows/quality.yml`](../.github/workflows/quality.yml).
Wyniki każdego przebiegu są publicznie widoczne w zakładce **Actions** tego repozytorium.

## Kiedy się uruchamia

| Zdarzenie | Po co |
|---|---|
| **każde zgłoszenie zmiany** (pull request) | zmiana nie wejdzie, dopóki komplet nie jest zielony |
| **każdy zapis na gałęzi głównej** | pilnuje, że główna gałąź zawsze jest sprawna |
| **każdy znacznik wydania** (`v*`) | wydanie ma **własny** zielony przebieg — nie dziedziczy wyniku po gałęzi |

Ostatni punkt jest celowy. Znacznik wskazuje na zmianę sprawdzoną wcześniej, ale bez własnego
przebiegu zdanie „wydanie przeszło kontrole" byłoby nie do udowodnienia.

## Co dokładnie się sprawdza — 16 kontroli

### Poprawność kodu na wszystkich wersjach PHP
- **Składnia i testy jednostkowe na pięciu wersjach PHP: 8.1, 8.2, 8.3, 8.4, 8.5.**
  Dolna granica (8.1) to wersja zadeklarowana w wymaganiach — sprawdzamy, że deklaracja jest
  prawdziwa, a nie przepisana z szablonu.

### Jakość i bezpieczeństwo
- **PHPCS** — zgodność ze standardem kodowania WordPressa oraz zgodność między wersjami PHP.
- **PHPStan, poziom 6** — analiza statyczna z definicjami typów WordPressa, **bez pliku
  wyjątków**. Plik wyjątków pozwoliłby zamieść istniejące błędy pod dywan; nie mamy takiego pliku.
- **`composer audit`** — znane podatności w bibliotekach, także narzędziowych.
- **Skan sekretów** (gitleaks) — na wypadek, gdyby do repozytorium trafiło hasło albo token.
- **Oficjalna kontrola wtyczek WordPressa** (Plugin Check) — osobno dla **każdej z trzech wtyczek**,
  uruchamiana na **zbudowanej paczce**, a nie na kodzie źródłowym. To ta sama kontrola, którą
  przechodzi się przy zgłoszeniu wtyczki do katalogu WordPress.org.

### Zgodność dokumentacji z kodem
- **Liczby w dokumentach zgodne z kodem** — osobna kontrola pilnująca, żeby wartości podane
  w instrukcjach (limity, progi, terminy) nie rozjechały się z tym, co robi kod.
- **Linter cudzych tabel** — pilnuje, żeby nasze wtyczki nie sięgały bezpośrednio do tabel,
  które do nich nie należą.

### Działanie na żywym WordPressie
- **Ponad 140 skryptów testowych na uruchomionym WordPressie 6.9.4** — nie atrapy, tylko prawdziwa
  instalacja z bazą danych. Dokładną, pełną listę wyznacza `testy/e2e/uruchom-wszystkie.sh --lista`,
  a jej kompletności pilnuje bramka w CI — przebieg pada, gdy choć jeden skrypt wypadnie
  z zestawu. Zakres obejmuje m.in.:
  formularz zgłoszenia i pułapki na roboty · załączniki (kontrola typu pliku, usuwanie danych
  EXIF, blokada dostępu, próby wejścia na cudzy plik) · RODO (zgody, anonimizacja, eksport
  i usuwanie danych) · logowanie klienta linkiem jednorazowym · maszyna statusów sprawy ·
  silnik reguł, w tym **blokada zapętlenia** reguł wzajemnie się wywołujących · terminy SLA
  (przypomnienie, eskalacja, przeliczenie po zmianie konfiguracji) · eksport zestawień
  z zabezpieczeniem przed formułami w arkuszu · **12 person szukających błędów**
  (próby wstrzyknięcia kodu, wejścia na cudze dane, wycieku danych osobowych).
- **Macierz negatywna uprawnień** — osobny krok sprawdzający, że użytkownik **bez** uprawnień
  dostaje odmowę na **każdym** ekranie administracyjnym. Testujemy nie tylko „czy uprawniony
  wejdzie", ale „czy nieuprawniony na pewno nie wejdzie".
- **Dostępność (WCAG)** — etykiety pól, komunikaty odczytywane przez czytniki ekranu.

### Odporność środowiskowa
- **Migracje bazy** — aktualizacja schematu bez reaktywacji wtyczki, wielokrotne uruchomienie
  bez skutków ubocznych.
- **Obce środowisko** — przebieg z włączoną pamięcią podręczną obiektów i cudzymi wtyczkami,
  bo u klienta nasz kod nigdy nie jest sam.
- **MySQL 8** — osobny przebieg na innym silniku bazy niż domyślny.
- **Test paczki wydania** — sprawdzenie, że zbudowana paczka instaluje się i uruchamia.

## Czego automat NIE sprawdza

Uczciwie, bo to ważniejsze niż lista tego, co działa:

- **Wyglądu na ekranie.** Automat sprawdza znaczniki i zachowanie, nie to, czy coś jest ładne
  ani czy kolumna się nie rozjeżdża. To robi człowiek.
- **Zrozumiałości instrukcji.** Żaden test nie powie, czy nietechniczna osoba zrozumie tekst.
- **Sensu biznesowego.** Test potwierdzi, że termin liczy się zgodnie z regułą — nie że reguła
  jest właściwa dla danego serwisu.

Te trzy obszary są domeną przeglądów opisanych w [`RAPORT-AUDYTU.md`](RAPORT-AUDYTU.md).

## Skala

- **ponad 190 plików testowych** w katalogu [`testy/`](../testy/)
- **ponad 25 zestawów testów jednostkowych** i **ponad 140 scenariuszy** na żywym WordPressie;
  dokładną liczbę scenariuszy wyznacza pełna lista `testy/e2e/uruchom-wszystkie.sh --lista`,
  której kompletności pilnuje bramka w CI
- kontrole uruchamiane przy **każdej** zmianie — nie na żądanie, nie przed wydaniem
