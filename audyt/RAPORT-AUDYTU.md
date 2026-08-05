# Raport z audytów — MP Service Suite

**Ten dokument jest protokołem z kolejnych przebiegów przeglądu — nie oświadczeniem o stanie
produktu.** Każda runda niżej ma własną datę, własny zakres i własny wynik. Wynik jednej rundy
nie rozciąga się ani na wydania późniejsze, ani na obszary, których ta runda nie obejmowała.

**Ostatnia runda — pięć niezależnych przebiegów, 5.08.2026, wersja audytowana 1.3.13.**
Zakres: dwa przeglądy **zewnętrzne** na kodzie wydawanym (surowa recenzja przedprodukcyjna oraz
kontrola wdrożenia prowadzona wyłącznie na zawartości paczki), trzy przebiegi własne (repozytorium
i paczka · wdrożenie i panel · dokumentacja, front i demo) oraz 16-punktowa kontrola oddania.
**Wynik: 51 pozycji** — **5 dużych**, 26 średnich i drobnych, 20 obserwacji środowiska pokazowego
i spraw oddanych do decyzji. **W wydaniu 1.3.13 zamknięto 17 pozycji**; co zostaje świadomie
i dlaczego, wymienia protokół tej rundy niżej. Naprawy opisuje
[`CHANGELOG.md`](../CHANGELOG.md) — wpis 1.3.13 podaje przy każdej test, który ją pilnuje.

**Poprzednia runda — audyt osobnego działu, lista złożona 3.08.2026, wersja audytowana 1.3.11.**
Zakres: trzy wtyczki, paczka dla klienta, dokumentacja i zgodność z **oryginalnym zamówieniem**
(nie z naszym opracowaniem), bez prawa zmiany kodu. **Wynik: 61 żywych pozycji** — rozkład wag
policzony z nagłówków listy: **3 krytyczne**, 16 dużych, 27 średnich, 15 drobnych — plus 5 miejsc
w części pierwszej. Naprawy weszły w wydaniu **1.3.12**; co zamknięte i czym udowodnione, mówią
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

## Runda przy 1.3.13 — dwa przeglądy zewnętrzne i trzy własne, na kodzie wydawanym

Przegląd przed wydaniem 1.3.13, przeprowadzony **5.08.2026** na tym samym kodzie, który jedzie do
klienta. Pięć niezależnych przebiegów w osobnych oknach: trzy własne (repozytorium i paczka ·
wdrożenie i panel administratora · dokumentacja, front i środowisko pokazowe) oraz **dwa
zewnętrzne, bez znajomości historii projektu i bez wglądu w nasze notatki** — surowa recenzja
przedprodukcyjna czytająca wyłącznie kod i zamówienie oraz kontrola wdrożenia wykonana wyłącznie
na zawartości paczki. Na koniec kontrola oddania: 16-punktowy scenariusz przeklikany na czystej
instalacji, z wtyczkami branymi **z paczki**, nie z repozytorium.

**Wynik łączny: 51 pozycji.** Rozkład wag policzony z nagłówków list: **5 dużych**, 26 średnich
i drobnych, 20 obserwacji środowiska pokazowego i spraw wątpliwych oddanych do decyzji.
**W wydaniu 1.3.13 zamknięto 17 pozycji**; reszta to świadome odstępstwa i dług projektowy opisane
niżej. Co dokładnie naprawiono i czym udowodniono, wymienia [`CHANGELOG.md`](../CHANGELOG.md) —
wpis 1.3.13 podaje przy każdej naprawie test, który ją pilnuje.

### Co sprawdzono

