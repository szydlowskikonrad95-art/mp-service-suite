#!/usr/bin/env bash
# ZYWY DOWOD 2.20: wiersze-sieroty w tabeli terminow sa naprawde sprzatane.
#
# BUG (audyt 2.20, waga srednia): CZTERY komentarze w module obiecywaly, ze
# osierocone wiersze posprzata zamiatarka („sweep sprzata osobno", „nie widzi
# sierot — nic nie robimy"), a w calym module nie bylo ANI JEDNEJ instrukcji
# kasowania poza czyszczeniem calej tabeli przy dezaktywacji. Wiersze terminow
# po usunietych sprawach zostawaly w bazie bez konca.
#
# FIX: `Sla::cleanup_orphans()` wolane przez zamiatarke, z kursorem po tabeli
# i DWOMA bezpiecznikami (kontrola nr 4 i 5) — bo pomylka tutaj kasuje dane.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

KURSOR='mp_automator_orphan_cursor'
ALARM='mp_automator_orphan_alert'

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

sprzataj() {
	wp eval 'echo (int) MP\Automator\Sla::cleanup_orphans();' 2>/dev/null | tr -d '[:space:]'
}

# ── 0. Stan zastany ──────────────────────────────────────────────────────────
SLA_ZASTANE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla")
wp eval "delete_option('$KURSOR'); delete_option('$ALARM');" >/dev/null 2>&1

# ── 1. Zywa sprawa z terminem + sierota po sprawie usunietej ────────────────
CID=$(mkcase sierota-zywa@example.com SIEROTA-1)
MA_TERMIN=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID")
[ "$MA_TERMIN" = "1" ] && ok "zywa sprawa ma wiersz terminu (przygotowanie)" || bad "brak wiersza terminu dla sprawy $CID"

# Sierota powstaje DOKLADNIE tak, jak w produkcji: sprawa znika, wiersz zostaje.
CID_ZNIKA=$(mkcase sierota-usunieta@example.com SIEROTA-2)
wp db query "DELETE FROM wp_mp_service_cases WHERE id=$CID_ZNIKA" >/dev/null 2>&1
ZOSTAL=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID_ZNIKA")
[ "$ZOSTAL" = "1" ] && ok "po usunieciu sprawy wiersz terminu ZOSTAJE (tak powstaje sierota)" || bad "nie udalo sie zrobic sieroty ($ZOSTAL)"

# ── 2. SEDNO: zamiatarka kasuje sierote i NIE rusza zywej ───────────────────
SKASOWANE=$(sprzataj)
[ "${SKASOWANE:-0}" -ge 1 ] 2>/dev/null \
	&& ok "sprzatanie zglasza skasowane wiersze ($SKASOWANE)" \
	|| bad "sprzatanie nic nie skasowalo (to jest wada 2.20)"

PO=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID_ZNIKA")
[ "$PO" = "0" ] \
	&& ok "wiersz-sierota usuniety z tabeli terminow" \
	|| bad "sierota nadal w tabeli (to jest wada 2.20)"

ZYWA=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID")
[ "$ZYWA" = "1" ] \
	&& ok "wiersz ZYWEJ sprawy nietkniety (nie kasujemy za duzo)" \
	|| bad "skasowany wiersz zywej sprawy! (naprawa gorsza od wady)"

# ── 3. Kursor przesuwa sie i ZAWIJA (inaczej dalsze sieroty nigdy nie trafia) ─
K1=$(wp option get "$KURSOR" 2>/dev/null | tr -d '[:space:]')
[ -n "$K1" ] && [ "${K1:-0}" -gt 0 ] 2>/dev/null \
	&& ok "kursor przesuniety po przebiegu (=$K1)" \
	|| bad "kursor nie ruszyl — dalsze wiersze nigdy nie trafia do paczki"

# Zawijanie sprawdzamy WPROST, nie „po kilku przebiegach": ustawiamy kursor za
# ostatni wiersz i zadamy, zeby nastepny przebieg wrocil na poczatek. Poprzednia
# wersja tej kontroli zakladala, ze dwa przebiegi wystarcza do konca tabeli —
# i padala, gdy wczesniejszy test zostawil w niej sto dwadziescia wierszy.
wp eval "update_option('$KURSOR', 999999999, false);" >/dev/null 2>&1
sprzataj >/dev/null
K2=$(wp option get "$KURSOR" 2>/dev/null | tr -d '[:space:]')
[ "${K2:-1}" = "0" ] \
	&& ok "kursor ZAWIJA po ostatnim wierszu (tabela sprawdzana w kolko, nie raz)" \
	|| bad "kursor nie zawinal (=$K2) — dalsza czesc tabeli nigdy nie zostanie sprawdzona"

