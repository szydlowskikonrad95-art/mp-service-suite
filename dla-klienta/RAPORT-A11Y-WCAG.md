# Raport dostępności (WCAG 2.1 AA) — MP Service Suite

**Data badania:** 2026-07-29 · **Wersja badana:** 1.3.0 (wynik obowiazuje dla 1.3.3 — patrz nota nizej)

Ten dokument mówi, czy ekrany, które widzi **Twój klient**, dają się obsłużyć osobom
z niepełnosprawnościami — i czym to sprawdziliśmy. Nie jest to deklaracja: badanie
**możesz powtórzyć u siebie** poleceniem podanym na końcu.

## Jak badaliśmy

- **Narzędzie:** `axe-core` — otwarty, powszechnie używany silnik testów dostępności.
- **Zakres reguł:** WCAG 2.1, poziomy **A i AA**.
- **Sposób:** badanie na **żywej stronie w prawdziwej przeglądarce**, na instalacji
  postawionej **z paczki 1.3.0 na czystym WordPressie** (WP 6.9, PHP 8.1, MySQL 8 —
  deklarowane minimum). Nie na samym kodzie: tylko tak da się sprawdzić rzeczy widoczne
  dopiero po wyrenderowaniu, czyli kontrast kolorów i pełne reguły ARIA.
- **Co liczymy osobno:** naszą część strony (formularz, panel klienta) i całą stronę
  razem z motywem. Za motyw, którego nie dostarczamy, nie możemy odpowiadać — ale
  pokazujemy, co w nim wychodzi, bo i tak zobaczysz to u siebie.
- Uzupełniają to testy w naszym systemie ciągłej kontroli, które przy każdej zmianie
  pilnują etykiet pól, nazw przycisków, komunikatów dla czytników ekranu
  i unikalności identyfikatorów.

## Wynik — nasze ekrany

| Ekran | Reguł zdanych | Naruszenia |
|---|---|---|
| Formularz zgłoszenia (publiczny) | 12 | **0** |
| Panel klienta — przed zalogowaniem | 7 | **0** |
| Panel klienta — po zalogowaniu (dane osobowe, historia sprawy) | 7 | **0** |

**Zero naruszeń WCAG 2.1 AA na wszystkich ekranach, które dostarczamy.**

Wcześniejsze badanie (22 lipca) wykazało dwa problemy z kontrastem tekstu w panelu
klienta — zbyt jasny szary przy komunikacie „Brak wiadomości" i zbyt jasna zieleń przy
informacji o zamkniętej sprawie. **Oba zostały naprawione**: kolory ustawione wprost
w kodzie zastąpiono jedną, kontrastową paletą w arkuszu stylów. Powyższy wynik pochodzi
z badania po tej poprawce.

## Wynik — cała strona razem z motywem

Na stronie testowej (domyślny motyw WordPressa **Twenty Twenty-Five 1.4**) badanie
całych stron dało **po jednym naruszeniu** na każdym z trzech ekranów. Za każdym razem
jest to **to samo miejsce i nie jest to nasz kod**:

- reguła **`list`** (ważność: poważna) w **bloku nawigacji WordPressa** w nagłówku
  witryny — `ul.wp-block-navigation__container` zawiera bezpośrednio kolejną listę
  (blok „Lista stron") zamiast elementów listy. Markup pochodzi z rdzenia WordPressa,
  a nasze wtyczki nie tworzą na stronie żadnej nawigacji.

Co to znaczy dla Ciebie: **problem zobaczysz na każdej podstronie tego motywu**, także
tam, gdzie naszych wtyczek nie ma. Jeśli używasz innego motywu albo własnego nagłówka,
wynik będzie inny — dlatego polecenie niżej warto uruchomić na **swojej** stronie.

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

**Nota o wersjach 1.3.1, 1.3.2 i 1.3.3.** Badanie wykonano na paczce **1.3.0** i **nie było powtarzane** —
piszemy to wprost, zamiast podmieniać numer wersji w nagłówku.

Co zmieniło się od tamtej paczki: sprzątanie jednej opcji technicznej przy odinstalowaniu wtyczki,
poprawki w przyjmowaniu plików CSV (kontrola liczby kolumn, rozpoznawanie polskich znaków, pola
wieloliniowe), odświeżanie danych sprawy między regułami automatu, blokada przycisku „Wznów" na
ekranie importu na czas trwania operacji oraz uzupełnienia w instrukcjach.

**Trzy ekrany, których dotyczyło badanie — publiczny formularz zgłoszenia oraz panel klienta przed
i po zalogowaniu — nie zostały zmienione ani o jeden element**, dlatego wynik badania obowiązuje
dla 1.3.3 bez zastrzeżeń. Jedyna zmiana widoczna w interfejsie dotyczy **ekranu importu w panelu
administratora** (przycisk staje się nieaktywny w trakcie wznawiania — zachowanie zgodne z
wytycznymi, bo blokada jest komunikowana zmianą stanu przycisku, a nie samym kolorem).
