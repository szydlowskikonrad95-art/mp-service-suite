"""S4 nr 6 — czy ekran USTAWIEN automatyzacji miesci sie w oknie i czy widac jego tabele.

Rodzenstwo `zoom200-panel.py` (poz. 2.6), ten sam sposob mierzenia, inny ekran. Roznica
jest wazna: 2.6 dotyczyla PANELU i tam naprawe zrobiono — region przewijany
`.mp-automator-table-scroll`. Ekran USTAWIEN dostal te sama choroba, a lekarstwa nigdy
nie dostal, bo `SettingsScreen` w ogole nie wczytywal arkusza modulu (klasy w kodzie byly,
stylu nie bylo).

MIERZYMY DWIE RZECZY, bo jedna nie wystarcza:

1. **Nadmiar strony** (`scrollWidth - clientWidth` na `<html>`): ile pikseli trzeba
   przewinac CALA strone w bok. Zero = strona miesci sie w oknie.
2. **Czy tabela jest DOSTEPNA, a nie tylko schowana**: sam brak nadmiaru mozna uzyskac
   obcinajac tabele (`overflow: hidden`) — wtedy kolumny znikaja NA ZAWSZE zamiast
   przewijac sie w ramce. Dlatego przy waskim oknie sprawdzamy, ze kazda szeroka tabela
   siedzi w regionie, ktory ma wlasne przewijanie ORAZ zaczep klawiatury (`tabindex`),
   czyli ze da sie do tych kolumn dojechac takze bez myszki (WCAG 2.1.1).

⭐ PROBA KONTROLNA JEST CZESCIA POMIARU. Mierzymy razem liste spraw i karte sprawy —
ekrany z sasiedniego modulu, na ktorych pracuje sie codziennie i ktorych ta naprawa
NIE MA PRAWA ruszyc. Jesli styl wyciekl poza swoj ekran, zobaczymy to tutaj: na
kontrolnych nie moze byc ani jednego regionu `.mp-automator-table-scroll`, a nadmiar
ma byc taki sam przed naprawa i po niej.

URUCHOMIENIE (wymaga zywego WordPressa i przegladarki — dlatego NIE chodzi w CI):

    MP_BASE=http://127.0.0.1:8101 MP_USER=konto MP_PASS=haslo \\
    CHROMIUM=/usr/local/bin/chromium python3 testy/a11y/uklad-tabel-ustawien.py

Opcjonalnie `MP_ZRZUTY=/sciezka/katalog` — zapisze zrzuty calej strony dla kazdej pary
(ekran, szerokosc). Konto musi byc administratorem systemu MP (ekran ustawien ma cap
`mp_system_admin`).

Kod wyjscia: 0 = wszystko miesci sie i tabele sa dostepne, 1 = wada,
2 = pomiar niewazny (nie udalo sie zalogowac, ekran nie wpuscil, brak tabel do zmierzenia).
"""

import json
import os
import sys
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

BAZA = os.environ.get("MP_BASE", "http://127.0.0.1:8101").rstrip("/")
LOGIN = os.environ.get("MP_USER", "")
HASLO = os.environ.get("MP_PASS", "")
CHROMIUM = os.environ.get("CHROMIUM", "/usr/local/bin/chromium")
ZRZUTY = os.environ.get("MP_ZRZUTY", "")

# Obie szerokosci z decyzji Dzidka: telefon i zwykly monitor. 1280 i 782 sa dolozone,
# bo 1280 to szerokosc obszaru tresci przy 1440, a 782 to prog responsywny WordPressa —
# gdyby naprawa dzialala tylko po jednej stronie progu, wyjdzie wlasnie tam.
SZEROKOSCI = (1440, 1280, 782, 390)

MIERZONY = ("Ustawienia automatyzacji", "admin.php?page=mp-automator-settings")
KONTROLNE = (
    ("Sprawy — lista (kontrola)", "admin.php?page=mp-cases"),
    ("Sprawy — karta (kontrola)", "admin.php?page=mp-cases&case_id=1"),
)

# Trzy szerokie tabele ekranu ustawien (czwarta, `form-table` przelacznika kasowania
# danych, miesci sie sama i celowo nie jest owijana).
OCZEKIWANE_REGIONY = 3

NADMIAR = "() => document.documentElement.scrollWidth - document.documentElement.clientWidth"

