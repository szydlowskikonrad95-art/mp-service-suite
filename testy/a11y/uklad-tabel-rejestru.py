"""S4 nr 6, CZESC DRUGA — czy ekrany Rejestru miesza sie w oknie i czy widac ich tabele.

Rodzenstwo `uklad-tabel-ustawien.py` (czesc pierwsza, ekran ustawien automatu) i
`zoom200-panel.py` (poz. 2.6). Ten sam sposob mierzenia, inne dwa ekrany:
wyjatki gwarancyjne i import CSV.

⛔ NAJWAZNIEJSZA ROZNICA WOBEC CZESCI PIERWSZEJ — pytamy o WYLICZONY STYL, nie tylko
o nadmiar strony. Powod jest konkretny: `overflow-x: hidden` daje DOKLADNIE TAKI SAM
zerowy nadmiar co `auto`, tylko kolumny znikaja NA ZAWSZE zamiast przewijac sie
w ramce. Pomiar samego nadmiaru przepuscilby taka „naprawe" jako udana. Dlatego
kazdy region musi miec `overflow-x` rowne `auto` albo `scroll` — i to jest kontrola,
ktora pada, gdy tabela jest schowana zamiast przewijalnej.

⭐ PROBA KONTROLNA JEST CZESCIA POMIARU: mierzymy razem liste spraw i karte sprawy —
ekrany z sasiedniego modulu, ktorych ta naprawa nie ma prawa ruszyc. Na nich nie
moze byc ANI JEDNEGO regionu naprawy (dowod, ze styl nie wyciekl poza swoj ekran).

⚠️ TABELA HISTORII IMPORTOW ISTNIEJE TYLKO, GDY JEST JAKIS IMPORT. Na czystej
instalacji ekran importu renderuje sie BEZ TABELI i pokazuje piekny nadmiar zero —
zero FALSZYWE, bo zmierzone w stanie, w ktorym wada nie ma jak wystapic. Skrypt
sprawdza to wprost i konczy sie kodem 2 („pomiar niewazny"), zamiast meldowac zielone.

URUCHOMIENIE (wymaga zywego WordPressa i przegladarki — dlatego NIE chodzi w CI):

    MP_BASE=http://localhost:8101 MP_USER=konto MP_PASS=haslo \\
    CHROMIUM=/usr/local/bin/chromium python3 testy/a11y/uklad-tabel-rejestru.py

Opcjonalnie `MP_ZRZUTY=/sciezka/katalog`. Konto musi byc administratorem systemu MP
(oba ekrany stoja za `mp_system_admin`).

Kod wyjscia: 0 = miesci sie i tabele sa przewijalne, 1 = wada,
2 = pomiar niewazny (brak logowania, brak tabel do zmierzenia).
"""

import json
import os
import sys
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

BAZA = os.environ.get("MP_BASE", "http://localhost:8101").rstrip("/")
LOGIN = os.environ.get("MP_USER", "")
HASLO = os.environ.get("MP_PASS", "")
CHROMIUM = os.environ.get("CHROMIUM", "/usr/local/bin/chromium")
ZRZUTY = os.environ.get("MP_ZRZUTY", "")

SZEROKOSCI = (1440, 390)

MIERZONE = (
    ("Wyjątki gwarancyjne", "admin.php?page=mp-registry-exceptions", 1),
    ("Import CSV", "admin.php?page=mp-registry-import", 1),
)
KONTROLNE = (
    ("Sprawy — lista (kontrola)", "admin.php?page=mp-cases"),
    ("Sprawy — karta (kontrola)", "admin.php?page=mp-cases&case_id=1"),
)

NADMIAR = "() => document.documentElement.scrollWidth - document.documentElement.clientWidth"

STAN_TABEL = """
() => {
  const tabele = Array.from(document.querySelectorAll('.wrap table.widefat'));
  return tabele.map((t, i) => {
    const region = t.closest('.mp-registry-table-scroll');
    const st = region ? getComputedStyle(region) : null;
    const naglowki = Array.from(t.querySelectorAll('thead th')).map(th => th.textContent.trim());
    return {
      nr: i + 1,
      naglowki: naglowki.slice(0, 3).join(' / ') || '(bez naglowka)',
      kolumn: naglowki.length,
      w_regionie: !!region,
      overflow_x: st ? st.overflowX : null,
      zaczep_klawiatury: region ? region.getAttribute('tabindex') === '0' : false,
      rola_regionu: region ? region.getAttribute('role') : null,
      ma_etykiete: region ? !!region.getAttribute('aria-label') : false,
      szerokosc_tabeli: Math.round(t.getBoundingClientRect().width),
    };
  });
}
"""

REGIONY_TU = "() => document.querySelectorAll('.mp-registry-table-scroll').length"


def zrzut(strona, nazwa_pliku):
    if not ZRZUTY:
        return
    os.makedirs(ZRZUTY, exist_ok=True)
    # Zrzut OKNA, nie calej strony: zrzut calej strony rozciaga sie do `scrollWidth`
    # i pokazalby wszystkie kolumny takze wtedy, gdy czlowiek ich nie widzi.
    strona.screenshot(path=os.path.join(ZRZUTY, nazwa_pliku), full_page=False)


def zmierz(strona, baza, sciezka, prefiks, zbieraj_tabele):
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
        zrzut(strona, f"{prefiks}-{szerokosc}px.png")
    return wynik


