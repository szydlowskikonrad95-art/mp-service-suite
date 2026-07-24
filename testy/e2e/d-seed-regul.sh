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
[ "$N" = "5" ] && ok "aktywacja zasiala 5 regul domyslnych (przydzial + mail statusu klient + mail statusu pracownik + 2x wiadomosci)" || bad "regul po seedzie: $N (oczekiwano 5)"

ROWA=$(q "SELECT CONCAT(source,'|',system_key,'|',trigger_type,'|',action_type,'|',enabled) FROM wp_mp_workflow_rules WHERE system_key='default_assign'")
[ "$ROWA" = "system|default_assign|case_created|assign|1" ] && ok "regula A: system/default_assign, case_created->assign ($ROWA)" || bad "zla regula przydzialu ($ROWA)"

ROWM=$(q "SELECT CONCAT(source,'|',system_key,'|',trigger_type,'|',action_type,'|',enabled) FROM wp_mp_workflow_rules WHERE system_key='status_changed_client_mail'")
[ "$ROWM" = "system|status_changed_client_mail|status_changed|notify|1" ] && ok "regula M: system/status_changed_client_mail, status_changed->notify ($ROWM)" || bad "zla regula mailowa ($ROWM)"

# NOWA regula: mail do PRACOWNIKA przy zmianie statusu (spec „klient i pracownik").
ROWS=$(q "SELECT CONCAT(source,'|',system_key,'|',trigger_type,'|',action_type,'|',enabled) FROM wp_mp_workflow_rules WHERE system_key='status_changed_staff_mail'")
[ "$ROWS" = "system|status_changed_staff_mail|status_changed|notify|1" ] && ok "regula S: system/status_changed_staff_mail, status_changed->notify ($ROWS)" || bad "zla regula mail-pracownik ($ROWS)"
SCFG=$(q "SELECT action_config_json FROM wp_mp_workflow_rules WHERE system_key='status_changed_staff_mail'")
echo "$SCFG" | grep -q '"recipient":"agent"' && echo "$SCFG" | grep -q '"template_key":"status_changed_staff"' && ok "regula mail-pracownik: recipient=agent, template=status_changed_staff" || bad "zla konfiguracja mail-pracownik ($SCFG)"
STPL=$(wp eval 'echo MP\Automator\MailTemplates::get("status_changed_staff") ? "1":"0";' 2>/dev/null)
[ "$STPL" = "1" ] && ok "szablon status_changed_staff zasiany (nie sierota reguly)" || bad "brak szablonu status_changed_staff"

POOL=$(q "SELECT action_config_json FROM wp_mp_workflow_rules WHERE system_key='default_assign'")
echo "$POOL" | grep -qE '"pool":\[\]' && ok "pula PUSTA (admin/demo wypelnia; do tego czasu ASSIGNMENT_UNMATCHED)" || bad "pula nie pusta ($POOL)"
# notify_agent USUNIETY z konfiguracji: notyfikacja przydzialu = stale zachowanie
# na hooku mp_case_assigned (kazdy przydzial), nie flaga w regule.
echo "$POOL" | grep -q 'notify_agent' && bad "notify_agent wciaz w konfiguracji (martwa flaga)" || ok "brak martwej flagi notify_agent (notyfikacja przez hook)"

MCFG=$(q "SELECT action_config_json FROM wp_mp_workflow_rules WHERE system_key='status_changed_client_mail'")
echo "$MCFG" | grep -q '"recipient":"client"' && ok "regula mailowa: recipient=client, template z config" || bad "zla konfiguracja maila ($MCFG)"

TPL=$(wp eval 'echo MP\Automator\MailTemplates::get("status_changed_client") ? "1":"0";' 2>/dev/null)
[ "$TPL" = "1" ] && ok "szablon status_changed_client zasiany RAZEM z regula (warstwa ii)" || bad "brak szablonu (sierota reguly!)"

# Reguly wiadomosci (message_added) — po author_type
MC=$(q "SELECT CONCAT(trigger_type,'|',condition_key,'|',condition_value,'|',action_type) FROM wp_mp_workflow_rules WHERE system_key='msg_client_to_agent'")
[ "$MC" = "message_added|author_type|client|notify" ] && ok "regula: wiadomosc klienta->agent (message_added/author_type=client)" || bad "zla regula msg-client ($MC)"
MS=$(q "SELECT CONCAT(trigger_type,'|',condition_key,'|',condition_value,'|',action_type) FROM wp_mp_workflow_rules WHERE system_key='msg_staff_to_client'")
[ "$MS" = "message_added|author_type|staff|notify" ] && ok "regula: wiadomosc staff->klient (message_added/author_type=staff)" || bad "zla regula msg-staff ($MS)"

SV=$(q "SELECT option_value FROM wp_options WHERE option_name='mp_automator_seed_version'")
[ "$SV" = "2" ] && ok "mp_automator_seed_version = 2 (bramka siewu; v2 dosiewa mail-pracownik)" || bad "seed_version = $SV"

# ── 2. Skasuj OBIE reguly + reaktywuj -> NIE wracaja (bramka wersji) ──────────
wp db query "DELETE FROM wp_mp_workflow_rules WHERE source='system'" >/dev/null 2>&1
reactivate
N2=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules")
[ "$N2" = "0" ] && ok "skasowane reguly NIE wracaja po reaktywacji (skasowanej nie odtwarzamy)" || bad "regula wrocila ($N2)"

# ── 3. Pelny uninstall (kasuje SEED_VERSION_OPTION) -> reinstalacja sieje swiezo ─
wp option delete mp_automator_seed_version >/dev/null 2>&1
reactivate
N3=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules")
[ "$N3" = "5" ] && ok "po skasowaniu seed_version reinstalacja SIEJE swiezo (5 regul)" || bad "reinstalacja nie zasiala ($N3)"

# ── 4. IDEMPOTENCJA DOSIEWU (upgrade v1->v2): symuluj STARA instalacje (skasuj nowa
#       regule + cofnij wersje do 1) -> dosiew dodaje TYLKO brakujaca, bez duplikatow ─
wp db query "DELETE FROM wp_mp_workflow_rules WHERE system_key='status_changed_staff_mail'" >/dev/null 2>&1
wp option update mp_automator_seed_version 1 >/dev/null 2>&1
reactivate
N4=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules")
[ "$N4" = "5" ] && ok "dosiew v2: dodal brakujaca regule mail-pracownik bez duplikowania (5 regul)" || bad "dosiew zly ($N4)"
DUPS=$(q "SELECT COUNT(*) FROM (SELECT system_key FROM wp_mp_workflow_rules WHERE source='system' GROUP BY system_key HAVING COUNT(*)>1) d")
[ "$DUPS" = "0" ] && ok "ZERO duplikatow system_key po dosiewie (bezpieczny upgrade bez reaktywacji)" || bad "duplikaty regul po dosiewie! ($DUPS)"

echo ""
echo "D-SEED-REGUL: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
