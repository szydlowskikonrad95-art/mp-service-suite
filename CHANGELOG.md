# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/pl/1.1.0/) · wersjonowanie: [SemVer](https://semver.org/lang/pl/).

## [Unreleased]

## [1.0.3] - 2026-07-28

Wydanie uzupełniające paczkę — **bez zmian w kodzie wtyczek**. Domyka to, czego brakowało
osobie technicznej po stronie klienta, i zamyka ostatnią uwagę recenzenta dotyczącą CI.

### Added (paczka dla klienta)
- `dla-informatyka/` — komplet dokumentacji technicznej w paczce: układ bazy, kontrakt
  między wtyczkami, model zdarzeń, maszyna statusów, własność danych, zasady bezpieczeństwa,
  polityka migracji. Wcześniej te dokumenty istniały wyłącznie w repozytorium, więc kto
  dostawał samą paczkę, nie dostawał nic dla programisty.
- `diagramy/zrodla/` — źródła diagramów (HTML + CSS), żeby dało się je poprawić, a nie
  tylko obejrzeć gotowy obrazek.

### Security (łańcuch dostaw CI)
- Wszystkie akcje w `quality.yml` przypięte do **skrótu commita (SHA)** zamiast ruchomych
  tagów `@v1`/`@v2`/`@v4`/`@v7`. Przejęcie repozytorium akcji nie podmieni nam już tego,
  co uruchamia się z dostępem do sekretów. Wersja pozostaje w komentarzu przy każdym wpisie.

### Changed (skrypt pakujący — bramka, nie komentarz)
- Samokontrola paczki sprawdza teraz, czy **każdy** dokument techniczny z repozytorium
  faktycznie znalazł się w paczce i czy liczba źródeł diagramów zgadza się z liczbą obrazków.

## [1.0.2] - 2026-07-28

Wydanie porządkujące paczkę — **bez zmian w kodzie wtyczek**. Powstało po pełnym sprawdzeniu
1.0.1 przed przekazaniem (kalibracja audytu + testy na żywym systemie); żadnej wady działania
nie znaleziono, poprawki dotyczą wyłącznie spójności materiałów dla klienta.

### Fixed (spójność paczki)
- Dwa dokumenty (`INSTRUKCJA-KLIENTA.md`, `RAPORT-A11Y-WCAG.md`) deklarowały wersję 1.0.0 mimo
  wydania 1.0.1 — ujednolicone do wersji wydania.
- Zrzut ekranu potwierdzenia e-mail pokazywał tymczasowy adres środowiska demonstracyjnego —
  przegenerowany na neutralny.

### Changed (skrypt pakujący — naprawa wzorca, nie objawu)
- `build/pakuj-dla-klienta.sh` kontroluje teraz zgodność wersji także w TREŚCI dokumentów
  (wcześniej tylko w nagłówkach wtyczek i `readme.txt` — stąd rozjazd wersji przeszedł niezauważony).
- Wykrywanie śladów wewnętrznych rozszerzone o adresy tuneli demonstracyjnych.

## [1.0.1] - 2026-07-28

Wydanie po przeglądzie na **żywym systemie** — każda pozycja niżej została złapana przez przejście
ścieżki klienta i pracownika w przeglądarce, nie przez czytanie kodu.

