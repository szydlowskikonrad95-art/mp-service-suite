#!/usr/bin/env bash
# ZYWY DOWOD 2.24: pracownik widzi na liscie TYLKO swoje sprawy — tak, jak produkt
# obiecuje w instrukcji pracownika.
#
# BUG (audyt 2.24, waga srednia): w JEDNYM pliku stały dwa sprzeczne kontrakty:
#  - `CaseRepo::query()`      — „mp_agent => tylko swoje" (i tak dziala),
#  - `CaseRepo::query_for_staff()` — „dowolny personel widzi wszystko", z komentarzem
#    autora „ekran i tak bramkuje". Ekran listy spraw uzywa TEJ DRUGIEJ funkcji
#    i NIE bramkowal: mial wylacznie OPCJONALNY filtr „Moje sprawy", ktory pracownik
#    mogl zignorowac.
# Rozstrzyga dokumentacja produktu — PRACOWNIK.md: „Nie zobaczysz spraw, ktorych
# nie masz prawa widziec". Zamawiajacy nie musial niczego dopowiadac.
#
# FIX: jeden kontrakt (`CaseRepo::scope_for_current_user`) uzywany przez OBIE funkcje.
#
# ⛔ To NIE jest wyciek do osob postronnych — wszyscy trzej to personel. Dlatego
# kontrole 4-6 pilnuja, ze naprawa nie odebrala widocznosci tym, ktorzy maja ja miec.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }


# Pytamy dokladnie ta funkcja, ktorej uzywa ekran.
ile_widzi() {
	wp eval --user="$1" '
		$r = MP\Intake\CaseRepo::query_for_staff( array(), 1, 100 );
		echo (int) $r["total"];' 2>/dev/null | tr -d '[:space:]'
}

zakres() {
	wp eval --user="$1" 'echo MP\Intake\CaseRepo::scope_for_current_user();' 2>/dev/null | tr -d '[:space:]'
}

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Stan zastany + konta ──────────────────────────────────────────────────
# Testy w e2e-import chodza po kolei na TEJ SAMEJ bazie — sprzatamy po sobie
# i sprawdzamy, ze sprzatniete (kontrola na koncu).
SPRAWY_ZASTANE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")

for R in mp_agent mp_coordinator; do
	wp user get "widok-$R" >/dev/null 2>&1 || wp user create "widok-$R" "widok-$R@przyklad.pl" --role="$R" --user_pass="$(head -c 18 /dev/urandom | base64 | tr -d '/+=')" >/dev/null 2>&1
done
AGENT=$(wp user get widok-mp_agent --field=ID 2>/dev/null | tr -d '[:space:]')
KOORD=$(wp user get widok-mp_coordinator --field=ID 2>/dev/null | tr -d '[:space:]')
{ [ -n "$AGENT" ] && [ -n "$KOORD" ]; } && ok "konta pracownika i koordynatora gotowe" || bad "nie udalo sie przygotowac kont"

# ── 1. Trzy sprawy: jedna przypisana pracownikowi, dwie nie ──────────────────
CID_MOJA=$(mkcase widok-moja@example.com WIDOK-1)
CID_OBCA=$(mkcase widok-obca@example.com WIDOK-2)
CID_WOLNA=$(mkcase widok-wolna@example.com WIDOK-3)
wp eval "apply_filters('mp_case_assign', null, $CID_MOJA, $AGENT, 0);" >/dev/null 2>&1
wp eval "apply_filters('mp_case_assign', null, $CID_OBCA, $KOORD, 0);" >/dev/null 2>&1

PRZYPISANA=$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID_MOJA")
[ "$PRZYPISANA" = "$AGENT" ] && ok "sprawa przypisana pracownikowi (przygotowanie)" || bad "przydzial nie zadzialal (=$PRZYPISANA)"

# ── 2. SEDNO: pracownik widzi TYLKO swoja ───────────────────────────────────
WIDZI_AGENT=$(ile_widzi "$AGENT")
[ "${WIDZI_AGENT:-0}" = "1" ] \
	&& ok "pracownik widzi wylacznie swoja sprawe (1 z 3)" \
	|| bad "pracownik widzi $WIDZI_AGENT spraw zamiast 1 (to jest wada 2.24)"

# Kontrakt nazwany wprost — zeby regresja byla czytelna, nie tylko liczbowa.
[ "$(zakres "$AGENT")" = "own" ] \
	&& ok "kontrakt dla pracownika = tylko swoje" \
	|| bad "kontrakt dla pracownika to '$(zakres "$AGENT")'"

