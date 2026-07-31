# MP Service Suite — instrukcja instalacji i konfiguracji

> System serwisowy dla WordPressa: przyjmowanie zgłoszeń, rejestr gwarancji i automatyzacja obsługi.
> Składa się z **3 wtyczek** działających razem. Instrukcja prostym językiem — instalacja bez pomocy programisty.

---

## 1. Co dostajesz (3 wtyczki)

| Wtyczka | Plik ZIP | Nazwa na liście wtyczek | Do czego |
|---|---|---|---|
| **Zgłoszenia serwisowe** | `mp-service-intake.zip` | MP Service Intake | formularz zgłoszenia, numer sprawy (SRV), panel klienta, RODO, historia sprawy |
| **Rejestr gwarancji** | `mp-warranty-registry.zip` | MP Warranty & Serial Registry | baza produktów/seriali, import CSV, sprawdzanie gwarancji, wyjątki gwarancyjne |
| **Automator** | `mp-workflow-automator.zip` | MP Workflow Automator | automatyczny przydział, terminy (SLA) + eskalacje, szablony maili, checklisty, eksport |

ℹ️ Kolumna „Nazwa na liście wtyczek" pokazuje, jak wtyczka podpisuje się w panelu WordPressa
(**Wtyczki → Zainstalowane**) — nazwy techniczne są po angielsku, w tej instrukcji używamy polskich.

Wtyczki rozmawiają ze sobą **automatycznie** (przez wewnętrzne haki). Każda działa też **sama** — jeśli którejś brakuje,
pozostałe przechodzą w tryb ograniczony (nigdy nie wywalają strony).

## 1a. Słowniczek — co znaczą słowa, które zobaczysz niżej

Nie musisz ich znać, żeby korzystać z systemu. Wyjaśniamy je, bo pojawiają się w tej instrukcji
i w komunikatach WordPressa.

| Słowo | Po ludzku |
|---|---|
| **wtyczka** | dodatek do WordPressa; wgrywa się plikiem ZIP i włącza jednym kliknięciem |
| **panel** | to, co widzisz po zalogowaniu na stronę jako administrator (`/wp-admin`) |
| **SLA (termin SLA)** | umówiony czas na zajęcie się sprawą, np. 24 godziny na pierwszą reakcję. System pilnuje go sam: przypomina pracownikowi przed upływem, a po terminie powiadamia koordynatora (§5.3) |
| **link do zalogowania (magic-link)** | jednorazowy link, który klient dostaje mailem. Klika go i wchodzi do swoich spraw — bez zakładania konta i wymyślania hasła |
| **anonimizacja** | usunięcie danych, po których dałoby się rozpoznać osobę (imię, nazwisko, e-mail, telefon, treść zgłoszenia). Sama sprawa i jej historia zostają, żeby statystyki się zgadzały — ale nie da się już powiedzieć, czyja była (§8) |
| **zadanie cykliczne (cron)** | czynność, którą serwer wykonuje sam co jakiś czas, np. co 5 minut sprawdza terminy |
| **WP-Cron** | wbudowany zegar WordPressa; ⚠️ rusza **tylko wtedy, gdy ktoś wejdzie na stronę** — dlatego w nocy „stoi" |
| **systemowe zadanie cykliczne** | prawdziwy zegar na serwerze; działa **niezależnie od odwiedzin**, dlatego zalecamy go na produkcji (§7.3) |
| **fileinfo, iconv, intl** | dodatki do PHP na serwerze; pierwszy sprawdza, czy wgrany plik jest naprawdę zdjęciem, dwa pozostałe pomagają z polskimi znakami |
| **hak / punkt zaczepienia / filtr** | miejsce w systemie, w którym programista może dołożyć własne zachowanie bez zmiany naszego kodu |
| **endpoint** | adres, pod który system wysyła lub odbiera dane w tle (nie strona do oglądania) |
| **snippet** | krótki fragment kodu do wklejenia w jednym konkretnym miejscu |
| **proxy / Cloudflare** | pośrednik między odwiedzającym a Twoim serwerem; przyspiesza stronę, ale ukrywa adres odwiedzającego (§7.4) |

