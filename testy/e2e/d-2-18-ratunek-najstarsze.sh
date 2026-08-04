#!/usr/bin/env bash
# ZYWY DOWOD 2.18: mechanizm ratunkowy siega spraw, ktore czekaja NAJDLUZEJ.
#
# BUG (audyt 2.18, waga duza): sprawa potwierdzona w chwili, gdy modul automatu byl
# wylaczony, nie dostaje ani przydzialu, ani terminu — „cicho, na zawsze" (slowa
# autora). Produkt ma na to mechanizm ratunkowy, ale ten pytal o 200 NAJNOWSZYCH
# spraw z 30 dni (`ORDER BY id DESC LIMIT 200`). Przy ruchu powyzej ~7 zgloszen
# dziennie najstarsze sprawy w ogole nie trafialy do zapytania — a to wlasnie one
# czekaja najdluzej. Po 30 dniach taka sprawa wypadala z okna BEZPOWROTNIE.
#
# FIX: kolejnosc jest JAWNYM parametrem kontraktu, a sciezka ratunkowa prosi
# o najstarsze. ⛔ DOMYSLNE zachowanie kontraktu (najnowsze pierwsze) zostaje
# NIETKNIETE — kontrole 2 i 3 pilnuja tego wprost, bo zmiana domyslnej kolejnosci
# dotknelaby po cichu kazdego innego konsumenta.
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

# ── 0. Cztery sprawy zweryfikowane, od najstarszej do najnowszej ────────────
# ⚠️ Baza jest WSPOLNA i moga w niej lezec sprawy z wczesniejszych testow — w tym
# STARSZE od naszych. Dlatego nizej sprawdzamy KOLEJNOSC wzgledna naszych spraw,
# a nie doslowna zawartosc listy. Pierwsza wersja tego testu zakladala pusta baze
# i padala na cudzej sprawie, ktora byla po prostu starsza.
SLA_ZASTANE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla")
SLA_ZASTANE_IDS=$(q "SELECT IFNULL(GROUP_CONCAT(case_id), '0') FROM wp_mp_case_sla")
C1=$(mkcase ratunek-1@example.com RATUNEK-1)
C2=$(mkcase ratunek-2@example.com RATUNEK-2)
C3=$(mkcase ratunek-3@example.com RATUNEK-3)
C4=$(mkcase ratunek-4@example.com RATUNEK-4)
{ [ -n "$C1" ] && [ -n "$C4" ]; } && ok "cztery sprawy testowe utworzone ($C1..$C4)" || bad "nie udalo sie utworzyc spraw"

# ── 1. SEDNO: kolejnosc JAWNA — o najstarsze prosi sie wprost ───────────────
# Pozycja NASZYCH spraw na liscie: przy prosbie o najstarsze C1 musi stac PRZED C4.
pozycja() { printf '%s' "$1" | tr ',' '\n' | grep -n "^$2$" | cut -d: -f1; }
ASC_LISTA=$(wp eval "echo implode(',', MP\\Intake\\CaseRepo::verified_ids_recent( 365, 500, 'ASC' ));" 2>/dev/null | tr -d '[:space:]')
P1=$(pozycja "$ASC_LISTA" "$C1"); P4=$(pozycja "$ASC_LISTA" "$C4")
{ [ -n "$P1" ] && [ -n "$P4" ] && [ "$P1" -lt "$P4" ]; } 2>/dev/null \
	&& ok "prosba o najstarsze: starsza sprawa PRZED nowsza (pozycje $P1 < $P4)" \
	|| bad "kolejnosc od najstarszych nie zadzialala (pozycje $P1 / $P4) — to jest wada 2.18"

# ── 2. KONTROLA: DOMYSLNE zachowanie NIETKNIETE ─────────────────────────────
# Gdyby naprawa odwrocila kolejnosc na sztywno, zmienilaby zachowanie kazdemu,
# kto ten kontrakt wola — i zrobilaby to po cichu.
DOMYSLNE=$(wp eval "echo implode(',', MP\\Intake\\CaseRepo::verified_ids_recent( 365, 2 ));" 2>/dev/null | tr -d '[:space:]')
[ "$DOMYSLNE" = "$C4,$C3" ] \
	&& ok "bez podania kolejnosci nadal NAJNOWSZE pierwsze ($DOMYSLNE)" \
	|| bad "domyslna kolejnosc ZMIENIONA na '$DOMYSLNE' — cicha zmiana dla innych konsumentow"

# ── 3. KONTROLA: stary sposob wolania kontraktu dziala jak dotad ────────────
# Inni konsumenci wolaja filtr z TRZEMA argumentami — maja dostac to, co dotad.
STARY=$(wp eval "echo implode(',', (array) apply_filters( 'mp_cases_verified_ids', array(), 365, 2 ));" 2>/dev/null | tr -d '[:space:]')
[ "$STARY" = "$C4,$C3" ] \
	&& ok "wolanie filtra po staremu (3 argumenty) zwraca to samo co przed naprawa" \
	|| bad "stary sposob wolania zmienil wynik na '$STARY'"

