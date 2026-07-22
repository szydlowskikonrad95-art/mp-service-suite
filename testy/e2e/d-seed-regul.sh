#!/usr/bin/env bash
# ZYWY DOWOD seed regul domyslnych: aktywacja sieje regule przydzialu (source=system,
# system_key) TYLKO raz; skasowana regula NIE wraca przy reaktywacji (bramka
# SEED_VERSION); pelny uninstall (kasuje SEED_VERSION_OPTION) => reinstalacja sieje
# swiezo. Chodzi tak samo na poligonie i w CI. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
reactivate() { wp plugin deactivate mp-workflow-automator >/dev/null 2>&1; wp plugin activate mp-workflow-automator >/dev/null 2>&1; }

# ── 1. Swiezy stan -> aktywacja sieje 1 regule domyslna ──────────────────────
wp db query "DELETE FROM wp_mp_workflow_rules" >/dev/null 2>&1
wp option delete mp_automator_seed_version >/dev/null 2>&1
reactivate

N=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules")
[ "$N" = "1" ] && ok "aktywacja zasiala 1 regule domyslna" || bad "regul po seedzie: $N (oczekiwano 1)"

ROW=$(q "SELECT CONCAT(source,'|',system_key,'|',trigger_type,'|',action_type,'|',enabled) FROM wp_mp_workflow_rules")
[ "$ROW" = "system|default_assign|case_created|assign|1" ] && ok "regula: source=system, system_key=default_assign, case_created->assign, enabled ($ROW)" || bad "zla regula seedu ($ROW)"

POOL=$(q "SELECT action_config_json FROM wp_mp_workflow_rules")
echo "$POOL" | grep -qE '"pool":\[\]' && ok "pula PUSTA (admin/demo wypelnia; do tego czasu ASSIGNMENT_UNMATCHED)" || bad "pula nie pusta ($POOL)"
echo "$POOL" | grep -q '"notify_agent":true' && ok "notify_agent=true (uzyte w P3.3)" || bad "brak notify_agent"

SV=$(q "SELECT option_value FROM wp_options WHERE option_name='mp_automator_seed_version'")
[ "$SV" = "1" ] && ok "mp_automator_seed_version = 1 (bramka siewu)" || bad "seed_version = $SV"

# ── 2. Skasuj regule + reaktywuj -> NIE wraca (bramka wersji) ─────────────────
wp db query "DELETE FROM wp_mp_workflow_rules WHERE system_key='default_assign'" >/dev/null 2>&1
reactivate
N2=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules")
[ "$N2" = "0" ] && ok "skasowana regula NIE wraca po reaktywacji (skasowanej nie odtwarzamy)" || bad "regula wrocila ($N2)"

# ── 3. Pelny uninstall (kasuje SEED_VERSION_OPTION) -> reinstalacja sieje swiezo ─
wp option delete mp_automator_seed_version >/dev/null 2>&1
reactivate
N3=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules")
[ "$N3" = "1" ] && ok "po skasowaniu seed_version reinstalacja SIEJE swiezo (1 regula)" || bad "reinstalacja nie zasiala ($N3)"

echo ""
echo "D-SEED-REGUL: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
