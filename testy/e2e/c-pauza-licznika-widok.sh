#!/usr/bin/env bash
# PAUZA LICZNIKA TERMINU, CZESC B: czlowiek ma ZOBACZYC, ze zegar stoi.
#
# Od wydania, w ktorym termin zatrzymuje sie na czas oczekiwania na klienta, sprawa
# w statusie „do uzupelnienia" nie ma terminu (`deadline_at` = NULL). Puste pole terminu
# bez slowa to CICHA ZMIANA: koordynator nie odrozni „terminu nie ma, bo tak ma byc"
# od „termin sie zepsul". Zamiast pustki ma stac napis „czeka na klienta".
#
# ⛔ WARUNKIEM JEST STATUS, NIE BRAK DATY — i to jest sedno tego testu. Pusty termin ma
# w produkcie WIECEJ przyczyn: sprawa zamknieta, modul automatu nieaktywny, brak wiersza
# terminu. Gdyby napis szedl na kazda pustke, klamalby na kazdym z tych ekranow.
#
# CO DOWODZI (piec kontroli):
#   1. lista spraw: sprawa czekajaca na klienta pokazuje napis,
#   2. karta sprawy: to samo,
#   3. PRZYPADEK KONTROLNY: sprawa z NORMALNYM terminem dalej pokazuje DATE, bez napisu,
#   4. PRZYPADEK KONTROLNY: sprawa BEZ terminu, ale w INNYM statusie, pokazuje kreske,
#      a nie napis (inaczej napis klamalby o sprawach zamknietych),
#   5. oba ekrany biora napis z JEDNEGO zrodla (`Statuses::awaiting_customer_label`).
#
# Termin podajemy WLASNYM filtrem `mp_case_deadline` — czesc B ma byc dowodliwa niezaleznie
# od tego, czy zmiana stalej w module automatu (czesc A) juz weszla.
#
# KALIBRACJA: na kodzie sprzed zmiany kontrole 1 i 2 MUSZA PASC (widac kreske zamiast napisu),
# a kontrole 3 i 4 maja przejsc tak samo przed i po.
#
# Chodzi na poligonie i w CI. Exit 0 = zero FAIL.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

NAPIS=$(wp eval 'echo MP\Intake\Statuses::awaiting_customer_label();' 2>/dev/null | tr -d '\n')
STATUS_CZEKA=$(wp eval 'echo MP\Intake\Statuses::AWAITING_CUSTOMER;' 2>/dev/null | tr -d '\n')

# ⛔ Napis i status bierzemy Z PRODUKTU — ale gdy produkt ich jeszcze NIE MA (kod sprzed
# zmiany), test nie moze paść na braku metody, tylko ma pokazac BRAK NAPISU NA EKRANIE.
# Inaczej kalibracja mierzy istnienie funkcji, a nie to, co widzi czlowiek.
ZASTEPCZO=0
if [ -z "$NAPIS" ]; then       NAPIS='czeka na klienta';     ZASTEPCZO=1; fi
if [ -z "$STATUS_CZEKA" ]; then STATUS_CZEKA='do uzupełnienia'; ZASTEPCZO=1; fi

if [ "$ZASTEPCZO" = "1" ]; then
	echo "  UWAGA produkt nie oddal napisu ani statusu — biore wartosci zastepcze (to jest przebieg KALIBRACYJNY)"
else
	ok "napis i status wziete Z PRODUKTU, nie wpisane do testu (status='$STATUS_CZEKA', napis='$NAPIS')"
fi

# ── 1 + 3 + 4. Kolumna terminu na LISCIE SPRAW ────────────────────────────────
# Renderujemy sama kolumne — to jest jedyna droga, ktora rysuje ten napis na liscie.
kolumna() { # $1=status $2=deadline ('' = brak); echo HTML
	wp eval "
		\$dl = '$2';
		add_filter( 'mp_case_deadline', static function () use ( \$dl ) {
			return '' === \$dl ? null : array( 'deadline_at' => \$dl );
		}, 99 );
		if ( ! class_exists( 'WP_List_Table' ) ) {
			require_once ABSPATH . 'wp-admin/includes/class-wp-list-table.php';
		}
		\$t = new MP\\Intake\\Admin\\CasesListTable( 'mp-cases' );
		echo \$t->column_deadline( array( 'id' => 1, 'status' => '$1' ) );
	" 2>/dev/null
}

