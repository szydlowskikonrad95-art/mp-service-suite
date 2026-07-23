# SECURITY.md — model bezpieczeństwa MP Service Suite

> Kontrakt D2 (macierz ról/capabilities) + wynik security-sweepu (DoD C §3).
> Zasada: **nonce = CSRF · capability = autoryzacja · ownership = IDOR**. Trzy warstwy, rozdzielone.

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
| Ekran „Rejestr MP" (lista produktów) | `mp_agent` lub `mp_system_admin` |

## 3. Macierz NEGATYWNA (kto NIE może → 403)

Każdy endpoint personelu jest zarejestrowany także jako `nopriv` → ten sam handler; capability/nonce odrzuca nieuprawnionego zanim wykona się jakakolwiek akcja. **Wynik zweryfikowany testem** `testy/e2e/c-dod-security-matrix.sh`:

| Endpoint (admin-post + ajax) | anon | subscriber | mp_client |
|------------------------------|------|-----------|-----------|
| wszystkie 9 endpointów personelu | **403** | **403** | **403** |

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
- Whitelist: JPG/PNG/WebP/PDF. Limity: rozmiar per plik + liczba per zgłoszenie (konfigurowalne). Losowe nazwy bez rozszerzeń.
- EXIF/metadane obrazów czyszczone przy uploadzie. **PDF świadomie BEZ strip-EXIF** — reenkoder obrazów nie dotyczy PDF; PDF przechodzi jak jest (brak biblioteki sanityzacji PDF w zakresie; ryzyko = zaufany klient serwisu, nie publiczny upload anonimowy — sprawa jest weryfikowana mailowo).

## 6. Dane / SQL / wyjścia

- SQL: `$wpdb->prepare` wszędzie; `esc_like` na wyszukiwarce; ZERO twardych prefiksów `wp_` (linter tabel w CI = 0).
- **Nazwy WŁASNYCH tabel** (`{$table}` z `Tables::full()` = prefiks + stała, ZERO wejścia użytkownika) są interpolowane —
  WordPress nie pozwala przepuścić nazwy tabeli przez `prepare` (tylko wartości). To standardowy, bezpieczny wzorzec
  z adnotacją `phpcs:disable … InterpolatedNotPrepared -- tabela wlasna`. ⚠️ Narzędzie **`plugin-check`** (osobne od PHPCS)
  mimo to **zgłasza to jako ostrzeżenie** (nie honoruje `phpcs:disable`) — **znany false-positive, zero ryzyka SQL**.
  Opcjonalna modernizacja gdyby wymagany był czysty plugin-check: placeholder `%i` na identyfikatory (`$wpdb->prepare`, WP 6.2+).
- Wejścia: `sanitize_*` / `absint` przy każdym `$_POST/$_GET`. Wyjścia: `esc_html/esc_attr/esc_url` przy każdym echo (WPCS w CI).
- Rate-limit zgłoszeń na transientach — pod persistent object-cache może różnić się od DB (na demo bez cache liczy z `wp_options`); twardsza gwarancja = własna tabela (poza zakresem anty-spamu P1.6).

## 7. Rate-limit — źródło IP za reverse-proxy (flaga #10)

- Rate-limit po IP liczy **domyślnie `$_SERVER['REMOTE_ADDR']`** — bezpieczna domyślka (`RateLimit::client_ip()`).
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
