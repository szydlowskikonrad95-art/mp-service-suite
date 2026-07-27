#!/usr/bin/env bash
# Sklada ZBIORCZA PACZKE DLA KLIENTA: 3 wtyczki (.zip) + dokumenty (md+PDF) + zdjecia + diagramy.
# Wczesniej skladane recznie — czego nie da sie odtworzyc jednym poleceniem, tego nie ma.
#
#   bash build/pakuj-dla-klienta.sh
#   -> build/dist/mp-service-suite-KLIENT-<WERSJA>.zip
#
# Wersja pochodzi z naglowka wtyczki (nie z argumentu) — trzy wtyczki musza sie zgadzac.
# Na koncu leci SAMOKONTROLA: komplet plikow, zdjecia z instrukcji, brak sladow wewnetrznych.
set -euo pipefail
cd "$(dirname "$0")/.."

DIST="build/dist"
ZRODLO_DOK="dla-klienta"
PLUGINS=(mp-service-intake mp-warranty-registry mp-workflow-automator)
ROLE=(KLIENT PRACOWNIK KOORDYNATOR ADMIN)

# --- wersja: jedno zrodlo prawdy = naglowek wtyczki ------------------------------
WERSJA="$(sed -n 's/^ \* Version: *//p' mp-service-intake/mp-service-intake.php | head -1)"
[ -n "$WERSJA" ] || { echo "BLAD: nie odczytalem wersji z naglowka mp-service-intake"; exit 1; }
for p in "${PLUGINS[@]}"; do
  w="$(sed -n 's/^ \* Version: *//p' "$p/$p.php" | head -1)"
  [ "$w" = "$WERSJA" ] || { echo "BLAD: $p ma wersje $w, a mp-service-intake $WERSJA"; exit 1; }
  s="$(sed -n 's/^Stable tag: *//p' "$p/readme.txt" | head -1)"
  [ "$s" = "$WERSJA" ] || { echo "BLAD: $p/readme.txt Stable tag=$s, naglowek=$WERSJA"; exit 1; }
done
echo "WERSJA: $WERSJA (zgodna w 3 wtyczkach + readme.txt)"

# --- 1) ZIP-y wtyczek ------------------------------------------------------------
bash build/build.sh

PACZKA="$DIST/paczka/mp-service-suite-$WERSJA"
rm -rf "$DIST/paczka"
mkdir -p "$PACZKA/instrukcje" "$PACZKA/diagramy"

# --- 2) wtyczki + dokumenty zrodlowe --------------------------------------------
for p in "${PLUGINS[@]}"; do cp "$DIST/$p.zip" "$PACZKA/"; done
cp "$ZRODLO_DOK/INSTRUKCJA-KLIENTA.md" "$ZRODLO_DOK/RAPORT-A11Y-WCAG.md" "$PACZKA/"
cp "$ZRODLO_DOK"/diagramy/*.png "$PACZKA/diagramy/"
cp "$ZRODLO_DOK"/instrukcje/*.md "$PACZKA/instrukcje/"
cp -r "$ZRODLO_DOK/instrukcje/zdjecia" "$PACZKA/instrukcje/"
sed "s/{{WERSJA}}/$WERSJA/g" "$ZRODLO_DOK/PRZECZYTAJ-MNIE.txt" > "$PACZKA/PRZECZYTAJ-MNIE.txt"

# --- 3) PDF-y (markdown -> HTML -> chromium) -------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
drukuj() { # $1=zrodlo.md  $2=wynik.pdf  $3=tytul
  python3 build/md2html.py "$1" "$TMP/dok.html" "$3"
  chromium --headless --disable-gpu --no-sandbox --no-pdf-header-footer \
           --print-to-pdf="$2" "file://$TMP/dok.html" > /dev/null 2>&1
  [ -s "$2" ] || { echo "BLAD: pusty PDF $2"; exit 1; }
}
drukuj "$ZRODLO_DOK/INSTRUKCJA-KLIENTA.md" "$PACZKA/INSTRUKCJA-KLIENTA.pdf" "Instrukcja wdrozenia"
for r in "${ROLE[@]}"; do
  drukuj "$ZRODLO_DOK/instrukcje/$r.md" "$PACZKA/instrukcje/$r.pdf" "Instrukcja: $r"
done

# --- 4) ZIP zbiorczy -------------------------------------------------------------
ZIP="mp-service-suite-KLIENT-$WERSJA.zip"
(cd "$DIST/paczka" && zip -qr "../$ZIP" "mp-service-suite-$WERSJA")

# --- 5) SAMOKONTROLA (bramka, nie komentarz) -------------------------------------
bledy=0
zglos() { echo "  ✗ $1"; bledy=$((bledy + 1)); }

# 5a. komplet plikow
for f in "${PLUGINS[@]/%/.zip}" PRZECZYTAJ-MNIE.txt INSTRUKCJA-KLIENTA.md INSTRUKCJA-KLIENTA.pdf \
         RAPORT-A11Y-WCAG.md; do
  [ -s "$PACZKA/$f" ] || zglos "brak/pusty: $f"
done
for r in "${ROLE[@]}"; do
  [ -s "$PACZKA/instrukcje/$r.md" ] || zglos "brak: instrukcje/$r.md"
  [ -s "$PACZKA/instrukcje/$r.pdf" ] || zglos "brak: instrukcje/$r.pdf"
done
[ "$(ls -1 "$PACZKA"/diagramy/*.png 2>/dev/null | wc -l)" -ge 4 ] || zglos "mniej niz 4 diagramy"

# 5b. kazde zdjecie z instrukcji faktycznie jest w paczce (martwy obrazek = wstyd u klienta)
while read -r img; do
  [ -f "$PACZKA/instrukcje/zdjecia/$img" ] || zglos "instrukcje odwoluja sie do brakujacego zdjecia: $img"
done < <(grep -ho 'src="zdjecia/[^"]*"\|(zdjecia/[^)]*)' "$PACZKA"/instrukcje/*.md |
         sed -e 's|.*zdjecia/||' -e 's|[")].*||' | sort -u)

# 5c. slady wewnetrzne — paczka idzie do OBCEJ firmy
SLADY='localhost|127\.0\.0\.1|:809[0-9]|poligon|Dzidek|dzidek|kolegi|mp-service-suite-repo|/tmp/'
if grep -rInE "$SLADY" "$PACZKA" --include='*.md' --include='*.txt' > /dev/null 2>&1; then
  zglos "slad wewnetrzny w dokumentach:"
  grep -rInE "$SLADY" "$PACZKA" --include='*.md' --include='*.txt' | head -10 | sed 's/^/      /'
fi

echo
if [ "$bledy" -gt 0 ]; then
  echo "PACZKA ODRZUCONA — $bledy problem(ow)"
  exit 1
fi
echo "PACZKA OK: $DIST/$ZIP ($(du -h "$DIST/$ZIP" | cut -f1))"