JUTRO=$(date -u -d '+2 days' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S')

LISTA_CZEKA=$(kolumna "$STATUS_CZEKA" "")
echo "$LISTA_CZEKA" | grep -qF "$NAPIS" \
	&& ok "lista spraw: sprawa czekajaca na klienta pokazuje napis zamiast pustki" \
	|| bad "lista spraw: brak napisu przy sprawie czekajacej na klienta (wyszlo: $(echo "$LISTA_CZEKA" | cut -c1-80))"

LISTA_TERMIN=$(kolumna "w analizie" "$JUTRO")
if echo "$LISTA_TERMIN" | grep -qF "$NAPIS"; then
	bad "PRZYPADEK KONTROLNY: sprawa z NORMALNYM terminem dostala napis zamiast daty"
elif echo "$LISTA_TERMIN" | grep -q "$(date -u -d '+2 days' '+%Y-%m-%d' 2>/dev/null || echo 20)"; then
	ok "PRZYPADEK KONTROLNY: sprawa z normalnym terminem dalej pokazuje DATE"
else
	bad "PRZYPADEK KONTROLNY: sprawa z terminem nie pokazala daty (wyszlo: $(echo "$LISTA_TERMIN" | cut -c1-80))"
fi

LISTA_ZAMKNIETA=$(kolumna "zamknięte" "")
# ⛔ Pusty render NIE jest zaliczeniem kontroli negatywnej — brak napisu i brak niczego
# wygladaja tak samo. Zlapane wlasnym przebiegiem: konstruktor wymagal argumentu, render
# rzucal blad, a kontrola „bez napisu" swiecila na zielono.
if [ -z "$LISTA_ZAMKNIETA" ]; then
	bad "PRZYPADEK KONTROLNY: render kolumny nic nie zwrocil — pomiar niewazny, nie zaliczenie"
elif echo "$LISTA_ZAMKNIETA" | grep -qF "$NAPIS"; then
	bad "PRZYPADEK KONTROLNY: sprawa ZAMKNIETA bez terminu dostala napis — to bylaby nieprawda"
else
	ok "PRZYPADEK KONTROLNY: pusty termin z INNEGO powodu dalej pokazuje kreske, nie napis"
fi

# ── 2. Karta sprawy ───────────────────────────────────────────────────────────
# Sekcja naglowka karty rysuje wiersz „Termin SLA" z tego samego kontraktu.
karta() { # $1=status $2=deadline; echo HTML
	wp eval "
		\$dl = '$2';
		add_filter( 'mp_case_deadline', static function () use ( \$dl ) {
			return '' === \$dl ? null : array( 'deadline_at' => \$dl );
		}, 99 );
		\$r = new ReflectionMethod( 'MP\\Intake\\Admin\\CaseCard', 'section_header' );
		\$r->setAccessible( true );
		ob_start();
		\$r->invoke( null, 1, array( 'status' => '$1', 'rodzaj' => 'naprawa' ) );
		echo ob_get_clean();
	" 2>/dev/null
}

KARTA_CZEKA=$(karta "$STATUS_CZEKA" "")
echo "$KARTA_CZEKA" | grep -qF "$NAPIS" \
	&& ok "karta sprawy: sprawa czekajaca na klienta pokazuje napis zamiast pustki" \
	|| bad "karta sprawy: brak napisu przy sprawie czekajacej na klienta (wyszlo: $(echo "$KARTA_CZEKA" | tr -d '\n' | cut -c1-100))"

KARTA_ZAMKNIETA=$(karta "zamknięte" "")
if [ -z "$KARTA_ZAMKNIETA" ]; then
	bad "PRZYPADEK KONTROLNY (karta): render nic nie zwrocil — pomiar niewazny, nie zaliczenie"
elif echo "$KARTA_ZAMKNIETA" | grep -qF "$NAPIS"; then
	bad "PRZYPADEK KONTROLNY (karta): sprawa zamknieta dostala napis"
else
	ok "PRZYPADEK KONTROLNY (karta): pusty termin z innego powodu bez napisu"
fi

echo
echo "WYNIK: $PASS ok, $FAIL fail"

# ⛔ STRAZNIK KOMPLETU: kontrola, ktora cicho nie wystartuje, nie zglasza sie jako FAIL.
RAZEM=$(( PASS + FAIL ))
if [ "$RAZEM" -lt 5 ]; then
	echo "  BLAD PRZYRZADU: wykonalo sie $RAZEM kontroli, oczekiwane min. 5 — ktoras nie wystartowala."
	exit 2
fi

[ "$FAIL" -eq 0 ]
