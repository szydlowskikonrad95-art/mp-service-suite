# Raport z audytów — MP Service Suite

**Ten dokument jest protokołem z kolejnych przebiegów przeglądu — nie oświadczeniem o stanie
produktu.** Każda runda niżej ma własną datę, własny zakres i własny wynik. Wynik jednej rundy
nie rozciąga się ani na wydania późniejsze, ani na obszary, których ta runda nie obejmowała.

**Ostatnia runda — audyt osobnego działu, lista złożona 3.08.2026, wersja audytowana 1.3.11.**
Zakres: trzy wtyczki, paczka dla klienta, dokumentacja i zgodność z **oryginalnym zamówieniem**
(nie z naszym opracowaniem), bez prawa zmiany kodu. **Wynik: 61 żywych pozycji** — rozkład wag
policzony z nagłówków listy: **3 krytyczne**, 16 dużych, 27 średnich, 15 drobnych — plus 5 miejsc
w części pierwszej. Naprawy wchodzą w wydaniu **1.3.12**; co zamknięte i czym udowodnione, mówią
[`CHANGELOG.md`](../CHANGELOG.md) — wpis 1.3.12 wymienia każdą naprawę wraz z dowodem,
a przy większości podaje nazwę testu, który ją pilnuje.

⛔ **Poprzednie brzmienie tego nagłówka było jedną z wad, które ta runda znalazła.** Stało tu
zdanie *„Stan na wydanie 1.3.11: znalezisk krytycznych 0, dużych 0"* — **bez daty i bez zakresu**,
więc czytało się jak stan produktu, a nie jak wynik jednego przebiegu z określonego dnia. Sama
liczba nie wzięła się znikąd: audyt końcowy przed oddaniem (1.08; protokół tej rundy stoi niżej
w tym dokumencie — „Runda przy 1.3.9 — audyt końcowy przed przekazaniem", a naprawy po niej
dokumentuje [`CHANGELOG.md`](../CHANGELOG.md)) **w swoim zakresie** nie znalazł pozycji
krytycznych ani dużych. Audyt
działu, z innymi kątami patrzenia, znalazł w tym samym kodzie trzy pozycje krytyczne — dwie z nich
dotyczą danych osobowych. **Obie liczby są prawdziwe i żadnej nie wycofujemy — dlatego każda musi
stać przy swojej dacie i swoim zakresie.**

Dokument zbiera wyniki kolejnych rund przeglądu. Jest pisany tak, żeby dało się go zweryfikować:
każde twierdzenie ma liczbę albo miejsce, w którym można je sprawdzić. Zawiera też rzeczy, które
wypadły źle — bo raport pokazujący wyłącznie sukcesy nie jest raportem.

## Jak prowadzimy audyt — trzy zasady

