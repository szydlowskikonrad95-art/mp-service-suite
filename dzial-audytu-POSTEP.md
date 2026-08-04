# POSTĘP NAPRAW 1.3.12 — co zrobione, co zostało

Kolejność wg `warsztat/dzial-audytu/KOLEJNOSC-NAPRAW-1312.md`. Decyzja Dzidka (3.08):
**robimy wszystkie pozycje po kolei**, bez dzielenia na drugą partię.

## GRUPA 0 — dane osobowe

| Poz. | Stan | Czym udowodnione |
|---|---|---|
| 2.54 (krytyczna) — e-mail publicznie na stronie autora | ✅ naprawione | `testy/e2e/c-tozsamosc-konta-klienta.sh` (20 kontroli, próby kontrolne + żądanie anonimowe HTTP) |
| 2.55 (średnia) — martwa ochrona przed sklejeniem osób | ✅ naprawione tą samą zmianą | ten sam test, sekcja 3 |
| konta założone WCZEŚNIEJ | ✅ migracja schematu 4 | ten sam test, sekcja 2 (odtworzenie stanu sprzed poprawki) |
| 2.58 (krytyczna) — usunięcie danych pomija zgłoszenia niepotwierdzone | ✅ naprawione | `testy/e2e/c-rodo-zgloszenia-niepotwierdzone.sh` (12 kontroli + **kalibracja podłożonym błędem**: bez naprawy pada w 3 miejscach) |

**GRUPA 0 ZAMKNIĘTA** — trzy pozycje krytyczne z listy: 2.54, 2.58 (dane osobowe) naprawione; 2.10 zostaje do grupy 1.

## GRUPA 1 i 2 — postęp

| Poz. | Stan | Czym udowodnione |
|---|---|---|
| 2.25 — koordynator miał mniej ekranów niż podwładny | ✅ scalone (#195) | `c-dostep-rol-ekrany.sh` (15 kontroli) |
| 2.5 + 2.8 — jedna sprawa, trzy nazwy; surowe klucze u klienta | ✅ scalone (#196) | `c-nazwy-rodzaju-i-statusu.sh` (9, panel mierzony renderem) |
| **2.10 — ślad operacji bez kontroli wyniku (KRYTYCZNA)** | ✅ scalone (#197) | `c-slad-operacji-nie-ginie.sh` (9, awarie wywoływane naprawdę) |
| 2.59 + 2.52 + 2.61 | 🔄 PR #198 | `c-drobne-2-52-2-59-2-61.sh` (12, pomiar na żywo) |

⬜ **Największy kawałek, jaki został: WARSTWA USTAWIEŃ** — zamyka **cztery** pozycje naraz
(2.16, 2.35, 2.11 i punkt 4 części 1). Robić PRZED naprawą statusów i reguł, inaczej te naprawy
trzeba będzie pisać dwa razy. Zaczynać na świeżym kontekście — to nie jest robota na resztki.

## ŚLADY DO SPRZĄTNIĘCIA PRZED WYDANIEM
- ⚠️ **2.34 (72 h vs 24 h) czeka** — zdanie o ważności linku stoi w `INSTRUKCJA-KLIENTA.md:349`
  i w dwóch innych plikach; naprawiać jako **wzorzec** (4 miejsca + bramka), nie egzemplarz.
- 🔴 **Zrzuty ekranu formularza są nieaktualne** — `dla-klienta/instrukcje/zdjecia/02-formularz-pusty.jpg`
  i `03-formularz-wypelniony-zalacznik.jpg` pokazują formularz **bez pola imienia i nazwiska**.
  Zrobić nowe przed wydaniem (grupa 3 — dokumenty).
- Wersję wtyczek na 1.3.12 podnosimy **raz, na końcu**, a nie przy każdej naprawie.

## DECYZJE PODJĘTE PRZY NAPRAWIE (ślad, bo kształtują produkt)
1. **Pole imienia jest WYMAGANE.** Opcjonalne zostawiłoby wadę 2.55 tylko częściowo zamkniętą
   (puste nazwisko = ochrona przed sklejeniem osób znowu nie startuje). Specyfikacja pola nie wymaga,
   ale też go nie zakazuje; wada była nasza, więc zamykamy ją u korzenia.
2. **Konto WordPressa nie nosi danych osobowych W OGÓLE** — ani e-maila, ani nazwiska.
   Alternatywa („wpisujmy nazwisko zamiast adresu") zamieniłaby wyciek adresu na wyciek
   nazwiska: strona autora jest jawna niezależnie od tego, co w niej stoi.
3. **Login też jest neutralny**, choć sam nie jest publikowany — adres strony autora powstaje
   z `user_nicename`, a ten domyślnie bierze się z loginu.