## 2. Wymagania

**Musisz mieć już działającą stronę na WordPressie.** Ten system to trzy wtyczki, które się do niej
dokłada — nie jest to gotowa strona i nie zawiera WordPressa.

- WordPress **6.0** lub nowszy — cała paczka przechodzi testy instalacji od zera na **6.9** (PHP 8.1) i na najnowszym **7.0** (PHP 8.2)
- PHP **8.1** lub nowszy (z rozszerzeniem `fileinfo` — potrzebne do bezpiecznego przyjmowania załączników)
- Baza **MySQL 8 / MariaDB 10.6+**
- Dostęp administratora do panelu WordPress

### Jak sprawdzić, czy Twój hosting to spełnia (nie musisz się na tym znać)

Najprościej **zapytaj pomoc techniczną swojego hostingu**. Możesz napisać dosłownie tak:

> *Dzień dobry, chcę zainstalować wtyczki wymagające PHP w wersji 8.1 lub nowszej z włączonym
> rozszerzeniem `fileinfo` oraz bazy MySQL 8 lub MariaDB 10.6 lub nowszej. Proszę o informację,
> czy moje konto to spełnia, a jeśli nie — czy da się to włączyć.*

Możesz też zajrzeć sam: panel WordPressa → **Narzędzia → Stan witryny → Informacje**, zakładki
*Serwer* i *Baza danych*. Są tam wypisane wersje. **Jeśli hosting nie spełnia wymagań** — nie
instaluj na siłę, tylko poproś hosting o podniesienie wersji PHP (u większości firm to jedno
kliknięcie w panelu, robi się w minutę i jest bezpłatne).

## 3. Instalacja (3 × ten sam krok)

⚠️ **Przed wgraniem wtyczek zrób kopię bazy danych i plików strony.** To standardowa ostrożność przy instalacji
nowego oprogramowania — gdyby coś poszło nie tak, wracasz do stanu sprzed instalacji jednym ruchem. Szczegółową
politykę kopii zapasowych i cofania zmian w bazie znajdziesz w pliku `MIGRATION_POLICY.md`, dołączonym do paczki.
ℹ️ **Ten plik jest napisany dla osoby technicznej** — nie musisz go czytać, żeby zainstalować system.
Przekaż go informatykowi albo hostingowi, jeśli będziesz potrzebować przywrócenia danych.

Dla **każdego** z 3 plików ZIP:
1. Panel WordPress → **Wtyczki → Dodaj nową → Wyślij wtyczkę na serwer**.
2. Wybierz plik ZIP → **Zainstaluj teraz**.
3. Kliknij **Włącz**.

**Kolejność nie ma znaczenia** — możesz włączać w dowolnej. Zalecane: najpierw Rejestr gwarancji, potem Zgłoszenia, na końcu Automator.

## 4. Co dzieje się po włączeniu (automatycznie)

- Tworzą się **2 strony**:
  - **„Zgłoszenie serwisowe"** — publiczny formularz dla klientów.
  - **„Panel zgłoszeń"** — logowanie klienta i podgląd jego spraw.
- Powstają **4 role** użytkowników (patrz §6). Twoje konto administratora dostaje pełne uprawnienia do ekranów systemu.
- W menu bocznym pojawiają się ekrany: **MP: Sprawy** (lista zgłoszeń), **MP: Niepotwierdzone**
  (zgłoszenia, których klient jeszcze nie potwierdził mailem), **Rejestr MP** (produkty i gwarancje)
  oraz **Automatyzacje MP** (przydział, terminy, raporty).

> Strony, role i uprawnienia zakładają się **same** przy włączeniu — system rusza od razu.
> Żeby jednak zaczął pracować za Ciebie (przydzielać sprawy, liczyć terminy, sprawdzać gwarancje),
> wykonaj kroki z sekcji 5 — najważniejszy to **wskazanie pracowników serwisu**, bo bez nich
> zgłoszenia będą tylko czekać na liście.