# ── 3. Zadna z cudzych spraw nie przecieka po numerze ───────────────────────
NUMERY=$(wp eval --user="$AGENT" '
	$r = MP\Intake\CaseRepo::query_for_staff( array(), 1, 100 );
	$n = array();
	foreach ( (array) $r["rows"] as $w ) { $n[] = (string) $w["case_number"]; }
	echo implode( ",", $n );' 2>/dev/null | tr -d '[:space:]')
NR_OBCA=$(q "SELECT case_number FROM wp_mp_service_cases WHERE id=$CID_OBCA")
NR_WOLNA=$(q "SELECT case_number FROM wp_mp_service_cases WHERE id=$CID_WOLNA")
{ ! printf '%s' "$NUMERY" | grep -q "$NR_OBCA"; } && { ! printf '%s' "$NUMERY" | grep -q "$NR_WOLNA"; } \
	&& ok "cudza i nieprzydzielona sprawa NIE pojawiaja sie na liscie pracownika" \
	|| bad "na liscie pracownika sa cudze sprawy ($NUMERY)"

# ── 4-6. KONTROLE „nie odebralismy za duzo" ─────────────────────────────────
WIDZI_KOORD=$(ile_widzi "$KOORD")
[ "${WIDZI_KOORD:-0}" -ge 3 ] 2>/dev/null \
	&& ok "koordynator widzi wszystkie sprawy ($WIDZI_KOORD)" \
	|| bad "koordynator stracil widocznosc (widzi $WIDZI_KOORD z co najmniej 3)"

[ "$(zakres 1)" = "all" ] \
	&& ok "administrator widzi wszystko (kontrakt = all)" \
	|| bad "administrator ma kontrakt '$(zakres 1)'"

KLIENT=$(q "SELECT ID FROM wp_users u INNER JOIN wp_usermeta m ON m.user_id=u.ID WHERE m.meta_key='wp_capabilities' AND m.meta_value LIKE '%mp_client%' LIMIT 1")
if [ -n "$KLIENT" ]; then
	[ "$(ile_widzi "$KLIENT")" = "0" ] \
		&& ok "klient nie widzi listy spraw personelu (zero wierszy)" \
		|| bad "klient widzi sprawy personelu!"
else
	ok "brak konta klienta w bazie — kontrola pominieta swiadomie (nie udajemy, ze przeszla)"
fi

# ── 7. Filtr „Moje sprawy" przestal byc JEDYNA ochrona ──────────────────────
# Pracownik proszacy WPROST o cudze sprawy nadal ich nie dostaje.
OBCE=$(wp eval --user="$AGENT" '
	$r = MP\Intake\CaseRepo::query_for_staff( array( "assigned" => "'"$KOORD"'" ), 1, 100 );
	echo (int) $r["total"];' 2>/dev/null | tr -d '[:space:]')
[ "${OBCE:-1}" = "0" ] \
	&& ok "jawne pytanie o cudze sprawy zwraca pustke (ochrona nie jest opcja)" \
	|| bad "pracownik wyciagnal $OBCE cudzych spraw jawnym filtrem"

# ── 8. SPRZATANIE ZE SPRAWDZENIEM ───────────────────────────────────────────
for ID in "$CID_MOJA" "$CID_OBCA" "$CID_WOLNA"; do
	[ -n "$ID" ] && wp db query "DELETE FROM wp_mp_service_cases WHERE id=$ID; DELETE FROM wp_mp_case_events WHERE case_id=$ID; DELETE FROM wp_mp_case_sla WHERE case_id=$ID;" >/dev/null 2>&1
done
# Konta testowe kasujemy — zostawione zmieniaja sklad personelu i wywalaja
# test SLA w miejscu bez zwiazku z ta zmiana (pulapka nr 5 z briefingu).
for R in mp_agent mp_coordinator; do
	wp user delete "widok-$R" --yes >/dev/null 2>&1
done

SPRAWY_KONIEC=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "${SPRAWY_KONIEC:-0}" = "${SPRAWY_ZASTANE:-0}" ] \
	&& ok "baza oddana w stanie zastanym ($SPRAWY_ZASTANE spraw)" \
	|| bad "zostawiamy $SPRAWY_KONIEC spraw (zastano $SPRAWY_ZASTANE)"

KONTA=$(q "SELECT COUNT(*) FROM wp_users WHERE user_login LIKE 'widok-mp_%'")
[ "${KONTA:-1}" = "0" ] \
	&& ok "konta testowe skasowane (sklad personelu bez zmian)" \
	|| bad "zostawiamy $KONTA kont testowych — zepsuja test SLA kilka pozycji dalej"

echo ""
echo "WYNIK 2.24: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
