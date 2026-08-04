#!/usr/bin/env bash
# ZYWY DOWOD 2.22: przeglad spraw w zadaniu cyklicznym kosztuje TYLE SAMO zapytan
# niezaleznie od tego, ile spraw jest w bazie.
#
# BUG (audyt 2.22, waga srednia): zadanie uruchamiane co piec minut robilo DO DWUSTU
# osobnych zapytan zliczajacych — po jednym na sprawe — zamiast jednego zbiorczego
# (`Sla::reconcile_untracked`). Przy dzisiejszej skali demonstracyjnej nieodczuwalne;
# zgloszone jako KOSZT ROSNACY Z LICZBA SPRAW, nie jako awaria.
#
# STAN: naprawione przy okazji pozycji 2.18 — tam okno przegladu urosalo z 200 do 500
# spraw, wiec zostawienie zapytania na sprawe oznaczaloby 500 zapytan na przebieg.
# Ten test jest BRAMKA: pilnuje, zeby wzorzec nie wrocil, bo pozycja bez testu wraca.
#
# ⛔ MIERZYMY LICZBE ZAPYTAN, nie czas. Czas na malej bazie niczego nie pokaze
# (audyt zmierzyl ponizej 3 ms przy 3000 spraw) — rosnacy koszt widac dopiero
# w liczbie zapytan i dopiero ona odrozni jedno zapytanie zbiorcze od petli.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# Ile zapytan kosztuje SAM PRZEGLAD spraw (bez doszywania — wszystkie sa znane).
koszt_przegladu() {
	wp eval '
		global $wpdb;
		$przed = $wpdb->num_queries;
		MP\Automator\Sla::reconcile_untracked( 20 );
		echo (int) ( $wpdb->num_queries - $przed );' 2>/dev/null | tr -d '[:space:]'
}

# ── 0. Kilka spraw, KAZDA ze swoim wierszem terminu (nie ma czego doszywac) ──
SPRAWY=""
for N in 1 2 3 4; do
	CID=$(mkcase "petla-$N@example.com" "PETLA-$N")
	SPRAWY="$SPRAWY $CID"
done
BEZ_TERMINU=$(q "SELECT COUNT(*) FROM wp_mp_service_cases c LEFT JOIN wp_mp_case_sla s ON s.case_id=c.id WHERE c.identity_status='verified' AND s.case_id IS NULL")
[ "${BEZ_TERMINU:-1}" = "0" ] \
	&& ok "wszystkie sprawy maja wiersz terminu (przeglad nie ma czego doszywac)" \
	|| bad "$BEZ_TERMINU spraw bez terminu — pomiar mierzylby doszywanie, nie przeglad"

# ── 1. Pomiar bazowy ────────────────────────────────────────────────────────
KOSZT_1=$(koszt_przegladu)
[ -n "$KOSZT_1" ] && ok "przeglad przy $(q 'SELECT COUNT(*) FROM wp_mp_service_cases') sprawach kosztuje $KOSZT_1 zapytan" || bad "nie udalo sie zmierzyc kosztu"

# ── 2. SEDNO: dokladamy sprawy — koszt NIE MOZE rosnac z ich liczba ─────────
for N in 5 6 7 8 9 10; do
	mkcase "petla-$N@example.com" "PETLA-$N" >/dev/null
done
KOSZT_2=$(koszt_przegladu)
ILE_SPRAW=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")

# Zapas jednego zapytania na rozne drobiazgi srodowiska; petla po sprawach
# dolozylaby SZESC (tyle spraw doszlo), wiec ta granica je rozroznia.
GRANICA=$(( KOSZT_1 + 2 ))
[ "${KOSZT_2:-999}" -le "$GRANICA" ] 2>/dev/null \
	&& ok "po dolozeniu 6 spraw koszt to $KOSZT_2 zapytan (bylo $KOSZT_1) — nie rosnie z liczba spraw" \
	|| bad "koszt urosl z $KOSZT_1 na $KOSZT_2 przy $ILE_SPRAW sprawach — zapytanie w petli wrocilo (to jest wada 2.22)"

# ── 3. Kontrola odwrotna: przeglad NADAL dziala (nie zmierzylismy pustki) ───
NAJNOWSZA=$(q "SELECT MAX(id) FROM wp_mp_service_cases")
wp db query "DELETE FROM wp_mp_case_sla WHERE case_id=$NAJNOWSZA" >/dev/null 2>&1
wp eval 'MP\Automator\Sla::reconcile_untracked( 20 );' >/dev/null 2>&1
DOSZYTE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$NAJNOWSZA")
[ "$DOSZYTE" = "1" ] \
	&& ok "przeglad nadal doszywa sprawy bez terminu (mierzylismy dzialajacy mechanizm)" \
	|| bad "przeglad przestal doszywac — pomiar dotyczyl martwego kodu"

# ── 4. SPRZATANIE ZE SPRAWDZENIEM ──────────────────────────────────────────
for ID in $SPRAWY; do
	[ -n "$ID" ] && wp db query "DELETE FROM wp_mp_service_cases WHERE id=$ID; DELETE FROM wp_mp_case_sla WHERE case_id=$ID; DELETE FROM wp_mp_case_events WHERE case_id=$ID;" >/dev/null 2>&1
done
wp db query "DELETE FROM wp_mp_case_sla WHERE case_id IN (SELECT id FROM wp_mp_service_cases WHERE form_data LIKE '%PETLA-%')" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_case_events WHERE case_id IN (SELECT id FROM wp_mp_service_cases WHERE form_data LIKE '%PETLA-%')" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_service_cases WHERE form_data LIKE '%PETLA-%'" >/dev/null 2>&1
ZOSTALO=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE form_data LIKE '%PETLA-%'")
[ "${ZOSTALO:-1}" = "0" ] \
	&& ok "sprawy testowe posprzatane" \
	|| bad "zostawiamy $ZOSTALO spraw testowych"

echo ""
echo "WYNIK 2.22: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
