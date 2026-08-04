# Raport dostępności (WCAG 2.1 AA) — MP Service Suite

**Data badania:** 2026-07-31 · **Wersja badana:** 1.3.6
**Wersja:** 1.3.12 — tyle ma paczka, z którą ten dokument jedzie.

⚠️ **Numeru w nagłówku nie podmieniamy** — badanie przeglądarką wykonaliśmy na 1.3.6 i tak to
zapisujemy. Dla każdego kolejnego wydania mówimy osobno, czy wynik nadal obowiązuje: noty
o wersjach **1.3.7 – 1.3.12** stoją na końcu tego dokumentu. ⛔ **Przeczytaj je, zanim uznasz ten
wynik za aktualny — wydanie 1.3.12 jest pierwszym od czasu badania, które zmienia badane ekrany,
i badania na nim NIE powtórzyliśmy.**

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

**Ile ekranów zbadasz u siebie.** Narzędzie sięga **jedenastu powierzchni**: trzech, które widzi
Twój klient (formularz, panel przed i po zalogowaniu), oraz **ośmiu ekranów personelu w panelu
WordPressa** — rejestr produktów, wyjątki gwarancyjne, import CSV, sprawy, zgłoszenia
niepotwierdzone, ustawienia zgłoszeń, automat i jego ustawienia.

- **Dwa publiczne ekrany zbadasz od ręki** — formularz i panel przed zalogowaniem.
- **Panel po zalogowaniu** wymaga wejścia na konto linkiem wysłanym mailem, więc skrypt musi mieć
  dostęp do skrzynki (`MP_MAILPIT`). Bez tego dostępu po prostu go pomija i mówi o tym wprost —
  **to nie jest błąd**. My zbadaliśmy go na instalacji testowej, gdzie taki dostęp mamy.
- **Ekrany personelu** wymagają konta w panelu: `MP_ADMIN_USER` i `MP_ADMIN_PASS`. Bez nich
  narzędzie je pomija — również bez błędu.

**Każdy przebieg drukuje ZDANIE O ZAKRESIE**: co zbadał i czego nie zbadał, z nazwy. Wynik „zero
naruszeń" bez tego zdania mówiłby tylko tyle, że coś zbadano i nie wiadomo co. Sam zakres możesz
obejrzeć bez uruchamiania przeglądarki:

```bash
MP_BASE=https://twoja-strona.pl python3 dla-informatyka/audyt-dostepnosci/audyt-axe.py --lista-powierzchni
```

⚠️ **Do wydania 1.3.11 to narzędzie badało wyłącznie trzy powierzchnie klienta** — i to zawężenie
siedziało w samym przyrządzie, nie w jednym przebiegu. Skutek: kolejne wydania wychodziły
„zielone" na dostępności, opisując część systemu i nie mówiąc, że to część. Luka nie była
teoretyczna — w obszarze, którego przyrząd nie sięgał, leżała prawdziwa wada (ekran automatu przy
powiększeniu 200% wychodził 184 piksele poza okno). **Poprawiliśmy przyrząd w 1.3.12**, a wynik
z tabel wyżej pochodzi sprzed tej zmiany i dotyczy trzech ekranów klienta — tak jak napisano.

---

**Nota o powtórzeniu badania oraz o wersjach od 1.3.7 do 1.3.12** — wydanie po wydaniu, czy wynik
badania nadal obowiązuje. Tak utrzymujemy ważność tego dokumentu: **nie podmieniając numeru
w nagłówku**, tylko uzasadniając każdy krok. Tam, gdzie uzasadnić się nie da — piszemy to wprost.

Pierwsze badanie wykonaliśmy 29 lipca na paczce **1.3.0**. Ten dokument długo mówił wprost, że
**nie było powtarzane** — zamiast podmieniać numer wersji w nagłówku. 31 lipca badanie
**powtórzyliśmy na paczce 1.3.6 pobranej z wydania**, żeby wynik dotyczył wersji, którą naprawdę
dostajesz. Wynik w naszej części jest ten sam: **zero naruszeń na wszystkich trzech ekranach**.

**Wydanie 1.3.7 nie zmieniło ani jednej linii kodu** — poprawiło wyłącznie ten dokument (świeży
wynik badania) i CHANGELOG.

**Wydanie 1.3.8 zmienia kod, ale wyłącznie napisy na ekranach administratora** — nagłówek kolumny
na ekranie importu, komunikaty błędów importu, podpis listy pól szablonu, nazwę przycisku
przeliczania terminów oraz zdania objaśniające czas UTC. **Trzy ekrany objęte tym badaniem —
publiczny formularz zgłoszenia oraz panel klienta przed i po zalogowaniu — nie zostały zmienione
ani o jeden element**, więc wynik badania obowiązuje dla 1.3.8 bez zastrzeżeń.

**Wydanie 1.3.9 nie zmienia ani jednej linii kodu wtyczek** — poprawia wyłącznie dokumenty
(instrukcja wdrożenia, README, ten dokument, CHANGELOG) oraz jedną kontrolę jakości w CI.
Wynik badania obowiązuje dla 1.3.9 bez zastrzeżeń.

