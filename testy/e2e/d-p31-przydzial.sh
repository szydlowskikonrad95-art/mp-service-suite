#!/usr/bin/env bash
# ZYWY DOWOD P3.1 (auto-przydzial): silnik regul reaguje na mp_case_created,
# dopasowuje regule przydzialu, robi round-robin ATOMOWY po puli i WOLA
# mp_case_assign w C. Testuje: alternacje A->B->A (round-robin), event CASE_ASSIGNED
# w C + RULE_EXECUTED w rejestrze D, ASSIGNMENT_UNMATCHED gdy nic nie pasuje,
# filtr puli (non-agent wypada). Chodzi tak samo na poligonie i w CI. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Tworzy+weryfikuje sprawe (mp_case_created odpala silnik). Echo: case_id.
mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Czysty stan + 2 agentow + 1 non-agent ─────────────────────────────────
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

A=$(wp user create p31_a p31_a@example.com --role=mp_agent --porcelain 2>/dev/null); [ -z "$A" ] && A=$(wp user get p31_a --field=ID 2>/dev/null)
B=$(wp user create p31_b p31_b@example.com --role=mp_agent --porcelain 2>/dev/null); [ -z "$B" ] && B=$(wp user get p31_b --field=ID 2>/dev/null)
X=$(wp user create p31_x p31_x@example.com --role=subscriber --porcelain 2>/dev/null); [ -z "$X" ] && X=$(wp user get p31_x --field=ID 2>/dev/null)
ok "agenci: A=$A B=$B (mp_agent), non-agent X=$X"

# ── 1. Regula przydzialu: pula [A, X, B] (X=non-agent, ma wypasc w filtrze) ───
RID=$(wp eval "echo MP\Automator\Rules::insert(array('trigger_type'=>'case_created','action_type'=>'assign','enabled'=>1,'condition_key'=>'','action_config'=>array('pool'=>array($A,$X,$B))));" 2>/dev/null)
[ -n "$RID" ] && ok "regula przydzialu utworzona (id=$RID, pula [A,X,B])" || bad "insert reguly nie zwrocil id"

# ── 2. Round-robin: 3 sprawy -> A, B, A (X przefiltrowany, wiec pula=[A,B]) ───
C1=$(mkcase c1@example.com RR-1); AS1=$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$C1")
[ "$AS1" = "$A" ] && ok "sprawa 1 -> A ($AS1) [index 0]" || bad "sprawa 1 przypisana do $AS1 (oczekiwano A=$A)"

C2=$(mkcase c2@example.com RR-2); AS2=$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$C2")
[ "$AS2" = "$B" ] && ok "sprawa 2 -> B ($AS2) [index 1, round-robin]" || bad "sprawa 2 przypisana do $AS2 (oczekiwano B=$B)"

C3=$(mkcase c3@example.com RR-3); AS3=$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$C3")
[ "$AS3" = "$A" ] && ok "sprawa 3 -> A ($AS3) [index 0, zawiniecie]" || bad "sprawa 3 przypisana do $AS3 (oczekiwano A=$A)"

# X (non-agent) NIGDY nie dostal sprawy (filtr puli runtime).
XGOT=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE assigned_to=$X")
[ "$XGOT" = "0" ] && ok "non-agent X nie dostal zadnej sprawy (pula filtrowana w runtime)" || bad "non-agent dostal sprawe!"

# ── 3. Eventy: CASE_ASSIGNED (w C) + RULE_EXECUTED (w D) per sprawa ───────────
CA=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE event_type='CASE_ASSIGNED'")
[ "$CA" = "3" ] && ok "3x CASE_ASSIGNED na osi spraw (C)" || bad "CASE_ASSIGNED = $CA (oczekiwano 3)"
RE=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='RULE_EXECUTED'")
[ "$RE" = "3" ] && ok "3x RULE_EXECUTED w rejestrze operacji D" || bad "RULE_EXECUTED = $RE (oczekiwano 3)"
REPAY=$(q "SELECT payload FROM wp_mp_workflow_events WHERE event_type='RULE_EXECUTED' ORDER BY id DESC LIMIT 1")
echo "$REPAY" | grep -q '"depth":0' && ok "RULE_EXECUTED payload: depth=0 ($REPAY)" || bad "brak depth=0 w payloadzie"

# ── 4. ASSIGNMENT_UNMATCHED: regula z warunkiem, ktory NIE pasuje ────────────
wp db query "UPDATE wp_mp_workflow_rules SET condition_key='kraj', condition_operator='equals', condition_value='ZZ' WHERE id=$RID" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_workflow_events" >/dev/null 2>&1
C4=$(mkcase c4@example.com UM-1); AS4=$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$C4")
if [ -z "$AS4" ] || [ "$AS4" = "0" ] || [ "$AS4" = "NULL" ]; then ok "sprawa 4 NIEPRZYDZIELONA (warunek kraj=ZZ nie pasuje)"; else bad "sprawa 4 przypisana do $AS4 mimo niepasujacego warunku"; fi
UM=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='ASSIGNMENT_UNMATCHED'")
[ "$UM" = "1" ] && ok "ASSIGNMENT_UNMATCHED zapisany (swiadomy stan, nie cicha magia)" || bad "brak ASSIGNMENT_UNMATCHED (jest $UM)"

# ── Sprzatanie + podsumowanie ────────────────────────────────────────────────
for u in "$A" "$B" "$X"; do wp user delete "$u" --yes >/dev/null 2>&1; done
echo ""
echo "D-P31-PRZYDZIAL: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
