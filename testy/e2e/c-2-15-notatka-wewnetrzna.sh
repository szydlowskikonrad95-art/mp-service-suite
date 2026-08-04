#!/usr/bin/env bash
# ZYWY DOWOD 2.15: personel ma gdzie zapisac uwage, ktorej klient nie zobaczy.
#
# BUG (audyt 2.15, waga srednia): wiadomosci sprawy mialy TRZY typy autora —
# klient, personel, system — i zaden nie byl niewidoczny dla klienta. Panel
# klienta czytal je zapytaniem BEZ filtra widocznosci. Serwisant nie mial gdzie
# zapisac uwagi dla kolegi: o podejrzeniu ingerencji, o wycenie, o kliencie.
# ✅ Produkt NIE wprowadzal w blad — pole nazywa sie „odpowiedz", a os czasu nie
# jest klientowi pokazywana. To byl BRAK MIEJSCA na notatke, nie pulapka.
#
# FIX: typ `internal`, niewidoczny DOMYSLNIE — wykluczony w ZAPYTANIU, nie
# w szablonie, i bez zdarzenia, zeby nie poszedl mail „masz nowa odpowiedz".
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

TRESC='PODEJRZENIE INGERENCJI - sprawdzic plomby'

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

CID=$(mkcase notatka@example.com NOTATKA-1)
[ -n "$CID" ] && ok "sprawa testowa utworzona (id=$CID)" || bad "nie udalo sie utworzyc sprawy"

# ── 1. SEDNO: notatke da sie zapisac ────────────────────────────────────────
wp eval "MP\\Intake\\Messages::add_internal_note( $CID, 1, '$TRESC' );" >/dev/null 2>&1
ZAPISANA=$(q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CID AND author_type='internal'")
[ "$ZAPISANA" = "1" ] \
	&& ok "notatka wewnetrzna zapisana w sprawie" \
	|| bad "nie da sie zapisac notatki niewidocznej dla klienta (to jest wada 2.15)"

# ── 2. Klient jej NIE dostaje — i to z ZAPYTANIA, nie z szablonu ────────────
KLIENT=$(wp eval "\$m = MP\\Intake\\Messages::for_case( $CID ); echo count( \$m );" 2>/dev/null | tr -d '[:space:]')
KLIENT_TRESC=$(wp eval "\$m = MP\\Intake\\Messages::for_case( $CID ); \$t=''; foreach (\$m as \$w) { \$t .= (string) \$w['body']; } echo \$t;" 2>/dev/null)
printf '%s' "$KLIENT_TRESC" | grep -q "PODEJRZENIE" \
	&& bad "notatka wyciekla do odczytu klienta" \
	|| ok "domyslny odczyt NIE zwraca notatki (wykluczona w zapytaniu, nie w wygladzie)"

# ── 3. Personel ja widzi, gdy poprosi WPROST ───────────────────────────────
PERSONEL=$(wp eval "\$m = MP\\Intake\\Messages::for_case( $CID, true ); \$t=''; foreach (\$m as \$w) { \$t .= (string) \$w['body']; } echo \$t;" 2>/dev/null)
printf '%s' "$PERSONEL" | grep -q "PODEJRZENIE" \
	&& ok "karta personelu widzi notatke (po jawnej prosbie)" \
	|| bad "personel tez nie widzi notatki — funkcja bez sensu"

# ── 4. PULAPKA: notatka NIE emituje zdarzenia (inaczej klient dostanie mail) ─
# Ukrycie tresci bez tego byloby polowiczne: klient nie zobaczylby notatki,
# ale dostalby wiadomosc „jest nowa odpowiedz".
ZDARZENIA=$(wp eval "
	\$licznik = 0;
	add_action( 'mp_case_message_added', static function () use ( &\$licznik ) { ++\$licznik; } );
	MP\\Intake\\Messages::add_internal_note( $CID, 1, 'druga notatka bez maila' );
	echo (int) \$licznik;" 2>/dev/null | tr -d '[:space:]')
[ "${ZDARZENIA:-1}" = "0" ] \
	&& ok "notatka NIE emituje zdarzenia (klient nie dostanie maila o niewidocznej tresci)" \
	|| bad "notatka wywolala zdarzenie ($ZDARZENIA) — pojdzie mail o czyms, czego klient nie zobaczy"

# ── 5. KONTROLA ODWROTNA: zwykla odpowiedz personelu DZIALA jak dotad ───────
ZDARZENIA_ODP=$(wp eval "
	\$licznik = 0;
	add_action( 'mp_case_message_added', static function () use ( &\$licznik ) { ++\$licznik; } );
	MP\\Intake\\Messages::add( $CID, 'staff', 1, 'zwykla odpowiedz do klienta' );
	echo (int) \$licznik;" 2>/dev/null | tr -d '[:space:]')
[ "${ZDARZENIA_ODP:-0}" = "1" ] \
	&& ok "zwykla odpowiedz nadal emituje zdarzenie (powiadomienia klienta bez zmian)" \
	|| bad "zwykla odpowiedz przestala powiadamiac klienta ($ZDARZENIA_ODP) — cisza poszla za daleko"

WIDZI_ODP=$(wp eval "\$m = MP\\Intake\\Messages::for_case( $CID ); \$t=''; foreach (\$m as \$w) { \$t .= (string) \$w['body']; } echo \$t;" 2>/dev/null)
printf '%s' "$WIDZI_ODP" | grep -q "zwykla odpowiedz" \
	&& ok "zwykla odpowiedz nadal widoczna dla klienta (regresja zero)" \
	|| bad "odpowiedz personelu zniknela klientowi — filtr objal za duzo"

# ── 6. Panel klienta: sprawdzamy RENDER, nie tylko warstwe danych ───────────
RENDER=$(wp eval "
	\$m = MP\\Intake\\Messages::for_case( $CID );
	\$t = '';
	foreach ( \$m as \$w ) { \$t .= (string) \$w['author_type'] . '|'; }
	echo \$t;" 2>/dev/null | tr -d '[:space:]')
printf '%s' "$RENDER" | grep -q "internal" \
	&& bad "typ internal trafil do zestawu czytanego przez panel klienta" \
	|| ok "panel klienta dostaje wylacznie typy jawne ($RENDER)"

# ── 7. SPRZATANIE ZE SPRAWDZENIEM ─────────────────────────────────────────
wp db query "DELETE FROM wp_mp_messages WHERE case_id=$CID; DELETE FROM wp_mp_service_cases WHERE id=$CID; DELETE FROM wp_mp_case_events WHERE case_id=$CID; DELETE FROM wp_mp_case_sla WHERE case_id=$CID;" >/dev/null 2>&1
ZOSTALO=$(q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CID")
[ "${ZOSTALO:-1}" = "0" ] \
	&& ok "sprawa i wiadomosci testowe posprzatane" \
	|| bad "zostawiamy $ZOSTALO wiadomosci"

echo ""
echo "WYNIK 2.15: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