## 5. Konfiguracja

### 5.1 Formularz zgłoszenia (Zgłoszenia serwisowe)
- **Rodzaje zgłoszeń i pola są wbudowane** — reklamacja wymaga numeru seryjnego, dokumentu zakupu i daty;
  zapytanie techniczne tylko opisu. Nie ma na to ekranu ustawień: zmiana zestawu pól albo kategorii
  to kilka linijek dla programisty (system udostępnia do tego gotowe punkty zaczepienia).
- Formularz ma wbudowaną ochronę: potwierdzenie e-mail jednorazowym linkiem do zalogowania, pułapki na boty, limity zgłoszeń, wymagana zgoda RODO.

> **Ile zgłoszeń można wysłać — warto to wiedzieć, zanim klient zadzwoni.**
> System przyjmuje z jednego adresu e-mail **3 zgłoszenia na dobę**, z jednego numeru seryjnego
> **5 na dobę**, a z jednego łącza internetowego **10 w ciągu 10 minut**. Dodatkowo identyczne
> zgłoszenie wysłane **dwa razy w ciągu 15 minut** nie zakłada drugiej sprawy — to ochrona przed
> podwójnym kliknięciem, a nie błąd.
>
> Gdy klient mówi „nie mogę wysłać zgłoszenia", **najpierw sprawdź, czy nie wysyłał już dziś kilku** —
> to najczęstsza przyczyna. Progi da się zmienić, ale wymaga to kilku linijek od programisty
> (opis w `SECURITY.md`, w dokumentacji dla informatyka).
> ⚠️ Jeśli Twoja strona stoi **za pośrednikiem** (np. Cloudflare), przeczytaj też §7.4 — wtedy
> limit na łącze może objąć **wszystkich** klientów naraz.
- **Załącznik zależy od kategorii.** Dla kategorii **„AGD drobne"** i **„Elektronarzędzia"** zdjęcie tabliczki
  znamionowej jest **wymagane** — bez niego serwis nie ustali modelu ani mocy urządzenia. Dla **„Elektronika audio"**
  i **„Inne"** załącznik pozostaje **opcjonalny**. Przyjmowane formaty: **JPG, PNG, WebP, PDF**, do **5 plików**.

### 5.2 Rejestr gwarancji (produkty)
- ⚠️ **Bazę produktów wgraj ZANIM udostępnisz formularz klientom.** Zgłoszenie łączy się z produktem
  **w chwili przyjęcia** i to powiązanie nie jest uzupełniane wstecz. Sprawy przyjęte przed importem
  zostaną bez produktu i bez statusu gwarancji (numer seryjny nadal będzie widoczny w opisie zgłoszenia).
- **Import produktów z CSV**: Rejestr MP → Import. Obsługiwane duże pliki (dziesiątki tysięcy wierszy), wznawianie po przerwaniu.
- 📎 **Gotowy przykład jest w paczce** — plik `przyklady/przyklad-import-produktow.csv` w folderze wtyczki, a na ekranie importu jest
  link **„Pobierz przykładowy plik CSV"**. Otwórz go w Excelu, podmień dane na swoje i wgraj.
- **Poprawianie danych produktu**: przy produkcie w rejestrze jest odnośnik **„popraw dane"** (tylko
  administrator systemu). Służy do naprawiania pomyłek z importu — najczęściej błędnej daty gwarancji.
  Każda poprawka zapisuje się w historii produktu: kto, kiedy, wartość przed i po.
  ⚠️ **Numeru seryjnego nie da się zmienić** — wiążą się z nim sprawy klientów. Zły numer = zarchiwizuj
  wpis i zaimportuj poprawny.
  ⚠️ **Sprawy przyjęte wcześniej zachowują status gwarancji z chwili zgłoszenia.** Poprawka działa na
  nowe zgłoszenia; na karcie starszej sprawy pojawi się informacja, że dane poprawiono po zgłoszeniu —
  jeśli poprawka ma objąć także tę sprawę, zmień jej status ręcznie.