| Kąt | Zakres | Wynik |
|---|---|---|
| Recenzja przedprodukcyjna (zewnętrzna) | 30 969 linii kodu produkcyjnego, cztery niezależne przeglądy trzech wtyczek plus budowa i kontrola ciągła, paczka wydania, żywe demo | ocena łączna **8,3/10**; 5 pozycji dużych, około 20 drobnych |
| Kontrola wdrożenia (zewnętrzna) | czysta instalacja z paczki na WordPressie 7.0.2 / PHP 8.3, pełna ścieżka zgłoszenia, aktualizacja z poprzedniego wydania, odinstalowanie i ponowna instalacja, porównanie ekranów ze zdjęciami z instrukcji | **z paczki da się wdrożyć działający produkt**; 1 pozycja wysoka, 2 średnie, 5 drobnych; zero błędów PHP w ~40 przejściach |
| Repozytorium i paczka (własne) | wejście obcego czytelnika, strona wydania, zawartość archiwum, martwe odsyłacze, język i historia zmian | rozbieżności wyłącznie w opisach i materiałach, nie w kodzie |
| Wdrożenie i panel administratora (własne) | instalacja od zera, pełna ścieżka zgłoszenia, kopia zapasowa i cofnięcie migracji, praca bez modułu rejestru, odinstalowanie, progi limitów zgłoszeń zmierzone na żywo | 2 pozycje duże, reszta drobna; kopia zapasowa i obie drogi cofnięcia migracji **potwierdzone** |
| Dokumentacja, front i demo (własne) | około 150 twierdzeń z pięciu instrukcji porównanych z kodem, zdjęcia i diagramy, dokumenty techniczne, stan środowiska pokazowego | 1 pozycja duża, 12 drobnych, reszta to porządki na demie |
| Kontrola oddania (16 punktów) | naprawy przeklikane na czystej instalacji, wtyczki wyłącznie z paczki, 31 zrzutów i wyjść poleceń jako dowód | **komplet przeszedł** po dwóch powtórkach opisanych niżej |

### Co zamknięto w tym wydaniu

Pozycje o największym ciężarze — każda z własnym testem, który czerwieni się na kodzie sprzed naprawy:

- **Reguła powiadomienia utworzona według podpowiedzi ekranu wysyłała wewnętrzną wiadomość do
  klienta.** Ekran uczył jednego zapisu odbiorcy, silnik rozumiał wyłącznie drugi. Znalezione
  niezależnie przez recenzję zewnętrzną i potwierdzone na żywo w kontroli oddania.
- **Zmiana sprawy mogła wejść bez wpisu na osi zdarzeń**, wbrew gwarancji z dokumentacji. Naprawa
  objęła najpierw zmianę statusu, a po własnym powrocie do tej samej klasy błędu — również przydział
  i zmianę priorytetu, wraz z sygnałem dla administratora, który wcześniej ginął przy wycofaniu
  transakcji.
- **Pracownik serwisu pobierał załącznik dowolnej sprawy**, także nieprzydzielonej — mimo że kartę
  cudzej sprawy system odbijał już wcześniej.
- **Obietnica usunięcia danych po zakończeniu zgłoszenia nie miała wykonawcy** — po zamknięciu sprawy
  dane zostawały w bazie, dopóki ktoś nie powtórzył żądania.
- **Trzy zachowania rozjeżdżały się przy równoczesnych żądaniach**: dobowy limit zgłoszeń,
  archiwizacja produktu z aktywną sprawą i próby wysyłki przypomnień o terminach.
- **Wbudowana diagnostyka podawała instrukcję, która nie usuwała problemu** — kontrola wdrożenia
  wykonała ją dosłownie i ostrzeżenie nie zniknęło. Warunek testu był poprawny; myliła treść porady.
- **Instrukcje i diagramy zrównane z zachowaniem produktu** w kilkunastu miejscach: limit wielkości
  pliku przy imporcie, zakres uprawnień w panelu koordynatora, warunki odinstalowania, moment wysyłki
  raportu końcowego, ważność linku potwierdzającego wobec okna na potwierdzenie.

### Dwie powtórki w kontroli oddania — obie zapisane

Kontrola oddania **zatrzymała wydanie dwukrotnie** i za każdym razem miała rację:

1. Naprawa odświeżania tabeli importów wniosła nowy defekt — link do raportu błędów dorabiany przez
   przeglądarkę był martwy do czasu odświeżenia strony. Punkt powtórzony po poprawce i zaliczony.
