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

ADRESY STRON: pytamy o nie sama witryne (REST `?rest_route=`), po slugach, ktore
wtyczka zaklada przy aktywacji. Wczesniej byly tu zaszyte `/zgloszenie/` i
`/moje-sprawy/` — takie strony istnialy tylko na recznie ustawionym srodowisku
deweloperskim. Na instalacji, ktora POWSTAJE Z PACZKI, oba adresy oddaja strone
glowna z kodem 200, a axe grzecznie zbadalby strone glowna i zameldowal zero
naruszen. Zapytanie o adres dziala takze przy „prostych" odnosnikach (?page_id=N),
bo REST zwraca gotowy `link`. Nadpisanie: MP_URL_FORMULARZ / MP_URL_PANEL.

BRAMKA: po wejsciu na strone sprawdzamy, ze to naprawde nasza powierzchnia
(formularz ma `select[name=kind]`, panel ma pole e-mail). Brak = blad, nie cichy pass.

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


def audytuj(strona, nazwa, nasz_selektor):
    """Bada CALA strone (tak widzi ja uzytkownik) i osobno NASZ fragment.

    Rozdzielenie jest konieczne, bo na stronie klienta obok naszego formularza stoi
    motyw WordPressa, ktorego nie dostarczamy i nie mozemy poprawic. Za wynik
    odpowiadamy w naszej czesci — i tylko ona decyduje o kodzie wyjscia. Naruszenia
    motywu raportujemy jawnie, bo klient i tak je u siebie zobaczy.
    """
    global bledy
    strona.add_script_tag(content=AXE)
    wynik = strona.evaluate(
        """async ([tagi, sel]) => {
            const opcje = { runOnly: { type: 'tag', values: tagi } };
            const skrot = r => ({ passes: r.passes.length, naruszenia: r.violations.map(v => ({
                id: v.id, impact: v.impact, ile: v.nodes.length,
                gdzie: v.nodes.slice(0, 3).map(n => n.target.join(' ')).join(' | ') })) });
            const cala = await axe.run(document, opcje);
            const wezel = sel ? document.querySelector(sel) : null;
            return { cala: skrot(cala), nasza: wezel ? skrot(await axe.run(wezel, opcje)) : null };
        }""",
        [TAGI, nasz_selektor],
    )
    nasza, cala = wynik["nasza"], wynik["cala"]
    if nasza is None:
        print(f"\n--- {nazwa}: BLAD — nie ma naszego fragmentu `{nasz_selektor}` na stronie")
        bledy += 1
        return wynik

    print(f"\n--- {nazwa}")
    print(f"     nasza czesc ({nasz_selektor}): przeszlo {nasza['passes']} regul, "
          f"naruszen {len(nasza['naruszenia'])}")
    for n in nasza["naruszenia"]:
        print(f"       {n['id']} [{n['impact']}] x{n['ile']} — {n['gdzie'][:110]}")
        bledy += 1

    obce = [n for n in cala["naruszenia"] if n["id"] not in {x["id"] for x in nasza["naruszenia"]}]
    print(f"     cala strona z motywem: przeszlo {cala['passes']} regul, "
          f"naruszen {len(cala['naruszenia'])}"
          + (f" (w tym {len(obce)} poza naszym kodem)" if obce else ""))
    for n in obce:
        print(f"       [motyw] {n['id']} [{n['impact']}] x{n['ile']} — {n['gdzie'][:110]}")
    return wynik


def adres_strony(slug, zmienna, opis):
    """Adres strony zalozonej przez wtyczke — pytamy o niego witryne, nie zgadujemy."""
    z_env = os.environ.get(zmienna)
    if z_env:
        return z_env
    url = f"{BAZA}/?rest_route=/wp/v2/pages&slug={slug}"
    try:
        strony = json.load(urllib.request.urlopen(url))
    except Exception as e:  # noqa: BLE001 — chcemy JASNY komunikat, nie stos wyjatkow
        sys.exit(f"Nie da sie zapytac witryny o adres strony '{opis}' ({url}): {e}")
    if not strony:
        sys.exit(
            f"Witryna nie ma strony '{opis}' (slug: {slug}). Wtyczka zaklada ja przy "
            f"aktywacji — sprawdz, czy jest aktywna. Adres mozna wskazac recznie: {zmienna}=..."
        )
    return strony[0]["link"]


def upewnij_sie(strona, selektor, opis):
    """Bramka: badamy TO, co mielismy badac. Pusto = blad, nie zero naruszen."""
    if strona.locator(selektor).count() < 1:
        sys.exit(
            f"BLAD: pod adresem {strona.url} nie ma powierzchni '{opis}' "
            f"(brak `{selektor}`). Badanie przerwane — inaczej wynik bylby falszywie czysty."
        )


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

    URL_FORMULARZ = adres_strony("zgloszenie-serwisowe", "MP_URL_FORMULARZ", "formularz zgloszenia")
    URL_PANEL = adres_strony("panel-zgloszen", "MP_URL_PANEL", "panel klienta")
    print(f"Badane adresy:\n  formularz: {URL_FORMULARZ}\n  panel:     {URL_PANEL}")

    s.goto(URL_FORMULARZ, wait_until="networkidle")
    s.wait_for_timeout(800)
    upewnij_sie(s, 'form select[name="kind"]', "formularz zgloszenia")
    audytuj(s, "Formularz zgloszenia (publiczny)", ".mp-intake")

    s.goto(URL_PANEL, wait_until="networkidle")
    s.wait_for_timeout(600)
    upewnij_sie(s, 'input[type="email"]', "panel klienta — logowanie mailem")
    audytuj(s, "Panel klienta — przed zalogowaniem", ".mp-account")

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
        audytuj(s, "Panel klienta — po zalogowaniu", ".mp-account")
    else:
        print("\n--- Panel zalogowany: POMINIETY (brak linku logowania w skrzynce)")
        bledy += 1

    b.close()

print("\nWYNIK:", "zero naruszen w naszych powierzchniach"
      if bledy == 0 else f"naruszen w naszych powierzchniach: {bledy}")
sys.exit(1 if bledy else 0)
