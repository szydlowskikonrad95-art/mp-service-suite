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
# ⛔ TESTY NISZCZACE — odinstalowuja wtyczki, wiec MUSZA byc ostatnie. Bez tego kazdy nowo
# wykryty plik doklejalby sie ZA nimi i lecial na wykasowanym produkcie (zlapane 4.08).
mapfile -t NA_KONIEC < <(wczytaj_liste "$KATALOG/NA-KONIEC.txt")

na_koniec() {
	local p
	for p in "${NA_KONIEC[@]:-}"; do [ "$p" = "$1" ] && return 0; done
	return 1
}

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
	na_koniec "$T" && continue
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
	na_koniec "$T" && continue
	NOWE+=( "$T" )
done

if [ "${#NOWE[@]}" -gt 0 ]; then
	echo "🆕 Wykryte automatycznie (nie ma ich w KOLEJNOSC.txt): ${NOWE[*]}"
	DO_URUCHOMIENIA+=( "${NOWE[@]}" )
fi

for T in "${NA_KONIEC[@]:-}"; do
	pomijany "$T" && continue
	if [ -f "$KATALOG/$T" ]; then
		DO_URUCHOMIENIA+=( "$T" )
	else
		BRAKUJACE+=( "$T" )
	fi
done

if [ "${#BRAKUJACE[@]}" -gt 0 ]; then
	echo "⚠ W KOLEJNOSC.txt sa nazwy BEZ PLIKU (skasowane albo przemianowane): ${BRAKUJACE[*]}"
fi

# PODZIAL NA CZESCI (sharding CI): MP_SHARDS=ile czesci, MP_SHARD=ktora (1..N).
# Kazda czesc bierze co N-ty plik od swojego offsetu — kolejnosc wzgledna zachowana,
# a testy NISZCZACE zajmuja koncowe pozycje pelnej listy, wiec w kazdej czesci
# tez laduja na samym koncu (kazda czesc ma wlasna instalacje WP).
# Bez zmiennych (domyslnie 1 czesc) zachowanie IDENTYCZNE jak dotad.
SHARDS=${MP_SHARDS:-1}
SHARD=${MP_SHARD:-1}
if [ "$SHARDS" -gt 1 ]; then
	CZESC=()
	i=0
	for T in "${DO_URUCHOMIENIA[@]}"; do
		if [ $(( i % SHARDS )) -eq $(( SHARD - 1 )) ]; then
			CZESC+=( "$T" )
		fi
		i=$(( i + 1 ))
	done
	DO_URUCHOMIENIA=( "${CZESC[@]:-}" )
	# Bramka widocznosci liczy CZESC zestawu — prog przeliczony na czesc,
	# inaczej kazda czesc padnie na progu calego zestawu.
	MINIMUM=$(( MINIMUM / SHARDS ))
	echo "◔ Czesc $SHARD z $SHARDS (prog widocznosci czesci: $MINIMUM)"
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

# Licznik do pliku — bramka sumujaca w CI sprawdza, czy czesci razem daja PELNA liste
# (podzial, ktory gubi pliki, wygladalby jak zielone CI).
if [ -n "${MP_WYKONANE_PLIK:-}" ]; then
	echo "$WYKONANE" > "$MP_WYKONANE_PLIK"
fi

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