# Kazda tabela `widefat` na tym ekranie ma siedziec w regionie przewijanym. Zwraca liste
# opisow: czy region jest, czy ma zaczep klawiatury, czy przy tej szerokosci faktycznie
# przewija (czyli czy schowane kolumny da sie wydobyc).
STAN_TABEL = """
() => {
  const tabele = Array.from(document.querySelectorAll('.wrap table.widefat'));
  return tabele.map((t, i) => {
    const region = t.closest('.mp-automator-table-scroll');
    const naglowki = Array.from(t.querySelectorAll('thead th')).map(th => th.textContent.trim());
    return {
      nr: i + 1,
      naglowek: naglowki[0] || '(bez naglowka)',
      kolumn: naglowki.length,
      w_regionie: !!region,
      zaczep_klawiatury: region ? region.getAttribute('tabindex') === '0' : false,
      rola_regionu: region ? region.getAttribute('role') : null,
      ma_etykiete: region ? !!region.getAttribute('aria-label') : false,
      region_przewija: region ? region.scrollWidth > region.clientWidth : false,
      szerokosc_tabeli: Math.round(t.getBoundingClientRect().width),
    };
  });
}
"""

# Ile regionow naprawy widzi ekran kontrolny. Ma byc zero — inaczej styl wyciekl.
REGIONY_TU = "() => document.querySelectorAll('.mp-automator-table-scroll').length"


def zrzut(strona, nazwa_pliku):
    if not ZRZUTY:
        return
    os.makedirs(ZRZUTY, exist_ok=True)
    # ⛔ Zrzut OKNA, nie calej strony. Zrzut calej strony w Chromium rozciaga sie do
    # `scrollWidth`, wiec pokazalby wszystkie kolumny takze wtedy, gdy czlowiek ich nie
    # widzi — czyli zamalowalby dokladnie te wade, ktora tu badamy.
    strona.screenshot(path=os.path.join(ZRZUTY, nazwa_pliku), full_page=False)


def zmierz(strona, baza, nazwa, sciezka, prefiks_zrzutu, zbieraj_tabele):
    """Nadmiar (i stan tabel) dla kazdej szerokosci."""
    wynik = {}

    for szerokosc in SZEROKOSCI:
        strona.set_viewport_size({"width": szerokosc, "height": 900})
        strona.goto(f"{baza}/wp-admin/{sciezka}", wait_until="domcontentloaded")
        strona.wait_for_timeout(400)

        wpis = {"nadmiar": int(strona.evaluate(NADMIAR))}
        if zbieraj_tabele:
            wpis["tabele"] = strona.evaluate(STAN_TABEL)
        else:
            wpis["regiony_naprawy"] = int(strona.evaluate(REGIONY_TU))
        wynik[szerokosc] = wpis

        zrzut(strona, f"{prefiks_zrzutu}-{szerokosc}px.png")

    return wynik


