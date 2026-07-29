"""Audyt dostepnosci (WCAG 2.1 A + AA) silnikiem axe-core na ZYWEJ stronie.

Raport dla klienta ma byc odtwarzalny, a nie deklaracja — to jest narzedzie, ktorym
kazdy (takze klient) sprawdzi wynik u siebie:

    npm i axe-core                       # raz, gdziekolwiek
    MP_BASE=http://localhost:8092 \\
    AXE=./node_modules/axe-core/axe.min.js \\
    python3 testy/a11y/audyt-axe.py

Sprawdza trzy powierzchnie, ktore widzi KLIENT: formularz zgloszenia, panel przed
zalogowaniem i panel po zalogowaniu (logowanie linkiem z maila czytanym z Mailpita).
Panel zalogowany jest najwazniejszy — tam sa dane osobowe i tam CI bez przegladarki
nie dosiegnie kontrastu kolorow.

Kod wyjscia: 0 = zero naruszen w naszych powierzchniach.
"""

import json
import os
import pathlib
import re
import sys
import urllib.request

from playwright.sync_api import sync_playwright

BAZA = os.environ.get("MP_BASE", "http://localhost:8092")
MAILPIT = os.environ.get("MP_MAILPIT", "http://localhost:8093")
EMAIL = os.environ.get("MP_EMAIL", "anna.nowak@example.com")
AXE_PLIK = pathlib.Path(os.environ.get("AXE", "./node_modules/axe-core/axe.min.js"))
TAGI = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]

if not AXE_PLIK.exists():
    sys.exit(f"Brak axe-core: {AXE_PLIK}. Zainstaluj: npm i axe-core (albo wskaz zmienna AXE).")

AXE = AXE_PLIK.read_text()
bledy = 0


def audytuj(strona, nazwa):
    global bledy
    strona.add_script_tag(content=AXE)
    wynik = strona.evaluate(
        """async (tagi) => {
            const r = await axe.run(document, { runOnly: { type: 'tag', values: tagi } });
            return { passes: r.passes.length, naruszenia: r.violations.map(v => ({
                id: v.id, impact: v.impact, ile: v.nodes.length,
                gdzie: v.nodes.slice(0, 3).map(n => n.target.join(' ')).join(' | ') })) };
        }""",
        TAGI,
    )
    print(f"\n--- {nazwa}: przeszlo {wynik['passes']} regul, naruszen {len(wynik['naruszenia'])}")
    for n in wynik["naruszenia"]:
        print(f"     {n['id']} [{n['impact']}] x{n['ile']} — {n['gdzie'][:110]}")
        bledy += 1
    return wynik


def link_logowania():
    dane = json.load(urllib.request.urlopen(f"{MAILPIT}/api/v1/messages"))
    mid = next(m["ID"] for m in dane["messages"] if "Logowanie" in m["Subject"])
    tresc = json.load(urllib.request.urlopen(f"{MAILPIT}/api/v1/message/{mid}"))
    szukaj = re.search(r"https?://[^\s\"<>]*mp_intake_login[^\s\"<>]*", tresc.get("Text") or "")
    return szukaj.group(0).replace("&amp;", "&").strip() if szukaj else None


with sync_playwright() as pw:
    b = pw.chromium.launch()
    k = b.new_context(viewport={"width": 1280, "height": 900}, locale="pl-PL")
    s = k.new_page()

    s.goto(f"{BAZA}/zgloszenie/", wait_until="networkidle")
    s.wait_for_timeout(800)
    audytuj(s, "Formularz zgloszenia (publiczny)")

    s.goto(f"{BAZA}/moje-sprawy/", wait_until="networkidle")
    s.wait_for_timeout(600)
    audytuj(s, "Panel klienta — przed zalogowaniem")

    s.fill('input[type="email"]', EMAIL)
    s.click('button[type="submit"]')
    s.wait_for_load_state("networkidle")
    s.wait_for_timeout(2500)
    link = link_logowania()
    if link:
        s.goto(link, wait_until="networkidle")
        s.click('button[type="submit"]')
        s.wait_for_load_state("networkidle")
        s.wait_for_timeout(1500)
        audytuj(s, "Panel klienta — po zalogowaniu")
    else:
        print("\n--- Panel zalogowany: POMINIETY (brak linku logowania w skrzynce)")
        bledy += 1

    b.close()

print("\nWYNIK:", "zero naruszen w naszych powierzchniach" if bledy == 0 else f"naruszen: {bledy}")
sys.exit(1 if bledy else 0)
