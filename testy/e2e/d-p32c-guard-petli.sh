#!/usr/bin/env bash
# ZYWY DOWOD P3.2 GUARD PETLI: akcja change_status odpala trigger status_changed,
# wiec reguly A->B i B->A groza nieskonczona petla. Strażnik glebokosci: mutacje
# TYLKO na glebokosci 0; na glebokosci 1 mutacja ZABLOKOWANA + RULE_LOOP_BLOCKED.
# Ksiegowanie zdarzen dzieje sie ZAWSZE. Testuje REALNA droga (mp_case_change_status
# + prawdziwy nasluch mp_case_status_changed). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
# Zmiana statusu REALNA droga kontraktowa C (jak panel/admin).
cs()  { wp eval "echo wp_json_encode( apply_filters('mp_case_change_status', null, $1, '$2', '$3', 1, $4) );" 2>/dev/null; }

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Czysty stan + WLASNY zestaw regul (kasujemy seed, sterujemy precyzyjnie) ─
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

# Regula A: status=='w analizie' -> zmien na 'zaakceptowane'
RA=$(wp eval "echo MP\Automator\Rules::insert(array('trigger_type'=>'status_changed','enabled'=>1,'condition_key'=>'status','condition_operator'=>'equals','condition_value'=>'w analizie','action_type'=>'change_status','action_config'=>array('new_status'=>'zaakceptowane')));" 2>/dev/null)
# Regula B: status=='zaakceptowane' -> zmien na 'w analizie' (petla z A!)
RB=$(wp eval "echo MP\Automator\Rules::insert(array('trigger_type'=>'status_changed','enabled'=>1,'condition_key'=>'status','condition_operator'=>'equals','condition_value'=>'zaakceptowane','action_type'=>'change_status','action_config'=>array('new_status'=>'w analizie')));" 2>/dev/null)
{ [ -n "$RA" ] && [ -n "$RB" ]; } && ok "reguly petli utworzone A=$RA (analiza->zaakcept) B=$RB (zaakcept->analiza)" || bad "insert regul nie zwrocil id (A=$RA B=$RB)"

# ── 1. Sprawa 'nowe'; czyscimy eventy PO utworzeniu (izolujemy pomiar guardu) ──
CID=$(mkcase gp@example.com GP-1)
[ "$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")" = "nowe" ] && ok "sprawa 'nowe' (case_id=$CID)" || bad "sprawa nie 'nowe'"
wp db query "DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_case_events WHERE case_id=$CID;" >/dev/null 2>&1

# ── 2. ZDARZENIE ZEWNETRZNE (depth 0): nowe -> 'w analizie' (odpala lancuch regul) ─
R=$(cs "$CID" "w analizie" "nowe" "null")
echo "$R" | grep -q '"success":true' && ok "zewnetrzna zmiana nowe->w analizie OK (start lancucha)" || bad "zewnetrzna zmiana nieudana ($R)"

# ── 3. KONIEC NA 'zaakceptowane': A zadzialal (depth0), B ZABLOKOWANY (depth1) ─
FIN=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
[ "$FIN" = "zaakceptowane" ] && ok "koniec na 'zaakceptowane' (A depth0 wykonany, B depth1 zablokowany)" || bad "status koncowy=[$FIN] (oczekiwano zaakceptowane; petla?)"

# ── 4. ZERO LAWINY: dokladnie 2 realne zmiany statusu na osi (extern + A) ─────
SC=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='STATUS_CHANGED'")
[ "$SC" = "2" ] && ok "dokladnie 2 STATUS_CHANGED (extern + regula A) — zero nieskonczonej petli" || bad "STATUS_CHANGED=$SC (petla lub brak reakcji!)"

# ── 5. RULE_LOOP_BLOCKED zaksiegowany dla mutacji z glebokosci 1 (regula B) ───
LB=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='RULE_LOOP_BLOCKED'")
[ "$LB" -ge 1 ] 2>/dev/null && ok "RULE_LOOP_BLOCKED zaksiegowany ($LB szt.) — mutacja depth>=1 zablokowana" || bad "brak RULE_LOOP_BLOCKED (guard nie zadzialal?)"
LBD=$(q "SELECT payload FROM wp_mp_workflow_events WHERE event_type='RULE_LOOP_BLOCKED' ORDER BY id DESC LIMIT 1")
echo "$LBD" | grep -q '"depth":1' && ok "RULE_LOOP_BLOCKED payload: depth=1 (glebokosc re-entrant, nie glebiej)" || bad "zla glebokosc w RULE_LOOP_BLOCKED ($LBD)"

# ── 6. Ksiegowanie ZAWSZE: udana mutacja A = RULE_EXECUTED depth=0 success ────
RE=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='RULE_EXECUTED' AND payload LIKE '%\"result\":\"success\"%' AND payload LIKE '%\"depth\":0%'")
[ "$RE" = "1" ] && ok "RULE_EXECUTED depth=0 success dla reguly A (ksiegowanie dziala)" || bad "RULE_EXECUTED depth0/success=$RE (oczekiwano 1)"

# ── 7. Mutacja B faktycznie NIE zaszla: brak RULE_EXECUTED success dla B (->w analizie) ─
# (gdyby B sie wykonal, status wrocilby na 'w analizie' — juz sprawdzone w 3/4, tu audyt logu)
BEX=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='RULE_EXECUTED' AND payload LIKE '%\"rule_id\":$RB%'")
[ "$BEX" = "0" ] && ok "regula B NIE ma wpisu RULE_EXECUTED (mutacja zablokowana, nie wykonana)" || bad "regula B sie wykonala mimo guardu ($BEX)"

echo ""
echo "D-P32C-GUARD-PETLI: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
