# SECURITY.md — model bezpieczeństwa MP Service Suite

> Kontrakt D2 (macierz ról/capabilities) + wynik przeglądu bezpieczeństwa.
> Zasada: **nonce = CSRF · capability = autoryzacja · ownership = IDOR**. Trzy warstwy, rozdzielone.
>
> ℹ️ **O ścieżkach typu `testy/e2e/…`, `build/…`, `lib/mp-common/…` w tym i sąsiednich dokumentach:**
> to pliki z **repozytorium dostawcy**, a nie z paczki, którą dostajesz. Podajemy je, żeby było
> wiadomo, czym konkretnie dana gwarancja jest sprawdzana przy każdej zmianie. Jeśli chcesz je
> obejrzeć albo uruchomić u siebie — poproś o dostęp do repozytorium.

## 1. Role i capabilities

4 dedykowane role (wspólne dla 3 wtyczek; slug = własna cap-marka; kod sprawdza WYŁĄCZNIE capability, nigdy nazwę roli):

| Rola | Slug | Cap-marka | Zakres |
|------|------|-----------|--------|
| Administrator systemu MP | `mp_system_admin` | `mp_system_admin` | pełny: import, wyjątki gwarancyjne, archiwum produktów |
| Koordynator serwisu | `mp_coordinator` | `mp_coordinator` | koordynacja spraw (personel) |
| Pracownik serwisu | `mp_agent` | `mp_agent` | obsługa spraw, panel niepotwierdzonych |
| Klient MP | `mp_client` | `mp_client` | WYŁĄCZNIE własne sprawy (panel „moje zgłoszenia") |

- **STAFF_CAPS** = `mp_system_admin`, `mp_coordinator`, `mp_agent`. Wbudowany `administrator` WP dostaje te cap-marki przy aktywacji (bez nich nie widziałby ekranów mp_*); zdejmowane przy uninstall.
- `mp_client` świadomie POZA STAFF_CAPS — nie ma dostępu do żadnego ekranu/endpointu personelu.

## 2. Macierz endpointów (autoryzacja)

### Publiczne (bez capability — z założenia; zabezpieczone tokenem/nonce)
| Endpoint | Mechanizm |
|----------|-----------|
| `mp_intake_submit` | nonce (CSRF) + honeypot + pułapka czasu + rate-limit + zgoda RODO |
| `mp_intake_verify` (GET) | renderuje TYLKO formularz — nie mutuje |
| `mp_intake_verify_confirm` (POST) | nonce + token jednorazowy (weryfikacja atomowa) |
| `mp_intake_login_request` / `mp_intake_login` / `mp_intake_login_confirm` | passwordless: token jednorazowy (selector+hash), POST-confirm; WYŁĄCZNIE `mp_client` bez uprawnień personelu |

### Klient (zalogowany — autoryzacja przez OWNERSHIP, nie capability)
| Endpoint | Mechanizm |
|----------|-----------|
| `mp_intake_message` | login + nonce + **ownership** (`case_id` ∈ sprawy zalogowanego) |
| `mp_intake_update_contact` | login + nonce (dotyka tylko rekordów bieżącego usera) |
| `mp_intake_withdraw` | login + nonce (tylko własne zgody/dane) |
| `mp_intake_attachment` | nonce + **ownership** (`Attachments::can_access`: personel LUB właściciel sprawy) |

### Personel (capability W PARZE z nonce)
| Endpoint | Wymagana capability |
|----------|---------------------|
| `mp_intake_resend` | `mp_agent` |
| `mp_import_upload` · `mp_import_report` · `mp_import_batch` (ajax) · `mp_import_reclaim` (ajax) | `mp_system_admin` |
| `mp_exception_add` · `mp_exception_revoke` | `mp_system_admin` |
| `mp_product_archive` · `mp_product_restore` | `mp_system_admin` |
| `mp_automator_pool_config` (pula pracowników reguły przydziału) | `mp_system_admin` |
| Ekran „Rejestr MP" (lista produktów) | `mp_agent` lub `mp_system_admin` |

## 3. Macierz NEGATYWNA (kto NIE może → 403)

Każdy endpoint personelu jest zarejestrowany także jako `nopriv` → ten sam handler; capability/nonce odrzuca nieuprawnionego zanim wykona się jakakolwiek akcja. **Wynik zweryfikowany testem** `testy/e2e/c-dod-security-matrix.sh`:

| Endpoint (admin-post + ajax) | anon | subscriber | mp_client |
|------------------------------|------|-----------|-----------|
| wszystkie endpointy personelu (9 w Intake + 4 AJAX Automatora) | **403** | **403** | **403** |

Żadna nieuprawniona rola nie wykonuje akcji ani nie odczytuje cudzych danych.

## 4. Załączniki — deny katalogu jest SERWER-ZALEŻNY (flaga #4)

- Katalog `uploads/mp-attachments/` ma `.htaccess deny` + `index.php` — **działa TYLKO na Apache/LiteSpeed. nginx `.htaccess` IGNORUJE.**
- **Realna brama** (każdy serwer) = odczyt WYŁĄCZNIE przez endpoint PHP `mp_intake_attachment` z nonce + ownership. Bezpośredni URL pliku na nginx nie jest chroniony `.htaccess`.
- **Nota dla wdrożenia na nginx** — dodaj do konfiguracji serwera:
  ```nginx
  location ^~ /wp-content/uploads/mp-attachments/ { deny all; return 403; }
  ```

## 5. Uploady

- MIME rozpoznawany po TREŚCI (`finfo`) — ZERO fallbacku po nazwie; brak `ext-fileinfo` = odmowa przyjęcia (admin-notice przy aktywacji).
- Dozwolone formaty (lista zamknięta): JPG/PNG/WebP/PDF. Limity: rozmiar per plik + liczba per zgłoszenie (konfigurowalne). Losowe nazwy bez rozszerzeń.
- EXIF/metadane obrazów czyszczone przy uploadzie. **PDF świadomie BEZ strip-EXIF** — reenkoder obrazów nie dotyczy PDF; PDF przechodzi jak jest (brak biblioteki sanityzacji PDF w zakresie; ryzyko = zaufany klient serwisu, nie publiczny upload anonimowy — sprawa jest weryfikowana mailowo).

## 6. Dane / SQL / wyjścia

- SQL: `$wpdb->prepare` wszędzie; `esc_like` na wyszukiwarce; ZERO twardych prefiksów `wp_` (linter tabel w CI = 0).
- **Nazwy WŁASNYCH tabel** (`{$table}` z `Tables::full()` = prefiks + stała, ZERO wejścia użytkownika) są interpolowane —
  WordPress nie pozwala przepuścić nazwy tabeli przez `prepare` (tylko wartości). To standardowy, bezpieczny wzorzec
  z adnotacją `phpcs:disable … InterpolatedNotPrepared -- tabela wlasna`. ⚠️ Narzędzie **`plugin-check`** (osobne od PHPCS)
  mimo to **zgłasza to jako ostrzeżenie** (nie honoruje `phpcs:disable`) — **znany false-positive, zero ryzyka SQL**.
  Opcjonalna modernizacja gdyby wymagany był czysty plugin-check: placeholder `%i` na identyfikatory (`$wpdb->prepare`, WP 6.2+).
- Wejścia: `sanitize_*` / `absint` przy każdym `$_POST/$_GET`. Wyjścia: `esc_html/esc_attr/esc_url` przy każdym echo (WPCS w CI).
- **Rate-limit zgłoszeń liczy WŁASNA TABELA** `wp_mp_rate_counters` (`Tables::RATE_COUNTERS`) — wszystkie liczniki,
  rezerwacje dedup i ich sprzątanie idą przez nią (`RateLimit.php`: `:181`, `:265`, `:395`, `:415`, `:620`, `:658`).
  **Wynik nie zależy od object-cache**, bo nic tu nie przechodzi przez transienty ani `wp_options` — progi kalibruje się
  na tej tabeli i na demo, i pod persistent object-cache, i dostaje się ten sam wynik.
  ⚠️ **Wersja transientowa to PRZESZŁOŚĆ, nie plan**: została zastąpiona właśnie dlatego, że pod object-cache omijała bazę —
  „dawny transientowy read-modify-write przepuszczał N żądań" (`RateLimit.php:16`), „dawny transientowy check-then-set"
  (`:20`), „rezerwacja w tabeli (nie transient…)" (`:119`). Atomową bramką przed utworzeniem sprawy jest `claim_submission`.

## 6b. Nagłówki bezpieczeństwa stron wtyczki

Strony formularza i panelu klienta dostają nagłówki ochronne (`X-Content-Type-Options: nosniff`,
`X-Frame-Options`, `Content-Security-Policy: frame-ancestors`, `Referrer-Policy`, a panel klienta
dodatkowo `X-Robots-Tag: noindex` i `Cache-Control: no-store`). Nagłówki idą na KAŻDĄ stronę
z formularzem — także tę, którą klient zrobił sam, wstawiając shortcode (wcześniej trafiały
wyłącznie na stronę zakładaną przez wtyczkę).

Zestaw jest nadpisywalny filtrem **`mp_intake_security_headers`** — wdrożenie za CDN/proxy,
które ustawia własne nagłówki, może je tu przyciąć zamiast walczyć z duplikatami.

## 7. Rate-limit — progi i źródło IP za reverse-proxy (flaga #10)

### Progi domyślne — formularz zgłoszenia

Ochrona jest **warstwowa**: trzy niezależne liczniki, wystarczy przekroczyć jeden. Wartości
domyślne (`RateLimit::limits()`), nadpisywalne filtrem **`mp_intake_rate_limits`**:

| Licznik | Próg | Okno | Po co |
|---|---|---|---|
| **na adres IP** | 10 zgłoszeń | 10 minut | zalew z jednego źródła |
| **na adres e-mail** | 3 zgłoszenia | 24 godziny | zapychanie kolejki jednym kontem |
| **na numer seryjny** | 5 zgłoszeń | 24 godziny | wielokrotne zgłaszanie tego samego produktu |

Osobno działa **twarda deduplikacja**: identyczne zgłoszenie (ten sam numer seryjny, e-mail
i rodzaj sprawy) w oknie **15 minut** nie zakłada nowej sprawy — to nie jest rate-limit, tylko
ochrona przed podwójnym kliknięciem „wyślij".

⚠️ **Przy testowaniu formularza** próg **3 zgłoszeń na dobę z jednego adresu e-mail** zostanie
osiągnięty szybciej, niż się spodziewasz. Czwarta próba dostaje odmowę — to działająca ochrona,
nie awaria. Do testów używaj różnych adresów e-mail albo podnieś progi wspomnianym filtrem.

### Progi domyślne — logowanie klienta

- Rate-limit po IP liczy **domyślnie `$_SERVER['REMOTE_ADDR']`** — bezpieczna domyślka (`RateLimit::client_ip()`).
- **Żądania magic-linku (logowanie) też są rate-limitowane** (`RateLimit::check_login`, osobne liczniki od formularza): domyślnie **5 żądań / 15 min na IP** i **5 / godz. na e-mail** — chroni skrzynki klientów przed zalewem linkami i endpoint przed nadużyciem (OWASP anti-automation). Komunikat NEUTRALNY (zero enumeracji kont). Progi nadpisywalne filtrem `mp_intake_login_rate_limits`; źródło IP jak niżej (`mp_intake_client_ip`).
- **Za reverse-proxy / Cloudflare** wszyscy klienci mają IP proxy = **jeden adres** → domyślny rate-limit po IP zablokowałby wszystkich naraz. (Warstwy e-mail/serial działają dalej niezależnie od IP.)
- **Nota dla wdrożenia za proxy** — podłącz filtr `mp_intake_client_ip` do **ZAUFANEGO** źródła IP. Kod celowo **nie ufa ślepo `X-Forwarded-For`** (nagłówek spoofowalny) — to decyzja wdrożenia, nie domyślka kodu. Przykład (odczyt tylko z zaufanego proxy, ostatni hop):
  ```php
  // mu-plugin / theme functions.php — TYLKO gdy przed WP stoi ZAUFANY proxy.
  add_filter( 'mp_intake_client_ip', function ( $ip ) {
      // Cloudflare podaje realny IP w CF-Connecting-IP; XFF bierz OSTATNI wpis
      // (dopisany przez własny proxy), nie pierwszy (podany przez klienta).
      if ( ! empty( $_SERVER['HTTP_CF_CONNECTING_IP'] ) ) {
          return sanitize_text_field( wp_unslash( $_SERVER['HTTP_CF_CONNECTING_IP'] ) );
      }
      return $ip; // brak zaufanego nagłówka → REMOTE_ADDR (domyślka).
  } );
  ```

## 8. Wspólny adres e-mail wielu osób (skrzynka sekretariatu) — model tożsamości

- **Tożsamość klienta = e-mail + nazwisko**, nie sam e-mail (`Customers::upsert_by_email`
  + `same_person`). Druga osoba pisząca z tego samego adresu (sekretariat, recepcja, rodzina)
  dostaje **osobny rekord klienta**: jej zgłoszenie nie nadpisuje danych pierwszej osoby
  i nie dokleja się do jej historii. Ta sama osoba (różnice wielkości liter/spacji
  w nazwisku) trafia do swojego istniejącego rekordu.
- **Usunięcie danych jest dwustopniowe**: `mp_intake_withdraw` niczego nie zmienia — przekierowuje
  na ekran potwierdzenia (co zniknie / co zostaje / operacja nieodwracalna). Operację wykonuje
  dopiero `mp_intake_withdraw_confirm`, z **własnym nonce**, więc token pierwszego kroku nie
  wystarcza. Powód: przycisk sąsiadował z „Zapisz dane" i jedno pudło kciukiem kasowało dane
  nieodwracalnie. Ten sam wzorzec, co przy potwierdzaniu zgłoszenia i logowaniu linkiem (GET nie
  zmienia stanu). Test pilnujący: `testy/e2e/c27-rodo-potwierdzenie.sh`.
- **Samoobsługa danych na koncie współdzielonym jest wyłączona**: gdy konto WP obsługuje
  więcej niż jeden rekord klienta, panel chowa formularze edycji danych i „Wycofaj zgodę
  i usuń moje dane", a POST-y odmawiają **po stronie serwera** (także ze starym, ważnym
  nonce). Powód: jedna osoba nie może jednym klikiem skasować ani nadpisać danych drugiej.
  Wniosek RODO przechodzi wtedy przez człowieka — wiadomość w sprawie albo wbudowany
  eraser WP uruchamiany przez administratora (per osoba, po potwierdzeniu tożsamości).
- **Świadoma granica**: kto ma dostęp do skrzynki, ten odczyta każdy magic-link — przy
  logowaniu przez e-mail współdzielona skrzynka oznacza współdzielony **podgląd** listy
  spraw (jak w każdym systemie z resetem hasła przez e-mail). Chronimy to, co da się
  chronić po stronie aplikacji: dane kontaktowe drugiej osoby nie są prezentowane
  w formularzach, a operacje modyfikujące/kasujące są zablokowane. Dowód: e2e
  `testy/e2e/c19-wspolny-email.sh` (CI).
