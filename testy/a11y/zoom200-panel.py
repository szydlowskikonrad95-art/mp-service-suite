"""Poz. 2.6 — czy ekran automatyzacji miesci sie w oknie, takze przy powiekszeniu 200%.

Mierzy JEDNA rzecz i mierzy ja tak, jak widzi ja czlowiek: ile pikseli tresci wychodzi
poza okno w poziomie (`scrollWidth - clientWidth` na `<html>`). Nadmiar > 0 znaczy, ze
zeby zobaczyc dane, trzeba przewijac CALA strone w bok — z menu i naglowkiem wlacznie.

⛔ DLACZEGO POWIEKSZENIE 200% JEST OSOBNYM POMIAREM: panel automatyzacji przy 100%
mial nadmiar ZERO i dlatego zaden wczesniejszy przebieg tej wady nie widzial. Wada
istnieje wylacznie dla osoby, ktora powieksza — czyli dokladnie dla tej, dla ktorej
powiekszanie w ogole istnieje (WCAG 1.4.10).

⭐ PROBA KONTROLNA JEST CZESCIA POMIARU, NIE DODATKIEM. Mierzymy razem z ekranem
„Sprawy" z sasiedniego modulu: to ten sam produkt, ta sama szerokosc, ta sama chwila.
Jesli kontrola tez pokaze nadmiar, to znaczy, ze mierzymy stanowisko, a nie ekran —
i wyniku nie wolno uzywac.

URUCHOMIENIE (wymaga zywego WordPressa i przegladarki — dlatego NIE chodzi w CI):

    pip install playwright && playwright install chromium
    MP_BASE=http://127.0.0.1:8095 MP_USER=konto MP_PASS=haslo \\
    CHROMIUM=/usr/local/bin/chromium python3 testy/a11y/zoom200-panel.py

Konto musi widziec panel automatyzacji (koordynator albo administrator systemu MP).
Kod wyjscia: 0 = zaden mierzony ekran nie wychodzi poza okno, 1 = wychodzi,
2 = pomiar niewazny (proba kontrolna nie wyszla albo nie udalo sie zalogowac).
"""

import json
import os
import sys
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

BAZA = os.environ.get("MP_BASE", "http://127.0.0.1:8095").rstrip("/")
LOGIN = os.environ.get("MP_USER", "")
HASLO = os.environ.get("MP_PASS", "")
CHROMIUM = os.environ.get("CHROMIUM", "/usr/local/bin/chromium")

# Szerokosci z pomiaru pozycji 2.6 (od zwyklego monitora po telefon).
SZEROKOSCI = (1280, 1024, 768, 390)
POWIEKSZENIA = ("100%", "200%")

MIERZONY = ("Panel automatyzacji", "admin.php?page=mp-automator")
KONTROLA = ("Sprawy (proba kontrolna)", "admin.php?page=mp-cases")

POMIAR = "() => document.documentElement.scrollWidth - document.documentElement.clientWidth"


def zmierz(strona, baza, sciezka):
    """Nadmiar w pikselach dla kazdej pary (szerokosc, powiekszenie)."""
    wynik = {}

    for szerokosc in SZEROKOSCI:
        strona.set_viewport_size({"width": szerokosc, "height": 900})
        strona.goto(f"{baza}/wp-admin/{sciezka}", wait_until="domcontentloaded")
        strona.wait_for_timeout(500)

        for zoom in POWIEKSZENIA:
            strona.evaluate("(z) => { document.documentElement.style.zoom = z; }", zoom)
            strona.wait_for_timeout(400)
            wynik[f"{szerokosc}px @ {zoom}"] = int(strona.evaluate(POMIAR))

    return wynik


def main():
    if "" in (LOGIN, HASLO):
        print("Podaj MP_USER i MP_PASS — panel personelu wymaga zalogowania.")
        return 2

    with sync_playwright() as p:
        b = p.chromium.launch(
            executable_path=CHROMIUM,
            headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
        )
        s = b.new_page(viewport={"width": 1280, "height": 900})
        s.goto(f"{BAZA}/wp-login.php", wait_until="domcontentloaded")
        s.fill("#user_login", LOGIN)
        s.fill("#user_pass", HASLO)
        s.click("#wp-submit")
        s.wait_for_load_state("domcontentloaded")

        # ⛔ ADRES BIERZEMY Z PRZEGLADARKI PO ZALOGOWANIU, nie z MP_BASE. Gdy witryna ma
        # inny adres kanoniczny (tunel, domena), WordPress przerzuca tam po logowaniu, a
        # ciasteczko spod MP_BASE juz nie pasuje. Pomiar szedl wtedy po EKRANIE LOGOWANIA
        # i pokazywal piekne zero — tak wlasnie przepadl pierwszy przebieg tej kontroli.
        u = urlparse(s.url)
        baza = f"{u.scheme}://{u.netloc}"

        if "/wp-admin/" not in s.url:
            print(f"Logowanie nie doszlo do skutku (jestem na {s.url}) — pomiar niewazny.")
            b.close()
            return 2

        wyniki = {nazwa: zmierz(s, baza, sciezka) for nazwa, sciezka in (MIERZONY, KONTROLA)}
        b.close()

    for nazwa, pomiary in wyniki.items():
        print(f"\n=== {nazwa}")
        for opis, nadmiar in pomiary.items():
            print(f"    {opis:>16}: {'0 (mieści się)' if nadmiar <= 0 else f'NADMIAR {nadmiar} px'}")

    print("\n" + json.dumps(wyniki, ensure_ascii=False))

    # Proba kontrolna rozstrzyga PUNKT PO PUNKCIE, nie zbiorczo. Ekran z sasiedniego
    # modulu ma wlasne slabe miejsca (u nas: 1024 i 390 px przy 200%) i gdyby jedno
    # z nich uniewazniało caly przebieg, wynik przepadalby razem z nim. Wada NASZEGO
    # ekranu = nadmiar tam, gdzie kontrola przy tym samym pomiarze ma zero.
    nasze = wyniki[MIERZONY[0]]
    kontrolne = wyniki[KONTROLA[0]]

    wady = {p: n for p, n in nasze.items() if n > 0 and kontrolne.get(p, 0) <= 0}
    wspolne = {p: n for p, n in nasze.items() if n > 0 and kontrolne.get(p, 0) > 0}

    if wspolne:
        print(
            "\n⚠️ Punkty, w ktorych OBA ekrany wychodza poza okno (to nie jest wada "
            "wylacznie tego ekranu — zglosic osobno): "
            + ", ".join(f"{p} = {n} px" for p, n in wspolne.items())
        )

    if wady:
        print(f"\n🔴 {MIERZONY[0]} wychodzi poza okno tam, gdzie proba kontrolna ma zero:")
        for punkt, nadmiar in wady.items():
            print(f"    {punkt}: {nadmiar} px (kontrola: 0)")
        return 1

    print("\n✅ Nigdzie, gdzie proba kontrolna ma zero, ten ekran nie wychodzi poza okno.")
    return 0


sys.exit(main())
