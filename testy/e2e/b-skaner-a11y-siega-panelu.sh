#!/usr/bin/env bash
# ZYWY DOWOD (2.46): przyrzad badajacy dostepnosc siega ekranow PERSONELU.
#
# Zawezenie siedzialo w NARZEDZIU, nie w jednym przebiegu: `testy/a11y/audyt-axe.py`
# byl zbudowany tak, zeby badac „trzy powierzchnie, ktore widzi KLIENT". Skutek —
# kazde kolejne wydanie wychodzilo „zielone" na dostepnosci, opisujac czesc systemu
# i nie mowiac, ze to czesc. Luka nie byla teoretyczna: w obszarze, ktorego przyrzad
# nie siegal, lezala prawdziwa wada (panel automatu przy powiekszeniu 200% wychodzil
# 184 px poza okno — pozycja 2.6). Zadny dotychczasowy pomiar nie mogl jej zobaczyc.
#
# Ten test pilnuje, ze:
#   1. da sie sprawdzic ZAKRES narzedzia bez przegladarki (inaczej nikt go nie kontroluje),
#   2. zakres obejmuje ekrany personelu z WSZYSTKICH TRZECH wtyczek,
#   3. adresy ekranow zgadzaja sie ze slugami, ktore wtyczki NAPRAWDE rejestruja,
#   4. narzedzie zapowiada zdanie o zakresie (raport bez niego to ten sam blad),
#   5. opis narzedzia nie twierdzi juz, ze bada wylacznie powierzchnie klienta.
#
# Wymaga `wp` i `python3`. Exit 0 = OK. Test nic nie zapisuje — nie ma czego sprzatac.
set -u

REPO="${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
NARZEDZIE="$REPO/testy/a11y/audyt-axe.py"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

if ! command -v python3 >/dev/null 2>&1; then
	echo "  --   pomijam caly test: brak python3 na tym stanowisku"
	echo "WYNIK: 0 ok, 0 fail (pominiete)"
	exit 0
fi

echo "== 1. ZAKRES DA SIE SPRAWDZIC BEZ PRZEGLADARKI =="
# Przyrzad, ktorego zakresu nie da sie odczytac maszynowo, nikt nie pilnuje —
# a wlasnie brak takiej kontroli pozwolil luce przezyc kilka wydan.
LISTA=$(MP_BASE=http://przyklad.test python3 "$NARZEDZIE" --lista-powierzchni 2>&1)
KOD=$?
[ "$KOD" = "0" ] && [ -n "$LISTA" ] \
	&& ok "podglad zakresu dziala bez playwrighta i bez axe (kod $KOD)" \
	|| bad "podglad zakresu nie dziala (kod $KOD): $(echo "$LISTA" | tail -2)"

echo "== 2. ZAKRES OBEJMUJE EKRANY PERSONELU Z TRZECH WTYCZEK =="
echo "$LISTA" | grep -q 'EKRANY PERSONELU' && ok "narzedzie w ogole zna pojecie ekranow personelu" || bad "brak sekcji ekranow personelu (przyrzad dalej siega tylko klienta)"
ILE=$(echo "$LISTA" | grep -c 'wp-admin/admin.php?page=')
[ "$ILE" -ge 6 ] && ok "ekranow panelu w zakresie: $ILE" || bad "ekranow panelu w zakresie tylko $ILE"

echo "== 3. ADRESY ZGADZAJA SIE ZE SLUGAMI, KTORE WTYCZKI REJESTRUJA =="
# Literowka w liscie = narzedzie wchodzi na nieistniejacy ekran. Slugi bierzemy
# z KODU (stale klas), nie z pamieci — zgodnie z zasada „nie wpisuj twardych wartosci".
sprawdz_slug() {
	SLUG=$(wp eval "echo $1::PAGE_SLUG;" 2>/dev/null | tr -d '[:space:]')
	if [ -z "$SLUG" ]; then
		bad "nie udalo sie odczytac slugu z $1"
		return
	fi
	echo "$LISTA" | grep -q "page=$SLUG\]" \
		&& ok "$2: zakres zawiera ekran '$SLUG' (odczytany z kodu)" \
		|| bad "$2: zakres NIE zawiera ekranu '$SLUG'"
}
sprawdz_slug 'MP\Registry\Admin\ProductsScreen'   'rejestr'
sprawdz_slug 'MP\Intake\Admin\CasesScreen'        'zgloszenia'
sprawdz_slug 'MP\Automator\Admin\PanelScreen'     'automat'

echo "== 4. NARZEDZIE ZAPOWIADA ZDANIE O ZAKRESIE =="
echo "$LISTA" | grep -q '^ZAKRES:' && ok "zakres nazwany wprost w wydruku" || bad "brak zdania o zakresie"
echo "$LISTA" | grep -q '^POWIERZCHNI RAZEM:' && ok "podana liczba powierzchni" || bad "brak liczby powierzchni"

echo "== 5. OPIS NARZEDZIA NIE ZAWEZA GO JUZ DO KLIENTA =="
# ⚠️ Kontrola tekstu opisu — celowo, bo to WLASNIE zdanie z opisu narzedzia jest
# cytowane w audycie jako dowod zawezenia. Reszta testu mierzy zachowanie.
grep -q 'trzy powierzchnie, ktore widzi KLIENT' "$NARZEDZIE" \
	&& bad "opis narzedzia nadal deklaruje wylacznie powierzchnie klienta" \
	|| ok "opis narzedzia nie zaweza badania do klienta"
grep -q 'MP_ADMIN_USER' "$NARZEDZIE" && ok "opis mowi, czym wejsc na ekrany personelu" || bad "brak informacji o koncie do panelu"

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
