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

# --- wersja W TRESCI dokumentow (nie tylko w naglowkach) -------------------------
# Lekcja 1.0.2: dwa dokumenty deklarowaly stara wersje, a kontrola patrzyla tylko
# na naglowki wtyczek. Kazda linia dokumentu, ktora deklaruje wersje pakietu
# ("Wersja:" albo "w wersji **X**"), MUSI podawac WERSJA — inaczej stop.
for dok in "$ZRODLO_DOK/INSTRUKCJA-KLIENTA.md" "$ZRODLO_DOK/RAPORT-A11Y-WCAG.md"; do
  ZLE="$(grep -nE '(\*\*Wersja:\*\*|wszystkie w wersji \*\*)[^*]*[0-9]+\.[0-9]+\.[0-9]+' "$dok" \
         | grep -vF "$WERSJA" || true)"
  [ -z "$ZLE" ] || { echo "BLAD: $dok deklaruje inna wersje niz $WERSJA:"; echo "$ZLE"; exit 1; }
done
echo "WERSJA w dokumentach: zgodna z $WERSJA"

# --- 1) ZIP-y wtyczek ------------------------------------------------------------
bash build/build.sh

PACZKA="$DIST/paczka/mp-service-suite-$WERSJA"
rm -rf "$DIST/paczka"
mkdir -p "$PACZKA/instrukcje" "$PACZKA/diagramy" "$PACZKA/dla-informatyka" "$PACZKA/diagramy/zrodla"