**Wydanie 1.3.10 zmienia kod, ale wyłącznie trzy napisy na ekranach ADMINISTRATORA** — komunikat
o roli pracownika, etykietę przycisku w Rejestrze zdarzeń i nagłówek kolumny w tabeli statusów.
**Trzy ekrany objęte tym badaniem — publiczny formularz zgłoszenia oraz panel klienta przed
i po zalogowaniu — nie zostały zmienione ani o jeden element**, więc wynik badania obowiązuje
dla 1.3.10 bez zastrzeżeń.

⚠️ Uczciwie: **ekrany administratora nie były przedmiotem tego badania** — ani przed, ani po
tej zmianie. Mierzyliśmy to, co widzi Twój klient. Zmienione napisy nie dotyczą więc wyniku
podanego w tabelach wyżej ani przed, ani po poprawce. (Samo narzędzie sięga ekranów personelu
od 1.3.12 — patrz rozdział „Jak powtórzyć to badanie u siebie". Pomiar z tabel wyżej jest
starszy od tej zmiany i ekranów personelu nie obejmuje.)

**Wydanie 1.3.11 zmienia kod, ale wyłącznie jeden ekran ADMINISTRATORA** — „Wyjątki gwarancyjne"
otwarte z menu, bez wybranego produktu, było ślepym zaułkiem; teraz tłumaczy, czym jest wyjątek,
i daje przycisk powrotu do Rejestru. Sprawdzone w historii zmian: to jedyny plik kodu ruszony
w tym wydaniu. **Trzy ekrany objęte tym badaniem nie zostały zmienione ani o jeden element**,
więc wynik badania obowiązuje dla 1.3.11 bez zastrzeżeń.

🔴 **Wydanie 1.3.12 jest pierwszym od czasu badania, które ZMIENIA badane ekrany — i dlatego
łańcucha „nic się nie zmieniło" tutaj NIE ciągniemy.** Na powierzchniach klienta zmieniło się:

- formularz zgłoszenia ma **nowe, wymagane pole „imię i nazwisko"** (to element, którego w chwili
  badania na tym ekranie nie było),
- **komunikat o błędzie prowadzi teraz do konkretnego pola**: podsumowanie błędów jest listą
  odnośników do pól, a pole z błędem jest oznaczone `aria-invalid`,
- **przycisk wysyłki ogłasza, że wysyłka trwa** — formularz dostaje `aria-busy`, napis przycisku
  się zmienia, a powtórne kliknięcie jest blokowane bez wyłączania kontrolki,
- w panelu klienta zmieniło się to, co wynika z ochrony danych osobowych (konto nie nosi już
  adresu e-mail w nazwie wyświetlanej).

⛔ **Badania axe-core w przeglądarce na 1.3.12 NIE powtórzyliśmy.** Piszemy to wprost, zamiast
podmieniać numer wersji w nagłówku.

**Czego przy tym NIE twierdzimy — bo to sprawdziliśmy.** Wszystkie powyższe zmiany **dokładają**
mechanizmy dostępności, nie odbierają ich; dwie z nich (błąd wskazujący pole, stan „to trwa")
powstały właśnie z zarzutu o dostępność. **Żaden arkusz stylów strony klienta nie został ruszony** —
jedyny zmieniony arkusz w tym wydaniu dotyczy panelu administratora — więc **kontrast kolorów**,
czyli ta część wyniku, której nie da się sprawdzić bez przeglądarki, zmian nie ma. W tym samym
wydaniu naprawiliśmy dwa ekrany personelu wychodzące poza okno przy powiększeniu 200%
(WCAG 1.4.10): panel automatu i „Zgłoszenia niepotwierdzone".

**Co za to sprawdzamy przy KAŻDEJ zmianie kodu, także w 1.3.12** — automatyczne kontrole
strukturalne w naszym systemie ciągłej kontroli, na renderach formularza, panelu klienta przed
i po zalogowaniu oraz ekranów personelu: etykieta spięta z każdym widocznym polem, błędy
w obszarze `role="alert"`, błąd spięty z polem przez `aria-describedby`, oznaczenie pól
wymaganych, brak powtórzonych identyfikatorów, opis alternatywny przy każdym obrazie, nazwa
dostępna przy każdym przycisku. **To warstwa strukturalna i nie zastępuje przebiegu
w przeglądarce** — kontrastu kolorów ani pełnych reguł ARIA tak sprawdzić się nie da.
Dlatego: chcesz mieć pomiar na 1.3.12, uruchom narzędzie z rozdziału wyżej u siebie —
albo poproś nas o powtórzenie badania.

Dla porządku, co działo się z kodem między badaniami: sprzątanie jednej opcji technicznej przy
odinstalowaniu wtyczki, poprawki w przyjmowaniu plików CSV (kontrola liczby kolumn, rozpoznawanie
polskich znaków, pola wieloliniowe), odświeżanie danych sprawy między regułami automatu, blokada
przycisku „Wznów" na ekranie importu na czas trwania operacji oraz uzupełnienia w instrukcjach.
**W wersjach 1.3.4 i 1.3.6 nie zmieniono ani jednej linii kodu.** W **1.3.5** zmiany dotyczyły
wyłącznie sposobu pobierania danych z bazy przez listy w panelu administratora (mniej zapytań).
Jedyna zmiana widoczna w interfejsie w całym tym okresie dotyczy **ekranu importu w panelu
administratora** (przycisk staje się nieaktywny w trakcie wznawiania — zachowanie zgodne
z wytycznymi, bo blokada jest komunikowana zmianą stanu przycisku, a nie samym kolorem).
