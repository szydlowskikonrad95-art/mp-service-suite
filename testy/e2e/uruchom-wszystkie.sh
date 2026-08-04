#!/usr/bin/env bash
# Uruchamia CALY zestaw testow e2e — z AUTOMATYCZNYM WYKRYWANIEM plikow.
#
# ⛔ PO CO TO POWSTALO. Kazdy nowy test trzeba bylo wpisac recznie do
# `.github/workflows/quality.yml`, zawsze w to samo miejsce listy. Skutek byl podwojny:
#   · kazde dwie galezie robione rownolegle KONFLIKTOWALY w tym pliku (u nas cztery razy
#     jednej nocy), a konflikt w YAML-u latwo rozwiazac tak, ze cudzy krok wypada po cichu;
#   · test napisany i NIEWPIETY nie chodzil nigdzie — wygladal jak dowod, a nim nie byl.
# Teraz dodanie testu = dodanie PLIKU. Wspolnego pliku nikt nie dotyka, wiec nie ma o co
# konfliktowac, a zapomniec o wpieciu sie nie da.
#
# KOLEJNOSC: `KOLEJNOSC.txt` trzyma porzadek, w ktorym testy chodzily do tej pory —
# zachowany co do pliku, zeby zmiana narzedzia NIE zmienila warunkow pomiaru. Pliki
# spoza listy doklejaja sie na koncu alfabetycznie. Nowego testu nie trzeba nigdzie
# dopisywac; wpis do KOLEJNOSC.txt sluzy WYLACZNIE wymuszeniu wczesniejszego miejsca.
#
# POZA-PRZEBIEGIEM.txt: testy nalezace do INNYCH zadan CI (instalacja z paczki, migracja,
# dirty-env). Ich uruchomienie tutaj nie ma sensu — maja wlasne srodowisko.
#
# ⛔ LICZBA WYKONANYCH TESTOW JEST DRUKOWANA I SPRAWDZANA. Bramka, ktora cicho nic nie
# uruchomi, swieci zielono — a to gorsze niz brak bramki.
set -u

KATALOG="$(cd "$(dirname "$0")" && pwd)"
: "${MP_BASE:=http://127.0.0.1:8080}"
export MP_BASE

MINIMUM=${MP_MIN_TESTOW:-80}

wczytaj_liste() {
	[ -f "$1" ] || return 0
	grep -vE '^\s*(#|$)' "$1" 2>/dev/null | tr -d '\r'
}

mapfile -t KOLEJNE < <(wczytaj_liste "$KATALOG/KOLEJNOSC.txt")
mapfile -t POMIJANE < <(wczytaj_liste "$KATALOG/POZA-PRZEBIEGIEM.txt")

pomijany() {
	local p
	for p in "${POMIJANE[@]:-}"; do [ "$p" = "$1" ] && return 0; done
	return 1
}

na_liscie() {
	local p
	for p in "${KOLEJNE[@]:-}"; do [ "$p" = "$1" ] && return 0; done
	return 1
}

DO_URUCHOMIENIA=()
BRAKUJACE=()

for T in "${KOLEJNE[@]:-}"; do
	pomijany "$T" && continue
	if [ ! -f "$KATALOG/$T" ]; then
		BRAKUJACE+=( "$T" )
		continue
	fi
	DO_URUCHOMIENIA+=( "$T" )
done

NOWE=()
for SCIEZKA in "$KATALOG"/*.sh; do
	T="$(basename "$SCIEZKA")"
	[ "$T" = "uruchom-wszystkie.sh" ] && continue
	na_liscie "$T" && continue
	pomijany "$T" && continue
	NOWE+=( "$T" )
done

if [ "${#NOWE[@]}" -gt 0 ]; then
	echo "🆕 Wykryte automatycznie (nie ma ich w KOLEJNOSC.txt): ${NOWE[*]}"
	DO_URUCHOMIENIA+=( "${NOWE[@]}" )
fi

if [ "${#BRAKUJACE[@]}" -gt 0 ]; then
	echo "⚠ W KOLEJNOSC.txt sa nazwy BEZ PLIKU (skasowane albo przemianowane): ${BRAKUJACE[*]}"
fi

ILE="${#DO_URUCHOMIENIA[@]}"

# Podglad bez uruchamiania — do sprawdzenia, CO wejdzie do przebiegu.
if [ "${1:-}" = "--lista" ]; then
	printf '%s\n' "${DO_URUCHOMIENIA[@]}"
	echo "RAZEM: $ILE"
	exit 0
fi

echo "▶ Do uruchomienia: $ILE testow (MP_BASE=$MP_BASE)"
echo

PADLY=()
WYKONANE=0

for T in "${DO_URUCHOMIENIA[@]}"; do
	echo "───── $T ─────"
	bash "$KATALOG/$T" || PADLY+=( "$T" )
	WYKONANE=$(( WYKONANE + 1 ))
	echo
done

echo "═══════════════════════════════"
echo "WYKONANE: $WYKONANE z $ILE · PADLY: ${#PADLY[@]}"

if [ "${#PADLY[@]}" -gt 0 ]; then
	printf '  ✖ %s\n' "${PADLY[@]}"
fi

# Bramka widocznosci: gdy zestaw nagle sie kurczy, to nie jest sukces, tylko awaria
# wykrywania albo skasowane pliki — inaczej zniknieciu polowy testow towarzyszyloby
# spokojne „zielone CI".
if [ "$WYKONANE" -lt "$MINIMUM" ]; then
	echo "⛔ URUCHOMIONO TYLKO $WYKONANE TESTOW, a minimum to $MINIMUM."
	echo "   To NIE jest zielone CI — to zepsute wykrywanie albo skasowane pliki testow."
	exit 1
fi

[ "${#PADLY[@]}" -eq 0 ] || exit 1
echo "✔ Caly zestaw przeszedl."
