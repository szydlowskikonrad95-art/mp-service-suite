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
VER=$(wp option get mp_automator_schema_version 2>/dev/null | tr -d '[:space:]')
[ "$VER" = "2" ] && ok "mp_automator_schema_version = $VER (== LATEST)" || bad "wersja schematu != 2 (jest: $VER)"

wp eval 'MP\Automator\Schema::migrate();' >/dev/null 2>&1
VER2=$(wp option get mp_automator_schema_version 2>/dev/null | tr -d '[:space:]')
[ "$VER2" = "2" ] && ok "ponowny migrate() idempotentny (wersja nadal $VER2)" || bad "ponowny migrate zmienil wersje na $VER2"

# ── Podsumowanie ─────────────────────────────────────────────────────────────
echo ""
echo "D1-SCHEMAT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
