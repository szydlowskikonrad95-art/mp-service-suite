#!/usr/bin/env bash
# ZYWY DOWOD P3.3 notyfikacja przydzialu: ZASADA "kazdy przydzial (auto i reczny,
# dowolny caller) -> mail assignment_notify do nowo przypisanego" jako GWARANCJA
# STRUKTURY — hook mp_case_assigned emitowany w C.assign() PO COMMIT, D sluchacz
# wysyla mail. Event CASE_ASSIGNED na osi robi C (w transakcji). NO-PII w logu D.
# Asercje na capture (dziala w CI bez Mailpita). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
CAP="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
capclear() { : > "$CAP"; }
caplast()  { tail -n 1 "$CAP" 2>/dev/null; }

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Czysty stan + 2 agentow ───────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
A1=$(wp user create an1 an1@example.com --role=mp_agent --porcelain 2>/dev/null); [ -z "$A1" ] && A1=$(wp user get an1 --field=ID 2>/dev/null)
A2=$(wp user create an2 an2@example.com --role=mp_agent --porcelain 2>/dev/null); [ -z "$A2" ] && A2=$(wp user get an2 --field=ID 2>/dev/null)
ok "agenci: A1=$A1 A2=$A2"

# ── 1. AUTO-przydzial (regula na case_created) -> mail do agenta A1 ───────────
wp eval "MP\Automator\Rules::insert(array('trigger_type'=>'case_created','action_type'=>'assign','enabled'=>1,'condition_key'=>'','action_config'=>array('pool'=>array($A1))));" >/dev/null 2>&1
CID=$(mkcase klan@example.com AN-1)
[ "$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID")" = "$A1" ] && ok "auto-przydzial do A1 (case_id=$CID)" || bad "sprawa nieprzydzielona do A1"
LINE=$(caplast)
echo "$LINE" | grep -q "\"to\":\"an1@example.com\"" && ok "assignment_notify wyslany do NOWEGO agenta A1" || bad "brak maila do agenta ($LINE)"
echo "$LINE" | grep -q 'Przydzielono Ci' && ok "tresc assignment_notify (szablon zrenderowany)" || bad "zla tresc maila"
echo "$LINE" | grep -q '{{' && bad "surowy marker w mailu" || ok "markery przydzialu zrenderowane (bez surowych {{)"

# ── 2. EVENT na osi (C): CASE_ASSIGNED w transakcji (nie tylko mail) ──────────
CA=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CASE_ASSIGNED'")
[ "$CA" = "1" ] && ok "CASE_ASSIGNED na osi sprawy (C, w transakcji przydzialu)" || bad "brak CASE_ASSIGNED na osi ($CA)"

# ── 3. NO-PII: log D notyfikacji bez adresu agenta ───────────────────────────
PAY=$(q "SELECT payload FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='RULE_EXECUTED' AND payload LIKE '%assignment_notify%'")
echo "$PAY" | grep -q '"recipient_ref":"agent"' && ok "recipient_ref=agent (kategoria, NO-PII)" || bad "brak recipient_ref=agent ($PAY)"
echo "$PAY" | grep -q 'an1@example.com' && bad "ADRES agenta w logu (wyciek PII!)" || ok "brak adresu agenta w logu (NO-PII)"

# ── 4. BULLETPROOF: bezposredni mp_case_assign (POMIJA run_assignment) tez notyfikuje ─
# (symuluje reczny przydzial koordynatora / dowolnego callera — hook w C.assign gwarantuje mail)
capclear
wp eval "apply_filters('mp_case_assign', null, $CID, $A2, 1);" >/dev/null 2>&1
[ "$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID")" = "$A2" ] && ok "przepisanie na A2 bezposrednim mp_case_assign" || bad "przepisanie nieudane"
RL=$(caplast)
echo "$RL" | grep -q "\"to\":\"an2@example.com\"" && ok "BULLETPROOF: bezposredni przydzial (bez run_assignment) TEZ wyslal mail do A2 (hook w C)" || bad "brak maila przy bezposrednim przydziale — obejscie! ($RL)"

# ── Sprzatanie ────────────────────────────────────────────────────────────────
capclear
for u in "$A1" "$A2"; do wp user delete "$u" --yes >/dev/null 2>&1; done
echo ""
echo "D-P33B-ASSIGN-NOTIFY: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
