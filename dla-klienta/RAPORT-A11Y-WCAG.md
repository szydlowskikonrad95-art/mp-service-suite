# Raport dostępności (WCAG 2.1 AA) — MP Service Suite

**Data badania:** 2026-08-04 · **Wersja badana:** 1.3.12 — czyli **kod tej paczki**.
**Wersja:** 1.3.12.

## Co zmieniło się od poprzedniego badania

Poprzedni pomiar wykonaliśmy 31 lipca na wersji **1.3.6** i obejmował **trzy ekrany klienta**.
Ten pomiar wykonaliśmy **na kodzie, który trzymasz w ręku**, i obejmuje **jedenaście
powierzchni** — trzy ekrany klienta oraz osiem ekranów personelu w panelu WordPressa.
Powtórzyliśmy go, bo wydanie 1.3.12 **zmieniło badane ekrany**, a stary wynik przestałby o nich
mówić cokolwiek. Zmiany, które to wymusiły, wyszły z zewnętrznego audytu — podajemy je z nazwy,
żeby dało się sprawdzić, skąd się wzięły:

- **Pozycja 2.57 — błąd formularza prowadzi do konkretnego pola.** Podsumowanie błędów jest listą
  odnośników, pole z błędem jest oznaczone dla czytnika ekranu, a wysyłka ogłasza, że trwa.
  Wcześniej osoba korzystająca z czytnika słyszała, że coś jest nie tak, ale nie **co**.
- **Pozycja 2.47 — ekran importu ogłasza postęp, zakończenie i błąd** także czytnikowi ekranu.
  Dotąd pasek postępu zmieniał się w ciszy.
- **Pozycja 2.6 — dwa ekrany personelu mieszczą się w oknie przy powiększeniu 200%.**
  Co z tej pozycji **zostaje otwarte**, piszemy niżej, w osobnym rozdziale.
- **Pozycja 2.46 — samo narzędzie badające dostępność sięga teraz ekranów personelu** i drukuje
  zakres badania. To dlatego ten raport mówi o jedenastu powierzchniach, a poprzedni o trzech.
- **Znalezione tym pomiarem i naprawione w tym samym wydaniu:** pole listy powodów odrzucenia
  na ekranie „Ustawienia zgłoszeń" nie miało nazwy dla czytnika ekranu (reguła `label`, waga
  krytyczna). Wyszło **dopiero** dzięki rozszerzeniu narzędzia z pozycji 2.46. Wynik w tabelach
  niżej pochodzi z przebiegu **po** tej poprawce; wydruk sprzed niej też zostawiamy w repozytorium,
  żeby dało się porównać.

## ⛔ Czego ten raport NIE obejmuje

Uczciwie, zanim przeczytasz liczby:

- ⛔ **Badanie nie mówi nic o dostępności motywu Twojej strony.** Motywu nie dostarczamy i nie
  możemy go poprawiać; pokazujemy tylko, co w nim wychodzi, bo i tak zobaczysz to u siebie.
- ⛔ **Pomiar wykonaliśmy na naszej instalacji**, postawionej od zera z tej paczki — nie na Twojej
  stronie. Twój motyw, wtyczki i treść mogą dać inny wynik, dlatego narzędzie jest w paczce.
- ⛔ **`axe-core` nie jest wyrocznią.** Wykrywa naruszenia, które da się rozpoznać maszynowo —
  brak etykiety, za mały kontrast, powtórzony identyfikator. Nie oceni za to, czy tekst jest
  zrozumiały ani czy kolejność klawisza Tab ma sens dla człowieka. Zero naruszeń to **brak wykrytych
  błędów**, nie certyfikat zgodności.
- ⚠️ **Jeden ekran personelu nadal wychodzi poza okno przy powiększeniu** — piszemy o tym niżej,
  w rozdziale „Co zostaje otwarte". Reguły `axe` tego nie mierzą, więc mierzymy to osobno.
- Pomiar szedł po zwykłym HTTP, bo instalacja stała lokalnie. Na wynik reguł WCAG nie ma to wpływu;
  poprzednie badanie, na środowisku pokazowym, szło po HTTPS.

---

Ten dokument mówi, czy ekrany, które widzi **Twój klient**, dają się obsłużyć osobom
z niepełnosprawnościami — i czym to sprawdziliśmy. Nie jest to deklaracja: badanie
**możesz powtórzyć u siebie** poleceniem podanym na końcu.

## Jak badaliśmy

