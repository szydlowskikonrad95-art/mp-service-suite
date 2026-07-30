# Rubryka „gotowe" — kryteria i dowody

Kryteria są **binarne**: albo istnieje dowód wykonania, albo kryterium jest niespełnione.
**„Wygląda dobrze" nie jest dowodem.** Lista narastała przez kolejne wydania — każde nowe
znalezisko dokładało kryterium, żeby ta sama klasa błędu nie wróciła.

## Wydanie i paczka

| Kryterium | Dowód |
|---|---|
| Numer wersji zgodny w 3 wtyczkach, ich plikach `readme.txt` i changelogu | skrypt pakujący wypisuje zgodność i **przerywa**, gdy jej nie ma |
| Dokumenty klienta zgodne z kodem (liczby, statusy, obietnice) | osobna kontrola „liczby zgodne z kodem"; **bramka skalibrowana podłożonym rozjazdem** — wykrywa też kontrolę, która cicho nie wystartowała |
| Paczka kompletna: 3 wtyczki, instrukcja główna + 4 instrukcje ról (w dwóch formatach), diagramy, zrzuty ekranu, raport dostępności, polityka kopii zapasowych | samokontrola paczki sprawdza osobno, czy **każde zdjęcie przywołane w instrukcji istnieje** |
| Zero śladów środowiska pracy w materiałach klienta | wzorzec obejmujący adresy lokalne, porty deweloperskie i nazwy robocze → 0 trafień |
| Zrzuty ekranu zgodne z interfejsem, **bez duplikatów** | porównanie sum kontrolnych → 0 powtórzeń (wcześniej dwa różne podpisy pokazywały ten sam obrazek) |

## Kod

| Kryterium | Dowód |
|---|---|
| Testy jednostkowe: **wszystkie** przechodzą | pełny przebieg zestawu, wynik zerowy |
| Analiza statyczna bez błędów | oba narzędzia kończą się **kodem wyjścia 0** — nie „ładnym wydrukiem" |
| Komplet kontroli zielony na gałęzi głównej **i na znaczniku wydania** | 16/16, osobny przebieg dla znacznika |
| Zero ostrzeżeń PHP z naszego kodu przy włączonym trybie diagnostycznym | krok testu instalacji od zera |

## Działanie u klienta

| Kryterium | Dowód |
|---|---|
| **Instalacja od zera z paczki** na deklarowanym minimum (WordPress 6.9 / PHP 8.1 / MySQL 8) | ścieżka klienta **20/0**, wgranie przez panel **6/0** |
| **Aktualizacja ze starszej wersji na żywych danych** — nie tylko instalacja od zera | środowisko testowe z istniejącymi sprawami, produktami i załącznikami: liczby rekordów **bez zmian**, wersje schematu bez zmian, dziennik błędów **pusty** |
| Przeglądarki z zamówienia (Chrome, Edge, Firefox) + widok na telefonie | dwa silniki przeglądarek + szerokość 390 px → **26/26**, zero błędów konsoli |
| Współistnienie z obcymi wtyczkami | edytor klasyczny + wtyczka poczty + wtyczka pamięci podręcznej: zadania cykliczne i testy diagnostyczne nadal działają |

## Bezpieczeństwo

| Kryterium | Dowód |
|---|---|
| Punkty wejścia bez logowania i bez tokenu **odrzucają żądanie** | zmiana statusu, przydział, eksport, raport importu, archiwizacja → odmowa; próba wejścia na cudzy załącznik po numerze → odmowa. Zero przecieku |
| Plik PHP podszyty pod obrazek **nie wchodzi** | prawdziwe żądanie z poprawnym zabezpieczeniem: zgłoszenie nie powstało, plik nie trafił na dysk |
| Dwóch pracowników zmienia tę samą sprawę naraz | jeden zapis przechodzi, drugi dostaje konflikt z aktualną wartością; w historii sprawy **jeden** wpis, bez duplikatu |
| Numery spraw przy równoległej pracy | 20 równoległych procesów → 20 unikalnych numerów, **zero duplikatów** |

## Zgodność z zamówieniem

| Kryterium | Dowód |
|---|---|
| Przejście zamówienia **punkt po punkcie**, na podstawie oryginalnego dokumentu, **bez naszych opracowań** | 35 z 39 punktów spełnionych z dowodem w postaci pliku i linii |
| Jeden punkt zgłoszony przez audytora jako brak | **obalony na żywym systemie** — funkcja istniała i działała, audytor patrzył w złe miejsce |

## Kalibracja kontroli — czy audyt w ogóle widzi

| Kryterium | Dowód |
|---|---|
| Audyt wykrywa **podłożony** błąd | bank 15 celowych usterek zbudowanych z realnych miejsc tego kodu; wynik **powyżej progu zaliczenia** |
| Bramka wersji w dokumentach **skalibrowana**, nie tylko dopisana | podłożony rozjazd numeru → skrypt przerywa z nazwą pliku i numerem linii; po cofnięciu → przechodzi |

Jedna z podłożonych usterek została **przeoczona** przez audytora. Klasę tego błędu domknięto
osobno, kontrolą maszynową obejmującą wszystkie miejsca tego rodzaju w kodzie — zero trafień.
Zapisujemy to, bo audyt, który zawsze wypada idealnie, znaczy zwykle tyle, że nikt go nie sprawdził.

## Otwarte decyzje zakresu — nie wady wykonania

- **Danych produktu nie da się edytować po zaimportowaniu** (ponowny import odrzuca duplikat),
  więc wymagana w zamówieniu „historia zmian danych produktu" nie ma czego zapisywać.
  Decyzje gwarancyjne są zapisywane. Świadome, zgłoszone, nie ukryte.
- **Kopia zapasowa i cofnięcie migracji** dostarczone jako **procedura** w dokumentacji
  technicznej, nie jako funkcja w kodzie.
- Wcześniejsza wersja skryptu testowego zawierała hasło testowe w historii repozytorium.
  Bieżący kod losuje je przy każdym uruchomieniu. Historii **nie przepisujemy** — wymuszony
  zapis na publiczne repozytorium niesie większe ryzyko niż samo znalezisko, które dotyczyło
  wyłącznie lokalnego środowiska testowego.

## Czego nie sprawdzono

- **Edge osobno** — testowany silnik jest wspólny dla Chrome i Edge. Firefox sprawdzony osobno.
- **Zachowanie po roku pracy** przy dużych wolumenach — wydajność mierzono jednorazowo,
  m.in. na 30 tysiącach spraw i 50 tysiącach produktów, ale nie w warunkach wieloletniego użycia.
- **Zrozumiałość instrukcji** zbadana na czytelniku wcielonym w rolę, nie na kliencie końcowym.
