"""Markdown -> jednoplikowy HTML gotowy do druku (chromium --print-to-pdf).

Uzywane przez build/pakuj-dla-klienta.sh do zlozenia dokumentow klienta.
Sciezki obrazkow zamieniane na absolutne, bo chromium drukuje z katalogu tymczasowego.
"""

import pathlib
import sys

import markdown

zrodlo = pathlib.Path(sys.argv[1]).resolve()
wynik = pathlib.Path(sys.argv[2])
tytul = sys.argv[3]

tresc = zrodlo.read_text(encoding="utf-8")
html_body = markdown.markdown(tresc, extensions=["tables", "fenced_code", "toc", "nl2br"])

# Obrazki: sciezki wzgledne musza dzialac przy druku spoza katalogu zrodla.
html_body = html_body.replace('src="zdjecia/', f'src="{zrodlo.parent}/zdjecia/')

STYL = """
@page { size: A4; margin: 18mm 16mm 20mm 16mm; }
body { font-family: -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif;
       font-size: 10.5pt; line-height: 1.55; color: #1f2328; max-width: 100%; }
h1 { font-size: 20pt; border-bottom: 3px solid #2271b1; padding-bottom: .3em; color: #0b4a75; }
h2 { font-size: 14pt; margin-top: 1.6em; color: #0b4a75; border-bottom: 1px solid #d0d7de; padding-bottom: .2em; }
h3 { font-size: 11.5pt; margin-top: 1.2em; color: #24292f; }
h2, h3 { page-break-after: avoid; }
img { max-width: 100%; border: 1px solid #d0d7de; border-radius: 4px; margin: .6em 0;
      page-break-inside: avoid; }
table { border-collapse: collapse; width: 100%; margin: .8em 0; font-size: 9.5pt;
        page-break-inside: avoid; }
th, td { border: 1px solid #d0d7de; padding: .45em .6em; text-align: left; vertical-align: top; }
th { background: #f6f8fa; font-weight: 600; }
code { background: #f6f8fa; padding: .12em .35em; border-radius: 3px;
       font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: .9em; }
pre { background: #f6f8fa; padding: .8em; border-radius: 6px; overflow-x: auto;
      page-break-inside: avoid; border: 1px solid #d0d7de; }
pre code { background: none; padding: 0; }
blockquote { border-left: 4px solid #2271b1; margin: .8em 0; padding: .1em 1em;
             background: #f6f8fa; color: #444; }
ul, ol { padding-left: 1.4em; }
li { margin: .25em 0; }
hr { border: none; border-top: 1px solid #d0d7de; margin: 1.5em 0; }
a { color: #2271b1; }
strong { color: #0b4a75; }
"""

wynik.write_text(
    f'<!doctype html><html lang="pl"><head><meta charset="utf-8">'
    f"<title>{tytul}</title><style>{STYL}</style></head><body>{html_body}</body></html>",
    encoding="utf-8",
)
print(f"HTML: {wynik.name} ({len(html_body)} znakow tresci)")
