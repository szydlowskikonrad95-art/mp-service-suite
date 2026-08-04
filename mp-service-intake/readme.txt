=== MP Service Intake ===
Requires at least: 6.0
Tested up to: 7.0
Requires PHP: 8.1
Stable tag: 1.3.11
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Service and warranty claim intake: dynamic request form, SRV case numbers, customer account, RODO/GDPR tools, spam protection.

== Description ==

Accepts service and warranty requests through a front-end form embedded on a WordPress page. Form fields and required attachments adapt to the request type (complaint, repair, technical question, return) and product category. Every case receives a race-safe SRV/YYYY/NNNN number.

Key features:

* Dynamic front-end form (Gutenberg block + `[mp_intake_form]` shortcode) with per-type validation.
* E-mail verification of every submission (one-time magic link, confirmed by a button — a plain link preview never confirms the case).
* Customer account (`mp_client`) with passwordless login: live case status, message history, contact-data editing (GDPR art. 16), and self-service consent withdrawal + data erasure (GDPR art. 7(3)/17).
* Hardened attachments: MIME detected by content (`finfo`), size/count limits, EXIF stripped from images, per-file ownership check on every download.
* Spam protection: honeypot, time trap, layered rate-limit (IP / e-mail / serial) and a hard 15-minute duplicate guard.
* Staff screen for unverified submissions (fix e-mail + resend a fresh link, throttled) with an operation audit log.
* GDPR eraser + exporter wired into WordPress privacy tools; consent text is frozen per row for accountability.

Part of the MP Service Suite (three cooperating plugins; each one also works standalone in a reduced mode, never causing fatal errors). The plugin UI and e-mails are in Polish (source language); every string is internationalized via the text domain, so the plugin can be translated to other languages. No separate .po/.mo is bundled because Polish is the base language.

== Requirements ==

* WordPress 6.x (6.0 or newer)
* PHP 8.1 or newer
* MySQL 8.0+ or MariaDB 10.6+
* HTTPS -- the suite handles passwordless (magic-link) login and customer personal data.
* WP-Cron enabled -- scheduled tasks rely on it: SLA deadlines, reminders and escalations (Workflow Automator), background CSV imports (Registry) and data-retention cleanup (Intake).

Developed and tested on WordPress 6.9.4, PHP 8.1-8.5, MariaDB 11.8.

== Installation ==

1. Upload the plugin ZIP in **Plugins → Add New → Upload Plugin**, then activate it.
2. Activation creates two pages automatically: the request form (`Zgłoszenie serwisowe`) and the customer panel (`Panel zgłoszeń`). You can move or rename them.
3. Set **Settings → General → Site Language** to Polish and the timezone to `Europe/Warsaw` so dates and messages display correctly.
4. Make sure your hosting can send e-mail (see the FAQ) — the plugin relies on `wp_mail()` for verification and login links.
5. The PHP extension `fileinfo` must be enabled for attachments (the plugin shows an admin notice if it is missing).

== Frequently Asked Questions ==

= Verification / login e-mails do not arrive =