- **Wyjątki gwarancyjne**: ręczne przyznanie/cofnięcie gwarancji dla konkretnego produktu lub sprawy (tylko administrator systemu).
- **Status gwarancji ma cztery możliwe wartości:**
  - **gwarancja aktywna** — data końca gwarancji jeszcze nie minęła,
  - **gwarancja wygasła** — data końca gwarancji już minęła,
  - **brak danych** — produkt nie jest w rejestrze albo nie ma wpisanej daty końca gwarancji,
  - **wymagana weryfikacja** — podany przez klienta numer dokumentu zakupu albo data zakupu **nie zgadzają
    się** z tym, co jest w rejestrze. System **nie rozstrzyga tego sam** — tylko oznacza sprawę do
    ręcznego sprawdzenia. Taką sprawę powinien obejrzeć pracownik: sprawdzić dokument zakupu klienta
    i ręcznie potwierdzić lub odrzucić gwarancję (np. przez wyjątek gwarancyjny opisany wyżej).

#### 5.2.1 Jak ma wyglądać plik CSV

| Kolumna (nagłówek) | Wymagana? | Co wpisać | Też zadziała nagłówek |
|---|---|---|---|
| `numer_seryjny` | ✅ **TAK** | numer seryjny produktu | `serial`, `sn` |
| `model` | nie | nazwa/oznaczenie modelu | — |
| `partia` | nie | partia produkcyjna | `batch`, `partia_produkcyjna` |
| `faktura` | nie | numer dokumentu zakupu | `dokument_zakupu`, `invoice`, `purchase_document` |
| `data_zakupu` | nie | data zakupu | `purchase_date` |
| `gwarancja_do` | **zalecana** | data końca gwarancji | `warranty_until`, `koniec_gwarancji` |
| `kategoria` | nie | `audio`, `agd`, `elektronarzedzia`, `inne` | `category`, `kategoria_produktu` |

