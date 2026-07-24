#!/usr/bin/env bash
# ZYWY DOWOD (spec „powiadomienia dla klienta I pracownika po kazdej waznej zmianie"):
# przy ZMIANIE STATUSU przydzielonej sprawy mail idzie do KLIENTA *oraz* do PRZYPISANEGO
# PRACOWNIKA (domyslna reguła status_changed_staff, recipient=agent). SELF-SKIP: gdy status
# zmienil SAM przypisany pracownik — NIE dostaje maila o wlasnej akcji (recipient_ref=agent_self),
# klient dostaje normalnie. Asercje na przechwyconym mailu (mp-mail-capture.jsonl). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

CAP="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
capclear() { : > "$CAP"; }
has_to()   { grep -q "\"to\":\"$1\"" "$CAP" 2>/dev/null; }

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name="$2" --serial="$3" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\\Intake\\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}
# zmiana statusu jako konkretny ACTOR (5. arg kontraktu).
cs_actor() { wp eval "apply_filters('mp_case_change_status', null, $1, '$2', '$3', $5, $4);" >/dev/null 2>&1; }

# ── 0. Czysty stan + seed domyslny (zawiera reguła status_changed_staff) ─────
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); delete_option("mp_automator_mail_templates"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1

AGENT_MAIL='agent-p33e@example.com'
COORD_MAIL='coord-p33e@example.com'
AGENT=$(wp user get agentp33e --field=ID 2>/dev/null); [ -z "$AGENT" ] && AGENT=$(wp user create agentp33e "$AGENT_MAIL" --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
COORD=$(wp user get coordp33e --field=ID 2>/dev/null); [ -z "$COORD" ] && COORD=$(wp user create coordp33e "$COORD_MAIL" --role=mp_coordinator --user_pass=x --porcelain 2>/dev/null)

SR=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules WHERE system_key='status_changed_staff_mail'")
[ "$SR" = "1" ] && ok "reguła status_changed_staff (recipient=agent) zasiana" || bad "brak reguły mail-pracownik ($SR)"

CID=$(mkcase klient-p33e@example.com "Jan Klient" P33E-1)
wp eval "apply_filters('mp_case_assign', null, $CID, $AGENT, 1);" >/dev/null 2>&1
ASG=$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID")
[ "$ASG" = "$AGENT" ] && ok "sprawa przydzielona pracownikowi (agent=$AGENT)" || bad "przydzial nie chwycil ($ASG)"

# ── A. Koordynator (NIE przypisany) zmienia status => KLIENT + PRACOWNIK maila ─
capclear
cs_actor "$CID" "w analizie" "nowe" "null" "$COORD"
has_to "klient-p33e@example.com" && ok "A: KLIENT dostal mail o zmianie statusu" || bad "A: brak maila do klienta"
has_to "$AGENT_MAIL" && ok "A: PRZYPISANY PRACOWNIK dostal mail (spec: klient i pracownik)" || bad "A: pracownik NIE dostal maila!"
# Audyt: regula wykonala sie dla odbiorcy 'agent'. NIE asertujemy result=success —
# transport (wp_mail) zalezy od srodowiska (CI bez MTA => failed; Mailpit => success).
RE=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='RULE_EXECUTED' AND payload LIKE '%\"recipient_ref\":\"agent\"%'")
[ "$RE" != "0" ] && ok "A: RULE_EXECUTED recipient_ref=agent (audyt maila do pracownika; transport-agnostyczny)" || bad "A: brak audytu maila do pracownika ($RE)"

# ── B. SAM przypisany pracownik zmienia status => SELF-SKIP (bez maila do siebie) ─
capclear
cs_actor "$CID" "zaakceptowane" "w analizie" "null" "$AGENT"
has_to "klient-p33e@example.com" && ok "B: KLIENT dostal mail (niezaleznie od self-skip)" || bad "B: brak maila do klienta"
has_to "$AGENT_MAIL" && bad "B: pracownik dostal mail o WLASNEJ zmianie (self-skip nie zadzialal)!" || ok "B: SELF-SKIP — pracownik NIE dostal maila o wlasnej zmianie"
SS=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='MAIL_SKIPPED_NO_RECIPIENT' AND payload LIKE '%agent_self%'")
[ "$SS" != "0" ] && ok "B: pominiecie zaksiegowane jako agent_self (audyt self-skip)" || bad "B: brak sladu agent_self ($SS)"

# sprzatanie userow testowych
wp user delete "$AGENT" --yes >/dev/null 2>&1
wp user delete "$COORD" --yes >/dev/null 2>&1

echo ""
echo "D-P33E-MAIL-PRACOWNIK: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