2. Diagnostyka, napisy przy imporcie z błędami i opis odinstalowania — trzy punkty powtórzone po
   ostatniej poprawce i zaliczone.

To jest powód, dla którego kontrola oddania pracuje na paczce, a nie na repozytorium: **oba defekty
były widoczne dopiero w zainstalowanym produkcie**.

### Co świadomie zostaje — i dlaczego

- **Przydział zgłoszeń według kraju i języka nie działa.** Zamówienie wymienia cztery kryteria
  przydziału; działają dwa — kategoria produktu i priorytet. Produkt nigdzie nie zbiera danych
  o kraju ani języku klienta, więc reguła oparta na nich nie dopasuje żadnej sprawy. **Nie jest to
  ukryte:** ostrzega o tym ekran ustawień przy zapisie reguły, opis bazy danych i instrukcja
  administratora, a w tym wydaniu poprawiono ostatnie miejsce, które o tym milczało — opis modułu
  automatyzacji. Uzupełnienie wymagałoby dołożenia pól do formularza zgłoszenia i zmiany zakresu
  zamówienia; **to decyzja zamawiającego, nie wykonawcy.**
- **Klasa obsługująca sprawy jest za duża** — 2371 linii i 45 metod w jednym pliku, przez który
  przechodzi każda zmiana w module zgłoszeń. Recenzja zewnętrzna ważyła to jako pozycję dużą ze
  względu na skalę, zaznaczając, że **nie jest to błąd działania, tylko koszt utrzymania**. Podział
  tej klasy to refaktor dotykający wszystkich ścieżek zapisu; przed wydaniem byłby zmianą
  najwyższego ryzyka przy zerowym zysku dla użytkownika. Zostaje jako dług do zaplanowania.
- **Jedno miejsce, w którym moduł automatyzacji sięga wprost do klasy modułu zgłoszeń**, zamiast
  przez punkt zaczepienia — przy ochronie przed podwójnym mailem. Kod ma zabezpieczenie na wypadek
  braku tej klasy i uczciwy komentarz, ale precedens narusza najmocniejszą regułę tej architektury.
  Zamiana na punkt zaczepienia jest prosta; nie robimy jej w wydaniu naprawczym, żeby nie zmieniać
  kontraktu między modułami w tym samym wydaniu, w którym zmieniamy zachowanie.
- **Sygnał o gubionych wpisach dziennika jest zapisywany, ale nie ma go na liście testów
  „Stanu witryny".** Kontrola oddania wywołała ten sygnał na żywo i potwierdziła, że administrator
  go nie zobaczy. Naprawa to dołożenie jednego testu diagnostycznego — zmiana innej klasy niż te
  z tego wydania, więc czeka na kolejne.
- **Niepotwierdzone zgłoszenie blokuje archiwizację produktu, a lista pokazuje przy nim zero
  spraw** — stan zastany z poprzedniego wydania, nie regresja. Ekran przeczy sam sobie i nie daje
  administratorowi drogi do znalezienia blokującego zgłoszenia. Do naprawy w kolejnym wydaniu.
- **Drobiazgi oddane do decyzji zamawiającego:** granica gwarancji liczona w czasie uniwersalnym
  (przesunięcie działa zawsze na korzyść klienta, jest udokumentowane) oraz daty gwarancji na karcie
  sprawy pokazywane z doklejoną godziną. Żaden z nich nie wpływa na rozstrzygnięcie gwarancji.

### Czego ta runda nie objęła

Przeglądy zewnętrzne pracowały na kodzie i na paczce — **nie** na środowisku produkcyjnym
zamawiającego. Nie badano wydajności pod obciążeniem ani importu bazy liczącej dziesiątki tysięcy
pozycji. Badanie dostępności **nie zostało powtórzone** na tym wydaniu; raport w paczce mówi wprost,
którego wydania dotyczy i których ekranów dotknęły zmiany. Kontrola wdrożenia prowadzona była
w jednej przeglądarce.

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
