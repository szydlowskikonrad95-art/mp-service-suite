#!/usr/bin/env bash
# ZYWY DOWOD 2.39: okno wykrywania powtornego zgloszenia tego samego egzemplarza
# jest WARTOSCIA DOMYSLNA, a nie liczba zaszyta w kodzie.
#
# BUG (audyt 2.39, waga srednia): okno 30 dni bylo wpisane na sztywno, bez filtra
# i bez ustawienia. Ten sam sprzet zgloszony po 31 dniach nie dostawal flagi
# powtorki W OGOLE — a sprzet wracajacy do serwisu z ta sama usterka to typowy
# przebieg reklamacyjny, nie przypadek brzegowy.
#
# ⭐ Co czyni ten zarzut mocnym: BLIZNIACZA liczba w TYM SAMYM pliku (retencja
# zgloszen niepotwierdzonych) od poczatku byla wartoscia domyslna przestawialna
# filtrem. Poprawny wzorzec istnial w produkcie i po prostu nie zostal tu uzyty.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

okno() { wp eval 'echo (int) MP\Intake\CaseRepo::serial_reuse_window_days();' 2>/dev/null | tr -d '[:space:]'; }

# okno_z_filtrem <wartosc> — ile dni zwroci produkt, gdy wdrozeniowiec poda tyle
okno_z_filtrem() {
	wp eval "add_filter('mp_intake_serial_reuse_days', static function () { return $1; });
		echo (int) MP\\Intake\\CaseRepo::serial_reuse_window_days();" 2>/dev/null | tr -d '[:space:]'
}

# ── 1. Domyslnie 30 dni — zachowanie NIEZMIENIONE ──────────────────────────
[ "$(okno)" = "30" ] \
	&& ok "bez zadnego ustawienia okno to nadal 30 dni (zachowanie bez zmian)" \
	|| bad "domyslne okno to $(okno) dni zamiast 30 — cicha zmiana zachowania"

# ── 2. SEDNO: da sie je przestawic, tak jak blizniacza liczbe w tym pliku ──
[ "$(okno_z_filtrem 90)" = "90" ] \
	&& ok "wdrozeniowiec moze ustawic wlasne okno (90 dni)" \
	|| bad "okno nadal zaszyte — filtr nic nie zmienia (to jest wada 2.39)"

# ── 3. Granice JAWNE: zero nie moze po cichu wylaczyc wykrywania ───────────
[ "$(okno_z_filtrem 0)" -ge 1 ] 2>/dev/null \
	&& ok "zero nie wylacza wykrywania po cichu (granica dolna)" \
	|| bad "okno 0 dni wylaczylo wykrywanie bez slowa"

[ "$(okno_z_filtrem -5)" -ge 1 ] 2>/dev/null \
	&& ok "liczba ujemna nie psuje wykrywania (granica dolna)" \
	|| bad "ujemne okno przeszlo"

[ "$(okno_z_filtrem 999999)" -le 3650 ] 2>/dev/null \
	&& ok "absurdalnie duze okno przycinane (granica gorna)" \
	|| bad "okno bez gornej granicy zamienia ostatnio w kiedykolwiek"


# ── 4. ZACHOWANIE, nie sama liczba: flaga powtorki dziala jak dotad ────────
# Pelna sciezke (dwa zgloszenia tego samego egzemplarza => flaga) sprawdza test
# c7a-serial-reuse.sh, ktory chodzi w tym samym przebiegu CI. Tu pilnujemy, ze
# funkcja liczaca okno jest NAPRAWDE uzywana przez wykrywanie — inaczej mozna by
# ja przestawiac do woli bez zadnego skutku.
UZYTA=$(wp eval '
	$plik = ( new ReflectionClass( "MP\\Intake\\CaseRepo" ) )->getFileName();
	$kod  = (string) file_get_contents( $plik );
	echo ( false !== strpos( $kod, "self::serial_reuse_window_days() * DAY_IN_SECONDS" ) ) ? "tak" : "nie";' 2>/dev/null | tr -d '[:space:]')
[ "$UZYTA" = "tak" ] \
	&& ok "wykrywanie liczy okno TA funkcja (ustawienie ma realny skutek)" \
	|| bad "funkcja okna istnieje, ale wykrywanie jej nie uzywa — ustawienie byloby atrapa"

echo ""
echo "WYNIK 2.39: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
