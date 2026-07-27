"""Renderuje diagramy dla klienta: HTML+CSS -> PNG (@2x, ostre na papierze i na ekranie).

Zrodlem jest HTML w dla-klienta/diagramy-zrodla/ — edytowalne, wersjonowane, czytelne
w diffie (inaczej niz binarny obrazek). PNG powstaje z niego jednym poleceniem:

    python3 build/render-diagramy.py

Wymaga playwright z chromium (jest w systemie; instalacja: playwright install chromium).
"""

import pathlib
import sys

from playwright.sync_api import sync_playwright

KORZEN = pathlib.Path(__file__).resolve().parent.parent
ZRODLA = KORZEN / "dla-klienta" / "diagramy-zrodla"
CEL = KORZEN / "dla-klienta" / "diagramy"

# zrodlo -> nazwa pliku PNG. Nazwa pliku ma opisywac TRESC: stare nazwy zostaly po
# poprzedniej wersji diagramow i klamaly (plik "maszyna-stanow" zawieral tabele,
# "przeplyw-8-krokow" mial 7 krokow, "architektura-hooki" — dokument bez slowa o hookach).
MAPA = {
    "01-z-czego-sklada-sie-system.html": "01-z-czego-sklada-sie-system.png",
    "02-przeplyw-zgloszenia.html": "02-droga-zgloszenia.png",
    "03-statusy-sprawy.html": "03-statusy-sprawy.png",
    "04-gdzie-mieszkaja-dane.html": "04-gdzie-mieszkaja-dane.png",
}

CEL.mkdir(parents=True, exist_ok=True)
bledy = 0

with sync_playwright() as pw:
    b = pw.chromium.launch(args=["--lang=pl-PL"])
    k = b.new_context(viewport={"width": 1000, "height": 800}, device_scale_factor=2,
                      color_scheme="light", locale="pl-PL")
    s = k.new_page()

    for zrodlo, wynik in MAPA.items():
        plik = ZRODLA / zrodlo
        if not plik.exists():
            print(f"  BRAK ZRODLA: {zrodlo}")
            bledy += 1
            continue
        s.goto(plik.as_uri(), wait_until="networkidle")
        s.wait_for_timeout(400)
        cel = CEL / wynik
        s.screenshot(path=str(cel), full_page=True)
        print(f"  {wynik}  ({cel.stat().st_size // 1024} KB)")

    b.close()

sys.exit(1 if bledy else 0)
