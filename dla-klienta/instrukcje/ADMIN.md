# Instrukcja: ADMINISTRATOR SYSTEMU

> Dla właściciela/administratora z rolą **Administrator systemu MP** (lub konta administratora WP).
> Masz wszystko, co koordynator (patrz `KOORDYNATOR.md`), plus rejestr produktów, import,
> wyjątki gwarancyjne i utrzymanie.

## 1. Instalacja i pierwsza konfiguracja

Krok po kroku w **`INSTRUKCJA-KLIENTA.md`** (instalacja 3 ZIP-ów, co powstaje automatycznie,
konfiguracja formularza, rejestru i Automatora, noty serwerowe: SMTP, nginx, systemowy cron).

### ⚠️ Zrób to zaraz po instalacji: wskaż, kto dostaje zgłoszenia

Świeżo zainstalowany system **nie przydziela spraw nikomu**, dopóki nie wskażesz pracowników.
Sprawy będą się poprawnie przyjmować, ale zostaną „nieprzydzielone".

1. **Użytkownicy → Dodaj nowego** — załóż konta pracownikom serwisu z rolą **„Pracownik serwisu"**.
2. **Automatyzacje MP** → przewiń pod tabelę reguł do sekcji **„Kto dostaje zgłoszenia"**.
3. Zaznacz osoby, między które system ma rozdzielać sprawy (po kolei, sprawiedliwie), i kliknij
   **Zapisz listę pracowników**.

Tę listę ustawia **wyłącznie administrator systemu** — koordynator widzi ostrzeżenie o pustej liście,
ale nie może jej zmienić. Kontrolnie: **Narzędzia → Stan witryny** przestanie zgłaszać pustą pulę,
a w tabeli reguł zamiast ostrzeżenia pojawią się imiona pracowników.

## 2. Rejestr produktów i gwarancji

**Rejestr MP** — baza produktów, numerów seryjnych, partii i okresów gwarancyjnych; wyszukiwarka
po serialu / kliencie / fakturze / modelu:

![Rejestr produktów](zdjecia/admin-04-rejestr.png)

**Import CSV** (Rejestr MP → Import) — porcjami, ze wznawianiem i raportem błędów per wiersz;
na ekranie jest przykładowy plik do pobrania i lista kolumn:

![Import CSV](zdjecia/admin-05-import-csv.png)

Produktu z **aktywną sprawą nie da się usunąć** (blokada integralności) — najpierw zamknij sprawę
albo zarchiwizuj produkt (archiwalny nie przyjmuje nowych zgłoszeń).

### Poprawianie danych produktu

![Poprawianie danych produktu](zdjecia/admin-04b-popraw-produkt.png)

Jeśli w pliku importu była pomyłka (najczęściej data gwarancji), kliknij przy produkcie
**„popraw dane"**. Możesz zmienić model, partię, kategorię, dokument zakupu, datę zakupu
i datę końca gwarancji. Daty przyjmujemy w formacie `RRRR-MM-DD` albo `DD.MM.RRRR`.

Co się dzieje po zapisaniu:

- **zmiana od razu wpływa na zgłoszenia** — jeśli poprawisz datę gwarancji, produkt przestaje
  być „po gwarancji" i kolejne zgłoszenia dostają właściwy status;
- **zmiana zapisuje się w historii produktu**: kto, kiedy i co poprawił (wartość przed i po).
  Wyjątek: przy dokumencie zakupu zapisujemy sam fakt zmiany bez treści — to dana osobowa;
- **numeru seryjnego nie da się zmienić.** To po nim sprawy klientów trzymają się produktu —
  podmiana przepisałaby cudzą historię serwisową na inny egzemplarz. Jeśli numer jest błędny,
  zarchiwizuj wpis i zaimportuj poprawny.

Odrzucimy zapis, gdy data jest niepoprawna albo gwarancja kończy się **przed** datą zakupu —
zobaczysz wtedy komunikat i wrócisz do formularza z wpisanymi danymi.

Produkt w archiwum jest zablokowany do edycji — najpierw go przywróć.

## 3. Wyjątki gwarancyjne (tylko Ty)

**Rejestr MP → Wyjątki** — ręczne przyznanie/cofnięcie gwarancji dla produktu lub konkretnej
sprawy (np. gest dobrej woli po terminie). Każdy wyjątek ma powód (notatka wewnętrzna — klient
jej nie widzi) i zostaje w historii produktu:

![Wyjątki gwarancyjne](zdjecia/admin-06-wyjatki.png)

## 4. RODO — obowiązki administratora

- Wnioski o **eksport/usunięcie danych**: wbudowane narzędzia WordPressa
  (**Narzędzia → Eksport / Usuwanie danych osobowych**) obejmują dane systemu serwisowego.
- Usuwanie = **anonimizacja**: dane osobowe znikają (także konto klienta i e-mail w zgodach),
  oś zdarzeń i statystyki zostają. Przy aktywnej sprawie — odroczenie do jej zamknięcia.
- **Wspólny adres wielu osób** (sekretariat): narzędzie WordPressa „Usuń dane osobowe" działa po adresie e-mail i obejmie wszystkie kartoteki
  z tego adresu — przed uruchomieniem potwierdź tożsamość i zakres wniosku.
- Retencja załączników i sprzątanie danych tymczasowych chodzą automatycznie (cron).

## 5. Utrzymanie

- **Narzędzia → Stan witryny** — 14 testów systemu (poczta zgłoszeń i automatu, załączniki, HTTPS, pula przydziału,
  wykonywanie się crona, sprawy poza automatyzacją…). Zielono = zdrowo; czerwono = instrukcja
  naprawy w treści testu.
- **Aktualizacje wtyczek**: standardowo przez ZIP; migracje bazy wykonują się same przy wejściu
  do panelu, crony odtwarzają się same. Przed aktualizacją na produkcji zrób kopię bazy
  (polityka: `dokumentacja-techniczna/MIGRATION_POLICY.md`).
- **Odinstalowanie** sprząta role systemowe (4 role), automatycznie założone strony (2), pliki
  załączników i zadania cykliczne. **16 tabel z danymi (klienci, sprawy, wiadomości, zgody)**
  oraz wpisy niepotwierdzonych zgłoszeń **zostają w bazie** — to świadoma decyzja, żeby
  przypadkowe odinstalowanie wtyczki nie skasowało danych biznesowych. Zostają też konta
  klientów założone przez system (bez roli). Uwaga: narzędzie do kasowania tych danych
  (obsługa wniosków RODO) znika razem z wtyczką — jeśli firma chce dane klientów usunąć,
  trzeba to zrobić **przed** odinstalowaniem, nie po.