- **Narzędzie:** `axe-core` — otwarty, powszechnie używany silnik testów dostępności.
- **Zakres reguł:** WCAG 2.1, poziomy **A i AA**.
- **Sposób:** badanie na **żywej stronie w prawdziwej przeglądarce**, po HTTPS. Nie na samym
  kodzie: tylko tak da się sprawdzić rzeczy widoczne dopiero po wyrenderowaniu, czyli kontrast
  kolorów i pełne reguły ARIA.
- **Badaliśmy trzy razy, na trzech różnych środowiskach** — i podajemy wszystkie wyniki, bo razem
  mówią więcej niż jeden:

  | | Badanie 1 | Badanie 2 | Badanie 3 |
  |---|---|---|---|
  | Data | 2026-07-29 | 2026-07-31 | **2026-08-04** |
  | Wersja wtyczek | 1.3.0 | 1.3.6 | **1.3.12** |
  | WordPress / PHP / baza | 6.9 / 8.1 / MySQL 8 | 7.0 / 8.2 / MariaDB 11.8 | **6.9 / 8.1 / MySQL 8 (deklarowane minimum)** |
  | Motyw strony | Twenty Twenty-Five 1.4 | motyw strony demonstracyjnej | **Twenty Twenty-Five** |
  | Instalacja | czysta, postawiona z paczki | z paczki pobranej z wydania | **czysta, postawiona z tej paczki** |
  | Zbadane powierzchnie | 3 ekrany klienta | 3 ekrany klienta | **11: 3 klienta + 8 personelu** |
- **Co liczymy osobno:** naszą część strony (formularz, panel klienta) i całą stronę
  razem z motywem. Za motyw, którego nie dostarczamy, nie możemy odpowiadać — ale
  pokazujemy, co w nim wychodzi, bo i tak zobaczysz to u siebie.
- Uzupełniają to testy w naszym systemie ciągłej kontroli, które przy każdej zmianie
  pilnują etykiet pól, nazw przycisków, komunikatów dla czytników ekranu
  i unikalności identyfikatorów.

## Wynik — nasze ekrany

**Ekrany, które widzi Twój klient:**

| Ekran | 1.3.0 | 1.3.6 | **1.3.12** | Naruszenia |
|---|---|---|---|---|
| Formularz zgłoszenia (publiczny) | 12 | 12 | **13** | **0** |
| Panel klienta — przed zalogowaniem | 7 | 7 | **7** | **0** |
| Panel klienta — po zalogowaniu (dane osobowe, historia sprawy) | 7 | 9 | **7** | **0** |

**Ekrany personelu — badane po raz pierwszy** (wcześniej narzędzie do nich nie sięgało):

| Ekran | Reguł zdanych (1.3.12) | Naruszenia |
|---|---|---|
| Rejestr produktów | 6 | **0** |
| Wyjątki gwarancyjne | 9 | **0** |
| Import CSV | 15 | **0** |
| Sprawy | 11 | **0** |
| Zgłoszenia niepotwierdzone | 1 | **0** |
| Ustawienia zgłoszeń | 10 | **0** |
| Automat | 20 | **0** |
| Ustawienia automatu | 17 | **0** |

**Zero naruszeń WCAG 2.1 AA na wszystkich jedenastu powierzchniach, które dostarczamy.**
Przebieg kończy się kodem błędu, jeśli znajdzie choć jedno naruszenie w naszej części — ten
zakończył się powodzeniem, a jego pełny wydruk leży w repozytorium projektu.

⚠️ **Ekran „Ustawienia zgłoszeń" ma w tabeli 10 zdanych reguł, a w przebiegu sprzed poprawki
miał 5.** To nie jest poprawa punktacji: brakująca etykieta sprawiała, że część reguł nie miała
czego badać. Po naprawie mają.

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
różnie w kolejnych badaniach.

**Badanie 3 (1.3.12, domyślny motyw WordPressa Twenty Twenty-Five):** na trzech stronach klienta
**po jednym naruszeniu**, za każdym razem **to samo i nie w naszym kodzie** — reguła `list`
w bloku nawigacji WordPressa (opis niżej). Osiem ekranów personelu: **zero naruszeń** także razem
z otoczeniem panelu.

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

## Co zostaje otwarte — jeden ekran personelu przy powiększeniu

Reguły `axe` nie mierzą jednej rzeczy, która dla osoby powiększającej stronę jest najważniejsza:
**czy treść mieści się w oknie, czy trzeba przewijać całą stronę w bok** (WCAG 1.4.10). Mierzymy
to osobno, własnym pomiarem, razem z próbą kontrolną na sąsiednim ekranie — bo tylko wtedy wiadomo,
czy problem jest w tym ekranie, czy w całym panelu.

