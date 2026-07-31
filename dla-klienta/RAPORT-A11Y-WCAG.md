# Raport dostępności (WCAG 2.1 AA) — MP Service Suite

**Data badania:** 2026-07-31 · **Wersja badana:** 1.3.6 — czyli **kod tej paczki**. Wydanie 1.3.7
nie zmienia ani jednej linii kodu: poprawia wyłącznie ten dokument i CHANGELOG (patrz nota niżej).

Ten dokument mówi, czy ekrany, które widzi **Twój klient**, dają się obsłużyć osobom
z niepełnosprawnościami — i czym to sprawdziliśmy. Nie jest to deklaracja: badanie
**możesz powtórzyć u siebie** poleceniem podanym na końcu.

## Jak badaliśmy

- **Narzędzie:** `axe-core` — otwarty, powszechnie używany silnik testów dostępności.
- **Zakres reguł:** WCAG 2.1, poziomy **A i AA**.
- **Sposób:** badanie na **żywej stronie w prawdziwej przeglądarce**, po HTTPS. Nie na samym
  kodzie: tylko tak da się sprawdzić rzeczy widoczne dopiero po wyrenderowaniu, czyli kontrast
  kolorów i pełne reguły ARIA.
- **Badaliśmy dwa razy, na dwóch różnych środowiskach** — i podajemy oba wyniki, bo razem mówią
  więcej niż jeden:

  | | Badanie 1 | Badanie 2 |
  |---|---|---|
  | Data | 2026-07-29 | **2026-07-31** |
  | Wersja wtyczek | 1.3.0 | **1.3.6** |
  | WordPress / PHP / baza | 6.9 / 8.1 / MySQL 8 (deklarowane minimum) | **7.0 / 8.2 / MariaDB 11.8** |
  | Motyw strony | Twenty Twenty-Five 1.4 | motyw dedykowany strony demonstracyjnej |
  | Instalacja | czysta, postawiona z paczki | z paczki pobranej z wydania |
- **Co liczymy osobno:** naszą część strony (formularz, panel klienta) i całą stronę
  razem z motywem. Za motyw, którego nie dostarczamy, nie możemy odpowiadać — ale
  pokazujemy, co w nim wychodzi, bo i tak zobaczysz to u siebie.
- Uzupełniają to testy w naszym systemie ciągłej kontroli, które przy każdej zmianie
  pilnują etykiet pól, nazw przycisków, komunikatów dla czytników ekranu
  i unikalności identyfikatorów.

## Wynik — nasze ekrany

| Ekran | Reguł zdanych (1.3.0) | Naruszenia | Reguł zdanych (1.3.6) | Naruszenia |
|---|---|---|---|---|
| Formularz zgłoszenia (publiczny) | 12 | **0** | 12 | **0** |
| Panel klienta — przed zalogowaniem | 7 | **0** | 7 | **0** |
| Panel klienta — po zalogowaniu (dane osobowe, historia sprawy) | 7 | **0** | 9 | **0** |

**Zero naruszeń WCAG 2.1 AA na wszystkich ekranach, które dostarczamy — w obu badaniach.**

„Reguł zdanych" to liczba sprawdzeń, które na danym ekranie miały co badać i wypadły dobrze.
Różni się między badaniami, bo zależy od tego, co akurat jest na ekranie (na przykład ile pól
ma formularz albo czy widać listę spraw) — nie jest to ocena ani punktacja.

Wcześniejsze badanie (22 lipca) wykazało dwa problemy z kontrastem tekstu w panelu
klienta — zbyt jasny szary przy komunikacie „Brak wiadomości" i zbyt jasna zieleń przy
informacji o zamkniętej sprawie. **Oba zostały naprawione**: kolory ustawione wprost
w kodzie zastąpiono jedną, kontrastową paletą w arkuszu stylów. Powyższy wynik pochodzi
z badania po tej poprawce.

## Wynik — cała strona razem z motywem

Ta część wyniku **zależy od motywu Twojej strony**, nie od naszych wtyczek — dlatego wypadła
różnie w dwóch badaniach.

**Badanie 2 (1.3.6, motyw strony demonstracyjnej):** całe strony razem z motywem —
**zero naruszeń** na wszystkich trzech ekranach (odpowiednio 20, 15 i 16 zdanych reguł).

**Badanie 1 (1.3.0, domyślny motyw WordPressa Twenty Twenty-Five 1.4):** badanie
całych stron dało **po jednym naruszeniu** na każdym z trzech ekranów. Za każdym razem
jest to **to samo miejsce i nie jest to nasz kod**:

