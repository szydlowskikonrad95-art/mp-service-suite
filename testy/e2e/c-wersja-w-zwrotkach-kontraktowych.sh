#!/usr/bin/env bash
# KONTRAKT (API-KONTRAKT.md, zasady twarde): „Zwrotki niosa `schema_version`".
#
# BUG (audyt bezpieczenstwa, spoza listy): zwrotki `mp_customer_find_products`
# i `mp_case_count_by_product` NIE nioly wersji ksztaltu w ZADNEJ galezi zwrotu.
# ⛔ To ta sama klasa co pozycja 2.27, ktora uznano za zamknieta — a byla zamknieta
# w dwoch miejscach z pieciu. Dlatego ten test pilnuje KAZDEJ galezi z osobna:
# pusta zwrotka tez jest zwrotka i odbiorca musi wiedziec, jaki ma ksztalt,
# ZANIM zajrzy do pol.
#
# ⭐ PRZYPADEK KONTROLNY jest tu rownie wazny jak sedno: sprawdzamy, ze dolozenie
# wersji NIE ruszylo pozostalych pol. Bez tego „naprawa" mogla by przemeblowac
# zwrotke i zepsuc odbiorce, a test i tak swiecilby na zielono.
#
# Pytamy przez FILTRY (czyli tak, jak pyta drugi modul), nie przez metody klasy —
# inaczej sprawdzalibysmy kod, a nie kontrakt.
#
# KALIBRACJA: uruchomiony na kodzie SPRZED naprawy musi PASC na kontrolach wersji
# (5 sztuk), a kontrole ksztaltu maja przejsc TAK SAMO przed i po.
#
# Chodzi na poligonie (MP_BASE z env) i w CI. Exit 0 = zero FAIL.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Wersje bierzemy Z KODU, nie wpisujemy liczby do testu — inaczej podniesienie
# wersji schematu wywalaloby test zamiast go potwierdzac.
WERSJA=$(wp eval 'echo MP\Intake\CaseRepo::SCHEMA_VERSION;' 2>/dev/null | tr -d '[:space:]')
if [ -z "$WERSJA" ]; then
	echo "  FAIL pomiar niewazny: nie udalo sie odczytac SCHEMA_VERSION z produktu"
	echo "WYNIK: 0 ok, 1 fail"
	exit 1
fi
echo "== wersja ksztaltu wg produktu: $WERSJA =="

# Zwrotka filtra jako JSON — pytamy dokladnie tak, jak pyta modul rejestru.
zwrotka() { wp eval "echo wp_json_encode( apply_filters( '$1', null, $2 ) );" 2>/dev/null; }

ma_wersje() { # $1=json $2=opis
	echo "$1" | python3 -c "
import json,sys
d=json.load(sys.stdin)
sys.exit(0 if isinstance(d,dict) and d.get('schema_version')==$WERSJA else 1)
" 2>/dev/null \
		&& ok "$2: zwrotka niesie schema_version=$WERSJA" \
		|| bad "$2: BRAK schema_version w zwrotce (odbiorca nie wie, jaki ma ksztalt) — $(echo "$1" | cut -c1-90)"
}

ma_pola() { # $1=json $2=lista pol po przecinku $3=opis
	echo "$1" | python3 -c "
import json,sys
d=json.load(sys.stdin)
pola='$2'.split(',')
sys.exit(0 if isinstance(d,dict) and all(p in d for p in pola) else 1)
" 2>/dev/null \
		&& ok "$3: pozostale pola na miejscu ($2)" \
		|| bad "$3: zwrotka zgubila pola ($2) — $(echo "$1" | cut -c1-90)"
}

echo
echo "== 1. mp_customer_find_products — GALAZ PUSTEJ FRAZY =="
PUSTA=$(zwrotka mp_customer_find_products "''")
ma_wersje "$PUSTA" "pusta fraza"
ma_pola   "$PUSTA" "ids,truncated,limit" "pusta fraza"
echo "$PUSTA" | python3 -c "
import json,sys
d=json.load(sys.stdin)
sys.exit(0 if d.get('ids')==[] and d.get('truncated') is False and isinstance(d.get('limit'),int) and d['limit']>0 else 1)
" 2>/dev/null \
	&& ok "pusta fraza: wartosci pol NIETKNIETE (ids=[], truncated=false, limit>0)" \
	|| bad "pusta fraza: wartosci pol sie zmienily — $(echo "$PUSTA" | cut -c1-90)"

echo
echo "== 2. mp_customer_find_products — GALAZ WYNIKU =="
WYNIK=$(zwrotka mp_customer_find_products "'klient-ktorego-nie-ma-$$'")
ma_wersje "$WYNIK" "galaz wyniku"
ma_pola   "$WYNIK" "ids,truncated,limit" "galaz wyniku"
echo "$WYNIK" | python3 -c "
import json,sys
d=json.load(sys.stdin)
sys.exit(0 if isinstance(d.get('ids'),list) and isinstance(d.get('truncated'),bool) and isinstance(d.get('limit'),int) else 1)
" 2>/dev/null \
	&& ok "galaz wyniku: typy pol NIETKNIETE (ids=lista, truncated=bool, limit=int)" \
	|| bad "galaz wyniku: typy pol sie zmienily — $(echo "$WYNIK" | cut -c1-90)"

echo
echo "== 3. mp_case_count_by_product =="
LICZBY=$(zwrotka mp_case_count_by_product "999999")
ma_wersje "$LICZBY" "rozbicie liczby spraw"
ma_pola   "$LICZBY" "total,active,closed,rejected" "rozbicie liczby spraw"
echo "$LICZBY" | python3 -c "
import json,sys
d=json.load(sys.stdin)
sys.exit(0 if all(isinstance(d.get(k),int) and d.get(k)>=0 for k in ('total','active','closed','rejected')) else 1)
" 2>/dev/null \
	&& ok "rozbicie: wszystkie cztery liczby dalej sa liczbami >= 0" \
	|| bad "rozbicie: zmienil sie typ albo zakres liczb — $(echo "$LICZBY" | cut -c1-90)"

echo
echo "== 4. Zwrotki, ktore wersje mialy JUZ WCZESNIEJ (kontrola, ze nic nie zepsulismy) =="
KONTEKST=$(wp eval "echo wp_json_encode( MP\\Intake\\CaseRepo::get_context( 999999 ) );" 2>/dev/null)
echo "$KONTEKST" | grep -q 'not_found' \
	&& ok "get_context dla nieistniejacej sprawy dalej oddaje 'not_found' (kontrakt bez zmian)" \
	|| bad "get_context zmienil odpowiedz dla nieistniejacej sprawy — $(echo "$KONTEKST" | cut -c1-90)"

ZAPYTANIE=$(wp eval "echo wp_json_encode( MP\\Intake\\CaseRepo::query( array(), 1, 1 ) );" 2>/dev/null)
ma_wersje "$ZAPYTANIE" "mp_cases_query (naprawione wczesniej)"
ma_pola   "$ZAPYTANIE" "rows,total,page,per_page" "mp_cases_query"

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