### Fixed (gwarancja — czwarty status naprawdę działa)
- **Dokument zakupu i data zakupu są wreszcie porównywane z rejestrem.** Zgłoszenie z cudzym
  numerem seryjnym i zmyśloną fakturą dostawało status **„gwarancja aktywna"**, bo moduł zgłoszeń
  pytał rejestr o gwarancję, ale nie przekazywał mu tego, co wpisał klient. Czwarty status
  z zamówienia („wymagana weryfikacja") był przez to **nieosiągalny**. Teraz niezgodność dokumentu
  albo daty oznacza sprawę do ręcznego sprawdzenia.
- **Karta sprawy pokazywała inny status, niż sprawa ma zapisany.** Sprawa z niezgodną fakturą
  miała w bazie „wymagana weryfikacja", a pracownik widział zielone „aktywna" — karta czytała
  bieżący stan produktu w rejestrze zamiast decyzji z chwili zgłoszenia. Pod plakietką jest teraz
  **powód**: „Niezgodne z rejestrem: dokument zakupu. Sprawdź dokument u klienta przed decyzją."
- **Ten sam status nazywał się różnie na dwóch ekranach** („do weryfikacji" na karcie sprawy,
  „wymagana weryfikacja" w rejestrze) — czytało się to jak dwa różne stany.

### Added (formularz zgłoszenia)
- **Załącznik zależny od kategorii produktu** (wymóg z zamówienia, wcześniej niedomknięty): dla
  **AGD drobnego** i **elektronarzędzi** trzeba dołączyć zdjęcie tabliczki znamionowej — bez niego
  serwis nie ustali modelu ani mocy. Audio i „inne" bez zmian. Wymóg spełnia wyłącznie plik, który
  **przejdzie kontrolę** — zdjęcie za duże albo w złym formacie nie „zalicza" go po cichu. Regułę
  można zmienić bez ruszania kodu (filtr `mp_intake_category_attachments`).

### Fixed (praca z systemem)
- **Kategoria wracała pusta po każdym błędzie formularza** — klient poprawiał jedno pole
  i dostawał formularz o innym kształcie niż wysłał (znikały pola kategorii).
- **Lista „Przydziel do" pokazywała osoby, których nie da się wybrać.** Wybranie koordynatora
  kończyło się zawsze komunikatem „Nie udało się przydzielić sprawy." bez wyjaśnienia. Teraz lista
  zawiera wyłącznie pracowników serwisu, a komunikat mówi powód.
- **Komunikat o zbyt dużym pliku radził „spróbuj ponownie"**, choć druga próba też się nie udawała.
  Teraz podaje limit **obowiązujący na tym serwerze** (mniejszy z: limit wtyczki i limit hostingu).
- **Uszkodzone zdjęcie zostawiało ostrzeżenia PHP w dzienniku strony.** Plik ucięty przy wysyłce
  przechodził kontrolę typu, ale nie dawał się odczytać przy usuwaniu danych EXIF — wtyczka radziła
  sobie z tym poprawnie, tylko po drodze wpisywała do `debug.log` trzy ostrzeżenia ze swoją nazwą.
  Teraz dziennik zostaje czysty, zgodnie z obietnicą z `PRZECZYTAJ-MNIE`.

### Changed (dokumentacja dla klienta)
- **Polityka kopii i cofania zmian w bazie trafia do paczki** (`MIGRATION_POLICY.md`), a kopia bazy
  przed instalacją jest **krokiem pierwszym** w `PRZECZYTAJ-MNIE` i w instrukcji wdrożenia.
- **Ryzyko za pośrednikiem (Cloudflare/nginx) opisane po polsku** w instrukcji — wcześniej wisiało
  tylko po angielsku w pliku technicznym wewnątrz wtyczki. Wszystkie zgłoszenia wyglądają wtedy jak
  z jednego adresu IP, więc ochrona przed spamem potrafi zablokować prawdziwych klientów.
- **Instrukcja administratora mówi prawdę o odinstalowaniu.** Obiecywała skasowanie tabel i kont
  klientów; kod świadomie ich **nie kasuje** (żeby przypadkowe kliknięcie nie skasowało firmie
  danych). Doszło ostrzeżenie: narzędzie RODO znika razem z wtyczką, więc dane trzeba usunąć PRZED.
- **Czwarty status gwarancji opisany** w instrukcji wdrożenia oraz w instrukcjach pracownika
  i koordynatora — co znaczy i co z taką sprawą zrobić. Wyjątek gwarancyjny przypisany właściwej
  roli: zatwierdza go **administrator systemu**, nie koordynator.
- **Wszystkie 21 zrzutów ekranu odświeżone.** Dwa różne podpisy pokazywały wcześniej ten sam
  obrazek, a zdjęcie „skrzynki mailowej" przedstawiało narzędzie testowe zamiast wiadomości.

## [1.0.0] - 2026-07-27

### Security (panel klienta — nieodwracalna akcja z potwierdzeniem)
- **Usunięcie danych osobowych wymaga teraz dwóch świadomych kliknięć.** Przycisk „Wycofaj zgodę
  i usuń moje dane" wysyłał formularz od razu: jedno kliknięcie wycofywało zgodę na **wszystkich**
  sprawach i uruchamiało usuwanie — a przycisk sąsiadował z niewinnym „Zapisz dane". Na telefonie
  pudło kciukiem kończyło się nieodwracalną utratą danych. Teraz pierwsze kliknięcie prowadzi na
  ekran, który mówi wprost **co zniknie** (imię, telefon, e-mail), **co zostaje** (historia zdarzeń
  i statystyki, bez danych identyfikujących) i że operacji **nie da się cofnąć**; dopiero przycisk
  na tym ekranie ją wykonuje — z osobnym nonce. Ten sam wzorzec, co przy potwierdzaniu zgłoszenia
  i logowaniu linkiem z maila.
- **Blok RODO przeniesiony pod listę spraw.** Rozdzielał dane kontaktowe od zgłoszeń, przez co
  klient wchodzący sprawdzić status naprawy w pierwszej kolejności widział czerwony przycisk
  kasowania konta.

### Changed (sprawdzenie na najnowszym WordPressie)
- **`Tested up to: 7.0`** we wszystkich trzech wtyczkach — paczka przeszła **instalację od zera na
  WordPressie 7.0.2** (PHP 8.2, MySQL 8): ścieżka klienta 19/0, wgranie wtyczki przez panel 6/0,
  zero PHP notice z naszego kodu. Wcześniej deklarowaliśmy 6.9, a oficjalny Plugin Check miał
  **wyciszone** ostrzeżenie o nieaktualnym nagłówku — wyciszenie zdjęte, nagłówek pilnuje się sam.
  Harness `testy/paczka-od-zera` przyjmuje teraz wersję WP przez `MP_WP_OBRAZ`, więc obie
  kombinacje (minimum 6.9/PHP 8.1 i najnowsza 7.0/PHP 8.2) da się powtórzyć jednym poleceniem.

### Fixed (poprawki z przeglądu ekranów przed wydaniem)
- **Zwrot przestał wyglądać na puste zgłoszenie.** Kolumna „Czego dotyczy" na liście spraw czytała
  wyłącznie opis usterki, a formularz zwrotu zbiera **powód zwrotu** — więc każdy zwrot pokazywał
  koordynatorowi „— bez opisu", mimo że klient napisał, dlaczego oddaje produkt. Teraz kolumna bierze
  opis usterki, a gdy go nie ma — powód zwrotu (pierwszeństwo opisu bez zmian).
- **Koniec surowego `CASE_CREATED` w historii sprawy.** Mapa etykiet nie miała wpisu dla zdarzenia
  narodzin sprawy, więc **każda karta** zaczynała się technicznym kodem w otoczeniu polskich wpisów.
  Uzupełniono komplet typów z `CaseEvents` (zgody RODO, usunięcie danych, przypomnienia i eskalacja SLA,
  nieudana wysyłka e-maila).
- **Priorytet po polsku** — karta sprawy pokazywała wartość z bazy (`normal`) zamiast „normalny".
- Dokumentacja klienta: jawne ostrzeżenie, że **bazę produktów trzeba wgrać przed udostępnieniem
  formularza** — powiązanie sprawy z produktem powstaje w chwili przyjęcia i nie jest uzupełniane wstecz.

**Pierwsze wydanie dla klienta.** Kompletny system obsługi zgłoszeń serwisowych i reklamacyjnych:
przyjmowanie zgłoszeń z weryfikacją mailową i kontem klienta bez hasła, rejestr produktów
i gwarancji z importem CSV, automatyczny przydział spraw, pilnowanie terminów SLA z przypomnieniami
i eskalacją, raporty. Poniżej pełna lista zmian od wersji 0.5.0.

### Added
- Registry (B) — **przykładowy plik importu w paczce + opis kolumn na ekranie.** Wtyczka wozi
  `przyklady/przyklad-import-produktow.csv` (8 wierszy pokazujących WSZYSTKIE obsługiwane kolumny, oba formaty
  daty, kategorię slugiem i etykietą, wiersz minimalny „tylko serial", jedną gwarancję już wygasłą), a ekran
  importu linkuje do niego („Pobierz przykładowy plik CSV"). Ekran wymienia teraz też **kolumny opcjonalne**
  (dotąd tylko wymaganą `serial`), formaty dat, listę kategorii **czytaną z `Categories::slugs()`** (nie
  przepisaną ręcznie — nie może się rozjechać) oraz jawnie mówi, że import DODAJE produkty i nie nadpisuje
  duplikatu serialu. Test-strażnik `test_dolaczony_przyklad_csv_importuje_sie_bez_bledow` przepuszcza dołączony
  plik przez realny parser — przykład nie może cicho przestać się importować.

### Changed
- **Numer sprawy ma format ze specyfikacji: `SRV/RRRR/NNNN` (cztery cyfry).** Dotąd kod nadawał
  pięć cyfr (`SRV/2026/00001`), mimo że kartka zamawiającego mówi `SRV/RRRR/NNNN`. Rozjazd
  utrwalił się, bo wcześniej „poprawiono literówkę" **w dokumentacji, dopasowując ją do kodu**
  zamiast odwrotnie — a komentarz w kodzie twierdził, że pięć cyfr to „spec klienta". Wyszło
  w audycie odbiorczym czytającym surową specyfikację. Po zmianie: pierwsza sprawa roku to
  `SRV/2026/0001`; po przekroczeniu 9999 spraw numer rośnie naturalnie do pięciu cyfr, więc
  licznik się nie zapętli ani nie zdubluje.

### Fixed
- **Poczta: awaria wysyłki przestała być niewidoczna (audyt 27.07).** Cztery miejsca w Intake
  (magic-link, ponowna wysyłka, potwierdzenie z numerem SRV, link logowania) ignorowały wynik
  `wp_mail()`. Gdy hosting odmawiał wysyłki, klient nie dostawał linku, formularz i tak pokazywał
  „sprawdź skrzynkę", a w bazie **nie zostawał żaden ślad** — nikt nie odkrywał, czemu zgłoszenia
  przestały się potwierdzać. Poprawny wzorzec istniał obok, w Automatorze. Teraz: jedno gardło
  wysyłki, zdarzenie `MAIL_FAILED` na osi sprawy, alert w Narzędzia → Stan witryny (gaśnie po
  pierwszej udanej wysyłce) i nowy test diagnostyczny „Poczta NIE WYCHODZI" z instrukcją naprawy.
- **Sprawa potwierdzona przy wyłączonym Automatorze nie zostaje sierotą (audyt 27.07).** Naprawa
  sierot z #1 rozpoznawała je po BRAKU zdarzenia narodzin — więc nie widziała przypadku, gdy Intake
  zapisał wszystko poprawnie, tylko Automator był wyłączony i nikt akcji nie usłyszał. Taka sprawa
  nigdy nie dostawała przydziału ani terminu. Sweep porównuje teraz swój stan z listą spraw
  (kontrakt `mp_cases_verified_ids` — same ID, zero danych osobowych) i doszywa różnicę.
- **Kontrakt `mp_cases_data_erased` ożył.** Sygnał był opisany w API-KONTRAKT.md, OWNERSHIP.md,
  EVENT_MODEL.md i na diagramie architektury, Rejestr miał gotowego słuchacza — a **nikt go nigdy
  nie emitował**. Po odinstalowaniu Intake w pozostałych wtyczkach zostawały wiersze wiszące na
  nieistniejących sprawach. Uninstall emituje sygnał, Automator dostał brakującego słuchacza
  (czyści terminy i checklisty; rejestr operacji zostaje jako historia).
- **Sweep SLA nie zaleje hostingu.** Paczki ograniczały liczbę spraw, nie maili: do 500 wiadomości
  sekwencyjnie w jednym żądaniu PHP (typowy hosting przepuszcza 200–500/godzinę). Dodany budżet
  120 maili na przebieg (filtr `mp_sla_mail_budget`); reszta czeka na kolejny przebieg z nietkniętym
  markerem, a przerwanie jest jawnie zapisane w rejestrze.
- **„Przelicz SLA" nie wywróci się na dużej bazie.** Zapytanie szło bez limitu, a potem pętla robiła
  zapytanie i UPDATE na każdy wiersz — przy 15 tys. spraw ~30 tys. zapytań w jednym żądaniu. Teraz
  paczki po 200 z dokańczaniem w tle (hak sprzątany przy deaktywacji i odinstalowaniu).
- **RODO: porzucone zgłoszenia znikają razem z danymi.** Kto wypełnił formularz i nie kliknął linku,
  zostawiał sprawę wraz z e-mailem i telefonem **na zawsze** (okno potwierdzenia to 72 h, więc taka
  sprawa i tak nie może ruszyć). Dzienny cron kasuje porzucone starsze niż 30 dni razem z plikami
  załączników; próg zmienia filtr `mp_intake_pending_retention_days`.
- **Zamknięta sprawa nie przyjmuje już przydziału ani zmiany pilności.** Bramka terminalna chroniła
  wyłącznie kolumnę statusu — przydział zamkniętej sprawy wysyłał maila do pracownika i dopisywał
  zdarzenie na jej osi. Do pracy sprawa wraca przez wznowienie, nie bocznymi drzwiami.
- **Formularz publiczny nie wywali się na hostingu bez `mbstring`.** Walidator używał gołego
  `mb_strlen()` — brak rozszerzenia oznaczał błąd krytyczny na każdym zgłoszeniu, a nie degradację.
- **Polska odmiana liczb w komunikatach.** Rejestr pokazywał „Produkt ma 1 aktywnych spraw";
  formy dobierane są teraz wg reguł języka (z wyjątkiem 12–14).
- **Panel: teksty i czytelność (audyt ekranów 27.07).** Diagnostyka odsyłała do edycji reguły w
  panelu, który jest tylko do odczytu — teraz podaje prawdziwą drogę (rola „Pracownik serwisu MP"
  w Użytkownikach). Rejestr zdarzeń mówi po polsku („Brak pasującej reguły przydziału" zamiast
  `ASSIGNMENT_UNMATCHED`), pokazuje numer sprawy zamiast wewnętrznego ID i czas lokalny zamiast UTC.
  Pole e-mail przy ponownej wysyłce dostało nazwę dla czytników ekranu, a tekst pomocniczy
  „nieprzydzielona" — kontrast zgodny z WCAG AA.
- **Teksty dodawane JavaScriptem przechodzą przez tłumaczenia** (wiersze konfiguracji dodawane
  przyciskiem miały etykiety i opisy dla czytników ekranu wpisane na sztywno).
- Intake (C) — **nagłówki bezpieczeństwa docierały TYLKO na auto-stronę wtyczki.** Warunek brzmiał
  „jeśli to strona o ID zapisanym w opcji" — a dokumentowany sposób użycia to **wstawienie shortcode'u
  na własną podstronę**. Takie strony (czyli te, które realnie robi klient) szły **bez żadnego nagłówka**:
  zmierzone na żywym WP — auto-strona miała `Cache-Control: no-store`, ręcznie założona `/moje-sprawy/`
  nie miała nic. Teraz decyduje obecność shortcode'u (`PageDetect::is_plugin_page`), a zestawy są
  filtrowalne (`mp_intake_security_headers`) — strona klienta może je dostosować albo wyłączyć.
  Formularz dostaje `X-Frame-Options`, `X-Content-Type-Options`, `CSP: frame-ancestors 'self'`,
  `Referrer-Policy`. **Panel klienta dodatkowo `X-Robots-Tag: noindex, nofollow`, `Cache-Control:
  no-store` i `Referrer-Policy: no-referrer`** — pokazuje dane osobowe, więc nie ma prawa trafić do
  wyszukiwarki ani zostać w cache; plus `<meta name="robots" noindex>` jako pas zapasowy, gdy hosting
  utnie nagłówki. Strony BEZ naszego shortcode'u zostają nietknięte (sprawdzane osobną asercją: zero
  ingerencji poza własnym terenem). Regresję pilnuje `testy/e2e/c3-front.sh` §8.
- Intake (C) — **panel klienta: 20 inline-style'i usuniętych, własne odstępy zamiast liczenia na motyw.**
  Objaw: na motywie, który zeruje marginesy `<p>` (a robi tak wiele motywów), przycisk „Wyślij"/„Zapisz dane"
  **przyklejał się do pola** — 0 px odstępu; na motywie domyślnym WP wychodziło 22 px, czyli poprawnie tylko
  przez przypadek. Przyczyna: `Front/AccountPage.php` budował formularze `<br>`-ami i inline-style'ami, które
  **przebijały własny CSS wtyczki** (pola dostawały `padding:.5rem` zamiast zaprojektowanego `.7rem/.85rem`,
  przycisk RODO czerwoną łatę zamiast obrysu). Teraz: klasy `mp-account__field` / `__actions` / `__meta` /
  `__message*` / `__note-closed` + reguły w `intake.css`, a zaszyte kolory (`#555`, `#666`, `#2e7d32`, `#a33`,
  `#fff`, `#f6f6f6`) zamienione na zmienne (`--mp-muted`, `--mp-ok` — nowa, `--mp-err`, `--mp-soft-bg`).
  Skutek: **ten sam wygląd na dowolnym motywie** i możliwość dopasowania kolorów bez tykania kodu wtyczki.
  Zmierzone po naprawie: odstęp pole→przycisk **18 px na OKTANie i 18 px na Twenty Twenty-Five**, kontrast
  przycisku „Wycofaj zgodę" **5.12:1** (AA). Zero zmian logiki i treści. Honeypot w `FormRenderer` zostaje
  inline świadomie — gdyby arkusz się nie wczytał, pułapka na boty stałaby się widoczna dla ludzi.
- Registry (B) + Automator (D) — **`str_getcsv`/`fputcsv` bez jawnego `$escape` = deprecated na PHP 8.4+.**
  Import 10 tys. wierszy potrafił wygenerować 10 tys. wpisów „deprecated" przy `WP_DEBUG` (łamie kontrakt
  dirty-env „zero notice z naszego kodu"), a **domyślna wartość ma się w przyszłym PHP zmienić** — czyli
  parsowanie zmieniłoby się samo. Teraz `$escape` podawany jawnie jako PUSTY = semantyka RFC-4180, taka jaką
  pisze Excel (cudzysłów podwajany, backslash literalny). Efekt uboczny naprawiony przy okazji: model typu
  `Kabel 3\4` i ścieżka `D:\dane\` parsują się poprawnie (z dotychczasowym domyślnym `\` psuły podział pola).
  Zabezpieczone testem `test_backslash_jest_zwyklym_znakiem`.

### Changed
- Admin — **kolorowe plakietki statusów w listach personelu (czytelność).** Intake (C): status sprawy
  (nowe=niebieski, w naprawie=pomarańczowy, zamknięte=szary…). Registry (B): status gwarancji
  (aktywna=zielony, wygasła=czerwony, weryfikacja=żółty, brak danych=szary) — reuse istniejącego
  `admin-registry.css`/`mp-badge`. **Bonus fix:** mapa etykiet statusu gwarancji miała klucze angielskie,
  a `WarrantyStatus::compute` zwraca polskie — lista pokazywała surowe „wygasla"/„brak_danych"; teraz
  poprawne „wygasła"/„brak danych". Styl natywny WP-admin, zero zmian logiki.
- Intake (C) — **spójny wygląd WSZYSTKICH ekranów klienta.** Strony samodzielne (weryfikacja „Potwierdź
  zgłoszenie", potwierdzenie/błędy, logowanie „Zaloguj się", „Link nieaktualny") stały poza motywem z gołym
  systemowym stylem — teraz wspólna skorupa `Front\Landing` (jedno źródło stylu: karta na jasnym tle, akcent
  `--mp-accent` jak formularz). Bezpieczeństwo bez zmian (no-store/no-referrer/nosniff/SAMEORIGIN/noindex).
  Karty spraw / kontakt / prywatność w panelu klienta dostały wygląd z `intake.css` (ładniejsze karty,
  subtelny warm-akcent na „wycofanie zgody"). Zero zmian logiki.
  <!-- SPROSTOWANIE 2026-07-26: pierwotnie stało tu „Usunięte inline-style'e z panelu klienta" — to było
       NIEPRAWDĄ, `AccountPage.php` miał ich dalej 20. Faktyczne usunięcie: wpis w „Fixed" niżej. -->

- Intake (C) — **dopracowany wygląd frontu (formularz zgłoszenia + panel klienta).** Dotąd CSS był surowy
  („techniczne" pola). Teraz profesjonalny, ale **neutralny motywowo** (wąski zakres `.mp-intake`/`.mp-account`,
  dziedziczy font motywu): pola z zaokrągleniem i wyraźnym focus, **własny chevron selecta**, **własny checkbox
  RODO**, przyciski-pigułki, sprawy w panelu jako karty, czytelne błędy/notki. Akcent przez zmienną
  **`--mp-accent`** (domyślnie ciemny neutral — ładnie na każdym motywie klienta; strona/motyw może nadpisać).
  Zero zmian logiki. Dostępność: `focus-visible`, kontrast AA.

### Fixed
- Intake (C) — **rate-limit zgłoszeń liczy tylko UDANE próby** (#D5). Dotąd `RateLimit::check()`
  inkrementował liczniki e-mail/serial PRZED walidacją (zgoda/serial/data), więc klient z literówką
  wyczerpywał limit 3/dobę i nie mógł złożyć reklamacji. Teraz `check()` **tylko czyta** liczniki
  e-mail/serial (blokada gdy już wyczerpane), a inkrement (`record_submission`) następuje dopiero po
  utworzeniu sprawy. Limit **IP (anty-flood)** dalej liczy każdą próbę atomowo. Anti-spam zachowany
  (3 udane zgłoszenia → 4. blok). Test `c6c`: 3 nieudane (bez zgody) nie zjadają limitu, ważne przechodzi.
- Registry (B) — **limit importu 20 MB → 8 MB (ochrona przed OOM)** (#D10). `create_job_from_file` wczytuje
  cały plik do pamięci (`file_get_contents` + `to_utf8` + `preg_split` w tablicę), co przy ~20 MB mogło
  przekroczyć domyślny `memory_limit` 128 MB. Limit obniżony do 8 MB (bezpieczny zapas); większe importy
  klient dzieli na części. Właściwe przetwarzanie (`process_batch`) i tak streamuje przez `fgetcsv`.
  Test `ImportEndpointsTest::test_import_limit_is_memory_safe` (strażnik przed przyszłym bumpem).
- Intake (C) — **honeypot czasowy: brak/za stary `mp_ts` też odrzucany** (#D11). Wcześniej pominięcie pola
  `mp_ts` omijało pułapkę czasu (warunek `$started > 0`) — bot mógł nie wysyłać znacznika. Teraz brak,
  zbyt szybkie (<2 s) i zbyt stare (>3 h, replay) znaczniki wpadają w cichy odrzut. Warstwa bonusowa —
  realna ochrona to nonce + rate-limit. Test `c3-front`: submit bez `mp_ts` → zero spraw.
- Intake (C) — **załączniki WebP bez `imagewebp()` nie są kaleczone** (#D8). Przy GD bez obsługi zapisu
  WebP (i bez Imagick) strip metadanych zapisywał JPEG do pliku z mime `image/webp` w bazie → `serve()`
  dawał błędny `Content-Type` (plik się nie otwierał). Teraz taki plik zostaje oryginalny (spójny).
- Intake (C) — **admin notice gdy brak biblioteki obrazów** (#D9). Bez Imagick i bez GD metadane EXIF/GPS
  ze zdjęć nie były usuwane po cichu — teraz admin dostaje ostrzeżenie (`Attachments::has_image_library`).
- Intake (C) — **licznik SRV i rate-limit czytają `$wpdb->insert_id`** zamiast osobnego `SELECT
  LAST_INSERT_ID()` (#D7, tylko ścieżki `INSERT … ON DUPLICATE KEY UPDATE` — zweryfikowane, że insert_id
  się tam odświeża). Bezpieczniejsze na HyperDB (bare SELECT mógłby trafić na replikę) + jedno zapytanie
  mniej. Round-robin automatora (plain UPDATE) świadomie zostaje przy `SELECT LAST_INSERT_ID()` — tam
  `insert_id` się NIE odświeża (potwierdzone empirycznie).
- Registry (B) — **pliki importu CSV kasowane (retencja RODO + dysk)** (poprawka #D2 z audytu kod-based).
  Znormalizowany plik importu (`uploads/mp-imports/{uuid}.csv`, PII: serial/faktura/nazwisko) nigdy nie
  był usuwany — `ImportJobs::finish()` robił tylko UPDATE statusu, a plugin B nie miał żadnego crona
  (`CRON_HOOKS` puste). Pliki rosły bez końca (art. 5 ust. 1 lit. e). Teraz `finish()` **kasuje źródłowy
  CSV** po zaksięgowaniu (raport błędów `.bledy.csv` ZOSTAJE — admin pobiera przez `handle_report`), a nowy
  **dobowy cron `mp_registry_imports_sweep`** (`Importer::sweep_import_files`) sprząta sieroty starsze niż
  24 h (joby przerwane w połowie + stare raporty), chroniąc guardy katalogu. Test `import-dod`: po `finish`
  źródłowy CSV zniknął, raport przetrwał, sweep skasował sierotę >24 h.
- Intake (C) — **rate-limit atomowy (odporny na współbieżność)** (poprawka #D3 z audytu kod-based).
  Liczniki rate-limitu (formularz zgłoszeń i żądania magic-linku) używały transientowego
  read-modify-write (`get_transient` + `set_transient`) — pod równoległymi żądaniami wszystkie czytały
  tę samą wartość i nadpisywały +1, przez co **limit dało się obejść** (repro: 20 równoległych → licznik
  spadał do ~2, zgubione ~18 inkrementów). Zastąpione **atomową tabelą `mp_rate_counters`** (migracja v2)
  z jedną kwerendą `INSERT … ON DUPLICATE KEY UPDATE … LAST_INSERT_ID` (wzorzec `SrvCounter`, okno
  przesuwane); wygasłe wiersze sprząta cron retencji (`cleanup_expired`). Test `c17`: 20 równoległych żądań
  → licznik dokładnie 20 (zero zgubionych) + reset okna. Dedup pozostaje transientem (bez zmian).
- Intake (C) — **załączniki: pominięte pliki są MELDOWANE klientowi** (poprawka #D4 z audytu kod-based).
  Dotąd `SubmissionHandler::handle_submit()` wywoływał `Attachments::store_for_case()` i **ignorował wynik**
  (`{stored, errors}`) — klient, którego pliki odpadły (zły typ, za duży, limit 5/sprawę, brak miejsca),
  widział neutralny „sukces", a serwis dostawał reklamację **bez dowodów**. Teraz wynik jest przechwytywany,
  a gotowe (istniejące server-side) teksty błędów doklejane do komunikatu PRG. Anty-enumeracja zachowana
  (błędy dotyczą plików, które klient sam wgrał — nie zdradzają istnienia konta). Test `c4-zalaczniki`:
  realny POST z plikiem złego typu → sprawa powstaje, plik odrzucony, notice niesie tekst błędu.
- Intake (C) — **RODO art. 17: eraser USUWA konto WP klienta** (poprawka #D1 z audytu kod-based).
  Dotąd anonimizacja tylko odpinała konto (`customers.wp_user_id = NULL`), a rekord `wp_users` z realnym
  e-mailem/loginem/nazwiskiem zostawał bezterminowo — mimo że panel raportował „dane zanonimizowane"
  (naruszenie art. 17 + art. 5 ust. 1 lit. a). Teraz `Privacy::erase()` łapie `wp_user_id` **przed**
  anonimizacją i woła nową `Accounts::purge_client_account()`, która **usuwa konto** (unieważnia sesje +
  `wp_delete_user`, e-mail/login/nazwisko znikają z `wp_users`). Kasuje **wyłącznie czyste konto klienta**
  (`mp_client`); konta personelu/admina podpięte po e-mailu (EDGE `ensure_for_customer`) oraz konta wciąż
  spięte z innym nieanonimizowanym klientem są nietknięte. Test `c5-rodo`: asercja skasowania z `wp_users`
  + asercja ochrony konta personelu (21/0).

### Added
- Intake (C) — **rate-limit żądań magic-linku (logowanie)** (`RateLimit::check_login`, osobne liczniki od
  formularza zgłoszeń): domyślnie 5 żądań/15 min na IP + 5/godz. na e-mail. Chroni skrzynki klientów przed
  zalewem linkami i endpoint przed nadużyciem (OWASP anti-automation — hardening poza kartką, standard
  bezpieczeństwa). Komunikat neutralny (zero enumeracji kont), progi nadpisywalne filtrem
  `mp_intake_login_rate_limits`, źródło IP przez `mp_intake_client_ip`. Test `c17-rate-limit-login` (5/5).

### Changed
- Automator (D) — **konfiguracja checklist i szablonów: surowy JSON → formularz** (poprawka #2 z audytu:
  UX/profeska, poza kartką — kartka wymaga funkcji, nie sposobu konfiguracji). Panel „Automatyzacje MP"
  renderuje **builder per rodzaj sprawy** (pola klucz/etykieta[/treść] + „+ dodaj" / „×" usuń) zamiast
  wklejania JSON. **Kontrakt backendu NIETKNIĘTY** — JS składa te same dane do ukrytego pola `payload`,
  ten sam handler + walidacja (zero regresji: `d-p35` 20/0). Surowy JSON zostaje jako fallback w sekcji
  „Zaawansowane: edytuj jako JSON" (działa też bez JS). Testy: `c18-config-form-render` (14/0) + żywy test
  serializacji JS (Playwright: edycja+dodanie wiersza → poprawny JSON, 4 rodzaje).
- Wymagania środowiska doprecyzowane wg specyfikacji klienta: `Requires at least` obniżone **6.9 → 6.0**
  (kartka: „WordPress 6.x" = 6.0 i nowsze; kod używa tylko stabilnych API). Dodana sekcja **Requirements**
  w readme (WordPress 6.x, PHP 8.1+, MySQL 8.0+/MariaDB 10.6+, **HTTPS** — passwordless login + dane klienta,
  **WP-Cron** — SLA/przypomnienia/eskalacje, importy, retencja). `Tested up to` bez zmian (6.9).
  Poprawka literówki formatu numeru w readme intake: `SRV/YYYY/NNNNN` (5 cyfr, spójnie z v0.5.0).

### Added
- Automator (D) — **przebieg krok 5: silnik reguł NADAJE priorytet.** Nowa akcja reguły
  `set_priority` (na `case_created`) ustawia priorytet sprawy wg warunku (np. kategoria/rodzaj)
  przez kontrakt C `mp_case_set_priority` (low/normal/high). Priorytet nadawany PRZED wierszem SLA
  (RuleEngine hook 10 < Sla 20) → pierwszy termin liczy się z nadanego priorytetu (high = krótszy).
  Idempotentny (ten sam priorytet = bez zdarzenia), waliduje (INVALID_PRIORITY), loguje `PRIORITY_CHANGED`.
  Domyślnie brak reguły → priorytet `normal` (politykę konfiguruje admin, jak pulę auto-przydziału).
  Test `d-p31-priorytet`.
- Automator (D) — **przebieg krok 8: raport końcowy przy zamknięciu.** Przy przejściu sprawy w status
  `zamknięte` D składa podsumowanie (numer SRV, rodzaj, data zamknięcia, czas obsługi, podziękowanie —
  klient-friendly, NO-PII) i dopisuje **wpis systemowy** przez `mp_case_add_system_message` (widoczny w
  panelu klienta i na karcie). Zdarzenie `CLOSING_REPORT_GENERATED` w rejestrze D. Zmiana nie-końcowa
  nie generuje raportu. Zachowanie strukturalne (gwarancja, nie reguła). Test `d-raport-koncowy`.

## [0.5.0] - 2026-07-24

Checkpoint „3 pluginy spec-complete" (pre-release). Weryfikacja specyfikacji klienta 1:1
dla wszystkich 3 pluginów (6/6 każdy) + karta pracy personelu, drobne poprawki i domknięcia
z audytu. Projekt NADAL w rozwoju — kolejne poprawki przed v1.0.0 (oddanie).

### Added
- Automator (D): **powiadomienie PRACOWNIKA przy zmianie statusu** (spec „powiadomienia dla klienta
  i pracownika po każdej ważnej zmianie") — dotąd zmiana statusu mailowała tylko klienta. Nowa domyślna
  reguła `status_changed → agent` (szablon `status_changed_staff`) informuje **przypisanego** pracownika.
  **SELF-SKIP:** gdy status zmienił SAM przypisany pracownik, nie dostaje maila o własnej akcji
  (`recipient_ref=agent_self`); zmiana przez koordynatora/innego → mail dochodzi. Seed **idempotentny per
  `system_key`** (bump `SEED_VERSION`→2 DOSIEWA nową regułę bez duplikowania na upgrade — bez reaktywacji).
  Testy `d-p33e-mail-pracownik` + idempotencja w `d-seed-regul`.
- Karta sprawy (C): **sekcja „Produkt i gwarancja"** — kontrakt B->C `mp_product_details` (Registry
  wystawia detale produktu po ID: model, nr seryjny, dokument+data zakupu, gwarancja do, **status
  gwarancji liczony z daty** aktywna/wygasła/brak-danych, flaga zarchiwizowany). Karta nie siega w
  tabele B (luzne wiazanie). `mp_case_get_context` wystawia teraz `product_registry_id` (bylo czytane
  wewnetrznie, nie zwracane). Degraduje gdy modul B nieaktywny / sprawa bez produktu. Test `b-product-details`.
- Intake (C): **ekran pracy personelu „MP: Sprawy" — karta sprawy (kartka krok 7)**. Domkniecie luki #1
  audytu adwersaryjnego (2026-07-24): personel nie mial GDZIE obslugiwac potwierdzonej sprawy. Teraz:
  **lista spraw** (`WP_List_Table`, kolumny nr/klient/rodzaj/status/przydzielony/termin-SLA/utworzono,
  filtry status/rodzaj/przydzielony + „moje"/„nieprzydzielone", wyszukiwarka po nr/kliencie, sortowanie,
  paginacja; model B — caly personel widzi wszystkie zweryfikowane sprawy) oraz **karta sprawy**
  (opis zgloszenia z `form_data` · dane klienta · zalaczniki · wiadomosci · **oS czasu zdarzen** ·
  **checklista interaktywna**). **Akcje personelu** (admin-post, KAZDA z capability + nonce): zmiana
  statusu (optimistic-lock `expected_status` => `STATUS_CONFLICT`, powod przy odrzuceniu), odpowiedz do
  klienta (szablony D wypelniaja pole), przydzial — **TYLKO koordynator/administrator** (pracownik `mp_agent`
  nie przydziela: 403). Kazda decyzja ląduje na osi (`case_events`) + maile P3.3. Nowe kontraktowe filtry
  **D->C** (`CaseCardApi`): `mp_case_checklist_state` / `mp_response_templates` / `mp_render_response_template`
  / `mp_case_deadline` (karta nie siega w tabele D). Nowe metody read C: `CaseRepo::query_for_staff` /
  `form_data_for_case`, `CaseEvents::for_case`. Testy e2e `c-case-card` (19) + `c-case-actions` (16, macierz
  capability+nonce). Zweryfikowane na zywo: klikacz admin + `mp_agent` (panel przydzialu ukryty pracownikowi).
- Registry (B): **kategoria produktu** (domkniecie kartki P1.2/P3.1 po stronie danych) — kolumna `category`
  (migracja v2 `maybe_upgrade`, BEZ reaktywacji; istniejace wiersze => `inne`), slownik 4 kategorii
  (audio / agd / elektronarzedzia / inne; konfigurowalny filtrem `mp_product_categories`), import CSV z kolumna
  `kategoria` (WSTECZNIE ZGODNY — stary CSV bez niej => `inne`; nieznana => `inne`, bez przerwania importu),
  oraz hak kontraktowy `mp_product_category` (Intake `get_context.kategoria` => os przydzialu w Automatorze).
  Test e2e `b-kategoria`. Przydzial wg kategorii udowodniony end-to-end (test `d-p31-kategoria`).
- Intake (C): **formularz P1.2 — pola wg kategorii produktu**. Dropdown kategorii na formularzu; dodatkowe pola per
  kategoria (sensowne domyslne + konfigurowalne filtrem `mp_intake_category_fields`); `fields_for($kind, $category)`
  ADDYTYWNIE (bez kategorii = pola rodzaju, ZERO regresji #15); zapis pol kategorii do `form_data`; walidacja serwera
  + JS-dynamika (pokazuje pola wg rodzaju ORAZ kategorii). Test e2e `c-kategoria-formularz`.
- Intake (C): **listener `mp_product_active_cases_count`** — domkniecie kartki l.50 (B5: „brak mozliwosci
  usuniecia produktu powiazanego z aktywna sprawa"). Registry (B) mial juz blokade (`Archive.php`) + akcje
  w adminie, ale brakowalo strony C odpowiadajacej liczba spraw => archiwizacja ODMAWIALA ZAWSZE (fail-closed
  bez listenera, nawet dla produktu bez spraw). Teraz Intake liczy sprawy NIE-TERMINALNE produktu
  (`CaseRepo::active_cases_count_for_product`); >0 => Registry odmawia z komunikatem, 0 => archiwizuje
  (soft-delete: `archived=1` + `deleted_at`). Test e2e `b5-usuwanie-produktu` (blok / OK / fail-closed).

### Fixed
- Automator (D): **cicha utrata konfiguracji przy błędnym JSON** (znalezisko audytu 24.07) — panel zapisywał
  config checklist/szablonów z surowego `<textarea>`; błędny JSON → `json_decode` null → zapis PUSTEGO
  configu bez ostrzeżenia. Teraz błędny JSON (składnia albo nie-obiekt) przy niepustej treści NIE nadpisuje
  (poprzednia konfiguracja zachowana) + komunikat błędu na panelu; puste pole = świadome wyczyszczenie.
  Dotyczy `ChecklistTemplates`/`ResponseTemplates`. Test `d-config-json-guard`.
- Automator (D): **rejestr zdarzeń zalewany `SWEEP_RUN`** (znalezisko audytu 24.07) — cron SLA co 5 min
  logował `SWEEP_RUN`, przez co zdarzenia biznesowe tonęły. Domyślny widok panelu ukrywa teraz `SWEEP_RUN`
  (`WHERE event_type <> 'SWEEP_RUN'`), a link „Pokaż techniczne" odsłania pełny log (toggle zachowany w paginacji).
- Registry (B): **brak auto-migracji przy AKTUALIZACJI** — `mp-warranty-registry` nie miał `maybe_upgrade`
  na `admin_init` (wzorzec obecny w Intake i Automator), więc update dodający migrację (v1→v2 kolumna
  `category`) NIE stosował jej bez deaktywacji+aktywacji → schemat zostawał stary → `SELECT category`
  sypał błędem DB. Dodano `Lifecycle::maybe_upgrade` (gated `Schema::LATEST`) + hook `admin_init` +
  `Schema::LATEST` — spójność 3 wtyczek. Regresja: `testy/e2e/registry-maybe-upgrade.sh` (migracja
  bez reaktywacji). Złapane audytem adwersaryjnym 2026-07-24.
- Automator (D): **flaky dedup maili `d-p33d`** — `MailDedup` kluczował po WYRENDEROWANYM body, a body niesie
  `{{data}}` (`wp_date('Y-m-d H:i')`, granica minuty). Dwie IDENTYCZNE notyfikacje sekundy od siebie na granicy
  minuty → różny body → różny hash → dedup gubił duplikat (~1/60 runów). Fix W PRZYCZYNIE: `MailTemplates::render`
  zwraca dodatkowo `dedup_key` = treść BEZ zmiennego `{{data}}` (numer/status/rodzaj podstawione, data pominięta);
  `RuleEngine` dedupuje po `dedup_key`, nie po `body`. Mail do wysłania dalej niesie prawdziwą datę. Asercja-strażnik
  w `d-p33d-dedup`.

- Intake (C): **kolumna „Sprawy" i wyszukiwarka po kliencie w Rejestrze** — Intake nie rejestrował listenerów
  kontraktowych `mp_case_count_by_product` i `mp_customer_find_products` → kolumna „Sprawy" pokazywała „moduł
  spraw nieaktywny" mimo aktywnego Intake, a wyszukiwarka po kliencie (kartka **P2.6**) była WYŁĄCZONA. Dodane
  `CaseRepo::case_count_by_product` (`{total,active,closed,rejected}`, unverified wykluczone) +
  `find_products_for_customer` (`{ids,truncated,limit}`) + rejestracja obu filtrów. Test `c-count-search-hooki`.
  Znalezione KLIKACZEM admina (bramka) — automaty testowały haki osobno, nie zintegrowany panel.

## [0.4.0] - 2026-07-23

Klocek D (Automator) kompletny: silnik reguł + auto-przydział, statusy, maile, SLA (1–4),
checklisty + szablony, eksport CSV, panel admina — spięte z Intake (C) i Registry (B)
kontraktem hooków. Plus szlif i naprawy Intake (C) z fazy pre-release.

### Fixed
- Automator (D): flaga #8 SLA (retroaktywność sweepa) — pierwszy przebieg po reaktywacji /
  instalacji nie zalewa lawiną: sprawy już po terminie dostają JEDNO powiadomienie (eskalacja),
  przypomnienie tłumione = marker `reminder_sent_at` zajęty BEZ maila i BEZ `mp_sla_notified`
  (zero `SLA_REMINDER_SENT` na osi C); przy masie po terminie — 1 zbiorczy digest. Test d-p34b/c.
- Intake (C): kontrast WCAG panelu klienta #13 (`AccountPage`) — kolory podniesione do ≥ 4.5:1.
- Intake (C): szlif frontu klienta (polerka, bez zmian logiki). (1) Pasek admina WP **ukryty** klientowi
  `mp_client` (filtr `show_admin_bar` + `Accounts::is_client_only`), personel/admin widzą go dalej.
  (2) Arkusz `assets/css/intake.css` (enqueue wersjonowany) — etykiety nad polami, pola pełnej szerokości,
  czytelne karty panelu (koniec „etykieta[pole]"). (3) CTA „Przejdź do panelu zgłoszeń" na stronie
  potwierdzenia (URL panelu dynamicznie z `AccountPage::url()`, nie hardkod). Test c16. Flaga #16.
- Intake (C): formularz zgłoszenia dynamiczny wg rodzaju po stronie klienta (kartka wymóg #1). Render
  UNII pól wszystkich rodzajów (każde pole raz, `data-mp-field`) — m.in. `return_reason` (zwrot) jest w
  DOM od razu, więc zwrot składa się za 1. razem (wcześniej pole renderowane dopiero PO błędzie). Nowy
  skrypt `assets/js/intake-form.js` (enqueue wersjonowany, config przez `wp_localize_script`) pokazuje/
  ukrywa pola i toggluje `required` przy zmianie „Rodzaj". Serwer pozostaje źródłem prawdy —
  `FormConfig::fields_for(kind)` waliduje na submit bez zmian (JS = progressive enhancement; no-JS też
  wyśle). Test c-form-dynamic + dowód w przeglądarce. Flaga #15.
- Intake (C): wyjątki gwarancyjne na osi zdarzeń sprawy — listener `mp_warranty_exception_changed`
  (B→C) zapisuje `EXCEPTION_APPLIED` (stan `active`) / `EXCEPTION_REVOKED` (stan `revoked`) do
  `wp_mp_case_events`; payload strukturalny `{exception_id}` (NO-PII, bez `reason`), `case_id=NULL`
  (wyjątek globalny) → no-op (EVENT_MODEL.md). Wcześniej decyzja gwarancyjna nie zostawiała śladu na
  osi czasu sprawy. Test c11 + blok-S S4. Flaga #11.
- Intake (C): rate-limit po REALNYM IP klienta — nowy filtr `mp_intake_client_ip`
  (`RateLimit::client_ip()`, domyślnie `REMOTE_ADDR`). Za reverse-proxy/Cloudflare wszyscy klienci
  mieli IP proxy = 1 adres → rate-limit blokował wszystkich; wdrożeniowiec podpina zaufane źródło IP
  (nota: SECURITY.md §7). Nie ufamy ślepo `X-Forwarded-For` (spoofowalny). Test c6c §4. Flaga #10.
- Intake (C): RODO — poprawny terminalny status „zamknięte" (był bez ogonka `zamkniete` w
  `TERMINAL_STATUSES` → `has_active_case()` nigdy nie widziała zamkniętej sprawy jako terminalnej →
  eraser odraczał anonimizację klienta w nieskończoność, łamiąc §4 kartki). Realny slug to `zamknięte`
  (z ę, jedyna droga zapisu = `change_status`). Testy c5-rodo/c6b/c6b2b przepięte na REALNĄ
  `change_status` (seed literówki maskował błąd — zielone kłamały). Flaga #14. (pre-release v0.3.0)

### Added
- Automator (D): schemat D — 4 tabele (`wp_mp_workflow_rules`, `wp_mp_case_sla`,
  `wp_mp_case_checklists`, `wp_mp_workflow_events` = rejestr operacji APPEND-ONLY, NO-PII);
  migracje bez reaktywacji (`maybe_upgrade`), uninstall opt-in kasuje wszystkie artefakty D
  i nic cudzego (kanarki + role współdzielone nietknięte). Test d1-schema + DoD D.
- Automator (D): P3.1 silnik reguł + auto-przydział round-robin — reguły STRUKTURALNE
  (trigger/warunek/akcja, zero eval), kursor RR per reguła, nasłuch `mp_case_created`;
  seed reguły domyślnej przydziału przy aktywacji (jednorazowo, skasowana nie wraca).
- Automator (D): P3.2 statusy własne D — provider `mp_registered_statuses` (rdzeń 7 + własne,
  guard długości sluga ≤20 = `VARCHAR(20)`), akcja `change_status` przez kontrakt C oraz
  **guard pętli reguł** (`RULE_LOOP_BLOCKED`, mutacja przy depth≥1 zablokowana, zero lawiny).
- Automator (D): P3.3 maile powiadomień — `Mailer` (bezpieczny egress: strip CRLF, sanityzacja
  odbiorcy, NO-PII w rejestrze), szablony `MailTemplates` z markerami, powiadomienia klient/
  pracownik po ważnej zmianie; notyfikacja przydziału (`mp_case_assigned` → mail agenta),
  reguły `message_added` (klient→agent, staff→klient, guard `from===to`), dedup-okno
  identycznych maili zdarzeniowych (best-effort, per typ).
- Automator (D): P3.4 SLA — księgowość `wp_mp_case_sla` (termin liczony od `status_changed_at`)
  + `SlaConfig` + notify send-then-claim (SLA-1); sweep cron 5-min (`GET_LOCK`, przypomnienia
  przed / eskalacje po terminie, SLA-2); resync po reaktywacji + digest bez lawiny
  (>próg = 1 zbiorczy mail do koordynatora, SLA-3); akcja admina „Przelicz SLA"
  (backend-handler-only, nieretroaktywność, audyt `SLA_RECALCULATED`, SLA-4).
- Automator (D): P3.5 checklisty per typ + szablony odpowiedzi (backend-handler-only) —
  checklisty konfigurowalne per rodzaj, **toggle przez hook `mp_case_checklist_authorize`**
  (własność/rolę egzekwuje C), stan w `wp_mp_case_checklists` (`step_label` zamrożony);
  szablony odpowiedzi per typ z markerami i WHITELIST markerów widoczną adminowi;
  konfiguracja przez `admin_post` (capability system-admin + nonce + audyt `CONFIG_CHANGED`).
- Automator (D): P3.6 eksport CSV spraw + zestawienia (backend-handler-only) — capability
  koordynator/system-admin + nonce + audyt `EXPORT_GENERATED`; **anti-formula-injection**
  (pola `=+-@`/TAB/CR → apostrof), nagłówki `text/csv`+`nosniff`+`Content-Disposition`,
  BOM UTF-8; dane WYŁĄCZNIE przez kontrakt `mp_cases_query` (minimalizacja PII — bez kontaktu);
  zestawienie: liczba per status, czas obsługi, rozkład powodów odrzuceń.
- Automator (D): panel admina D — menu `mp-automator` (widoczne koordynator/system-admin;
  klient/pracownik/anon nie widzą), spina handlery Przelicz SLA + Eksport CSV + konfigurację
  checklist/szablonów, listy read-only (reguły, statusy przez `mp_all_statuses`, rejestr
  zdarzeń paginowany), obrona warstwowa (capability na stronie ORAZ per-przycisk), a11y-lite.
- Kontrakt C↔D: funkcje kontraktowe spraw (jedyna droga D po dane/zapis C — D nigdy nie
  dotyka tabel C, pilnuje linter): `mp_case_get_context`, `mp_case_assign`,
  `mp_case_change_status` (optimistic-lock + STATE_MACHINE), `mp_cases_query` (paginowane
  chunk 500, respekt roli, pola zminimalizowane), `mp_case_checklist_authorize`
  (ownership + event `CHECKLIST_ITEM_TOGGLED`), `mp_all_statuses` (read-only lista statusów
  C→D, degrade gdy Intake OFF).
- Testy klocka D w CI: seria `d-*` (schemat, hooki, P3.1–P3.6), DoD D (uninstall zero-śladu +
  kanarki + tryb degraded C/B OFF + macierz uprawnień NEGATYWNA anon/subscriber/klient/agent),
  panel admina (widoczność per rola); odślepione niezmienniki BLOK-S (E2E/tabletop/bug-hunt/
  a11y) na P3.1/P3.2.
- Intake (C): zgody RODO + wiadomości + eraser/exporter (P1.5 + RODO) — `wp_mp_consents` z PEŁNYM
  TEKSTEM zgody zamrożonym przy zbieraniu (rozliczalność art. 7) + wycofanie self-service
  (`CONSENT_WITHDRAWN`, art. 7(3)); zgoda wymagana w formularzu, podpinana do klienta po weryfikacji
  (`CONSENT_RECORDED`); `wp_mp_messages` — historia wiadomości klient↔serwis (redagowalne przy RODO,
  event `mp_case_message_added` bez treści; listener `mp_case_add_system_message` dla D); eraser i
  exporter wpięte w natywne narzędzia WP (Narzędzia → Dane osobowe): eraser szuka PO EMAILU,
  anonimizuje klienta (pola czyszczone, `anonymized_at`, odpięcie konta WP, wiersz zostaje), redaguje
  messages + form_data-PII + `warranty_exceptions.reason` (B przez filter), kasuje załączniki, emituje
  `PII_REDACTION`/`CUSTOMER_ANONYMIZED`; **sprawa aktywna/okno roszczeń → odroczenie EN BLOC**
  (`items_retained`); exporter: dane klienta + sprawy + wiadomości + metadane załączników; test C5 w CI.
- Intake (C): załączniki twardo (spec T5) — MIME PO TREŚCI (finfo; brak ext-fileinfo = admin
  notice + odmowa), limity 8 MB/plik + 5/zgłoszenie + globalny CAP przestrzeni pending 2 GB;
  katalog `uploads/mp-attachments/` z deny-ALL + losowe nazwy UUID BEZ rozszerzenia; strip EXIF/GPS
  (imagick → fallback reenkod GD) dla JPEG/PNG/WebP; `retention_until` liczone z rodzaju sprawy
  (reklamacja 24 / naprawa·zwrot 12 / zapytanie 3 mies.) + cron retencji (kasuje wiersz + PLIK);
  serwowanie przez endpoint PHP z bramką IDOR (personel każdy; klient tylko własna sprawa verified;
  unverified = tylko personel) + Content-Type z finfo + nosniff; kasacja ZAWSZE = wiersz + plik
  z dysku; pole załączników w formularzu; sprzątanie katalogu przy uninstall (warstwa i);
  test C4 w CI (upload z EXIF, deny-ALL, IDOR/ownership, retencja).
- Intake (C): front zgłoszenia (P1.1 + antyspam część) — renderowanie formularza BLOKIEM Gutenberga
  `mp/intake-form` (+ shortcode fallback, lekcja: buildery nie renderują shortcode), WCAG-lite
  (label per pole, aria-describedby, role=alert/status); auto-strona tworzona przy aktywacji
  z ODCISKIEM PALCA (kasowana w uninstall tylko gdy nieedytowana ręcznie); handler zgłoszenia
  (admin-post): nonce + honeypot + pułapka czasu (<2 s = bot, cichy odrzut) → CaseRepo::create
  → mail z magic-linkiem → komunikat NEUTRALNY (bez enumeracji); potwierdzenie magic-linkiem (GET)
  na własnej minimalnej stronie (Cache-Control: no-store, Referrer-Policy: no-referrer, nosniff,
  SAMEORIGIN), neutralnej (SRV tylko mailem) + 2. mail z numerem SRV po weryfikacji; nagłówki
  bezpieczeństwa na stronie formularza; test C3 w CI (wp server + przechwyt wp_mail).
- Intake (C): formularz dynamiczny + walidacje (P1.1/1.2/1.4) — PLASKI schemat pol per RODZAJ
  sprawy (reklamacja/naprawa/zapytanie/zwrot; `FormConfig`, zero logiki warunkowej, admin nadpisze
  opcja autoload=no); walidacja SYNCHRONICZNA PRZED insertem (odmowa = bledy {field, reason_code},
  NIC nie ldauje w bazie): dokument zakupu, serial (ksztalt), data zakupu (format Y-m-d, nie
  z przyszlosci, nie sprzed 1990), email, pola wymagane per rodzaj; form_data buduje etykiety
  i flagi pii_sensitive ZE SCHEMATU z chwili zlozenia (render historyczny); komenda `wp mp
  case-create` rozszerzona (--document/--date/--return-reason); test C2 w CI.
- Intake (C): rdzen sprawy serwisowej — schemat 7 tabel (customers, service_cases, case_events,
  messages, attachments, consents, srv_counters) z migracjami; atomowy licznik numeru sprawy
  SRV/RRRR/NNNNN (`INSERT ... VALUES(year, LAST_INSERT_ID(1)) ON DUPLICATE KEY UPDATE ...` +
  UNIQUE na case_number — zero duplikatow przy zbieznosci); narodziny sprawy wg flow z krytyki:
  zgloszenie -> sprawa `unverified` (status NULL, SRV nadany od razu, snapshot gwarancji z chwili
  zgloszenia NIOSACY PARTIE, token jednorazowy = tylko HASH w bazie, TTL 24h) -> potwierdzenie
  magic-linkiem ATOMOWE (UPDATE-warunkowy: token zywy, w oknie 72h) -> DOPIERO TERAZ event
  CASE_CREATED (append-only, NO-PII) + akcja `mp_case_created` + utworzenie/podpiecie klienta
  (Automator nigdy nie widzi niepotwierdzonych); form_data z etykietami z chwili zlozenia
  (render historyczny) + flaga pii_sensitive per pole; komendy `wp mp case-create` / `case-verify`;
  test C1 w CI (job e2e-import: SRV wspolbiezny 30 procesow + narodziny + snapshot z partia).
- Registry (B): tabele produktow/eventow/wyjatkow/jobow importu z migracjami, silnik statusu
  gwarancji (`mp_warranty_check`), silnik importu CSV odporny na polskiego Excela (Windows-1250,
  separatory `;`/`,`, raport bledow per wiersz, joby z lockiem INSERT-pod-UNIQUE i tokenem UUID,
  batche transakcyjne po 100 z wznowieniem z offsetu), komenda `wp mp import-products`.
- Registry (B): ekran admina "Import produktow z CSV" — upload przez admin-post (PRG),
  pasek postepu i petla batchy przez AJAX (TEN SAM silnik co WP-CLI), przycisk "Wznow"
  (przejecie joba = nowy token, stare batche dostaja odmowe), pobieranie raportu bledow
  przez PHP z capability (nonce + nosniff), stale-detekcja przy renderze, ostrzezenie
  gdy serwer nie ma iconv/intl.
- Registry (B): wyjatki gwarancyjne — CRUD stanu wg precedensu kontraktu (max 1 aktywny per
  zakres, per-sprawa > globalny, wylacznie mp_system_admin, "expired" wyliczane z valid_until
  nigdy zapisywane, valid_until > NOW przy CREATE), emisja `mp_warranty_exception_changed`
  PO COMMIT (5 argumentow), historia produktu `wp_mp_product_events` (append-only, payload bez
  reason, pola PII w diffach jako {field, changed:true}), listenery `mp_cases_data_erased`
  (rewokacja per-sprawa, globalne zostaja) i `mp_privacy_redact_for_customer` (redakcja reason),
  komendy `wp mp exception-add` / `wp mp exception-revoke`.
- Registry (B): wyszukiwarka produktow (serial/model/faktura przez esc_like — `_`/`%` szukaja
  literalnie; "po kliencie" mechanika odwrocona P2.6 przez `mp_customer_find_products` z obsluga
  truncated="doprecyzuj"; degraded bez Intake = pole klienta nieaktywne), archiwum produktu
  (soft delete FAIL-CLOSED: bez `mp_product_active_cases_count` odmowa; wpis w historii),
  ekrany admina: lista produktow (WP_List_Table, status gwarancji wyliczany + badge wyjatku,
  liczba spraw z C albo uczciwe "brak danych") za `mp_agent`, wyjatki gwarancyjne (lista +
  przyznanie + cofniecie) i archiwizacja za `mp_system_admin`; import przeniesiony do submenu
  Rejestru MP; CLI `wp mp product-archive` / `product-restore`.
- Registry (B): `wp mp import-resume <job>` (wznowienie przerwanego importu z CLI — ta sama
  mechanika co "Wznow" w UI) oraz testy DoD klocka B w CI (job e2e-import na zywym WP 6.9.4
  + MariaDB 11.8): import 10 000 wierszy, kill -9 klienta w polowie + wznowienie z offsetu
  (ksiegowosc joba == wiersze w bazie, zero duplikatow), partia CSV->mp_warranty_check,
  negatywne uprawnienia, snapshot-uninstall (default OFF: dane zostaja; opt-in: tabele znikaja,
  role i caps zdjete).
- Role mp_* dostaja swoje capabilities (cap-marka per rola) przy aktywacji; wbudowany
  administrator dostaje caps personelu (zdejmowane przy uninstall ostatniego pluginu).
  Pelna macierz uprawnien doprecyzuje SECURITY.md (D2).
- Fundament repo (D1): szkielety 3 pluginow (bootstrap OOP, cykl zycia, wspolne role mp_*, i18n),
  wspolna biblioteka `lib/mp-common` (kopiowana do pluginow przy buildzie ze stemplem namespace),
  build ZIP-ow z BUILD-INFO, CI (php -l matrix 8.1-8.5, PHPCS/WPCS, PHPStan lvl 6, Plugin Check,
  linter cudzych tabel, gitleaks), testy jednostkowe smoke, poligon Docker (WP 6.9.4, MariaDB 11.8,
  Mailpit) z realnym cronem i SMTP dev.
