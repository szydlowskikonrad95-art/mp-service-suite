# Raport a11y / WCAG 2.1 — MP Service Suite (bramka dostępności)

**Data:** 2026-07-22 · **Audytor:** czat B2 (delivery-prep) · **Klient końcowy = instytucja publiczna → dostępność jest WYMOGIEM, nie opcją** (BRAMKA-ODDANIA §7).

## Metoda (realny axe-core, nie deklaracja)
- **Silnik:** axe-core (npm) uruchomiony w **prawdziwym DOM przeglądarki** przez Playwright + systemowy Chromium (`/usr/bin/chromium`, headless).
- **Reguły:** WCAG 2.1 poziom **A + AA** (tagi `wcag2a, wcag2aa, wcag21a, wcag21aa`).
- **Środowisko:** działająca instalacja WordPress 7.0.2 z kompletem trzech wtyczek.
- To uzupełnia strukturalny sweep w CI (`testy/e2e/blok-s-a11y.sh` + `a11y-forms.sh`: etykiety, `role=alert`, nazwy przycisków, img-alt, duplikaty id) o warstwę, której CI nie zrobi bez przeglądarki: **kontrast kolorów i pełne reguły ARIA na wyrenderowanym DOM**.
- Wyniki poniżej pochodzą wprost z przebiegu axe-core (liczby przejść, naruszeń i pozycji niepewnych).

## Audytowane powierzchnie i wynik

| Powierzchnia | URL (demo) | passes | Naruszenia (nasz kod) |
|---|---|---|---|
| Formularz zgłoszenia (publiczny) | `/?page_id=7` | 24 | **0** |
| Panel klienta — wylogowany (logowanie) | `/?page_id=8` | 24 | **0** |
| Strona weryfikacji e-mail (magic-link GET) | `admin-post.php?action=mp_intake_verify` | 8 | **0** |
| Panel klienta — zalogowany | `/?page_id=8` (po passwordless login) | 30 | **1** (kontrast) |

## Naruszenia

### A. NASZ KOD — do naprawy przed v1.0.0 (C-patch, poza tym czatem)
Strażnik: nie tykam `mp-service-intake` (B1 w C-hookach) — zgłaszam jako findingi do C-patcha.

1. **`color-contrast` — WCAG 1.4.3 AA (serious).** `mp-service-intake/includes/Front/AccountPage.php:371`
   `<p class="mp-account__empty" style="color:#777">Brak wiadomości.</p>` — `#777` na białym = **4,48:1** (próg 4,5:1). Wykrył axe.
   **Fix:** `#767676` (4,54:1) minimalnie, albo `#595959` (7,0:1) z zapasem.
2. **`color-contrast` — WCAG 1.4.3 AA (serious), NIEWYKRYTY automatycznie** (axe nie dosięgnął — wymaga sprawy w stanie „zamknięte"). `AccountPage.php:415`
   `<p style="color:#7a5">Sprawa jest zamknięta — …</p>` — `#7a5` na białym = **2,74:1** (wyraźny FAIL).
   **Fix:** ciemniejsza zieleń, np. `#2e7d32` (~4,5:1+). Znaleziony przeglądem kodu przy okazji #1 (ten sam wzorzec inline-color).

> Oba to drobne, tanie poprawki (jedna wartość koloru każdy). Rekomendacja: przenieść inline-kolory do CSS klasy i ustawić kontrastową paletę raz.

### B. POZA ZAKRESEM — motyw WordPressa, nie nasz kod
- **`list` — WCAG 1.3.1 (serious).** `<ul class="wp-block-navigation__container …">` — to blok **nawigacji motywu** (Twenty Twenty-*), nie kod wtyczek MP. Na stronie klienta z jego motywem to naruszenie zależy od ICH motywu, nie od nas. Odnotowane dla pełności; **nie jest naszą wadą do naprawy**.

## Werdykt bramki §7
- **Powierzchnie publiczne wtyczek (formularz, logowanie, weryfikacja): 0 naruszeń a11y** w naszym kodzie. ✅
- **Panel zalogowany: 2 findingi kontrastu** (1 wykryty axe + 1 z przeglądu kodu) — **do C-patcha przed v1.0.0**. Blokują „zielony" bramki §7 do czasu naprawy.
- Naruszenia motywu = poza naszym zakresem (zależne od motywu klienta).

## Do zrobienia przed oddaniem v1.0.0
- [ ] C-patch: kontrast `#777` (AccountPage:371) + `#7a5` (AccountPage:415) → paleta ≥4,5:1 (B1/C-hooki).
- [ ] Re-run tego audytu po C-patchu (te same 2 skrypty: `run-axe.js`, `run-axe-panel.js`) → oczekiwane 0 naruszeń w naszym kodzie.
- [ ] (Opcjonalnie) sekcje D panelu, gdy B1 skończy Automator — dołożyć do audytu.