# --- 2) wtyczki + dokumenty zrodlowe --------------------------------------------
for p in "${PLUGINS[@]}"; do cp "$DIST/$p.zip" "$PACZKA/"; done
cp "$ZRODLO_DOK/INSTRUKCJA-KLIENTA.md" "$ZRODLO_DOK/RAPORT-A11Y-WCAG.md" "$PACZKA/"
# Polityka kopii i cofania migracji — kartka, sekcja 4 („Backup przed wdrozeniem
# oraz mozliwosc cofniecia migracji bazy na srodowisku testowym"). Dokument
# powstal, ale do paczki nie trafial: klient mial obowiazek zrobic kopie i nie
# mial gdzie przeczytac jak.
cp dokumentacja-techniczna/MIGRATION_POLICY.md "$PACZKA/"
# Czesc DLA PROGRAMISTY klienta — architektura, kontrakt miedzy wtyczkami, model
# zdarzen, maszyna statusow, wlasnosc danych, bezpieczenstwo. Wczesniej te dokumenty
# zylly TYLKO w repozytorium: kto dostal sam ZIP, nie dostawal nic technicznego.
cp dokumentacja-techniczna/*.md "$PACZKA/dla-informatyka/"
# Narzedzie audytu dostepnosci — RAPORT-A11Y-WCAG.md kaze klientowi je URUCHOMIC,
# wiec musi byc w paczce. Wczesniej dokument odsylal do `testy/a11y/audyt-axe.py`,
# a katalogu `testy/` paczka nie zawiera wcale: obietnica bez pokrycia (29.07).
mkdir -p "$PACZKA/dla-informatyka/audyt-dostepnosci"
cp testy/a11y/audyt-axe.py "$PACZKA/dla-informatyka/audyt-dostepnosci/"
cp "$ZRODLO_DOK"/diagramy/*.png "$PACZKA/diagramy/"
# Zrodla diagramow (HTML+CSS) — zeby dalo sie je poprawic, a nie tylko ogladac obrazek.
cp "$ZRODLO_DOK"/diagramy-zrodla/* "$PACZKA/diagramy/zrodla/"
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
         RAPORT-A11Y-WCAG.md MIGRATION_POLICY.md; do
  [ -s "$PACZKA/$f" ] || zglos "brak/pusty: $f"
done
for r in "${ROLE[@]}"; do
  [ -s "$PACZKA/instrukcje/$r.md" ] || zglos "brak: instrukcje/$r.md"
  [ -s "$PACZKA/instrukcje/$r.pdf" ] || zglos "brak: instrukcje/$r.pdf"
done
[ "$(ls -1 "$PACZKA"/diagramy/*.png 2>/dev/null | wc -l)" -ge 4 ] || zglos "mniej niz 4 diagramy"

# 5a-bis. Czesc dla programisty klienta — musi byc KOMPLETNA w paczce.
# ⚠️ Lista wymaganych nazw jest WPISANA TUTAJ, a nie czytana z katalogu zrodlowego.
# Petla po `dokumentacja-techniczna/*.md` sprawdzalaby tylko to, co akurat istnieje:
# skasowanie dokumentu w repo przechodziloby na zielono (zlapane kalibracja 28.07).
DOK_TECH=(API-KONTRAKT.md DATABASE.md EVENT_MODEL.md JAKOSC-I-AUDYTY.md MIGRATION_POLICY.md OWNERSHIP.md SECURITY.md STATE_MACHINE.md)
for d in "${DOK_TECH[@]}"; do
  [ -s "$PACZKA/dla-informatyka/$d" ] || zglos "brak w paczce: dla-informatyka/$d"
done
# Dokument DOLOZONY do repo, a nieujety na liscie wyzej, tez ma zapalic lampke —
# inaczej nowa dokumentacja po cichu nie trafialaby do klienta.
LICZBA_REPO="$(ls -1 dokumentacja-techniczna/*.md 2>/dev/null | wc -l)"
[ "$LICZBA_REPO" -eq "${#DOK_TECH[@]}" ] || zglos "w repo jest $LICZBA_REPO dokumentow technicznych, a lista w skrypcie ma ${#DOK_TECH[@]} — zaktualizuj DOK_TECH"
# Zrodla diagramow — tyle zrodel HTML, ile obrazkow PNG (inaczej ktoregos nie da sie poprawic).
ZR="$(ls -1 "$PACZKA"/diagramy/zrodla/*.html 2>/dev/null | wc -l)"
PN="$(ls -1 "$PACZKA"/diagramy/*.png 2>/dev/null | wc -l)"
[ "$ZR" -eq "$PN" ] || zglos "zrodel diagramow ($ZR) nie tyle co obrazkow ($PN)"
[ -s "$PACZKA/diagramy/zrodla/style.css" ] || zglos "brak stylu zrodel diagramow (style.css)"

# 5a-ter. Narzedzie, ktore dokument kaze uruchomic, MUSI byc w paczce.
[ -s "$PACZKA/dla-informatyka/audyt-dostepnosci/audyt-axe.py" ] || zglos "brak w paczce: dla-informatyka/audyt-dostepnosci/audyt-axe.py"
# ...i zaden dokument nie moze odsylac do katalogu `testy/`, ktorego w paczce NIE MA.
# Tak wlasnie powstala poprzednia dziura: raport a11y kazal uruchomic `testy/a11y/audyt-axe.py`.
if grep -rInE '^[[:space:]]*(python3|bash|sh)[[:space:]]+testy/' "$PACZKA" --include='*.md' --include='*.txt' > /dev/null 2>&1; then
  zglos "dokument kaze uruchomic cos z katalogu testy/, ktorego paczka nie zawiera:"
  grep -rInE '^[[:space:]]*(python3|bash|sh)[[:space:]]+testy/' "$PACZKA" --include='*.md' --include='*.txt' | head -5 | sed 's/^/      /'
fi

# 5a-quater. Odnosnik do PLIKU W PACZCE musi prowadzic do czegos, co w paczce JEST.
# Zlapane audytem 4c (29.07): ADMIN.md odsylal do `dokumentacja-techniczna/MIGRATION_POLICY.md`
# przy poleceniu „zrob kopie bazy przed aktualizacja" — a takiego katalogu paczka nie ma wcale
# (plik lezy w korzeniu i w dla-informatyka/). Poprzednia kontrola pilnowala tylko `testy/`,
# wiec ten sam blad w innym katalogu przeszedl. Teraz sprawdzamy KAZDA sciezke .md/.txt/.py
# wygladajaca na odnosnik do pliku w paczce.
while read -r SC; do
	[ -n "$SC" ] || continue
	# Pomijamy odnosniki do repozytorium dostawcy — sa opisane jako takie w SECURITY.md.
	case "$SC" in testy/*|build/*|lib/*) continue ;; esac
	# Plik moze lezec LUZEM w paczce albo WEWNATRZ ZIP-a wtyczki (np. przykladowy CSV
	# w `mp-warranty-registry/przyklady/`) — instrukcja mowi wtedy „w folderze wtyczki".
	# Bez zagladania do ZIP-ow ta kontrola dawalaby falszywy alarm, a bramka, ktora
	# krzyczy bez powodu, konczy wylaczona.
	# ⛔ Sprawdzamy DOKLADNIE te sciezke, ktora podaje dokument. Wczesniejsza wersja
	# przepuszczala plik o tej samej NAZWIE lezacy gdzie indziej — a wlasnie o to chodzi:
	# ADMIN.md odsylal do `dokumentacja-techniczna/MIGRATION_POLICY.md`, plik lezal
	# w korzeniu, i klient szukalby katalogu, ktorego w paczce nie ma.
	if [ -e "$PACZKA/$SC" ]; then
		continue
	fi
	# ⚠️ BEZ potoku do `grep -q`: grep konczy po pierwszym trafieniu, `unzip` dostaje
	# SIGPIPE, a `set -o pipefail` uznaje CALY potok za porazke — kontrola zglaszalaby
	# brak pliku, ktory w zipie JEST (zlapane przy pierwszym uruchomieniu tej bramki).
	W_ZIPIE=0
	for Z in "$PACZKA"/*.zip; do
		[ -f "$Z" ] || continue
		LISTA_ZIP="$(unzip -l "$Z" 2>/dev/null || true)"
		case "$LISTA_ZIP" in *"$SC"*) W_ZIPIE=1; break ;; esac
	done
	[ "$W_ZIPIE" = "1" ] || zglos "dokument odsyla do pliku, ktorego w paczce nie ma: $SC"
done < <(grep -rhoE '`[A-Za-z0-9_./-]+/[A-Za-z0-9_.-]+\.(md|txt|py|csv)`' "$PACZKA" \
         --include='*.md' --include='*.txt' | tr -d '`' | sort -u)

# 5b. kazde zdjecie z instrukcji faktycznie jest w paczce (martwy obrazek = wstyd u klienta)
while read -r img; do
  [ -f "$PACZKA/instrukcje/zdjecia/$img" ] || zglos "instrukcje odwoluja sie do brakujacego zdjecia: $img"
done < <(grep -ho 'src="zdjecia/[^"]*"\|(zdjecia/[^)]*)' "$PACZKA"/instrukcje/*.md |
         sed -e 's|.*zdjecia/||' -e 's|[")].*||' | sort -u)

# 5c. slady wewnetrzne — paczka idzie do OBCEJ firmy
#
# Wzorce OGOLNE (srodowiskowe) sa tutaj — neutralne, maja byc widoczne w repozytorium,
# zeby kontrola dzialala u kazdego, kto sklada paczke.
#
# Wzorce PRYWATNE (imiona, nazwy robocze zespolu) czytamy z pliku obok, ktorego
# w repozytorium NIE MA (`build/.slady-prywatne`, wpisany do .gitignore). Powod:
# lista slow „ktorych nie chcemy w paczce" sama w sobie ujawnia to, co ma chronic —
# imie wypisane wprost w kodzie kontrolnym to ten sam wyciek, tylko innymi drzwiami.
# Brak pliku = kontrola leci na samych wzorcach ogolnych (nie przestaje dzialac).
# `/root/` i `:8088` dolozone 29.07 (audyt 4c): wzorzec deklarowal, ze pilnuje sladow maszyny
# roboczej, a NAJBARDZIEJ oczywistego — sciezki katalogu domowego serwera — nie lapal wcale.
# Port 8088 to lokalny WordPress warsztatu; stary zakres :809[0-9] go mijal.
SLADY='localhost|127\.0\.0\.1|:809[0-9]|:8088|/root/|poligon|mp-service-suite-repo|/tmp/|trycloudflare|mailpit|Mailpit'

MP_SLADY_PRYWATNE="$(dirname "$0")/.slady-prywatne"
if [ -s "$MP_SLADY_PRYWATNE" ]; then
  MP_DODATKOWE="$(grep -vE '^[[:space:]]*(#|$)' "$MP_SLADY_PRYWATNE" | paste -sd'|' -)"
  [ -n "$MP_DODATKOWE" ] && SLADY="$SLADY|$MP_DODATKOWE"
fi
if grep -rInE "$SLADY" "$PACZKA" --include='*.md' --include='*.txt' --include='*.py' > /dev/null 2>&1; then
  zglos "slad wewnetrzny w dokumentach:"
  grep -rInE "$SLADY" "$PACZKA" --include='*.md' --include='*.txt' --include='*.py' | head -10 | sed 's/^/      /'
fi

echo
if [ "$bledy" -gt 0 ]; then
  echo "PACZKA ODRZUCONA — $bledy problem(ow)"
  exit 1
fi
echo "PACZKA OK: $DIST/$ZIP ($(du -h "$DIST/$ZIP" | cut -f1))"
