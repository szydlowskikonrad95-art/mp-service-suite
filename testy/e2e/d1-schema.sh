#!/usr/bin/env bash
# ZYWY DOWOD D1 (schemat Automatora): aktywacja tworzy 4 tabele wlasne D wg
# kontraktu (DATABASE.md / OWNERSHIP.md), kluczowe kolumny/indeksy sa na miejscu,
# rejestr operacji jest ZAPISYWALNY (append-only), a migracja jest IDEMPOTENTNA
# (drugi przebieg = no-op, wersja == LATEST). Chodzi tak samo na poligonie i w CI.
# Exit 0 = wszystkie asercje przeszly.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

PREFIX=$(wp db prefix 2>/dev/null | tr -d '[:space:]')
[ -n "$PREFIX" ] || PREFIX="wp_"

# ── 1. Cztery tabele wlasne D istnieja po aktywacji ──────────────────────────
for T in workflow_rules case_sla case_checklists workflow_events; do
	FULL="${PREFIX}mp_${T}"
	CNT=$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='$FULL'")
	[ "$CNT" = "1" ] && ok "tabela $FULL istnieje" || bad "BRAK tabeli $FULL (aktywacja nie zbudowala schematu)"
done

# ── 2. Kolumny/indeksy kontraktowe (najslabsze miejsca) ──────────────────────
# workflow_rules: rr_cursor (round-robin) + system_key UNIQUE + indeks triggera.
RR=$(q "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='${PREFIX}mp_workflow_rules' AND column_name='rr_cursor'")
[ "$RR" = "1" ] && ok "workflow_rules.rr_cursor obecny (atomowy round-robin)" || bad "brak rr_cursor"

SYSU=$(q "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='${PREFIX}mp_workflow_rules' AND index_name='system_key' AND non_unique=0")
[ "$SYSU" = "1" ] && ok "workflow_rules.system_key UNIQUE (rozpoznanie seedow)" || bad "system_key nie jest UNIQUE"

TRIDX=$(q "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='${PREFIX}mp_workflow_rules' AND index_name='trigger_enabled_priority'")
[ "$TRIDX" -ge 1 ] 2>/dev/null && ok "workflow_rules indeks (trigger_type,enabled,priority)" || bad "brak indeksu trigger_enabled_priority"

# case_sla: PK = case_id + indeks deadline_at (sweep sarga po nim).
PKCOL=$(q "SELECT column_name FROM information_schema.key_column_usage WHERE table_schema=DATABASE() AND table_name='${PREFIX}mp_case_sla' AND constraint_name='PRIMARY'")
[ "$PKCOL" = "case_id" ] && ok "case_sla PK = case_id" || bad "case_sla PK != case_id (jest: $PKCOL)"

DLIDX=$(q "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='${PREFIX}mp_case_sla' AND index_name='deadline_at'")
[ "$DLIDX" -ge 1 ] 2>/dev/null && ok "case_sla indeks deadline_at (sweep SARGABLE)" || bad "brak indeksu deadline_at"

# case_sla v2 (SLA-2): kolumna + indeks warning_at (sweep SARGA po progu przypomnienia).
WACOL=$(q "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='${PREFIX}mp_case_sla' AND column_name='warning_at'")
[ "$WACOL" = "1" ] && ok "case_sla kolumna warning_at (migracja v2)" || bad "brak kolumny warning_at"
WAIDX=$(q "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='${PREFIX}mp_case_sla' AND index_name='warning_at'")
[ "$WAIDX" -ge 1 ] 2>/dev/null && ok "case_sla indeks warning_at (sweep SARGABLE)" || bad "brak indeksu warning_at"

# case_sla v3 (M4): stemple ostatniej proby wysylki — na nich stoi ODSTEP miedzy
# ponowieniami (bez nich komplet prob palil sie w jednym przebiegu zamiatarki).
for K in reminder_attempt_at escalation_attempt_at; do
	KOL=$(q "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='${PREFIX}mp_case_sla' AND column_name='$K'")
	[ "$KOL" = "1" ] && ok "case_sla kolumna $K (migracja v3)" || bad "brak kolumny $K"
done

# case_checklists: UNIQUE (case_id,template_id,step_key) — wiersz per krok, zero wyscigu o blob.
CLU=$(q "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='${PREFIX}mp_case_checklists' AND index_name='case_step' AND non_unique=0")
[ "$CLU" -ge 1 ] 2>/dev/null && ok "case_checklists UNIQUE (case_id,template_id,step_key)" || bad "brak UNIQUE case_step"

# ── 3. Rejestr operacji ZAPISYWALNY (append-only) + case_id NULL dozwolony ────
wp db query "DELETE FROM ${PREFIX}mp_workflow_events" >/dev/null 2>&1
wp eval 'MP\Automator\WorkflowEvents::log( MP\Automator\WorkflowEvents::EXPORT_GENERATED, array( "rows" => 3, "filters_hash" => "abc" ), null, 1 );' >/dev/null 2>&1
ROWS=$(q "SELECT COUNT(*) FROM ${PREFIX}mp_workflow_events WHERE event_type='EXPORT_GENERATED' AND case_id IS NULL")
[ "$ROWS" = "1" ] && ok "WorkflowEvents::log zapisal wpis (case_id NULL = zdarzenie nie-per-sprawa)" || bad "rejestr operacji nie zapisal wpisu (rows=$ROWS)"

PAY=$(q "SELECT payload FROM ${PREFIX}mp_workflow_events WHERE event_type='EXPORT_GENERATED' ORDER BY id DESC LIMIT 1")
echo "$PAY" | grep -q '"rows":3' && ok "payload strukturalny JSON zapisany ($PAY)" || bad "payload nie zawiera rows:3 ($PAY)"