> ⚠️ Te cztery kategorie są **wbudowane**. Dołożenie własnej (np. „rowery elektryczne")
> to kilka linijek dla programisty — nie ma na to ekranu ustawień.

**Zasady, które warto znać (tak działa system):**
- **Tylko `numer_seryjny` jest obowiązkowy.** Pozostałe pola mogą być puste — wiersz i tak wejdzie.
- ⚠️ **Bez `gwarancja_do` system nie policzy statusu gwarancji** dla tego produktu (pokaże „brak danych"). To najważniejsza
  kolumna po serialu.
- **Daty:** `2026-04-12` albo `12.04.2026` (format polskiego Excela). Inny zapis = wiersz trafia do raportu błędów.
- ⚠️ **Gwarancja nie może kończyć się przed datą zakupu.** Taki wiersz trafia do raportu błędów
  z powodem „gwarancja kończy się przed datą zakupu", a reszta pliku importuje się normalnie.
  To najczęstsza literówka przy ręcznym uzupełnianiu (rok wpisany z pamięci). Ta sama reguła
  obowiązuje przy poprawianiu danych produktu w panelu — po obu stronach tak samo.
- **Kategoria:** można podać slug (`agd`) albo etykietę (`AGD drobne`). Wartość spoza listy nie jest błędem — wpada do `inne`.
- **Separator:** `;` albo `,` — rozpoznawany automatycznie z nagłówka.
- **Kodowanie:** UTF-8 albo Windows-1250 (domyślne z polskiego Excela). Jeśli serwer nie ma rozszerzenia `iconv` ani `intl`,
  import **uczciwie odmówi** pliku z Windows-1250 (zamiast przekłamać polskie znaki) i poprosi o UTF-8 — ekran importu
  ostrzega o tym z góry. W Excelu: *Zapisz jako → CSV UTF-8*.
- **Limit rozmiaru pliku: 8 MB** — większą bazę podziel na części (import można wznawiać).
- **Import DODAJE produkty, nie nadpisuje.** Numer seryjny, który już jest w rejestrze, trafia do raportu błędów jako duplikat.
  Przy porównywaniu **spacje i myślniki są pomijane, wielkość liter nie ma znaczenia** — `SN-AUD-1001`, `sn aud 1001`
  i `snaud1001` to dla systemu **ten sam** produkt.
- Po imporcie z błędami: kolumna „Raport błędów" w tabeli *Ostatnie importy* → **pobierz CSV** z numerem wiersza i przyczyną.

### 5.3 Automator (przydział, terminy, szablony, raporty)

**Najważniejszy pierwszy krok: uzupełnij pulę pracowników.**
- Najpierw dodaj pracowników jako użytkowników WordPressa z rolą **„Pracownik serwisu MP"**
  (Użytkownicy → Dodaj nowego). Bez tego nie będzie kogo wskazać.
- Wejdź w **Automatyzacje MP** (menu boczne) → sekcja **„Kto dostaje zgłoszenia"** (pod tabelą reguł)
  → zaznacz pracowników, między których system ma rozdzielać sprawy (po kolei, sprawiedliwie —
  round-robin) → **Zapisz listę pracowników**.
- **Pusta lista = przydział nie działa** (sprawy zostają „nieprzydzielone"). Tabela reguł pisze o tym
  wprost przy regule przydziału, a **Narzędzia → Stan witryny** pokazuje to jako problem do naprawienia.
- Reguły opisane są po polsku: KIEDY (np. nowa sprawa) → JEŚLI (kategoria/kraj/język/priorytet)
  → ZRÓB (przydziel / zmień status / ustaw priorytet / powiadom). ⚠️ Sama **treść reguł jest wbudowana
  i pokazywana tylko do odczytu** — z panelu ustawia się listę pracowników; dołożenie nowej reguły
  to zadanie dla programisty.

**Terminy SLA:**
- Terminy są **wbudowane i liczą się same**: nowe zgłoszenie — 24 h na pierwszą reakcję,
  „w analizie" — 48 h, „zaakceptowane" — 24 h. Przypomnienie wychodzi po upływie 75 % czasu.
  ⚠️ Nie ma ekranu do zmiany tych godzin — inne wartości ustawia programista.
- System sam wysyła pracownikowi **przypomnienie przed terminem** i **eskalację do koordynatora
  po terminie**. Sprawdzanie chodzi co 5 minut (patrz nota §7.3 — na produkcji ustaw systemowy cron).

**Statusy spraw:**
- 7 statusów podstawowych (nowe / do uzupełnienia / w analizie / zaakceptowane / odrzucone /
  w naprawie / zamknięte) jest wbudowanych i nieusuwalnych. ⚠️ System przewiduje dokładanie własnych
  statusów, ale **nie ma na to ekranu** — dołożenie statusu to zadanie dla programisty.
- Odrzucenie sprawy zawsze wymaga podania powodu. **Wznowić zamkniętą sprawę może tylko
  koordynator** (i tylko do statusu „w analizie").

**Szablony i checklisty:**
- **Automatyzacje MP → sekcja „Checklisty i szablony odpowiedzi"** — gotowe treści maili z podstawianymi polami (numer sprawy,
  status, termin).
- w tej samej sekcji **checklisty per typ sprawy** — lista kroków obsługi dla każdego rodzaju sprawy; pracownik odhacza
  kroki na karcie sprawy, każde odhaczenie zostaje w historii.

**Raporty:**
- **Automatyzacje MP → Eksport CSV** — zestawienie: ile spraw, jak długo trwała obsługa, powody odrzuceń;
  eksport listy spraw do CSV. ⚠️ Eksport robi **koordynator albo administrator systemu** — pracownik
  serwisu go nie ma. To celowe: zestawienie opisuje pracę nad sprawami klientów, więc wychodzi z systemu wyłącznie
  przez osobę, która za to odpowiada.

## 6. Role i użytkownicy

| Rola | Kto | Może |
|---|---|---|
| **Administrator systemu MP** | Ty / właściciel | wszystko: import, wyjątki gwarancyjne, archiwum produktów |
| **Koordynator serwisu MP** | kierownik zespołu | koordynacja spraw |
| **Pracownik serwisu MP** | serwisant | obsługa przydzielonych spraw |
| **Klient MP** | zgłaszający | **tylko własne** zgłoszenia (panel „moje sprawy") |

- **Personel:** WordPress → Użytkownicy → nadaj pracownikom rolę *Koordynator serwisu MP* lub *Pracownik serwisu MP* (dokładnie tak nazywają się na liście ról).
- **Klienci:** rola *Klient MP* nadaje się **automatycznie** po pierwszym potwierdzonym zgłoszeniu — nic nie robisz ręcznie.

## 7. Noty dla serwera (ważne przy wdrożeniu)

> ### ⛔ Zanim zaczniesz czytać ten rozdział — to NIE JEST rozdział dla Ciebie
>
> **Ta część nie jest do samodzielnego wykonania, jeśli nie zajmujesz się serwerami.** Są tu
> fragmenty kodu i ustawienia, które wpisuje się w konfigurację serwera — nie w panel WordPressa.
> Wpisane w złym miejscu nie zadziałają, a niektóre mogą wyłączyć stronę.
>
> **Co z tym zrobić — wybierz jedno:**
> 1. **Przekaż ten rozdział osobie, która wdrażała Ci system** (albo firmie, która go dla Ciebie
>    zrobiła) z prośbą: „proszę to skonfigurować przy wdrożeniu".
> 2. **Albo wyślij go do pomocy technicznej swojego hostingu.** Możesz napisać dosłownie tak:
>
>    > *Dzień dobry, mam na stronie system obsługi zgłoszeń serwisowych. Proszę o pomoc
>    > w trzech rzeczach: (1) ustawienie zadania cyklicznego co 5 minut wywołującego
>    > `wp-cron.php`, (2) jeśli serwer to nginx — dodanie reguły blokującej bezpośredni dostęp do
>    > katalogu z załącznikami, (3) jeśli strona stoi za Cloudflare — przekazywanie prawdziwego
>    > adresu IP odwiedzających. Szczegóły techniczne przesyłam w załączniku.*
>
> **Najważniejsze, żebyś wiedział:** jeśli punkt **7.3 (zadanie cykliczne)** nie zostanie
> wykonany, przypomnienia i terminy **stoją w nocy**, a system i tak wygląda na sprawny.
> To jedyny krok z tego rozdziału, którego pominięcie da się zauważyć dopiero po czasie —
> dlatego sprawdź w **Narzędzia → Stan witryny**, czy nie świeci na czerwono przy terminach.
>
> ⏱️ **Ile to zajmie:** samo wgranie i włączenie wtyczek (rozdziały 3-6) to około **30-45 minut**.
> Rozdział 7 to zwykle jedna wiadomość do hostingu i czekanie na odpowiedź.

### 7.1 Dostarczanie maili (SMTP)

> ✅ **Ten jeden podpunkt możesz zrobić sam** — w odróżnieniu od reszty rozdziału 7 nie wymaga
> dotykania serwera. Robi się go w panelu WordPressa, tak samo jak instalację naszych wtyczek
> (rozdział 3). Potrzebujesz tylko danych do swojej skrzynki — jak je zdobyć, piszemy niżej.

System wysyła maile (potwierdzenia, linki do zalogowania, powiadomienia) standardową funkcją
WordPressa. Na wielu hostingach maile z `wp_mail()` **lądują w spamie lub nie dochodzą** — a wtedy
klient nie dostanie potwierdzenia zgłoszenia i uzna, że formularz nie działa.

**Co zrobić:** zainstaluj wtyczkę SMTP (np. darmowe *WP Mail SMTP*) i podłącz skrzynkę nadawczą
swojej firmy. Kreator wtyczki poprowadzi Cię krok po kroku, ale poprosi o dane, których zwykle
nie ma się pod ręką. **Poproś o nie dostawcę poczty** (to ta firma, u której masz firmowego maila
— często ten sam hosting). Możesz napisać dosłownie tak:

> *Dzień dobry, chcę skonfigurować wysyłkę maili z mojej strony internetowej przez skrzynkę
> [tu wpisz swój adres, np. serwis@twojafirma.pl]. Proszę o dane do połączenia SMTP: adres serwera
> (host), port, rodzaj szyfrowania (SSL/TLS), nazwę użytkownika oraz informację, czy potrzebne jest
> osobne hasło do aplikacji. Dziękuję.*

Gdy dostaniesz odpowiedź, przepisz te dane do kreatora wtyczki SMTP i wyślij wiadomość testową.
To sprawa Twojej skrzynki i hostingu — nie kodu systemu, więc my nie możemy ustawić tego za Ciebie.

### 7.2 Ochrona załączników na nginx
Załączniki są chronione **na dwa sposoby**: bramką PHP (działa zawsze) oraz plikiem `.htaccess` (działa tylko na Apache/LiteSpeed).
**Jeśli Twój serwer to nginx**, `.htaccess` jest ignorowany — dodaj do konfiguracji serwera:
```nginx
location ^~ /wp-content/uploads/mp-attachments/ { deny all; return 403; }
```
(Pobieranie plików i tak przechodzi przez bezpieczny endpoint z kontrolą uprawnień — to dodatkowa warstwa.)

### 7.3 Pilnowanie terminów wymaga crona
Przypomnienia i eskalacje SLA sprawdzają się **co 5 minut** przez WP-Cron, a WP-Cron uruchamia się
przy odwiedzinach strony. **Bez ruchu (np. nocą) terminy stoją**, choć wszystko wygląda na sprawne.
**Na produkcji ustaw w panelu hostingu zadanie systemowe (cron):**
```
*/5 * * * * wget -q -O /dev/null https://twoja-domena.pl/wp-cron.php
```
Diagnostyka w **Narzędzia → Stan witryny** pokazuje, kiedy sprawdzanie terminów **naprawdę**
ostatnio się wykonało — jeśli stoi ponad 10 minut, zaświeci na czerwono z tą instrukcją.

### 7.4 Strona za pośrednikiem (Cloudflare / nginx jako proxy)
Jeśli strona stoi za pośrednikiem — np. Cloudflare albo nginx pracujący jako proxy — wszystkie zgłoszenia
mogą wyglądać dla systemu tak, jakby przychodziły z **jednego, tego samego adresu IP**. Ochrona formularza
przed spamem (limity zgłoszeń, patrz §5.1) liczy właśnie po adresie IP, więc w takiej sytuacji może
**zablokować zwykłych, prawdziwych klientów**, biorąc ich za jedno źródło. **Rozwiązanie:** osoba wdrażająca
system podpina filtr `mp_intake_client_ip`, żeby system czytał **prawdziwy adres klienta**, a nie adres
pośrednika. To jednorazowa konfiguracja przy wdrożeniu.

## 8. RODO (dane osobowe)

- Zgody klienta są zapisywane z treścią i wersją; klient może **wycofać zgodę** i **poprosić o usunięcie danych** z panelu.
- Usunięcie danych wymaga **dwóch kliknięć**: pierwsze pokazuje ekran z informacją, co zniknie, co
  zostaje i że operacji nie da się cofnąć — dopiero przycisk na tym ekranie ją wykonuje. Dzięki temu
  klient nie skasuje sobie danych przypadkiem (np. pudłem kciukiem na telefonie).
- **Wyjątek — wspólny adres e-mail** (np. sekretariat zgłaszający za kilka osób): system prowadzi
  wtedy **osobne kartoteki** dla każdej osoby, a samodzielna edycja i usuwanie danych z panelu są
  wyłączone — wniosek składa się wiadomością w sprawie i rozpatruje go pracownik (żeby jedna osoba
  nie usunęła danych drugiej).
- Wbudowane w mechanizmy WordPressa: **eksport** i **usuwanie** danych osobowych (Narzędzia → Eksport/Usuwanie danych osobowych).
- Usunięcie danych przy **aktywnej sprawie** jest **wstrzymywane** (dane potrzebne do obsługi) i wykonuje się po jej zamknięciu — z raportem co zostało zatrzymane i dlaczego.
- Historia zdarzeń sprawy jest **nieusuwalna, ale bez danych osobowych** (same fakty/daty/decyzje).
- **Porzucone zgłoszenia kasują się same.** Jeśli ktoś wypełni formularz i nigdy nie kliknie linku
  potwierdzającego, zgłoszenie po **30 dniach** znika razem z jego danymi kontaktowymi i załącznikami
  (link potwierdzający jest ważny 72 godziny, więc takie zgłoszenie i tak nie może już ruszyć).
  Sprawy **potwierdzone** — czyli realna praca serwisu — nie są przez to ruszane. Jeśli chcesz inny
  okres, powiedz: to jedna linijka w konfiguracji.

## 9. Najczęstsze pytania / kłopoty

| Problem | Rozwiązanie |
|---|---|
| Maile nie dochodzą / w spamie | Zainstaluj wtyczkę SMTP (§7.1) — to hosting, nie system. |
| Ktoś pobiera cudzy załącznik po linku (nginx) | Dodaj snippet nginx (§7.2). |
| „Brak uprawnień" na ekranach systemu | Sprawdź, czy użytkownik ma rolę personelu (§6). |
| Formularz nie wyświetla się na stronie | Upewnij się, że wtyczka Zgłoszenia jest **włączona** i strona „Zgłoszenie serwisowe" istnieje. |
| Zgłoszenia nie są nikomu przydzielane | Wejdź w **Automatyzacje MP → Kto dostaje zgłoszenia** i zapisz listę pracowników — dopóki jest pusta, sprawy nie mają właściciela. |
| „Stan witryny" świeci na czerwono | Otwórz **Narzędzia → Stan witryny** — każde nasze ostrzeżenie mówi wprost, co zrobić. Jeśli nie wiesz, jak to wykonać, patrz §10 niżej. |

## 10. Gdy coś nie działa — do kogo się zwrócić

Systemy dzielą się na trzy części i **każdą naprawia ktoś inny**. Zanim gdzieś zadzwonisz, ustal,
z którą masz kłopot:

| Objaw | Do kogo | Co powiedzieć |
|---|---|---|
| Cała strona nie działa · maile nie wychodzą · potrzebna kopia zapasowa · wersja PHP | **pomoc techniczna hostingu** | „Moja strona…" — hosting odpowiada za serwer, pocztę i kopie |
| Terminy nie są pilnowane w nocy · trzeba wkleić coś w konfigurację serwera (§7) | **hosting albo osoba wdrażająca** | prześlij rozdział 7 tej instrukcji |
| Ekran systemu pokazuje błąd · coś liczy się nie tak · brakuje funkcji | **twórca systemu (utrzymanie)** | podaj **numer sprawy** (np. `SRV/2026/0042`), co robiłeś i co się stało; jeśli możesz — zrzut ekranu |

⚠️ **Przy zgłaszaniu problemu z systemem podaj zawsze:** co widzisz w **Narzędzia → Stan witryny**
(zrzut ekranu wystarczy) oraz numer sprawy, przy której to wystąpiło. Bez tego naprawa zaczyna się
od zgadywania.

📌 **Kontakt do utrzymania systemu:** ustalany przy przekazaniu — wpisz go tutaj, żeby był pod ręką,
i przekaż osobom, które będą pracować w systemie:

```
Osoba/firma:  ......................................
E-mail:       ......................................
Telefon:      ......................................
Godziny:      ......................................
```

---
*Wersje w tej paczce: MP Service Intake · MP Warranty & Serial Registry · MP Workflow Automator — wszystkie w wersji **1.3.7**.*
