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
| ⚠️ **CZĘŚCIOWO** — przeglądarki z zamówienia (Chrome, Edge, Firefox) + widok na telefonie | **dwa silniki**: Chromium (obsługuje Chrome i Edge) oraz Gecko (Firefox), szerokość 390 px → **26/26**, zero błędów konsoli. ⛔ **Edge nie był uruchomiony osobno** — kryterium wymienia trzy przeglądarki z nazwy, więc przy zasadzie „albo dowód, albo niespełnione" **nie wolno go liczyć jako spełnione w całości**. Ta sama rubryka przyznawała to osiem wierszy niżej i mimo to stawiała zaliczenie |
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
| ⚠️ **CZĘŚCIOWO** — przejście zamówienia **punkt po punkcie**, na podstawie oryginalnego dokumentu, **bez naszych opracowań** | **35 z 39** punktów spełnionych z dowodem w postaci pliku i linii. ⛔ **Pozostałe CZTERY nie są tu wymienione z nazwy**, a dla odbiorcy to jedyna informacja, która się liczy — dopóki nie zostaną nazwane, **to kryterium jest wg naszej własnej zasady NIESPEŁNIONE**. ⚠️ Osobno: mianownik **39 nie zgadza się** z odczytem zamówienia przez audyt zewnętrzny, który dał **61 pozycji** — „punkt po punkcie" znaczy co innego po obu stronach, więc **odsetków z tego dokumentu nie da się z niczym porównać** |
| Jeden punkt zgłoszony przez audytora jako brak | **obalony na żywym systemie** — funkcja istniała i działała, audytor patrzył w złe miejsce |

## Kalibracja kontroli — czy audyt w ogóle widzi

| Kryterium | Dowód |
|---|---|
| Audyt wykrywa **podłożony** błąd | bank 15 celowych usterek zbudowanych z realnych miejsc tego kodu; wynik **powyżej progu zaliczenia** |
| Bramka wersji w dokumentach **skalibrowana**, nie tylko dopisana | podłożony rozjazd numeru → skrypt przerywa z nazwą pliku i numerem linii; po cofnięciu → przechodzi |

Jedna z podłożonych usterek została **przeoczona** przez audytora. Klasę tego błędu domknięto
osobno, kontrolą maszynową obejmującą wszystkie miejsca tego rodzaju w kodzie — zero trafień.
Zapisujemy to, bo audyt, który zawsze wypada idealnie, znaczy zwykle tyle, że nikt go nie sprawdził.

⛔ **Trzy zdania tej rubryki łamały jej własną zasadę** („albo dowód, albo niespełnione") —
dwa stawiały zaliczenie na dowodzie, o którym ten sam dokument mówił, że go nie obejmuje,
a jedno zdejmowało wymóg z zamówienia na podstawie nieprawdy o produkcie. Wszystkie trzy są
wyżej poprawione i **oznaczone**, a nie po cichu przepisane: rubryka, która sama siebie
poprawia bez śladu, jest warta tyle, co „wygląda dobrze".

## Otwarte decyzje zakresu — nie wady wykonania

- ⛔ **WYCOFANE — to zdanie było nieprawdą i zdejmowało z nas wymóg z zamówienia.** Stało tu:
  *„Danych produktu nie da się edytować po zaimportowaniu, więc wymagana w zamówieniu «historia
  zmian danych produktu» nie ma czego zapisywać"*. **Danych produktu DA SIĘ edytować**: lista pól
  edytowalnych z panelu stoi w `mp-warranty-registry/includes/Repo.php:335`
  (`EDITABLE_FIELDS`: model, partia, kategoria, dokument zakupu, data zakupu, koniec gwarancji),
  a `Repo::update()` zapisuje wpis do historii z różnicą wartości
  (`ProductEvents::log( …, 'PRODUCT_UPDATED', $diff, … )`, `Repo.php:471`). Ekran „popraw dane"
  opisują też `dla-klienta/instrukcje/ADMIN.md` i **zamrożony** `dokumentacja-techniczna/EVENT_MODEL.md`.
  **Wymóg jest wykonany, nie odłożony** — rubryka zamarzła na stanie sprzed zbudowania ekranu.
  Widoczna ścieżka do tej historii (ekran historii egzemplarza) doszła w wydaniu **1.3.12**.
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
