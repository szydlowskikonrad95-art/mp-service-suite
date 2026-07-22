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

# ── 1. Swiezy stan -> aktywacja sieje 2 reguly domyslne (przydzial + mail) ────
wp db query "DELETE FROM wp_mp_workflow_rules" >/dev/null 2>&1
wp option delete mp_automator_seed_version >/dev/null 2>&1
wp option delete mp_automator_mail_templates >/dev/null 2>&1
reactivate

N=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules")
[ "$N" = "2" ] && ok "aktywacja zasiala 2 reguly domyslne (przydzial + mail statusu)" || bad "regul po seedzie: $N (oczekiwano 2)"

ROWA=$(q "SELECT CONCAT(source,'|',system_key,'|',trigger_type,'|',action_type,'|',enabled) FROM wp_mp_workflow_rules WHERE system_key='default_assign'")
[ "$ROWA" = "system|default_assign|case_created|assign|1" ] && ok "regula A: system/default_assign, case_created->assign ($ROWA)" || bad "zla regula przydzialu ($ROWA)"

ROWM=$(q "SELECT CONCAT(source,'|',system_key,'|',trigger_type,'|',action_type,'|',enabled) FROM wp_mp_workflow_rules WHERE system_key='status_changed_client_mail'")
[ "$ROWM" = "system|status_changed_client_mail|status_changed|notify|1" ] && ok "regula M: system/status_changed_client_mail, status_changed->notify ($ROWM)" || bad "zla regula mailowa ($ROWM)"

POOL=$(q "SELECT action_config_json FROM wp_mp_workflow_rules WHERE system_key='default_assign'")
echo "$POOL" | grep -qE '"pool":\[\]' && ok "pula PUSTA (admin/demo wypelnia; do tego czasu ASSIGNMENT_UNMATCHED)" || bad "pula nie pusta ($POOL)"
echo "$POOL" | grep -q '"notify_agent":true' && ok "notify_agent=true (uzyte w P3.3)" || bad "brak notify_agent"

MCFG=$(q "SELECT action_config_json FROM wp_mp_workflow_rules WHERE system_key='status_changed_client_mail'")
echo "$MCFG" | grep -q '"recipient":"client"' && ok "regula mailowa: recipient=client, template z config" || bad "zla konfiguracja maila ($MCFG)"

TPL=$(wp eval 'echo MP\Automator\MailTemplates::get("status_changed_client") ? "1":"0";' 2>/dev/null)
[ "$TPL" = "1" ] && ok "szablon status_changed_client zasiany RAZEM z regula (warstwa ii)" || bad "brak szablonu (sierota reguly!)"

SV=$(q "SELECT option_value FROM wp_options WHERE option_name='mp_automator_seed_version'")
[ "$SV" = "1" ] && ok "mp_automator_seed_version = 1 (bramka siewu)" || bad "seed_version = $SV"

# ── 2. Skasuj OBIE reguly + reaktywuj -> NIE wracaja (bramka wersji) ──────────
wp db query "DELETE FROM wp_mp_workflow_rules WHERE source='system'" >/dev/null 2>&1
reactivate
N2=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules")
[ "$N2" = "0" ] && ok "skasowane reguly NIE wracaja po reaktywacji (skasowanej nie odtwarzamy)" || bad "regula wrocila ($N2)"

# ── 3. Pelny uninstall (kasuje SEED_VERSION_OPTION) -> reinstalacja sieje swiezo ─
wp option delete mp_automator_seed_version >/dev/null 2>&1
reactivate
N3=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules")
[ "$N3" = "2" ] && ok "po skasowaniu seed_version reinstalacja SIEJE swiezo (2 reguly)" || bad "reinstalacja nie zasiala ($N3)"

echo ""
echo "D-SEED-REGUL: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