def main():
    if "" in (LOGIN, HASLO):
        print("Podaj MP_USER i MP_PASS — oba ekrany wymagaja zalogowania.")
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

        u = urlparse(s.url)
        baza = f"{u.scheme}://{u.netloc}"
        if "/wp-admin/" not in s.url:
            print(f"Logowanie nie doszlo do skutku (jestem na {s.url}) — pomiar niewazny.")
            b.close()
            return 2

        wyniki = {}
        minimum = {}
        for nazwa, sciezka, min_tabel in MIERZONE:
            prefiks = sciezka.split("page=")[1]
            wyniki[nazwa] = zmierz(s, baza, sciezka, prefiks, True)
            minimum[nazwa] = min_tabel
        for nr, (nazwa, sciezka) in enumerate(KONTROLNE, start=1):
            wyniki[nazwa] = zmierz(s, baza, sciezka, f"kontrola-{nr}", False)
        b.close()

    for nazwa, pomiary in wyniki.items():
        print(f"\n=== {nazwa}")
        for szerokosc, wpis in pomiary.items():
            n = wpis["nadmiar"]
            print(f"  {szerokosc:>5} px: {'0 (mieści się)' if n <= 0 else f'NADMIAR {n} px'}")
            for t in wpis.get("tabele", []):
                print(
                    f"        tabela {t['nr']} „{t['naglowki']}…” ({t['kolumn']} kol., "
                    f"{t['szerokosc_tabeli']} px): region={'tak' if t['w_regionie'] else 'NIE'}"
                    f", overflow-x={t['overflow_x']}"
                    f", klawiatura={'tak' if t['zaczep_klawiatury'] else 'NIE'}"
                )
            if wpis.get("regiony_naprawy"):
                print(f"        ⚠️ regionów naprawy na ekranie kontrolnym: {wpis['regiony_naprawy']}")

    print("\n" + json.dumps(wyniki, ensure_ascii=False))

    wady = []
    wykonane = 0

    # ⛔ STRAZNIK KOMPLETU. Tabela historii importow istnieje tylko przy jakimkolwiek
    # imporcie — bez niej ekran daje zero, ktore NIE jest dowodem niczego.
    for nazwa, _, min_tabel in MIERZONE:
        for szerokosc, wpis in wyniki[nazwa].items():
            ile = len(wpis.get("tabele", []))
            if ile < min_tabel:
                print(
                    f"\n⛔ POMIAR NIEWAZNY: „{nazwa}" f"” przy {szerokosc} px pokazuje {ile} "
                    f"tabel `widefat`, oczekiwane min. {min_tabel}. Ekran nie wpuscil albo "
                    "nie ma danych, ktore te tabele w ogole renderuja (import: potrzebny "
                    "co najmniej jeden wpis w historii)."
                )
                return 2

    for nazwa, _, _ in MIERZONE:
        for szerokosc, wpis in wyniki[nazwa].items():
            wykonane += 1
            if wpis["nadmiar"] > 0:
                wady.append(f"{nazwa} @ {szerokosc} px: strona wychodzi poza okno o {wpis['nadmiar']} px")

            for t in wpis["tabele"]:
                wykonane += 3
                if not t["w_regionie"]:
                    wady.append(f"{nazwa} @ {szerokosc} px: tabela „{t['naglowki']}…” poza regionem przewijanym")
                    continue
                # ⛔ TA KONTROLA PADA, GDY TABELA JEST SCHOWANA ZAMIAST PRZEWIJALNEJ.
                if t["overflow_x"] not in ("auto", "scroll"):
                    wady.append(
                        f"{nazwa} @ {szerokosc} px: region tabeli „{t['naglowki']}…” ma "
                        f"overflow-x={t['overflow_x']} — kolumny sa SCHOWANE, nie przewijalne"
                    )
                if not t["zaczep_klawiatury"] or not t["ma_etykiete"] or t["rola_regionu"] != "region":
                    wady.append(
                        f"{nazwa} @ {szerokosc} px: region tabeli „{t['naglowki']}…” bez "
                        "tabindex=0 / role=region / aria-label"
                    )

    for nazwa, _ in KONTROLNE:
        for szerokosc, wpis in wyniki[nazwa].items():
            wykonane += 2
            if wpis.get("regiony_naprawy"):
                wady.append(
                    f"{nazwa} @ {szerokosc} px: styl naprawy WYCIEKL na ekran kontrolny "
                    f"({wpis['regiony_naprawy']} region(ów))"
                )
            if wpis["nadmiar"] > 0:
                wady.append(f"{nazwa} @ {szerokosc} px: ekran kontrolny wychodzi poza okno o {wpis['nadmiar']} px")

    MIN_KONTROLI = 20
    if wykonane < MIN_KONTROLI:
        print(f"\n⛔ BLAD PRZYRZADU: wykonalo sie {wykonane} kontroli, oczekiwane min. {MIN_KONTROLI}.")
        return 2

    print(f"\nWykonanych kontroli: {wykonane} (min. {MIN_KONTROLI}).")

    if wady:
        print(f"\n🔴 {len(wady)} wad:")
        for w in wady:
            print(f"    - {w}")
        return 1

    print("\n✅ Oba ekrany Rejestru miesza sie w oknie, kazda szeroka tabela ma region "
          "PRZEWIJANY (nie schowany) z zaczepem klawiatury, ekrany kontrolne nietkniete.")
    return 0


sys.exit(main())