def main():
    if "" in (LOGIN, HASLO):
        print("Podaj MP_USER i MP_PASS — ekran ustawien wymaga zalogowania.")
        return 2

    with sync_playwright() as p:
        b = p.chromium.launch(
            executable_path=CHROMIUM,
            headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
        )
        s = b.new_page(viewport={"width": 1440, "height": 900})
        s.goto(f"{BAZA}/wp-login.php", wait_until="domcontentloaded")
        s.fill("#user_login", LOGIN)
        s.fill("#user_pass", HASLO)
        s.click("#wp-submit")
        s.wait_for_load_state("domcontentloaded")

        # Adres bierzemy z przegladarki po zalogowaniu (lekcja z poz. 2.6: przy innym
        # adresie kanonicznym pomiar szedl po ekranie logowania i pokazywal zero).
        u = urlparse(s.url)
        baza = f"{u.scheme}://{u.netloc}"

        if "/wp-admin/" not in s.url:
            print(f"Logowanie nie doszlo do skutku (jestem na {s.url}) — pomiar niewazny.")
            b.close()
            return 2

        wyniki = {
            MIERZONY[0]: zmierz(s, baza, MIERZONY[0], MIERZONY[1], "ustawienia-automatora", True)
        }
        for nr, (nazwa, sciezka) in enumerate(KONTROLNE, start=1):
            wyniki[nazwa] = zmierz(s, baza, nazwa, sciezka, f"kontrola-{nr}", False)

        b.close()

    # ---- wydruk dla czlowieka -------------------------------------------------
    for nazwa, pomiary in wyniki.items():
        print(f"\n=== {nazwa}")
        for szerokosc, wpis in pomiary.items():
            n = wpis["nadmiar"]
            print(f"  {szerokosc:>5} px: {'0 (mieści się)' if n <= 0 else f'NADMIAR {n} px'}")
            for t in wpis.get("tabele", []):
                print(
                    f"        tabela {t['nr']} „{t['naglowek']}" f"” ({t['kolumn']} kol., "
                    f"{t['szerokosc_tabeli']} px): region={'tak' if t['w_regionie'] else 'NIE'}"
                    f", klawiatura={'tak' if t['zaczep_klawiatury'] else 'NIE'}"
                    f", przewija={'tak' if t['region_przewija'] else 'nie trzeba'}"
                )
            if "regiony_naprawy" in wpis and wpis["regiony_naprawy"]:
                print(f"        ⚠️ regionów naprawy na ekranie kontrolnym: {wpis['regiony_naprawy']}")

    print("\n" + json.dumps(wyniki, ensure_ascii=False))

    # ---- ocena ----------------------------------------------------------------
    nasze = wyniki[MIERZONY[0]]
    wady = []
    wykonane = 0

    # ⛔ Straznik kompletu (lekcja: „bramka, ktora cicho nie startuje, swieci zielono").
    # Jesli ekran nie wpuscil albo markup sie zmienil, tabel nie bedzie w ogole i
    # wszystkie kontrole „przeszlyby" po cichu.
    for szerokosc, wpis in nasze.items():
        if len(wpis.get("tabele", [])) < OCZEKIWANE_REGIONY:
            print(
                f"\n⛔ POMIAR NIEWAZNY: przy {szerokosc} px widze "
                f"{len(wpis.get('tabele', []))} tabel `widefat`, oczekiwane min. "
                f"{OCZEKIWANE_REGIONY}. Ekran nie wpuscil albo zmienil sie markup."
            )
            return 2

    for szerokosc, wpis in nasze.items():
        wykonane += 1
        if wpis["nadmiar"] > 0:
            wady.append(f"{szerokosc} px: strona wychodzi poza okno o {wpis['nadmiar']} px")

        for t in wpis["tabele"]:
            wykonane += 3
            if not t["w_regionie"]:
                wady.append(
                    f"{szerokosc} px: tabela „{t['naglowek']}” nie siedzi w regionie przewijanym"
                )
                continue
            if not t["zaczep_klawiatury"]:
                wady.append(
                    f"{szerokosc} px: region tabeli „{t['naglowek']}” bez tabindex=0 "
                    "(bez myszki nie da sie go przesunac)"
                )
            if not t["ma_etykiete"] or t["rola_regionu"] != "region":
                wady.append(
                    f"{szerokosc} px: region tabeli „{t['naglowek']}” bez role=region/aria-label"
                )

    # Proba kontrolna: ekrany codzienne maja byc nietkniete.
    for nazwa, _ in KONTROLNE:
        for szerokosc, wpis in wyniki[nazwa].items():
            wykonane += 2
            if wpis.get("regiony_naprawy"):
                wady.append(
                    f"{nazwa} @ {szerokosc} px: styl naprawy WYCIEKL na ekran kontrolny "
                    f"({wpis['regiony_naprawy']} region(ów))"
                )
            if wpis["nadmiar"] > 0:
                wady.append(
                    f"{nazwa} @ {szerokosc} px: ekran kontrolny wychodzi poza okno o "
                    f"{wpis['nadmiar']} px — ⚠️ porownaj z przebiegiem sprzed naprawy, "
                    "jesli bylo tak samo, to nie jest skutek tej zmiany"
                )

    MIN_KONTROLI = len(SZEROKOSCI) * (1 + 3 * OCZEKIWANE_REGIONY) + len(KONTROLNE) * len(SZEROKOSCI) * 2
    if wykonane < MIN_KONTROLI:
        print(f"\n⛔ BLAD PRZYRZADU: wykonalo sie {wykonane} kontroli, oczekiwane min. {MIN_KONTROLI}.")
        return 2

    print(f"\nWykonanych kontroli: {wykonane} (min. {MIN_KONTROLI}).")

    if wady:
        print(f"\n🔴 {len(wady)} wad:")
        for w in wady:
            print(f"    - {w}")
        return 1

    print("\n✅ Ekran ustawien miesci sie w oknie na kazdej mierzonej szerokosci, "
          "kazda szeroka tabela ma wlasny region przewijany z zaczepem klawiatury, "
          "a ekrany kontrolne sa nietkniete.")
    return 0


sys.exit(main())
