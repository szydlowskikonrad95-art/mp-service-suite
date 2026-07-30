# Zakres sprawdzony — i czego nie sprawdzono

Ten dokument istnieje po to, żeby **nie sprawdzać dwa razy tego samego** i żeby było jasne,
gdzie przebiega granica. Każda pozycja niżej ma za sobą wykonanie na działającym systemie,
nie przeczytanie kodu.

## Instalacja i aktualizacja

- **Paczka pobrana z opublikowanego wydania**, zainstalowana na czystym WordPressie na
  deklarowanym minimum (PHP 8.1 / MySQL 8): ścieżka klienta **20/0**, wgranie przez panel **6/0**
- **Aktualizacja ze starszej wersji na żywych danych: zero różnic** — suma kontrolna treści
  identyczna, numeracja spraw kontynuowana bez przerwy, wcześniej zaimportowany produkt
  rozpoznany, zero błędów w dzienniku
- **Odinstalowanie**: role, zadania cykliczne, strony i pliki znikają; dane w tabelach zostają
  (świadomie — usunięcie danych klienta wymaga jego decyzji). Po odinstalowaniu **czysta
  ponowna instalacja** działa
- **Awaria w połowie migracji.** Symulacja prawdziwej awarii: wersje schematu cofnięte, tabele
  zostawione w stanie pośrednim. Po zwykłym wejściu do panelu migracja **dokończyła się sama**,
  suma kontrolna treści identyczna, zero błędów. Obietnica z polityki migracji potwierdzona
  wykonaniem, nie deklaracją

## Bezpieczeństwo — audyt prowadzony jak atak

- Ekrany **bez logowania**, konto **bez uprawnień** na pięciu ekranach, wejście bokiem przez
  podmianę numeru w adresie (5 wariantów), interfejs REST, żądania bez uwierzytelnienia,
  katalog załączników, jednorazowy token logowania → **zero wycieku**
- **Izolacja danych klientów potwierdzona**: przy dwóch sprawach dwóch różnych osób pierwszy
  klient **nie widzi ani numeru sprawy, ani treści** drugiego
- Jednorazowość linku logowania: **link zużyty zwraca odmowę** „link wygasł lub został już
  użyty"; ważność 20 minut; kliknięcie w link **samo nie loguje** — jest przycisk potwierdzenia,
  bo skanery poczty otwierają odnośniki samoczynnie
- **Numeru seryjnego produktu nie da się podmienić** — obsługa formularza w ogóle nie czyta tego
  pola z przesłanych danych. Obietnica instrukcji jest właściwością kodu, nie deklaracją
- **Uprawnienia do wyjątków gwarancyjnych**: pracownik zablokowany, koordynator zablokowany,
  **zero wpisów w bazie** po obu próbach; administrator przechodzi

## RODO

- Eksport danych w trzech grupach, **anonimizacja zweryfikowana w 6 tabelach**
- Wstrzymanie usunięcia przy aktywnej sprawie, z odroczeniem do jej zamknięcia
- Retencja załączników: świeże nietknięte, przeterminowane skasowane — sprawdzone przez
  przesunięcie czasu, nie przez przeczytanie ustawienia

## Działanie systemu

- Rejestr: import z pliku CSV, normalizacja kategorii i dat, **cztery statusy gwarancji**
- Automat: przydział po kolei, termin 24 h z przypomnieniem po 75% czasu, **eskalacja do
  koordynatora**, 7 statusów, odrzucenie wymagające powodu, wznowienie tylko do właściwego stanu
- Eksport zestawień: koordynator i administrator tak, pracownik nie — **także przy próbie
  z podkradzionym zabezpieczeniem formularza**
- **Historia zmian produktu ma komplet**: kto, kiedy, wartość przed i po
- **Migawka starej sprawy pozostaje nietknięta** po poprawieniu danych produktu — sprawa złożona
  przy poprzedniej gwarancji zachowuje swój ówczesny stan, żeby dało się pokazać „dane poprawiono
  po zgłoszeniu"
- Checklisty: cztery typy spraw, kroki po polsku; odhaczenie zapisuje **kto i kiedy**
- Szablony wiadomości: 8 sztuk, w obie strony

## Skala i współbieżność

- Import **50 000 wierszy**: wszystkie przyjęte, 51,6 s, szczyt pamięci **59 MB**
- **50 000 produktów**: ekran rejestru **41 ms**, wyszukanie po numerze seryjnym **0,2 ms**
- **20 równoległych procesów** nadających numery spraw → 20 unikalnych numerów, **zero duplikatów**
- Współistnienie z obcymi wtyczkami (edytor klasyczny, wtyczka poczty, pamięć podręczna)

## Dane brzegowe

- Polskie znaki, emoji, znacznik skryptu, apostrof, cudzysłów, znaki nowej linii → zapisane
  i odczytane bez uszkodzenia; tekst przekraczający limit odrzucony
- Formuły w eksporcie (`=`, `+`, `-`, `@`) unieszkodliwione; polskie znaki przepuszczone bez
  fałszywych trafień
- Plik PHP podszyty pod obrazek: zgłoszenie nie powstało, plik nie trafił na dysk

---

## Co zostało otwarte — świadomie

Trzy rzeczy, żadna nie wpływa na poprawność działania:

1. **Jedno miejsce z nadmiarowymi zapytaniami do bazy.** Usunięcie wymaga zmiany uzgodnienia
   między dwiema wtyczkami naraz — czyli ryzyka nieproporcjonalnego do zysku, bo ekran renderuje
   się w ~26 ms nawet przy 50 tysiącach rekordów. Odłożone do kolejnego wydania, z decyzją
   po stronie zamawiającego.
2. **Kolumna zapisywana, a nigdy nieczytana.** Martwa mechanika bez skutku funkcjonalnego.
   Usunięcie oznacza migrację danych, czyli ryzyko — dlatego czeka.
3. **Jedno uproszczenie zapytań** dostępne dopiero w nowszej wersji WordPressa niż nasze
   deklarowane minimum. Wejdzie, gdy podniesiemy minimum.

## Czego nadal nie sprawdzono

- **Wygląd ekranów oceniony przez projektanta.** Ekrany obejrzano pod kątem błędów i poprawności,
  nie estetyki.
- **Badanie dostępności na żywej stronie u klienta** — pomiar wykonano na naszym środowisku,
  na wcześniejszej wersji paczki; od tamtej pory nie zmieniano badanych ekranów.
- **Zrozumiałość instrukcji po ostatnich poprawkach na kolejnej żywej osobie.** Ostatnia ocena
  (79/100) pochodzi od czytelnika wcielonego w rolę osoby nietechnicznej.
- **Wieloletnia praca bez przerwy** przy narastających danych. Wydajność mierzono jednorazowo,
  na dużych wolumenach, ale nie w warunkach długotrwałego użycia.
- **Zachowanie przy niestandardowej konfiguracji serwera** wykraczającej poza sprawdzone
  środowiska (PHP 8.1–8.5, MySQL 8, WordPress 6.9 i 7.0).

Żaden audyt nie dowodzi braku wszystkich błędów. Powyższe to lista tego, co sprawdzono i czym —
oraz tego, gdzie kończy się nasza wiedza.
