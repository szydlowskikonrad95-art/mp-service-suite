# Dział audytu

Ten katalog zawiera **dowody z kontroli jakości**, a nie ich opis. Opis metody — czym i jak
sprawdzamy — leży w [`dokumentacja-techniczna/JAKOSC-I-AUDYTY.md`](../dokumentacja-techniczna/JAKOSC-I-AUDYTY.md).
Tutaj są wyniki: co sprawdzono, co znaleziono, co z tym zrobiono.

Katalog **nie wchodzi do paczki dla klienta końcowego** — właściciel serwisu nie potrzebuje
raportów z audytu kodu. Jest tu dla osoby technicznej, która chce zweryfikować, jak ten system
powstawał.

## Co tu jest

| Plik | Co zawiera |
|---|---|
| [`KONTROLE-AUTOMATYCZNE.md`](KONTROLE-AUTOMATYCZNE.md) | co sprawdza się **samo**, przy każdej zmianie — 16 kontroli, ponad 140 skryptów na żywym WordPressie |
| [`RAPORT-AUDYTU.md`](RAPORT-AUDYTU.md) | wyniki kolejnych rund przeglądów: co znaleziono i jak naprawiono |
| [`RUBRYKA-GOTOWE.md`](RUBRYKA-GOTOWE.md) | definicja „gotowe" — lista warunków z dowodem wykonania przy każdym |
| [`ZAKRES-SPRAWDZONY.md`](ZAKRES-SPRAWDZONY.md) | co zostało sprawdzone i **czego nie sprawdzono** |

## Jak to jest zorganizowane — trzy poziomy

**1. Maszyna, przy każdej zmianie.** 16 kontroli uruchamianych automatycznie: testy na pięciu
wersjach PHP (8.1–8.5), analiza statyczna bez pliku wyjątków, skan sekretów, oficjalna kontrola
wtyczek WordPressa na zbudowanej paczce, ponad 140 skryptów testowych na uruchomionym WordPressie 6.9.4.
Zmiana nie wejdzie, dopóki komplet nie jest zielony.

**2. Przeglądy przed wydaniem — każdy pod innym kątem.** Bramki automatyczne łapią **regresje**
(coś działało i przestało). Nie łapią **braków** — rzeczy, której nigdy nie zbudowano, żaden test
nie zgłosi. Dlatego osobne przeglądy: zgodność z **oryginalnym zamówieniem** (nie z naszą
dokumentacją), bezpieczeństwo, kompletność, spójność paczki.

**3. Diagnostyka po wdrożeniu.** Testy meldujące się na ekranie *Narzędzia → Stan witryny*
u klienta — np. ostrzeżenie, gdy pilnowanie terminów przestało się wykonywać, mimo że system
wygląda na sprawny.

## Ponowny audyt — dlaczego jedno przejście nie wystarcza

Po każdej naprawie przechodzimy zakres **jeszcze raz**. Powód jest praktyczny: naprawa potrafi
unieważnić własną dokumentację albo istniejące testy, a poprawka wprowadzona w jednym miejscu
zwykle dotyczy klasy błędów obecnej w kilku.

Kolejne rundy przynoszą **mniej** znalezisk, ale **trudniejsze** — te proste wypadły wcześniej.
Nie zakładamy, że n-ta runda da zero; przestajemy, gdy kolejny przebieg przestaje przynosić
nowe rzeczy.

## Kalibracja — dlaczego „nic nie znaleziono" tutaj coś znaczy

Audyt, który niczego nie znalazł, jest bezwartościowy, dopóki nie wiadomo, **czy w ogóle
potrafiłby coś znaleźć**.

Dlatego audytora sprawdzamy podstępem: do kodu wstrzykiwane są **celowe błędy** na gałęzi
tymczasowej, a audytor dostaje zadanie, nie wiedząc, że trwa kalibracja. Jeśli ich nie znajdzie —
jest ślepy, a jego „czysto" nic nie znaczy i nie zalicza kontroli.

Przy ostatnim audycie bezpieczeństwa audytor znalazł **13 z 15** podłożonych błędów; jeden
z pominiętych okazał się słusznie odrzucony jako nieszkodliwy. Dlatego jego raport ma wagę.
