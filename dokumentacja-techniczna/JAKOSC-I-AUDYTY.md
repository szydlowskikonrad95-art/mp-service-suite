# Jakość i audyty — jak ten system jest sprawdzany

**Wersja:** 1.3.5

Ten dokument opisuje, **czym i jak kontrolowana jest jakość** trzech wtyczek MP: co sprawdza
się automatycznie przy każdej zmianie kodu, co sprawdza się ręcznie przed wydaniem, a co system
sprawdza **sam u Ciebie na serwerze**, już po wdrożeniu. Powstał, żeby osoba techniczna nie
musiała nam wierzyć na słowo — każdą z opisanych kontroli można obejrzeć w repozytorium
i powtórzyć.

Kontrola jakości ma tu **trzy poziomy** i każdy odpowiada na inne pytanie:

| Poziom | Pytanie | Kiedy działa |
|---|---|---|
| 1. Bramki automatyczne | „Czy ta zmiana nie psuje niczego?" | przy **każdej** zmianie kodu |
| 2. Audyty przed wydaniem | „Czy całość jest gotowa do oddania?" | przed każdą wersją |
| 3. Diagnostyka witryny | „Czy system **dziś** działa zdrowo?" | stale, u Ciebie na serwerze |

---

## Poziom 1 — bramki automatyczne (przy każdej zmianie kodu)

Żadna zmiana nie wchodzi do gałęzi głównej bez przejścia **16 niezależnych kontroli**.
Gałąź główna jest chroniona: wymagane są wszystkie kontrole, zabroniona jest historia
przepisywana siłą. Co się uruchamia:

- **Analiza statyczna PHP** (PHPStan, poziom 6) — wyłapuje błędy typów i nieosiągalny kod bez
  uruchamiania wtyczki.
- **Standard kodu WordPress** (WordPress Coding Standards) — z dwiema regułami dołożonymi
  celowo pod ten projekt: kontrola **uprawnień** i kontrola **tłumaczeń**.
- **Zgodność wersji PHP** — testy jednostkowe chodzą na **PHP 8.1, 8.2, 8.3, 8.4 i 8.5**,
  czyli od deklarowanego minimum w górę. Nie zdarzy się, że wtyczka działa u nas, a pada
  u Ciebie na starszym PHP.
- **Plugin Check** — **oficjalne narzędzie zespołu WordPress.org**, to samo, którym recenzenci
  sprawdzają wtyczki zgłaszane do katalogu wtyczek.
- **Skan sekretów** — pilnuje, żeby do repozytorium nie trafiło żadne hasło ani token.
- **Kontrola zależności** — sprawdzenie bibliotek pomocniczych pod kątem znanych podatności.
- **Testy żywych scenariuszy** — kilkadziesiąt przebiegów wykonywanych na prawdziwym
  WordPressie w kontenerze: zgłoszenie przez formularz, załączniki zależne od kategorii,
  zmiana statusu, terminy, eskalacje, import i eksport, uprawnienia ról.
- **Bramka zgodności dokumentów z kodem** — 33 kontrole pilnujące, że dokumentacja i instrukcje
  nie obiecują niczego, czego kod nie robi (nazwy ról, nazwy statusów, liczby, formaty).
  Powstała, bo dokument rozjeżdżający się z kodem jest groźniejszy niż brak dokumentu.
- **Kontrola plików procesu budowy** — same pliki definiujące automatyzację też są sprawdzane,
  łącznie z przypięciem wszystkich użytych narzędzi zewnętrznych do konkretnej, niezmiennej
  wersji (żeby nikt nam po cichu nie podmienił narzędzia w trakcie).

## Poziom 2 — audyty przed wydaniem

Bramki automatyczne łapią **regresje** — czyli to, że coś, co działało, przestało działać.
Nie łapią **braków**: rzeczy, której nigdy nie zbudowano, żaden test nie zgłosi. Dlatego przed
każdym wydaniem przechodzimy zestaw audytów, z których każdy patrzy pod **innym kątem**:

- **Zgodność z zamówieniem** — porównanie kodu z **oryginalnym dokumentem zamówienia**, nie
  z naszą własną dokumentacją. To rozróżnienie jest istotne: audyt czytający nasze dokumenty
  potwierdzi, że są zgodne ze sobą, i przepuści rozbieżność z tym, co faktycznie zamówiono.
- **Bezpieczeństwo** — osobny przegląd nastawiony wyłącznie na realnie wykorzystywalne luki:
  wstrzyknięcie SQL, wykonanie obcego skryptu, dostęp do cudzych danych przez podmianę numeru
  w adresie, obejście kontroli plików, wyciek danych osobowych do dziennika zdarzeń. Zakres
  i przyjęte zasady opisuje SECURITY.md w tym samym katalogu.
- **Kompletność** — kąt „czy coś czegoś **nie robi**, choć wygląda na sprawne": ustawienie
  zapisywane, a nigdy nieczytane; zadanie cykliczne zaplanowane bez obsługi; uprawnienie
  sprawdzane, a nikomu nienadane; ekran, który nic nie zmienia; pełny cykl życia wtyczki
  (włączenie, wyłączenie, ponowne włączenie, odinstalowanie).