# ── 4. BEZPIECZNIK: brak kontraktu = NIE kasujemy nic ───────────────────────
# Gdy modul zgloszen nie odpowiada, KAZDY wiersz wyglada na sierote. To jest
# moment, w ktorym zla naprawa kasuje cala tabele terminow.
wp eval "delete_option('$KURSOR');" >/dev/null 2>&1
BEZ_KONTRAKTU=$(wp eval '
	remove_all_filters( "mp_case_exists" );
	echo (int) MP\Automator\Sla::cleanup_orphans();' 2>/dev/null | tr -d '[:space:]')
[ "${BEZ_KONTRAKTU:-1}" = "0" ] \
	&& ok "bez kontraktu sprawdzania spraw NIE kasujemy nic (bezpiecznik 1)" \
	|| bad "bez kontraktu skasowano $BEZ_KONTRAKTU wierszy — tak ginie cala tabela"

NADAL=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID")
[ "$NADAL" = "1" ] \
	&& ok "wiersz zywej sprawy przetrwal probe z martwym kontraktem" \
	|| bad "wiersz zywej sprawy zniknal przy martwym kontrakcie"

# ── 4b. SPRAWA ISTNIEJE, ale NIE JEST POTWIERDZONA => wiersz ZOSTAJE ────────
# To byla glebsza przyczyna regresji zlapanej przez test „jeden digest": pierwsza
# wersja pytala `mp_case_get_context`, a ten odpowiada TYLKO o sprawach
# zweryfikowanych — wiec sprawa istniejaca, lecz niepotwierdzona, wygladala jak
# nieistniejaca i jej wiersz szedl do kasacji. Teraz pytamy WPROST o istnienie.
wp eval "delete_option('$KURSOR');" >/dev/null 2>&1
OUT=$(wp mp case-create --kind=reklamacja --email=sierota-pending@example.com --name='T Test' --serial=SIEROTA-3 --document='FV/1' --date='2026-05-01' --desc='x' 2>/dev/null)
CID_PENDING=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)   # NIE potwierdzamy
if [ -n "$CID_PENDING" ]; then
	wp db query "INSERT INTO wp_mp_case_sla (case_id, status, sla_policy_version) VALUES ($CID_PENDING, 'nowe', 1)" >/dev/null 2>&1
	sprzataj >/dev/null
	ZOSTAL_PENDING=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID_PENDING")
	[ "$ZOSTAL_PENDING" = "1" ] \
		&& ok "sprawa niepotwierdzona ISTNIEJE — jej wiersz NIE jest sierota i zostaje" \
		|| bad "skasowany wiersz istniejacej sprawy tylko dlatego, ze nie jest potwierdzona"
	wp db query "DELETE FROM wp_mp_service_cases WHERE id=$CID_PENDING; DELETE FROM wp_mp_case_sla WHERE case_id=$CID_PENDING;" >/dev/null 2>&1
else
	bad "nie udalo sie utworzyc sprawy niepotwierdzonej — kontrola NIE zostala wykonana"
fi

# ── 5. BEZPIECZNIK: cala paczka martwa => ALARM zamiast kasowania ───────────
# Podkladamy piec wierszy bez spraw. Kontrakt ZYJE, ale nic w paczce nie zyje —
# to znacznie bardziej prawdopodobne jako awaria niz jako prawda o danych.
wp eval "delete_option('$KURSOR'); delete_option('$ALARM');" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_case_sla" >/dev/null 2>&1
for N in 900001 900002 900003 900004 900005; do
	wp db query "INSERT INTO wp_mp_case_sla (case_id, status, sla_policy_version) VALUES ($N, 'nowe', 1)" >/dev/null 2>&1
done
PODLOZONE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id >= 900001")
[ "$PODLOZONE" = "5" ] && ok "podlozono 5 wierszy bez spraw (przygotowanie bezpiecznika 2)" || bad "nie udalo sie podlozyc wierszy ($PODLOZONE)"

MASOWE=$(sprzataj)
[ "${MASOWE:-1}" = "0" ] \
	&& ok "cala paczka martwa => NIE kasujemy (bezpiecznik 2)" \
	|| bad "skasowano $MASOWE wierszy na raz — tak wyglada awaria kontraktu, nie prawda o danych"

AL=$(wp option get "$ALARM" --format=json 2>/dev/null)
{ [ -n "$AL" ] && [ "$AL" != "false" ]; } \
	&& ok "podniesiony alarm zamiast cichego kasowania" \
	|| bad "brak alarmu — nikt sie nie dowie, ze sprzatanie stoi"

# ── 6. SPRZATANIE ZE SPRAWDZENIEM ──────────────────────────────────────────
wp db query "DELETE FROM wp_mp_case_sla WHERE case_id >= 900001" >/dev/null 2>&1
[ -n "$CID" ] && wp db query "DELETE FROM wp_mp_service_cases WHERE id=$CID; DELETE FROM wp_mp_case_events WHERE case_id=$CID; DELETE FROM wp_mp_case_sla WHERE case_id=$CID;" >/dev/null 2>&1
wp eval "delete_option('$KURSOR'); delete_option('$ALARM');" >/dev/null 2>&1

PODLOZONE_KONIEC=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id >= 900001")
[ "${PODLOZONE_KONIEC:-1}" = "0" ] \
	&& ok "podlozone wiersze usuniete (nie zostaja w bazie dla nastepnego testu)" \
	|| bad "zostawiamy $PODLOZONE_KONIEC podlozonych wierszy"

AL_KONIEC=$(wp option get "$ALARM" --format=json 2>/dev/null)
{ [ -z "$AL_KONIEC" ] || [ "$AL_KONIEC" = "false" ]; } \
	&& ok "alarm zgaszony po tescie (nastepny test nie dziedziczy naszego)" \
	|| bad "zostawiamy podniesiony alarm"

echo ""
echo "WYNIK 2.20: PASS=$PASS FAIL=$FAIL (wierszy terminow na starcie: $SLA_ZASTANE)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
