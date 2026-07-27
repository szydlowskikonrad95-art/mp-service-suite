"""Zgodnosc przegladarek (wymog kartki: Chrome, Edge, Firefox).

Kartka zamawiajacego wymaga testow w Chrome, Edge i Firefoksie. Chrome i Edge stoja
na TYM SAMYM silniku (Blink/Chromium), wiec realnie sa dwa silniki do sprawdzenia:
Blink i Gecko. Ten test przechodzi sciezke KLIENTA w obu.

Sprawdzamy to, co u klienta zalezy od przegladarki:
  - formularz sie renderuje,
  - JavaScript przelacza pola wg rodzaju sprawy (reklamacja pyta o serial, zapytanie nie),
  - wyslanie konczy sie komunikatem (a nie cicha bledna strona),
  - panel klienta pokazuje logowanie mailem.

Uruchomienie (demo albo dowolna instancja):
    MP_BASE=http://localhost:8092 python3 testy/przegladarki/sciezka-klienta-w-przegladarkach.py

Wymaga: playwright + zainstalowane silniki (playwright install chromium firefox).
Brakujacy silnik = jasny komunikat, nie cichy pass.
"""

import os
import sys
import time

from playwright.sync_api import sync_playwright

BAZA = os.environ.get("MP_BASE", "http://localhost:8092")
SILNIKI = ("chromium", "firefox")

wynik_ogolny = 0


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
    s.goto(f"{BAZA}/zgloszenie/", wait_until="networkidle")
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
    s.fill('input[name="email"]', f"przegladarki-{nazwa}-{int(time.time())}@przyklad.pl")
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

    s.goto(f"{BAZA}/moje-sprawy/", wait_until="networkidle")
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