- reguła **`list`** (ważność: poważna) w **bloku nawigacji WordPressa** w nagłówku
  witryny — `ul.wp-block-navigation__container` zawiera bezpośrednio kolejną listę
  (blok „Lista stron") zamiast elementów listy. Markup pochodzi z rdzenia WordPressa,
  a nasze wtyczki nie tworzą na stronie żadnej nawigacji.

Co to znaczy dla Ciebie: **problem zobaczysz na każdej podstronie tego motywu**, także
tam, gdzie naszych wtyczek nie ma. Jeśli używasz innego motywu albo własnego nagłówka,
wynik będzie inny — drugie badanie, na innym motywie, dało w tym miejscu zero naruszeń.
Dlatego polecenie niżej warto uruchomić na **swojej** stronie.

## Co jest poza naszym zakresem

Dostępność **motywu Twojej strony** (nagłówek, menu, stopka) zależy od motywu, nie od
naszych wtyczek — jeśli jest w nim problem, zobaczysz go także na stronach bez naszego
formularza. Chętnie wskażemy, co poprawić, ale nie zmieniamy cudzego motywu bez ustaleń.

## Jak powtórzyć to badanie u siebie

Narzędzie, którym badaliśmy, **jest w tej paczce**:
`dla-informatyka/audyt-dostepnosci/audyt-axe.py`. Potrzebuje Pythona 3 i dwóch
darmowych bibliotek:

```bash
npm i axe-core
pip install playwright
playwright install chromium

MP_BASE=https://twoja-strona.pl \
AXE=./node_modules/axe-core/axe.min.js \
python3 dla-informatyka/audyt-dostepnosci/audyt-axe.py
```

Skrypt sam pyta Twoją witrynę o adresy obu stron (zakłada je wtyczka przy aktywacji)
i **kończy się błędem, jeśli znajdzie choć jedno naruszenie w naszej części**.
Naruszenia motywu wypisuje osobno, z dopiskiem `[motyw]`, i nie przerywa przez nie
badania. Jeśli strony zostały u Ciebie przeniesione pod inne adresy, wskaż je wprost:
`MP_URL_FORMULARZ=... MP_URL_PANEL=...`.

**Ile ekranów zbadasz u siebie.** Dwa publiczne — formularz i panel przed zalogowaniem —
od ręki. Trzeci, panel **po zalogowaniu**, wymaga wejścia na konto linkiem wysłanym
mailem, więc skrypt musi mieć dostęp do skrzynki. Bez tego dostępu po prostu go pomija
i mówi o tym wprost — **to nie jest błąd**. My zbadaliśmy go na instalacji testowej,
gdzie taki dostęp mamy; wynik z tego ekranu widzisz w tabeli wyżej.

---

**Nota o powtórzeniu badania i o wersji 1.3.7.**

Pierwsze badanie wykonaliśmy 29 lipca na paczce **1.3.0**. Ten dokument długo mówił wprost, że
**nie było powtarzane** — zamiast podmieniać numer wersji w nagłówku. 31 lipca badanie
**powtórzyliśmy na paczce 1.3.6 pobranej z wydania**, żeby wynik dotyczył wersji, którą naprawdę
dostajesz. Wynik w naszej części jest ten sam: **zero naruszeń na wszystkich trzech ekranach**.

**Wydanie 1.3.7 nie zmienia ani jednej linii kodu** — poprawia wyłącznie ten dokument (świeży
wynik badania) i CHANGELOG. Kod wtyczek jest bit w bit taki sam jak w 1.3.6, więc wynik badania
przeprowadzonego na 1.3.6 obowiązuje dla 1.3.7 bez żadnych zastrzeżeń.

Dla porządku, co działo się z kodem między badaniami: sprzątanie jednej opcji technicznej przy
odinstalowaniu wtyczki, poprawki w przyjmowaniu plików CSV (kontrola liczby kolumn, rozpoznawanie
polskich znaków, pola wieloliniowe), odświeżanie danych sprawy między regułami automatu, blokada
przycisku „Wznów" na ekranie importu na czas trwania operacji oraz uzupełnienia w instrukcjach.
**W wersjach 1.3.4 i 1.3.6 nie zmieniono ani jednej linii kodu.** W **1.3.5** zmiany dotyczyły
wyłącznie sposobu pobierania danych z bazy przez listy w panelu administratora (mniej zapytań).
Jedyna zmiana widoczna w interfejsie w całym tym okresie dotyczy **ekranu importu w panelu
administratora** (przycisk staje się nieaktywny w trakcie wznawiania — zachowanie zgodne
z wytycznymi, bo blokada jest komunikowana zmianą stanu przycisku, a nie samym kolorem).
