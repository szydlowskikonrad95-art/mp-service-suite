# POSTĘP NAPRAW 1.3.12 — co zrobione, co zostało

Kolejność wg `warsztat/dzial-audytu/KOLEJNOSC-NAPRAW-1312.md`. Decyzja Dzidka (3.08):
**robimy wszystkie pozycje po kolei**, bez dzielenia na drugą partię.

## GRUPA 0 — dane osobowe

| Poz. | Stan | Czym udowodnione |
|---|---|---|
| 2.54 (krytyczna) — e-mail publicznie na stronie autora | ✅ naprawione | `testy/e2e/c-tozsamosc-konta-klienta.sh` (20 kontroli, próby kontrolne + żądanie anonimowe HTTP) |
| 2.55 (średnia) — martwa ochrona przed sklejeniem osób | ✅ naprawione tą samą zmianą | ten sam test, sekcja 3 |
| konta założone WCZEŚNIEJ | ✅ migracja schematu 4 | ten sam test, sekcja 2 (odtworzenie stanu sprzed poprawki) |
| 2.58 (krytyczna) — usunięcie danych pomija zgłoszenia niepotwierdzone | ⬜ następne | — |

## ŚLADY DO SPRZĄTNIĘCIA PRZED WYDANIEM
- 🔴 **Zrzuty ekranu formularza są nieaktualne** — `dla-klienta/instrukcje/zdjecia/02-formularz-pusty.jpg`
  i `03-formularz-wypelniony-zalacznik.jpg` pokazują formularz **bez pola imienia i nazwiska**.
  Zrobić nowe przed wydaniem (grupa 3 — dokumenty).
- Wersję wtyczek na 1.3.12 podnosimy **raz, na końcu**, a nie przy każdej naprawie.

## DECYZJE PODJĘTE PRZY NAPRAWIE (ślad, bo kształtują produkt)
1. **Pole imienia jest WYMAGANE.** Opcjonalne zostawiłoby wadę 2.55 tylko częściowo zamkniętą
   (puste nazwisko = ochrona przed sklejeniem osób znowu nie startuje). Kartka pola nie wymaga,
   ale też go nie zakazuje; wada była nasza, więc zamykamy ją u korzenia.
2. **Konto WordPressa nie nosi danych osobowych W OGÓLE** — ani e-maila, ani nazwiska.
   Alternatywa („wpisujmy nazwisko zamiast adresu") zamieniłaby wyciek adresu na wyciek
   nazwiska: strona autora jest jawna niezależnie od tego, co w niej stoi.
3. **Login też jest neutralny**, choć sam nie jest publikowany — adres strony autora powstaje
   z `user_nicename`, a ten domyślnie bierze się z loginu.
