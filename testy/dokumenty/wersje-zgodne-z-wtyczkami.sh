#!/usr/bin/env bash
# STRAZNIK: wersja wtyczki musi byc TA SAMA w naglowku, w stalej, w readme.txt
# i w pliku tlumaczen .pot. Trzy wtyczki, cztery zrodla kazda.
#
# POWOD ISTNIENIA — ta sama klasa bledu zlapana DWA RAZY w jednym tygodniu,
# za kazdym razem PRZYPADKIEM, przez czlowieka, a nie przez maszyne:
#
#   1) audyt paczki 1.3.12: wszystkie trzy .pot mowily `0.5.0`, wtyczki `1.3.11`.
#      Zamkniete w #253 — ale zamkniety zostal EGZEMPLARZ, nie klasa.
#   2) tydzien pozniej, po podbiciu wydania do 1.3.12: te same trzy .pot zostaly
#      na `1.3.11`. Podbicie wersji ruszylo naglowki, stale i readme, a plikow
#      tlumaczen nie tknelo. Do klienta pojechalaby paczka 1.3.12 z tlumaczeniami
#      oznaczonymi jako 1.3.11.
#
# ⛔ Dlatego ten test NIE sprawdza jednej pary. Trzeci raz przyjdzie przy nastepnym
#    podbiciu wersji i znowu zlapalby go przypadek — o ile ktos akurat spojrzy.
#    Bramka patrzy zawsze i na wszystkie cztery zrodla naraz.
#
# ⛔ STRAZNIK KOMPLETU: ekstraktory musza zlozyc co najmniej MIN_PAR par do
#    porownania. Literowka w regeksie albo przemianowany plik = BLAD PRZEBIEGU,
#    nie zielone zero. Kontrola, ktora cicho nie startuje, swieci zielono.
#    ⭐ TA LICZBA JEST ZMIERZONA, NIE OSZACOWANA: 3 wtyczki × 3 porownania
#    (naglowek↔stala, naglowek↔readme, naglowek↔.pot) = 9 par. Policzone
#    poleceniem na scalonym `main` 4.08.2026, nie z pamieci.
#
# Uruchomienie z katalogu repo:  bash testy/dokumenty/wersje-zgodne-z-wtyczkami.sh
# Zero WordPressa i zero bazy — czyta pliki repo. Exit 0 = zero FAIL.
set -u

# Katalog repo liczony z $0, nie wzglednie (w CI test chodzi z /tmp/wp).
REPO="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
cd "$REPO" || { echo "BLAD PRZEBIEGU: nie wchodze do $REPO"; exit 2; }

WTYCZKI=("mp-service-intake:MP_INTAKE_VERSION" \
         "mp-warranty-registry:MP_REGISTRY_VERSION" \
         "mp-workflow-automator:MP_AUTOMATOR_VERSION")
MIN_PAR=9

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Wersja wyglada jak wersja — pusty string albo smiec z regeksu ma byc bledem
# przyrzadu, a nie „zgodnoscia dwoch pustych".
wersja_ok() { printf '%s' "$1" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; }

PAR=0
for wpis in "${WTYCZKI[@]}"; do
	dir="${wpis%%:*}"; stala="${wpis##*:}"
	glowny="$dir/$dir.php"
	readme="$dir/readme.txt"
	pot="$dir/languages/$dir.pot"

	for f in "$glowny" "$readme" "$pot"; do
		[ -f "$f" ] || { echo "BLAD PRZEBIEGU: brak $f"; exit 2; }
	done

	# Naglowek wtyczki — zrodlo prawdy. To ta wersja, ktora widzi WordPress
	# i z ktorej `build/pakuj-dla-klienta.sh` bierze numer calej paczki.
	NAGLOWEK=$(grep -m1 -oE '^ \* Version: *[0-9]+\.[0-9]+(\.[0-9]+)?' "$glowny" \
		| grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || true)
	STALA=$(grep -m1 -oE "define\( *'$stala', *'[0-9]+\.[0-9]+(\.[0-9]+)?' *\)" "$glowny" \
		| grep -oE "'[0-9]+\.[0-9]+(\.[0-9]+)?'" | tr -d "'" || true)
	README=$(grep -m1 -oE '^Stable tag: *[0-9]+\.[0-9]+(\.[0-9]+)?' "$readme" \
		| grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || true)
	# .pot: `"Project-Id-Version: MP Service Intake 1.3.12\n"` — numer na koncu,
	# przed `\n"`. Nazwa produktu miedzy dwukropkiem a numerem bywa wieloczlonowa.
	POT=$(grep -m1 -oE '^"Project-Id-Version:.*[0-9]+\.[0-9]+(\.[0-9]+)?' "$pot" \
		| grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?$' || true)

	# PROBA KONTROLNA metody: kazdy ekstraktor ma zwrocic cos, co wyglada jak
	# wersja. Bez tego „zgodne" moglo znaczyc „oba puste".
	for para in "naglowek:$NAGLOWEK" "stala:$STALA" "readme:$README" "pot:$POT"; do
		nazwa="${para%%:*}"; wart="${para#*:}"
		wersja_ok "$wart" || {
			echo "BLAD PRZEBIEGU: ekstraktor '$nazwa' dla $dir zwrocil '$wart' — to nie jest wersja."
			echo "Kontrola NIE wykonala sie dla tej wtyczki — to wada przyrzadu, nie zielone zero."
			exit 2
		}
	done

	echo "  ($dir: naglowek=$NAGLOWEK stala=$STALA readme=$README pot=$POT)"

	[ "$STALA" = "$NAGLOWEK" ] \
		&& ok "$dir: stala $stala zgodna z naglowkiem ($NAGLOWEK)" \
		|| bad "$dir: stala $stala = $STALA, a naglowek = $NAGLOWEK"
	PAR=$((PAR+1))

	[ "$README" = "$NAGLOWEK" ] \
		&& ok "$dir: readme.txt Stable tag zgodny z naglowkiem ($NAGLOWEK)" \
		|| bad "$dir: readme.txt Stable tag = $README, a naglowek = $NAGLOWEK"
	PAR=$((PAR+1))

	[ "$POT" = "$NAGLOWEK" ] \
		&& ok "$dir: .pot Project-Id-Version zgodny z naglowkiem ($NAGLOWEK)" \
		|| bad "$dir: .pot Project-Id-Version = $POT, a naglowek = $NAGLOWEK — paczka pojedzie z tlumaczeniami z innego wydania"
	PAR=$((PAR+1))
done

# STRAZNIK KOMPLETU — mniej par niz zmierzono znaczy, ze czesc kontroli nie ruszyla.
if [ "$PAR" -lt "$MIN_PAR" ]; then
	echo "BLAD PRZEBIEGU: zlozono tylko $PAR par do porownania (< $MIN_PAR)."
	echo "Czesc wtyczek wypadla z przebiegu — to wada przyrzadu, nie zielone zero."
	exit 2
fi
echo "  (porownano $PAR par wersji w ${#WTYCZKI[@]} wtyczkach)"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