The plugin sends e-mail through WordPress `wp_mail()`. Reliable delivery is the responsibility of your hosting / an SMTP plugin — install and configure an SMTP plugin (e.g. one that points to your provider's SMTP server). Without working outgoing mail, customers cannot confirm submissions or log in.

= Are attachment files protected from direct URL access? =

Yes on **Apache / LiteSpeed** (a `.htaccess deny` is written to the upload folder). **nginx ignores `.htaccess`** — on nginx add a server rule:
`location ^~ /wp-content/uploads/mp-attachments/ { deny all; return 403; }`
Regardless of the web server, files are always served through a PHP endpoint that checks ownership, so the direct URL is only a secondary layer. See `dokumentacja-techniczna/SECURITY.md`.

= What does this plugin NOT do? =

* It does **not** deliver e-mail by itself — that depends on your hosting/SMTP.
* It does **not** strip metadata from PDF attachments (only images are re-encoded/cleaned).
* It does **not** run the workflow automation (auto-assignment, SLA, status e-mails) — that is the separate *MP Workflow Automator* plugin.
* Its rate-limit uses transients; under a persistent object cache the counters live in the cache rather than the database.

== Changelog ==

= 1.3.11 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.
  Jedyna poprawka tego wydania dotyczy ekranu „Wyjątki gwarancyjne" w module Rejestr MP.

= 1.3.10 =
* Komunikat na karcie sprawy cytuje nazwę roli DOKŁADNIE tak, jak brzmi ona na liście
  użytkowników („Pracownik serwisu MP", nie „Pracownik serwisu") — administrator szukający
  cytowanej nazwy znajdzie ją teraz bez zgadywania.
* Kontrola jakości pilnująca nazw ról obejmuje teraz TAKŻE napisy w kodzie, nie tylko dokumenty
  — poprzednio te same błędne cytaty przeżyły poprawkę dokumentów.
* Działanie wtyczki bez zmian — wydanie językowe. Pozostałe poprawki językowe tego wydania
  (nagłówek kolumny w tabeli statusów, etykieta przycisku w Rejestrze zdarzeń) dotyczą modułu
  Automatyzacja MP.

= 1.3.9 =
* Instrukcja wdrozenia: nowy krok „schowaj formularz na czas przygotowan". Strona zgloszenia jest
  publiczna od chwili wlaczenia wtyczki, a instrukcja nie mowila, jak ja tymczasowo ukryc — przez
  co zgloszenie moglo trafic do systemu, zanim rejestr gwarancji i pula pracownikow byly gotowe.
* Dokumentacja: poprawiona sprzeczna liczba testow diagnostyki (bylo „42 testy" w jednym akapicie
  README, jest czternascie — tyle, ile wtyczki realnie rejestruja w Stanie witryny).
* Kontrola dokumentow w CI sprawdza teraz SPOJNOSC liczb w calym pliku, a nie tylko obecnosc
  poprawnej liczby w jednym miejscu (poprzednia wersja przepuszczala blad opisany wyzej).
* Dzialanie wtyczek bez zmian — wydanie dokumentacyjne.

= 1.3.8 =
* Wydanie zbiorcze pakietu: bez zmian w kodzie tego modułu, numer wersji podniesiony razem
  z pozostałymi. Poprawki językowe tego wydania dotyczą ekranów importu i wyjątków gwarancyjnych
  w module Rejestr MP oraz ekranów modułu Automatyzacja MP.
* Instrukcje (materiał wspólny dla pakietu): poprawione nazwy pozycji menu i filtrów (były
  nieaktualne względem panelu), dodany opis pól podstawianych w szablonach odpowiedzi oraz
  prawidłowa droga do wyjątków gwarancyjnych. Odświeżone zdjęcia w instrukcji administratora.

= 1.3.7 =
* Zmiana wylacznie w dokumentacji: raport dostepnosci (WCAG 2.1 AA) zostal powtorzony na
  paczce 1.3.6 pobranej z wydania, na WordPressie 7.0 i innym motywie. Wynik ten sam: zero
  naruszen na wszystkich trzech ekranach klienta. W kodzie wtyczki bez zmian.

= 1.3.6 =
* Zmiany wylacznie w instrukcjach dla klienta: wyjasnione SLA, anonimizacja, blokada
  integralnosci i link do zalogowania; §7.1 (SMTP) dostal gotowa tresc wiadomosci do dostawcy
  poczty. Poprawiony jeden zrzut ekranu (data po polsku). W kodzie wtyczki bez zmian.

= 1.3.5 =
* Listy w panelu (sprawy, produkty) pobieraja dane jednym zapytaniem na strone zamiast
  jednego na kazdy wiersz. Ekran spraw zszedl z 43 do 4 zapytan do bazy. Wyglad i dzialanie
  ekranow bez zmian.
* Poprawki w instrukcji: nazwa ekranu w menu (MP: Sprawy), opis ekranu MP: Niepotwierdzone,
  ostrzezenie przy poleceniu kopii bazy dla PIERWSZEJ instalacji.

= 1.3.4 =
* Wydanie porzadkowe dokumentacji: dwa zdania w dokumentacji technicznej opisywaly
  zabezpieczenia szerzej, niz robi to kod (automatyczne generowanie testow z kontraktu
  oraz test wspolbieznosci na 20 procesach). Zdania poprawiono tak, by opisywaly stan
  faktyczny. **Zero zmian w kodzie wtyczek.**

= 1.3.3 =
* Wydanie porzadkowe: dokument opisujacy kontrole jakosci deklarowal numer poprzedniej wersji.
  Kontrola wersji w skrypcie pakujacym obejmuje teraz WSZYSTKIE dokumenty dla klienta (wczesniej
  dwa wpisane z nazwy) i liczy, ile plikow objela.

= 1.3.2 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.3.1 =
* Odinstalowanie wtyczki kasuje teraz także opcję techniczną z flagą awarii wysyłki poczty
  (`mp_intake_mail_alert`) — wcześniej zostawała w bazie jako osierocony wpis.

= 1.3.0 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.5 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.4 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.3 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.2 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.1 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.2.0 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.1.0 =
* Wydanie zbiorcze pakietu: bez zmian w tym module, numer wersji podniesiony razem z pozostałymi.

= 1.0.3 =
* Paczka zawiera teraz część techniczną dla programisty (układ bazy, kontrakt między modułami, model zdarzeń, maszyna statusów, bezpieczeństwo) oraz źródła diagramów do edycji. Bez zmian w kodzie tego modułu.

= 1.0.2 =
* Wydanie porządkujące paczkę dla klienta: ujednolicona wersja w dokumentach i przegenerowany zrzut ekranu. Bez zmian w kodzie tego modułu.

= 1.0.1 =
* Dokument zakupu i data zakupu są porównywane z rejestrem — zgłoszenie z cudzym numerem seryjnym i zmyśloną fakturą nie dostaje już statusu „gwarancja aktywna".
* Karta sprawy pokazuje status TEJ sprawy (decyzję z chwili zgłoszenia) wraz z powodem niezgodności, a nie bieżący stan produktu w rejestrze.
* Załącznik zależny od kategorii: AGD drobne i elektronarzędzia wymagają zdjęcia tabliczki znamionowej. Wymóg spełnia tylko plik, który przejdzie kontrolę.
* Wybrana kategoria wraca do formularza po błędzie — wcześniej znikała razem z polami kategorii.
* Lista „Przydziel do" zawiera wyłącznie pracowników serwisu; nieudany przydział podaje powód.
* Komunikat o zbyt dużym pliku podaje limit obowiązujący na tym serwerze zamiast rady „spróbuj ponownie".
* Uszkodzone zdjęcie nie zostawia już ostrzeżeń PHP w dzienniku strony (plik ucięty przy wysyłce przechodził kontrolę typu, ale nie dawał się odczytać przy usuwaniu danych EXIF).

= 1.0.0 =
* Pierwsze wydanie dla klienta.
* Awaria wysyłki maila zostawia ślad na sprawie i alert w Narzędzia → Stan witryny (dotąd była całkowicie niewidoczna: klient nie dostawał linku, a panel milczał).
* Sprawy potwierdzone przy wyłączonym module automatyzacji są doszywane automatycznie (nie zostają bez przydziału i terminu).
* RODO: porzucone zgłoszenia niepotwierdzone znikają wraz z danymi kontaktowymi i załącznikami po 30 dniach (próg zmienia filtr).
* Zamknięta sprawa nie przyjmuje już przydziału ani zmiany pilności.
* Formularz działa także na hostingu bez rozszerzenia mbstring.
* Numer sprawy w formacie ze specyfikacji: SRV/RRRR/NNNN.
* Sprzątanie starych danych odtwarza się samo, gdy zadanie cykliczne zniknie z WordPressa; Stan witryny ostrzega, gdy go brakuje.

= 0.5.0 =
* Karta pracy personelu „MP: Sprawy" (lista spraw + karta: status/odpowiedź/przydział/checklista/oś czasu), sekcja Produkt i gwarancja. Numer sprawy w formacie SRV/RRRR/NNNN.

= 0.4.0 =
* Contract functions for the Workflow Automator: case context, assignment, status change (optimistic-lock), paginated cases query (role-aware, minimized), checklist authorization (ownership + event), read-only status list.
* Submission form now dynamic by case type client-side (all fields in DOM; return-reason works first time).
* Guarantee exceptions recorded on the case timeline (EXCEPTION_APPLIED/REVOKED, NO-PII).
* Rate-limit by real client IP (mp_intake_client_ip filter) for reverse-proxy/Cloudflare setups.
* GDPR fix: correct terminal status "zamknięte" so erasure is no longer deferred indefinitely.
* Client front polish (admin bar hidden for clients, CSS, panel CTA) + panel WCAG contrast ≥ 4.5:1.

= 0.3.0 =
* Customer account + passwordless login + panel (live status, message history).
* GDPR: contact-data editing (art. 16), self-service consent withdrawal + erasure (art. 7(3)/17), eraser/exporter, consent e-mail redaction on erasure.
* Verification hardened to POST-confirm (mail scanners no longer auto-confirm).
* Spam protection: layered rate-limit + hard duplicate guard.
* Serial reuse flag (`possible_duplicate`) for recent verified cases of the same product.
* Staff screen for unverified submissions: fix e-mail + resend (throttled) + operation audit log.
* Safe upgrade without reactivation (schema migrates on admin load).

= 0.1.0 =
* Plugin skeleton: OOP bootstrap, lifecycle (activation/deactivation/uninstall), shared mp_* roles, i18n.