**Wynik na wydaniu 1.3.12:**

| Ekran | 1280 px @ 200% | 768 px @ 200% | 390 px @ 100% |
|---|---|---|---|
| Zgłoszenia niepotwierdzone | mieści się | mieści się | mieści się |
| **Panel automatyzacji** | mieści się | 🔴 **wychodzi o 167 px** | 🔴 **wychodzi o 78 px** |
| Sprawy (próba kontrolna) | mieści się | mieści się | mieści się |

🔴 **Panel automatyzacji przy węższym oknie nadal wychodzi poza ekran** — w obu tych punktach
próba kontrolna mieści się bez zarzutu, więc to wada tego jednego ekranu, nie całego panelu.
Poprawka z tego wydania zamknęła szerokość typowego monitora i tyle. **Mówimy o tym wprost,
zamiast pokazać wyłącznie punkt, który wypadł dobrze.** W praktyce dotyczy to osoby, która
powiększa panel na wąskim oknie albo pracuje na telefonie.

⚠️ Osobno, i to **nie jest** wada tego ekranu: przy 1024 px z powiększeniem 200% oraz przy 390 px
z powiększeniem 200% poza okno wychodzą **wszystkie** mierzone ekrany panelu, łącznie z próbą
kontrolną. To szersza sprawa układu panelu WordPressa przy bardzo dużym powiększeniu i zgłaszamy
ją jako osobną, otwartą pozycję.

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

**Historia tego dokumentu — wydanie po wydaniu.** ⭐ **Wynik w tabelach wyżej pochodzi z pomiaru
na wersji 1.3.12, więc poniższe jest już tylko zapisem drogi, a nie uzasadnieniem ważności.**
Zostawiamy je, bo pokazuje zasadę, której się trzymamy: **numeru w nagłówku nigdy nie podmieniamy**.
Dopóki badania nie było, dokument mówił, na czym je zrobiono i dlaczego wynik nadal obowiązuje;
gdy przestało dać się to uzasadnić — badanie powtórzyliśmy.

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

⭐ **Wydanie 1.3.12 zmieniło badane ekrany — i dlatego badanie POWTÓRZYLIŚMY** zamiast dopisywać
kolejne uzasadnienie. Wynik z 4 sierpnia, opisany na początku tego dokumentu, dotyczy właśnie tej
wersji i obejmuje jedenaście powierzchni zamiast trzech. Tutaj zostaje jedno zdanie, którego wyżej
nie ma: łańcuch not, który czytasz powyżej, **urwał się** przy tym wydaniu — i to było zgłoszone
jako wada dokumentu, zanim ktokolwiek zdążył się na niego powołać.

**Co sprawdzamy przy KAŻDEJ zmianie kodu, także między badaniami** — automatyczne kontrole
strukturalne w naszym systemie ciągłej kontroli, na renderach formularza, panelu klienta przed
i po zalogowaniu oraz ekranów personelu: etykieta spięta z każdym widocznym polem, błędy
w obszarze `role="alert"`, błąd spięty z polem przez `aria-describedby`, oznaczenie pól
wymaganych, brak powtórzonych identyfikatorów, opis alternatywny przy każdym obrazie, nazwa
dostępna przy każdym przycisku. **To warstwa strukturalna i nie zastępuje przebiegu
w przeglądarce** — kontrastu kolorów ani pełnych reguł ARIA tak sprawdzić się nie da. Dlatego
badanie w prawdziwej przeglądarce robimy osobno i zapisujemy jego datę oraz wersję.

Dla porządku, co działo się z kodem między badaniami: sprzątanie jednej opcji technicznej przy
odinstalowaniu wtyczki, poprawki w przyjmowaniu plików CSV (kontrola liczby kolumn, rozpoznawanie
polskich znaków, pola wieloliniowe), odświeżanie danych sprawy między regułami automatu, blokada
przycisku „Wznów" na ekranie importu na czas trwania operacji oraz uzupełnienia w instrukcjach.
**W wersjach 1.3.4 i 1.3.6 nie zmieniono ani jednej linii kodu.** W **1.3.5** zmiany dotyczyły
wyłącznie sposobu pobierania danych z bazy przez listy w panelu administratora (mniej zapytań).
Jedyna zmiana widoczna w interfejsie w całym tym okresie dotyczy **ekranu importu w panelu
administratora** (przycisk staje się nieaktywny w trakcie wznawiania — zachowanie zgodne
z wytycznymi, bo blokada jest komunikowana zmianą stanu przycisku, a nie samym kolorem).
