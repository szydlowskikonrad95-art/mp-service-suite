# Uwagi do dokumentów audytu — zdania do rozstrzygnięcia przez autora

⛔ **Ten plik NICZEGO nie poprawia.** Pozostałe dokumenty w tym katalogu (`RAPORT-AUDYTU.md`,
`ZAKRES-SPRAWDZONY.md`, `RUBRYKA-GOTOWE.md`, `KONTROLE-AUTOMATYCZNE.md`) są **przedmiotem
audytu**, a nie jego wynikiem — poprawianie ich cudzą ręką zatarłoby ślad, do którego odwołuje
się nasza własna lista (cytujemy z nich plik i linię). Dlatego zamiast edycji: **lista zdań
z cytatem, powodem i dowodem z kodu.** Decyzja, co z nimi zrobić, należy do autora dokumentów.

**Stan odniesienia:** gałąź `main` z 4.08.2026 (po scaleniu napraw #200–#214).
Każda pozycja sprawdzona poleceniem na tej gałęzi, nie z pamięci.

---

## 1. `ZAKRES-SPRAWDZONY.md:48` — „odrzucenie wymagające powodu"

> *„Automat: przydział po kolei, termin 24 h z przypomnieniem po 75% czasu, **eskalacja do
> koordynatora**, 7 statusów, **odrzucenie wymagające powodu**, wznowienie tylko do właściwego
> stanu"*

**Dlaczego to nie jest prawdą jako „wykonanie na działającym systemie":** odrzucenia nie da się
wykonać w interfejsie w ogóle. Pole powodu renderuje się **wyłącznie**, gdy lista powodów nie
jest pusta (`mp-service-intake/includes/Admin/CaseCard.php:194`), a lista pochodzi z zaczepu
`mp_rejection_reasons` (`:177`), który w całym produkcie **nie ma ani jednej rejestracji** —
są tylko dwa odczyty (`CaseCard.php:177`, `mp-workflow-automator/includes/CsvExport.php:134`).
Bez powodu zapis statusu „odrzucone" zwraca `REJECTION_REASON_REQUIRED`
(`mp-service-intake/includes/CaseRepo.php:769-773`).

**Stan na 4.08:** ⬜ **zarzut aktualny** — sprawdzone poleceniem, zero rejestracji zaczepu.
Sama wada to część 1 punkt 5 i pozostaje otwarta w kodzie.

---

## 2. `ZAKRES-SPRAWDZONY.md:51` — „Historia zmian produktu ma komplet"

> *„**Historia zmian produktu ma komplet**: kto, kiedy, wartość przed i po"*

**Zarzut brzmiał:** dane owszem są, ale **nie ma żadnej drogi**, którą człowiek by do nich
doszedł — dziennik był zapisywany i nigdy nieczytany.

**Stan na 4.08:** ✅ **zarzut NIEAKTUALNY — unieważniła go nasza własna naprawa.**
Po scaleniu #207 (pozycja 2.38) droga istnieje: link **„historia"** przy każdym produkcie
na liście rejestru (`mp-warranty-registry/includes/Admin/ProductsTable.php:213`) prowadzi
do ekranu historii egzemplarza (`Admin/ProductsScreen.php:133` → `render_history()`,
adres z `history_url()`, `:364`). Ekran pokazuje kiedy, co się stało, kto i szczegóły zmiany.

📌 **Zapisujemy to po to, żeby nikt nie policzył tej pozycji dwa razy** — zdanie w dokumencie
audytu jest dziś prawdziwe także w warstwie, o którą nam chodziło.

---

## 3. `ZAKRES-SPRAWDZONY.md:24-28` — zakres części o bezpieczeństwie

> *„Ekrany **bez logowania**, konto **bez uprawnień** na pięciu ekranach, wejście bokiem przez
> podmianę numeru w adresie (5 wariantów), interfejs REST, żądania bez uwierzytelnienia…"*

**Uwaga dotyczy zakresu, nie prawdziwości:** wszystkie wymienione próby dotyczą **obcego albo
klienta**. Nie ma ani jednej pozycji o **widoczności między rolami personelu** — a właśnie tam
siedziała różnica między tym, co pracownik ma prawo widzieć, a co widział.

**Stan na 4.08:** ⚠️ **luka w zakresie dokumentu zostaje, ale sama wada jest naprawiona.**
Po scaleniu #205 (pozycja 2.24) pracownik widzi wyłącznie swoje sprawy:
`mp-service-intake/includes/CaseRepo.php:990-1000` (`scope_for_current_user()` → `SCOPE_OWN`
dla `mp_agent`) i `:1056-1058` (warunek `c.assigned_to = %d`).

🔴 **Przy okazji, do poprawienia przez właściciela modułu zgłoszeń:** komentarz nad
`query_for_staff()` (`CaseRepo.php:1003-1007`) opisuje **stary** model — *„CALY personel
widzi WSZYSTKIE zweryfikowane sprawy — BEZ scopingu per assigned_to"* — czyli przeczy kodowi
dwadzieścia linii niżej.

---

## 4. `RUBRYKA-GOTOWE.md:12` — kryterium „Dokumenty klienta zgodne z kodem"

> *„Dokumenty klienta zgodne z kodem (liczby, statusy, **obietnice**) | osobna kontrola
> «liczby zgodne z kodem»…"*

**Dlaczego dowód nie pokrywa kryterium:** przywołana bramka
(`.github/workflows/quality.yml:63-64` → `testy/dokumenty/liczby-zgodne-z-kodem.sh`) porównuje
**liczby**: liczbę tabel, statusów rdzenia, rodzajów zgłoszenia, testów diagnostycznych, dni
retencji, okno potwierdzenia, minimalną wersję PHP i progi formularza (`:21-36`).
**Obietnic nie sprawdza żadna kontrola** — bo nie da się ich sprowadzić do liczby.

**Dowód, że to nie jest zarzut teoretyczny:** przy zielonej bramce w dokumentach klienta stały
**cztery zdania nieprawdziwe**, wszystkie znalezione ręcznie 4.08:
`INSTRUKCJA-KLIENTA.md:226` i `instrukcje/KOORDYNATOR.md:52` (*„nie ma na to ekranu — zrobi to
programista"* o statusach własnych, a ekran istnieje: `SettingsScreen.php:210-275`),
`instrukcje/ADMIN.md:75-77` (ekran wyjątków *„to nie awaria, tylko ekran czekający"*, a po #209
pokazuje listę wszystkich wyjątków) oraz `README.md:20` (*„7 konfigurowalnych statusów"*,
gdy siódemka rdzenia jest nieusuwalna — `StatusDefs.php:5`).

**Stan na 4.08:** ⬜ **zarzut aktualny.** Same cztery zdania są już poprawione (#220, #223),
ale **kryterium nadal nie ma dowodu w części „obietnice"** — następny rozjazd przejdzie tak samo.

---

## Czego ta lista NIE zawiera

Nie wskazujemy trzech spornych zdań z `RUBRYKA-GOTOWE.md` poza pozycją 4 — opis pozycji 2.44
w paczce urywa się na zasadzie („kryteria binarne") i tych zdań nie wymienia. Wskazanie ich
byłoby **wykonaniem kawałka audytu, a nie naprawy**, więc zostawiamy to autorowi listy.
