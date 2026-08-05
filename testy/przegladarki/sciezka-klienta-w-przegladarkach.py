"""Zgodnosc przegladarek (wymog specyfikacji: Chrome, Edge, Firefox).

Specyfikacja zamawiajacego wymaga testow w Chrome, Edge i Firefoksie. Chrome i Edge stoja
na TYM SAMYM silniku (Blink/Chromium), wiec realnie sa dwa silniki do sprawdzenia:
Blink i Gecko. Ten test przechodzi sciezke KLIENTA w obu.

Sprawdzamy to, co u klienta zalezy od przegladarki:
  - formularz sie renderuje,
  - JavaScript przelacza pola wg rodzaju sprawy (reklamacja pyta o serial, zapytanie nie),
  - wyslanie konczy sie komunikatem (a nie cicha bledna strona),
  - panel klienta pokazuje logowanie mailem.

Uruchomienie (demo albo dowolna instancja):
    MP_BASE=http://localhost:8097 python3 testy/przegladarki/sciezka-klienta-w-przegladarkach.py

Wymaga: playwright + zainstalowane silniki (playwright install chromium firefox).
Brakujacy silnik = jasny komunikat, nie cichy pass.
"""

import json
import os
import sys
import time
import urllib.request

from playwright.sync_api import sync_playwright

# Domyslnie witryna, ktora repo stawia samo (`testy/paczka-od-zera/uruchom.sh`).
# Poprzednia wartosc (8092) wskazywala na srodowisko, ktorego juz nie ma — domyslna
# wartosc prowadzaca donikad to zaproszenie do badania nie tego, co trzeba.
BAZA = os.environ.get("MP_BASE", "http://localhost:8097")
SILNIKI = ("chromium", "firefox")

wynik_ogolny = 0


def adres_strony(slug, zmienna, opis):
    """Adres strony zalozonej przez wtyczke — pytamy o niego witryne, nie zgadujemy.

    Zaszyte `/zgloszenie/` i `/moje-sprawy/` istnialy tylko na recznie ustawionym
    srodowisku deweloperskim; instalacja z paczki zaklada `zgloszenie-serwisowe`
    i `panel-zgloszen`. REST oddaje gotowy `link`, wiec dziala takze przy
    „prostych" odnosnikach (?page_id=N). Nadpisanie: MP_URL_FORMULARZ / MP_URL_PANEL.
    """
    z_env = os.environ.get(zmienna)
    if z_env:
        return z_env
    url = f"{BAZA}/?rest_route=/wp/v2/pages&slug={slug}"
    try:
        strony = json.load(urllib.request.urlopen(url))
    except Exception as e:  # noqa: BLE001 — jasny komunikat zamiast stosu wyjatkow
        sys.exit(f"Nie da sie zapytac witryny o adres strony '{opis}' ({url}): {e}")
    if not strony:
        sys.exit(
            f"Witryna nie ma strony '{opis}' (slug: {slug}). Wtyczka zaklada ja przy "
            f"aktywacji — sprawdz, czy jest aktywna. Adres mozna wskazac recznie: {zmienna}=..."
        )
    return strony[0]["link"]


URL_FORMULARZ = adres_strony("zgloszenie-serwisowe", "MP_URL_FORMULARZ", "formularz zgloszenia")
URL_PANEL = adres_strony("panel-zgloszen", "MP_URL_PANEL", "panel klienta")


def sciezka(nazwa, przegladarka):
    global wynik_ogolny
    ok = fail = 0

    def sprawdz(warunek, opis):
        nonlocal ok, fail
        if warunek:
            ok += 1
            print(f"  OK   {opis}")
        else:
            fail += 1
            print(f"  FAIL {opis}")

    k = przegladarka.new_context(viewport={"width": 1280, "height": 900}, locale="pl-PL")
    s = k.new_page()
    s.goto(URL_FORMULARZ, wait_until="networkidle")
    s.wait_for_timeout(900)

    sprawdz(s.locator('form select[name="kind"]').count() == 1, "formularz zgloszenia renderuje sie")

    s.select_option('select[name="kind"]', "reklamacja")
    s.wait_for_timeout(500)
    serial_widoczny = s.locator('input[name="serial"]').is_visible()
    s.select_option('select[name="kind"]', "zapytanie")
    s.wait_for_timeout(500)
    serial_ukryty = not s.locator('input[name="serial"]').is_visible()
    sprawdz(serial_widoczny and serial_ukryty, "JS przelacza pola wg rodzaju sprawy")

    s.select_option('select[name="kind"]', "reklamacja")
    s.wait_for_timeout(400)
    # example.com — domena zarezerwowana (RFC 2606). `przyklad.pl` jest prawdziwa i cudza.
    s.fill('input[name="email"]', f"przegladarki-{nazwa}-{int(time.time())}@example.com")
    s.fill('input[name="customer_name"]', "Klient Testowy")
    s.fill('input[name="serial"]', "SN-AUD-1001")
    s.fill('input[name="purchase_document"]', "FV/2026/0410")
    s.fill('input[name="purchase_date"]', "2026-04-12")
    s.fill('textarea[name="issue_description"]', "Test zgodnosci przegladarek.")
    s.check('input[name="mp_consent"]')
    s.wait_for_timeout(2200)  # pulapka czasu: formularz odrzuca wysylke ponizej 2 s
    s.click('button[type="submit"]')
    s.wait_for_load_state("networkidle")
    s.wait_for_timeout(1200)
    tresc = s.inner_text("body").lower()
    sprawdz(any(x in tresc for x in ("sprawd", "potwierd", "dziękujemy", "wysłal")),
            "wyslanie konczy sie komunikatem dla klienta")

    s.goto(URL_PANEL, wait_until="networkidle")
    s.wait_for_timeout(700)
    sprawdz(s.locator('input[type="email"]').count() >= 1, "panel klienta: logowanie mailem")

    k.close()
    if fail:
        wynik_ogolny = 1
    return ok, fail


with sync_playwright() as pw:
    for nazwa in SILNIKI:
        try:
            b = getattr(pw, nazwa).launch()
        except Exception as e:  # brakujacy silnik NIE moze udawac sukcesu
            print(f"\n=== {nazwa}: NIE URUCHOMIONO ===\n  {str(e)[:160]}")
            wynik_ogolny = 1
            continue
        print(f"\n=== {nazwa} {b.version} ===")
        sciezka(nazwa, b)
        b.close()

print("\nWYNIK:", "wszystkie silniki OK" if wynik_ogolny == 0 else "SA BLEDY")
sys.exit(wynik_ogolny)