NOWY=$(wp eval "echo implode(',', (array) apply_filters( 'mp_cases_verified_ids', array(), 365, 500, 'ASC' ));" 2>/dev/null | tr -d '[:space:]')
[ "$NOWY" = "$ASC_LISTA" ] && [ "$NOWY" != "$DOMYSLNE" ] \
	&& ok "filtr przepuszcza kolejnosc czwartym argumentem (wynik jak przy prosbie wprost)" \
	|| bad "filtr nie przepuszcza kolejnosci"

# ── 4. Kolejnosc idzie do SQL — musi byc z WHITELISTY, nie z wejscia ───────
SMIEC=$(wp eval "echo implode(',', MP\\Intake\\CaseRepo::verified_ids_recent( 365, 2, 'ASC; DROP TABLE wp_mp_service_cases' ));" 2>/dev/null | tr -d '[:space:]')
TABELA=$(q "SHOW TABLES LIKE 'wp_mp_service_cases'")
[ "$SMIEC" = "$C4,$C3" ] && [ -n "$TABELA" ] \
	&& ok "smiec w kolejnosci => zapas DESC, tabela nietknieta (whitelist dziala)" \
	|| bad "smieciowa kolejnosc zmienila wynik ('$SMIEC') albo ruszyla tabele"

# ── 5. SEDNO ZACHOWANIA: ratunek bierze NAJSTARSZA sprawe, nie najnowsza ───
# Zdejmujemy wiersze terminow wszystkim czterem (tak wyglada sprawa potwierdzona
# przy wylaczonym automacie) i pozwalamy doszyc TYLKO JEDNA. Przed naprawa
# mechanizm siegal od najnowszej, czyli ratowal te, ktora czekala NAJKROCEJ.
wp db query "DELETE FROM wp_mp_case_sla WHERE case_id IN ($C1,$C2,$C3,$C4)" >/dev/null 2>&1
BEZ_TERMINU=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id IN ($C1,$C2,$C3,$C4)")
[ "$BEZ_TERMINU" = "0" ] && ok "cztery sprawy bez wiersza terminu (przygotowanie)" || bad "nie udalo sie przygotowac spraw bez terminu ($BEZ_TERMINU)"

# Ktora sprawa jest NAPRAWDE najstarsza z tych bez terminu — liczymy z bazy,
# nie zakladamy. W bazie moga lezec starsze sprawy z wczesniejszych testow.
NAJSTARSZA_BEZ=$(q "SELECT MIN(c.id) FROM wp_mp_service_cases c LEFT JOIN wp_mp_case_sla s ON s.case_id=c.id WHERE c.identity_status='verified' AND s.case_id IS NULL")
wp eval 'MP\Automator\Sla::reconcile_untracked( 1 );' >/dev/null 2>&1
MA_NAJSTARSZA=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$NAJSTARSZA_BEZ")
MA_NAJNOWSZA=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$C4")
[ "$MA_NAJSTARSZA" = "1" ] \
	&& ok "ratunek doszyl NAJSTARSZA sprawe bez terminu (id=$NAJSTARSZA_BEZ — te, ktora czeka najdluzej)" \
	|| bad "najstarsza sprawa ($NAJSTARSZA_BEZ) nadal bez terminu — mechanizm zaczyna od zlej strony (to jest wada 2.18)"
[ "$MA_NAJNOWSZA" = "0" ] \
	&& ok "najnowsza sprawa czeka na swoja kolej (kolejnosc naprawde odwrocona)" \
	|| bad "ratunek poszedl od najnowszej — kolejnosc nie dotarla do sciezki ratunkowej"

# ── 6. Mechanizm nadal domyka calosc (regresja zero) ───────────────────────
wp eval 'MP\Automator\Sla::reconcile_untracked( 20 );' >/dev/null 2>&1
WSZYSTKIE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id IN ($C1,$C2,$C3,$C4)")
[ "$WSZYSTKIE" = "4" ] \
	&& ok "kolejny przebieg domyka reszte (wszystkie cztery maja termin)" \
	|| bad "po pelnym przebiegu terminy ma $WSZYSTKIE z 4 spraw"

# ── 7. SPRZATANIE ZE SPRAWDZENIEM ─────────────────────────────────────────
for ID in "$C1" "$C2" "$C3" "$C4"; do
	[ -n "$ID" ] && wp db query "DELETE FROM wp_mp_service_cases WHERE id=$ID; DELETE FROM wp_mp_case_sla WHERE case_id=$ID; DELETE FROM wp_mp_case_events WHERE case_id=$ID; DELETE FROM wp_mp_workflow_events WHERE case_id=$ID;" >/dev/null 2>&1
done
# Wiersze, ktore ten test wywolal dla CUDZYCH spraw (ratunek doszyl je po drodze),
# tez sa nasze do posprzatania — inaczej nastepny test dostanie inny stan wejsciowy.
wp db query "DELETE FROM wp_mp_case_sla WHERE case_id NOT IN ($SLA_ZASTANE_IDS)" >/dev/null 2>&1
SLA_KONIEC=$(q "SELECT COUNT(*) FROM wp_mp_case_sla")
[ "${SLA_KONIEC:-0}" = "${SLA_ZASTANE:-0}" ] \
	&& ok "tabela terminow oddana w stanie zastanym ($SLA_ZASTANE wierszy)" \
	|| bad "zostawiamy $SLA_KONIEC wierszy terminow (zastano $SLA_ZASTANE)"

echo ""
echo "WYNIK 2.18: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