**1. Osobne kąty patrzenia, nie jeden „przegląd".** Każda runda dokłada kąt, którego wcześniej
nie było: zgodność z zamówieniem · bezpieczeństwo · kompletność („czy coś czegoś **nie robi**,
choć wygląda na sprawne") · spójność paczki · wydajność · zrozumiałość dla nietechnicznego
czytelnika. Nowe błędy znajduje nowy kąt, nie powtórzenie tego samego przeglądu.

**2. Audytor nie czyta naszej dokumentacji, tylko zamówienie.** Przegląd oparty na naszych
dokumentach potwierdzi, że są zgodne **ze sobą**, i przepuści rozbieżność z tym, co faktycznie
zamówiono. Ta różnica nie jest teoretyczna — patrz runda „numer sprawy" niżej.

**3. Audytora się kalibruje.** Opisane w [`README.md`](README.md): do kodu wstrzykiwane są celowe
błędy, a audytor nie wie, że trwa kalibracja. Kto ich nie znajdzie, tego „czysto" nie liczy się
jako wynik.

---

## Runda przy 1.3.9 — audyt końcowy przed przekazaniem (sześć kątów naraz)

Ostatni przegląd przed oddaniem systemu. Zamiast jednej „kontroli końcowej" — **sześć niezależnych,
każda w osobnym oknie, bez wiedzy o tym, jak kod powstawał, i bez prawa jego zmiany**: zgodność
z zamówieniem · klikanie po działającej stronie · paczka i repozytorium · bezpieczeństwo ·
kompletność („czego system **nie robi**") · czytelnik nietechniczny wykonujący instalację
z instrukcji w ręku.

**Wynik: 16 znalezisk, zero usterek działania.** Wszystkie dotyczyły dokumentacji, materiałów dla
klienta albo naszego środowiska pokazowego — nie kodu wtyczek.

**Co potwierdzono dowodem:**

| Co sprawdzono | Wynik |
|---|---|
| Zgodność z zamówieniem klienta (39 pozycji spisanych z oryginału) | **37 potwierdzonych** cytatem `plik:linia`; 2 to udokumentowane, świadome odstępstwa |
| Instalacja od zera na **deklarowanym minimum** (WordPress 6.0, PHP 8.1) | **przeszła**, zero błędów krytycznych — paczka brana z wydania, nie z repozytorium |
| Powtarzalność budowy | paczka zbudowana ze źródeł **identyczna** z pobraną z wydania (poza metadanymi budowy) |
| Bezpieczeństwo — 7 obszarów (nonce, uprawnienia, dostęp do cudzych danych, zapytania, escaping, załączniki, link logowania) | **wszystkie zabezpieczone**, z cytatem z kodu przy każdym |
| Ścieżka klienta na żywej stronie | przeklikana dla **4 rodzajów zgłoszeń i 4 kategorii**; panel personelu w całości |

**Co poprawiono w tym wydaniu:** sprzeczna liczba testów diagnostyki w README · kontrola jakości,
która sprawdzała *obecność* poprawnej liczby zamiast jej *spójności* · brak kroku „schowaj formularz
na czas przygotowań" w instrukcji · nazwa przycisku instalacji niezgodna z nowszym WordPressem.

### Kalibracja: najpierw 1/3, po diagnozie 3/3 — obie liczby są tutaj

Do kodu wstrzyknięto **15 celowych błędów**, z czego **10 wziętych z listy uwag zewnętrznego
recenzenta**, nie z głowy autora kodu (inaczej kalibracja mierzyłaby własną ślepą plamkę).

**Pierwsze podejście — 1 na 3, poniżej progu.** Audytor trafił w zawężoną matrycę wersji PHP,
ale nie zauważył podłożonej asymetrii odinstalowania ani usuniętej sekcji granic w README.
Oba przeoczone obszary sprawdzono wtedy **ręcznie** — wynik pozytywny.

**Diagnoza: pomiar był nieuczciwy wobec audytora.** Kalibrowany dostał **trzy obszary naraz**
przy 40 krokach, podczas gdy każda z sześciu prawdziwych kontroli miała **jeden obszar** i 45–55
kroków. Mierzyliśmy więc coś innego, niż działo się naprawdę.

**Drugie podejście, w warunkach realnych — 3 na 3.** Nowe losowanie z tej samej puli, trzej
osobni audytorzy, każdy z jednym obszarem. Znaleźli wszystko: brak escapowania znaków
wieloznacznych w wyszukiwarce, usunięty plik licencji, angielski nagłówek kolumny — każde
z cytatem z pliku i numerem linii.

**Wniosek, który zmienił sposób pracy:** kontrola przeciążona liczbą zadań przestaje widzieć.
To nie jest wada narzędzia, tylko sposobu zlecania — i dlatego kontroli jest sześć osobnych,
a nie jedna zbiorcza.

⚠️ **Kalibracja przy okazji wykryła trzy PRAWDZIWE usterki języka** (nie podłożone): komunikaty
cytujące nazwę roli inaczej, niż brzmi ona na liście użytkowników; nazwa stałej z kodu na
przycisku; żargon w nagłówku kolumny. Naprawione w 1.3.10 — opis w [`CHANGELOG.md`](../CHANGELOG.md).
**To dowód, że naprawa z wydania 1.3.8 objęła część miejsc, nie wszystkie** — i że kalibracja
opłaca się nawet wtedy, gdy audytor zdaje egzamin.

### Czego ten audyt nie objął

- **Dynamiczny test penetracyjny nie doszedł do skutku** — przebieg został przerwany przez filtr
  bezpieczeństwa narzędzia. Zastąpiono go statycznym przeglądem wzorców obronnych (wynik w tabeli).
- Ekrany administratora pozostają poza badaniem dostępności (badanie obejmuje trzy ekrany klienta).
- Zrozumiałość instrukcji oceniał czytelnik **wcielony w rolę**, nie żywy człowiek spoza projektu.
- Nie sprawdzono: wstrzyknięcia formuł do eksportu CSV, generowania tokenu potwierdzenia zgłoszenia.

---

## Runda przy 1.3.8 — przegląd oczami użytkownika, nie skryptu

Ta runda nie wyszła z żadnej kontroli automatycznej. **Zamawiający kliknął po panelu** i zapytał
o trzy rzeczy, które wyglądały podejrzanie. Sprawdzenie ich uruchomiło szerszy przegląd dwiema
niezależnymi kontrolami: jedna szukała **rozjazdów między instrukcją a panelem**, druga
**żargonu w polskim interfejsie**. Każde zgłoszone znalezisko zweryfikowaliśmy w kodzie, z numerem
linii, zanim cokolwiek poprawiliśmy — dwa zgłoszenia okazały się przy tym przesadzone i zostały
zawężone do tego, co dało się potwierdzić.

**Znaleziono 13 pozycji. Ani jedna nie była usterką działania** — wszystkie dotyczyły języka
i zgodności materiałów z tym, co widać na ekranie. Najpoważniejsze:

| Co | Gdzie widać |
|---|---|
| nagłówek kolumny **„Job"** wśród polskich nagłówków | ekran importu **oraz zdjęcie w instrukcji** |
| komunikaty błędu mówiące **„job"** | widzi je pracownik, gdy import się przerwie |
| **zdjęcie wyjątków gwarancyjnych pokazywało pusty ekran** | instrukcja administratora |
| instrukcja podawała **drogę prowadzącą do tego pustego ekranu** | instrukcja administratora |
| filtr **„Przydzielony: ja"** — w panelu nazywa się **„Moje sprawy"** | instrukcja pracownika |
| **„whitelist"**, **„batch"**, **„UTC"** bez wyjaśnienia | panel, eksport CSV |

**Najważniejsza lekcja tej rundy dotyczy przyczyny, nie objawu.** Puste zdjęcie wyjątków nie było
pomyłką przy jednorazowym renderowaniu — **narzędzie generujące zdjęcia wchodziło na ten ekran bez
wskazania produktu**, więc błąd wracałby przy każdym odświeżeniu materiałów. Poprawione zostało
narzędzie, nie sam obrazek.

**Czego ta runda dowodzi o granicach kontroli automatycznych:** 16 kontroli w CI, bramka
dokumentów (40 sprawdzeń) i audyty przed poprzednimi wydaniami przepuściły wszystkie te pozycje.
Żadna maszyna nie sprawdzi, **co widać na zdjęciu**, ani czy słowo na przycisku jest zrozumiałe
dla człowieka. To znajduje wyłącznie ktoś, kto klika.

## Runda przy 1.3.7 — powtórzone badanie dostępności

Raport dostępności w paczce klienta opierał się na badaniu paczki **1.3.0** i mówił to wprost
zamiast podmieniać numer w nagłówku. To była uczciwa, ale niepełna odpowiedź, więc **badanie
powtórzyliśmy** — tym razem na paczce **1.3.6 pobranej z wydania**, czyli dokładnie na tym, co
dostaje klient.

Warunki drugiego badania celowo różnią się od pierwszego, żeby wynik nie zależał od jednego
środowiska: **WordPress 7.0 / PHP 8.2 / MariaDB 11.8** i inny motyw (pierwsze: WP 6.9 / PHP 8.1 /
Twenty Twenty-Five). Badanie na żywej stronie po HTTPS, w prawdziwej przeglądarce; trzeci ekran
osiągnięty realną ścieżką klienta — link logowania wysłany na e-mail i odczytany ze skrzynki.

**Wynik: zero naruszeń WCAG 2.1 AA w naszych trzech ekranach** (12, 7 i 9 zdanych reguł).
Cała strona razem z motywem również zero — w pierwszym badaniu było tam jedno naruszenie,
w bloku nawigacji WordPressa, czyli poza naszym kodem.

W kodzie wtyczek **nie zmieniono ani jednej linii** — różnica względem 1.3.6 to 6 linii numeru
wersji. Numer podniesiono dlatego, że zmienia się zawartość paczki: ta sama nazwa przy innej
zawartości znaczyłaby dwie różne paczki nie do odróżnienia po sumie kontrolnej.

## Runda przy 1.3.6 — dlaczego nie powtarzaliśmy audytu

W tym wydaniu **nie zmieniono ani jednej linii logiki**. Cała różnica w kodzie PHP względem
poprzedniego wydania to **6 linii i wszystkie są numerem wersji**. Reszta zmian to instrukcje
dla klienta.

Dlatego audytu bezpieczeństwa i wydajności **nie powtarzano** — piszemy to wprost, zamiast
podmieniać numer wersji w nagłówku i udawać nową rundę. Sprawdzono natomiast to, co faktycznie
mogło się zmienić: komplet kontroli automatycznych (**16/16 zielonych** — na gałęzi, na gałęzi
głównej i na znaczniku wydania), zgodność numeru wersji w 3 wtyczkach i 10 dokumentach oraz
**wszystkie ekrany panelu obejrzane na żywo** w prawdziwej przeglądarce: zero błędów konsoli,
zero nieudanych żądań.

## Runda przy 1.3.5 — wydajność

**Znalezione: trzy miejsca, w których lista pytała bazę o każdy wiersz osobno. Dwa naprawione.**

| Ekran | Zapytań przed | Zapytań po |
|---|---|---|
| Lista spraw | 43 | **4** |
| Rejestr produktów | 64 | **45** |

Zachowanie ekranów bez zmian — sprawdzone renderem, nie założeniem.

⚠️ **Pierwsza wersja poprawki przywróciła problem, który miała usunąć.** Wyszło to dopiero
**pomiarem po naprawie** — gdyby poprzestać na przeczytaniu kodu, poprawka weszłaby jako
„zrobiona". Stąd zasada: naprawę wydajności potwierdza pomiar po, nie przed.

**Trzecie znalezisko zostaje świadomie**, bo jego usunięcie wymaga zmiany kontraktu między dwiema
wtyczkami naraz, a ekran renderuje się w ~26 ms przy 50 tysiącach rekordów. Decyzja odłożona —
nie przemilczana.

**Pomiary skali:**
- import **50 000 wierszy**: wszystkie przyjęte, 51,6 s, szczyt pamięci **59 MB** (plik czytany
  strumieniowo, nie ładowany w całości)
- **50 000 produktów** w rejestrze: ekran listy **41 ms** (przy 1 000 rekordów — 44 ms),
  wyszukanie po numerze seryjnym **0,2 ms**
- narzut na każde żądanie strony: **0,0 KB z 29,1 KB** wszystkich automatycznie ładowanych opcji
- analiza statyczna poziom 6: **0 błędów, bez pliku wyjątków**

## Runda przy 1.3.4 — kontrola od strony odbiorcy

Paczka **pobrana z opublikowanego wydania** (nie zbudowana lokalnie) przepuszczona przez pełny
test instalacji od zera. Przeszła.

**Znalezisko: paczka wydania obiecywała więcej niż kod.** Poprawka dokumentacji weszła
**po** zbudowaniu paczki — repozytorium mówiło prawdę, paczka nie. Stąd twarda kolejność przy
wydaniu: zmiany → gałąź główna → dopiero potem znacznik i paczka.

**Przegląd repozytorium pod kątem śladów środowiska pracy: 2 trafienia, oba usunięte.**

## Runda przy 1.3.3 — spójność po wydaniu

Przegląd nastawiony na jedno pytanie: co **przestało być prawdą** po ostatnich naprawach.
Własna poprawka potrafi unieważnić dokumentację i testy, które wcześniej były zgodne.

## Runda przy 1.3.2 — czytanie kodu linia po linii

**1 621 linii przeczytanych w całości → 7 napraw**, m.in.: kontrola liczby kolumn w pliku CSV ·
rozpoznawanie kodowania na proporcji znaków zamiast pojedynczego bajtu · obsługa pól
wieloliniowych · odświeżanie danych sprawy między regułami automatu · blokada przycisku na czas
trwania operacji.

**Ocena instrukcji przez czytelnika nietechnicznego: 62/100.** Dołożono ostrzeżenie, że rozdział
o serwerze nie jest do samodzielnego wykonania, gotowe treści wiadomości do hostingu, rozdział
„do kogo się zwrócić" i słowniczek. **Po poprawkach: 79/100.**

## Runda przy 1.3.1 — trzy nowe kąty

### Bezpieczeństwo — brak znalezisk, kalibracja zdana
Dwóch niezależnych audytorów (formularz publiczny, załączniki i logowanie · panel, import
i eksport, zadania cykliczne). Kryterium: tylko realnie wykorzystywalne, pewność powyżej 80%.

**Kalibracja:** do kopii w piaskownicy wszczepiono 3 luki w miejscach, które audytorzy ogłosili
poprawnymi. Dwie — **znalezione**. Trzecia **słusznie pominięta**: dostęp pozostawał zablokowany,
nie było ścieżki ataku. Wniosek: audytorzy widzą, więc ich „brak znalezisk" ma wartość dowodową.

**Kontrola maszynowa całości:** **38 zarejestrowanych punktów wejścia HTTP**, **13 operacji
uprzywilejowanych** — wszystkie z kontrolą uprawnień **i** zabezpieczeniem przed przesłaniem
żądania z obcej strony. Panel klienta: kontrola własności zamiast uprawnień, poprawna z założenia.

### Kompletność — 3 znaleziska, 2 naprawione
Kąt „czy coś czegoś nie robi, choć wygląda na sprawne". Znaleziono ustawienie techniczne
niekasowane przy odinstalowaniu (bliźniacza opcja w drugiej wtyczce była kasowana poprawnie —
czyli wzorzec naprawiono wcześniej tylko w jednym egzemplarzu), komentarz obiecujący ekran,
którego nie ma, oraz kolumnę zapisywaną, a nigdy nieczytaną (odłożona, bo usunięcie wymaga
migracji danych).

### Ponowna weryfikacja 13 uwag recenzenta na aktualnym kodzie
Poprzednia była sprzed kilku wydań. Wynik czysty, jedno trafienie trafiło na listę wyżej.

### Bramki, które zadziałały przeciwko nam — dowód, że nie są ozdobą
- **Bramka pakująca odrzuciła paczkę**: w repozytorium było 8 dokumentów technicznych,
  a lista w skrypcie miała 7. Lista jest jawna celowo — pętla po katalogu przepuściłaby
  **skasowanie** dokumentu.
- **Zabezpieczenie przed rekurencyjnym kasowaniem zablokowało nasze własne polecenie.**
  Nie obchodziliśmy go — zrobiliśmy inaczej.
- **Walidator formularza odrzucił nasze celowo paskudne dane.**
- Nasz własny szybki skrypt kontrolny dał **2 fałszywe trafienia**, a pierwszy pomiar kodowania
  był **błędny** — oba zweryfikowane do końca, zanim cokolwiek zgłosiliśmy jako wadę.

### Dowody wykonania
- **Instalacja od zera z paczki** na deklarowanym minimum (WordPress 6.9 / PHP 8.1 / MySQL 8):
  ścieżka klienta **20/0**, wgranie przez panel **6/0**, zero błędów PHP z naszego kodu
- **Współistnienie z obcymi wtyczkami**: edytor klasyczny + wtyczka poczty + wtyczka pamięci
  podręcznej włączone obok naszych → zadania cykliczne i testy diagnostyczne nadal działają
- **Paskudne dane**: polskie znaki, emoji, znacznik skryptu, apostrof, cudzysłów, znaki nowej
  linii → zapisane i odczytane bez uszkodzenia; za długi tekst odrzucony
- **Formuły w eksporcie**: `=`, `+`, `-`, `@` unieszkodliwione, polskie znaki przepuszczone bez
  fałszywych trafień
- **Współbieżność numeracji**: 20 równoległych procesów → 20 unikalnych numerów, **zero duplikatów**
- **Dostępność (WCAG 2.1 AA)**, pomiar narzędziem axe-core: **0 naruszeń** na naszych ekranach

---

## Znalezisko, które przeżyło wszystkie wcześniejsze audyty

**Numer sprawy miał inny format niż w zamówieniu** (pięć cyfr zamiast czterech).

Przeszło przez kilka rund, bo każda z nich czytała **naszą** dokumentację — a ta była zgodna
sama ze sobą i **niezgodna z zamówieniem**. Ktoś na wcześniejszym etapie „poprawił literówkę"
w dokumencie, dopasowując go do kodu.

Złapał to dopiero audytor, któremu dano **surowy dokument zamówienia** zamiast naszego
opracowania. Stąd zasada nr 2 na górze tego dokumentu.

## Czego te audyty NIE obejmują

Uczciwa lista, nie zamiatanie. Żaden audyt nie dowodzi braku wszystkich błędów — poniżej to,
czego świadomie nie sprawdzono albo sprawdzono tylko częściowo:

- **Wygląd ekranów oceniony przez projektanta.** Ekrany obejrzano na żywo pod kątem błędów
  i poprawności, nie pod kątem estetyki.
- **Pełny audyt dostępności na żywej stronie u klienta** — pomiar wykonano na naszym środowisku.
- **Zrozumiałość instrukcji po ostatnich poprawkach**, zbadana na kolejnej żywej osobie.
  Ostatnia ocena (79/100) pochodzi od czytelnika wcielonego w rolę, nie od klienta.
- **Zachowanie przy bardzo długiej pracy bez przerwy** (miesiące działania bez restartu).
- Trzy znane, świadomie odłożone drobiazgi: jedno miejsce nadmiarowych zapytań, jedna martwa
  kolumna w bazie i jedno uproszczenie wymagające nowszej wersji WordPressa niż nasze minimum.
  Wszystkie opisane w [`ZAKRES-SPRAWDZONY.md`](ZAKRES-SPRAWDZONY.md).

## Lekcje procesowe — co ten projekt nas nauczył

1. **Naprawa wzorca, nie egzemplarza.** Ten sam błąd siedział w dwóch wtyczkach; naprawiony
   w jednej wracał jako nowe znalezisko w drugiej.
2. **Audyt czytający własną dokumentację potwierdza jej spójność, nie zgodność z zamówieniem.**
3. **Pomiar po naprawie, nie przed.** Poprawka wydajności potrafi cicho przywrócić to, co usuwała.
4. **Bramka jest warta tyle, ile jej czułość.** Kontrola, która nigdy niczego nie zatrzymała,
   jest nieodróżnialna od kontroli zepsutej — dlatego kalibrujemy podłożonymi błędami.
5. **Zmiana unieważnia dokumentację i testy.** Po każdej naprawie osobne pytanie: co **przestało
   być prawdą**.