- **Spójność paczki** — czy paczka zawiera wszystko, co obiecuje, czy każde zdjęcie przywołane
  w instrukcji istnieje i czy nie ma w niej śladów naszego środowiska pracy.

### Kalibracja audytu — dlaczego „nic nie znaleziono" coś znaczy

Audyt, który nic nie znalazł, sam z siebie nie jest dowodem. Może znaczyć „jest czysto", a może
znaczyć „patrzący był nieuważny" — i tego nie da się rozróżnić z samego wyniku.

Dlatego audyt jest **kalibrowany**: do kopii kodu (nigdy do wersji wydawanej) wszczepiamy
**celowo przygotowane, prawdziwe błędy** — wzięte z realnych wpadek tego projektu, nie wymyślone.
Audyt przechodzi na kopii i sprawdzamy, **czy je znalazł**. Jeśli nie znalazł, jest odrzucany
jako nieskuteczny i wynik „czysto" z niego nie liczy się jako dowód.

Wszczepione błędy trafiają celowo w miejsca, które audyt wcześniej ogłosił poprawnymi — bo tylko
tak sprawdza się, czy naprawdę patrzył, czy tylko przepisał wnioski.

### Test instalacji od zera

Przed wydaniem paczka jest instalowana **na całkowicie świeżym WordPressie**, na **deklarowanym
minimum** środowiska (PHP 8.1, MySQL 8) — nie na naszym wygodnym, nowszym. Instalacja idzie
**wyłącznie z paczki**, tej samej, którą dostajesz, a nie z kodu roboczego. Sprawdzana jest cała
ścieżka: zgłoszenie klienta, potwierdzenie, załączniki, numer sprawy, wiadomości, panel
administratora, a osobno **wgranie wtyczki przez panel WordPressa** — tak jak zrobi to Twój
informatyk. Do tego kontrola, że w dzienniku diagnostycznym nie pojawia się żadne ostrzeżenie
PHP pochodzące z naszego kodu.

## Poziom 3 — diagnostyka na Twojej witrynie (po wdrożeniu)

Tu nie chodzi już o jakość kodu, a o zdrowie działającego systemu. Wtyczki **nie budują własnego
panelu diagnostycznego** — dopisują swoje testy do mechanizmu wbudowanego w WordPressa, dostępnego
w panelu pod **Narzędzia → Stan witryny**. To świadoma decyzja: jedno miejsce, znane
administratorom, zamiast czwartego ekranu do nauczenia się.

W tym jednym miejscu znajdziesz razem:

- **28 testów samego WordPressa** — wersja PHP i brakujące rozszerzenia, zaległe aktualizacje,
  HTTPS, zaplanowane zadania cykliczne, dostępność interfejsu programistycznego, limity
  wgrywania plików, miejsce na dysku, tryb diagnostyczny włączony na produkcji;
- **14 testów dopisanych przez nasze wtyczki** — m.in. czy zadanie usuwające stare dane osobowe
  nie zniknęło z listy zadań (wymóg ochrony danych), czy poczta do klientów nie zaczęła się
  odbijać, czy ustawiona jest pula pracowników przyjmujących zgłoszenia (bez niej sprawy nie
  będą przydzielane), czy nie zostały niedokończone weryfikacje, czy obecne są biblioteki do
  obsługi obrazów i rozpoznawania typów plików.

Każdy nasz test, który wypada źle, podaje **co zrobić**, a nie tylko że jest problem.

WordPress uruchamia te testy **sam, raz w tygodniu**, i pokazuje wynik na pulpicie panelu.

⚠️ **Ważne ograniczenie:** ten wynik jest **widoczny po zalogowaniu** — WordPress **nie wysyła
z niego powiadomień pocztą**. Jeśli nikt nie zagląda do panelu, awaria może pozostać
niezauważona. Zalecenie: raz w tygodniu spojrzeć na pulpit albo zamówić u nas dosłanie
powiadomień pocztą jako rozszerzenie.

---

## Czego ten system kontroli **nie** robi

Uczciwa granica jest częścią jakości. Powyższe kontrole **nie**:

- **nie zastępują kopii zapasowej** — zasady aktualizacji i wycofania zmian opisuje
  MIGRATION_POLICY.md w tym samym katalogu;
- **nie są ochroną przed włamaniem w czasie rzeczywistym** — nie zastępują zapory ani wtyczki
  bezpieczeństwa; kontrola bezpieczeństwa odbywa się na etapie tworzenia kodu, a nie jako
  skaner działający na Twoim serwerze;
- **nie badają wtyczek i motywu innych dostawców** ani konfliktów, jakie mogą wprowadzić —
  sprawdzamy nasze trzy wtyczki i ich współpracę ze sobą;
- **nie dowodzą braku wszystkich błędów.** Żaden audyt tego nie potrafi i nikt uczciwy tego nie
  obieca. Da się powiedzieć tylko: **te** klasy błędów sprawdzono, **tą** metodą, i wykazano,
  że metoda potrafi je wykryć. Dlatego każde wydanie ma spis wykonanych kontroli wraz z listą
  rzeczy, których **nie** sprawdzono;
- **nie oceniają wydajności przy bardzo dużej skali** — przy planowanych dziesiątkach tysięcy
  spraw albo imporcie bardzo dużych plików warto zamówić osobny test obciążeniowy.