# NO-PII-IN-LOG: w payloadzie NIE MA adresu e-mail (kontrola zasady, nie tylko obietnica).
echo "$PAY" | grep -qE '@[a-z]+\.' && bad "payload zawiera adres e-mail (zlamana NO-PII)" || ok "payload bez adresu e-mail (NO-PII-IN-LOG)"
wp db query "DELETE FROM ${PREFIX}mp_workflow_events" >/dev/null 2>&1

# ── 4. Migracja IDEMPOTENTNA: wersja == LATEST, drugi przebieg nie sypie ──────
# ⛔ WERSJE BIERZEMY Z KODU, NIE Z LICZBY WPISANEJ W TEST. Twarda „2" siedziala tu
# do 1.3.13 i zaswiecila czerwono przy PIERWSZEJ poprawnej migracji, jaka po niej
# przyszla (v3, rozsuniecie prob SLA) — test mowil „wersja schematu != 2", choc
# produkt zachowal sie dokladnie tak, jak powinien. Taki test nie pilnuje niczego,
# tylko nakazuje, zeby schemat nigdy sie nie zmienil. Ta sama lekcja jest juz
# zastosowana w `c22-indeks-przydzialu.sh` i `migration.sh`.
LATEST=$(wp eval 'echo (int) MP\Automator\Schema::LATEST;' 2>/dev/null | tr -d '[:space:]')
[ -n "$LATEST" ] && [ "$LATEST" -ge 1 ] 2>/dev/null \
	&& ok "Schema::LATEST odczytane z kodu ($LATEST)" \
	|| { bad "nie udalo sie odczytac Schema::LATEST z kodu"; LATEST=""; }

VER=$(wp option get mp_automator_schema_version 2>/dev/null | tr -d '[:space:]')
{ [ -n "$LATEST" ] && [ "$VER" = "$LATEST" ]; } \
	&& ok "mp_automator_schema_version = $VER (== Schema::LATEST)" \
	|| bad "wersja schematu = $VER, oczekiwana $LATEST (== Schema::LATEST)"

wp eval 'MP\Automator\Schema::migrate();' >/dev/null 2>&1
VER2=$(wp option get mp_automator_schema_version 2>/dev/null | tr -d '[:space:]')
{ [ -n "$LATEST" ] && [ "$VER2" = "$LATEST" ]; } \
	&& ok "ponowny migrate() idempotentny (wersja nadal $VER2)" \
	|| bad "ponowny migrate zmienil wersje na $VER2 (oczekiwana $LATEST)"

# ── 5. Doganianie zaleglej migracji: instalacja starsza o jedna wersje ────────
# Nie wystarczy, ze SWIEZA instalacja ma komplet kolumn — u klienta migracja
# dobiega z wersji POPRZEDNIEJ, na tabeli pelnej danych. Cofamy wiec znacznik
# wersji o jeden i sprawdzamy, czy przebieg dogania schemat, NIE gubiac wiersza.
if [ -n "$LATEST" ] && [ "$LATEST" -ge 2 ] 2>/dev/null; then
	POPRZEDNIA=$(( LATEST - 1 ))
	wp db query "INSERT INTO ${PREFIX}mp_case_sla (case_id, status, deadline_at, warning_at, updated_at)
		VALUES (999901, 'nowe', UTC_TIMESTAMP(), UTC_TIMESTAMP(), UTC_TIMESTAMP())
		ON DUPLICATE KEY UPDATE updated_at = UTC_TIMESTAMP();" >/dev/null 2>&1
	wp option update mp_automator_schema_version "$POPRZEDNIA" >/dev/null 2>&1

	wp eval 'MP\Automator\Schema::migrate();' >/dev/null 2>&1
	VER3=$(wp option get mp_automator_schema_version 2>/dev/null | tr -d '[:space:]')
	[ "$VER3" = "$LATEST" ] \
		&& ok "zalegla migracja v$POPRZEDNIA -> v$LATEST dogoniona przy wejsciu do panelu" \
		|| bad "migracja z v$POPRZEDNIA nie dogonila (wersja: $VER3)"

	ZOSTAL=$(q "SELECT COUNT(*) FROM ${PREFIX}mp_case_sla WHERE case_id = 999901")
	[ "$ZOSTAL" = "1" ] \
		&& ok "wiersz sprzed migracji PRZEZYL (migracja nie przebudowuje tabeli od zera)" \
		|| bad "migracja zgubila istniejacy wiersz — to utrata danych klienta"

	# Drugi przebieg TEJ SAMEJ migracji na doganianej instalacji: zero zmian, zero bledu.
	wp eval 'MP\Automator\Schema::migrate();' >/dev/null 2>&1
	VER4=$(wp option get mp_automator_schema_version 2>/dev/null | tr -d '[:space:]')
	ZOSTAL2=$(q "SELECT COUNT(*) FROM ${PREFIX}mp_case_sla WHERE case_id = 999901")
	{ [ "$VER4" = "$LATEST" ] && [ "$ZOSTAL2" = "1" ]; } \
		&& ok "powtorzony przebieg po doganianiu tez idempotentny (wersja $VER4, dane nietkniete)" \
		|| bad "powtorzony przebieg zmienil stan (wersja $VER4, wierszy $ZOSTAL2)"

	wp db query "DELETE FROM ${PREFIX}mp_case_sla WHERE case_id = 999901" >/dev/null 2>&1
else
	ok "pominieto doganianie zaleglej migracji (schemat ma tylko jedna wersje)"
fi

# ── Podsumowanie ─────────────────────────────────────────────────────────────
echo ""
echo "D1-SCHEMAT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
