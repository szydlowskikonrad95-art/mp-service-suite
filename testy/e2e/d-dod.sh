#!/usr/bin/env bash
# DoD D — twardy audyt gotowosci automatora (3 sekcje). Prefix-agnostic (wp db prefix)
# => chodzi na e2e-import (wp_) I na dirty-env (cms_x9_ + object-cache + WP_DEBUG).
# (1) UNINSTALL ZERO-SLADU: opt-in delete_data kasuje WSZYSTKIE artefakty D (tabele+
#     opcje+cron+marker) i NIC cudzego — kanarki (obca opcja/tabela/cron) + rodzenstwo
#     C/B + wspoldzielone role NIETKNIETE. Symetria: 0 sladu mp_automator_* po uninstall.
# (2) DEGRADED: automator NIE fataluje gdy C/B WYLACZONE (hooki nieobecne => graceful).
# (3) MACIERZ NEGATYWNA: mp_agent (pracownik bez uprawnien) + anon => brak dostepu do
#     endpointow admin_post D; zablokowana proba NIE loguje audytu ani nie mutuje.
#     (HTTP 403 anon/subscriber/mp_client: c-dod-security-matrix.sh.)
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

PFX=$(wp db prefix 2>/dev/null); PFX=${PFX:-wp_}
OPT="${PFX}options"

# WP_DEBUG zero-notice: baseline logu (istotne na dirty-env; w env bez debug => pomijane).
LOG=$(wp eval 'echo (defined("WP_DEBUG_LOG") && WP_DEBUG_LOG) ? (is_string(WP_DEBUG_LOG) ? WP_DEBUG_LOG : WP_CONTENT_DIR."/debug.log") : "";' 2>/dev/null)
LOG0=0; [ -n "$LOG" ] && [ -f "$LOG" ] && LOG0=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')

echo "== SEKCJA 1: UNINSTALL ZERO-SLADU (symetria + kanarki), prefiks=$PFX =="

# Upewnij sie ze D aktywny + ma DANE (opcje P3.5 + wiersze w tabelach D).
wp plugin activate mp-service-intake mp-warranty-registry mp-workflow-automator >/dev/null 2>&1
wp eval "update_option('mp_automator_checklist_templates', array('reklamacja'=>array(array('key'=>'x','label'=>'X')))); update_option('mp_automator_response_templates', array('reklamacja'=>array(array('key'=>'x','label'=>'X','body'=>'B'))));" >/dev/null 2>&1
wp eval "MP\\Automator\\WorkflowEvents::log(MP\\Automator\\WorkflowEvents::EXPORT_GENERATED, array('rows'=>0), null, 1);" >/dev/null 2>&1
OPTBEF=$(q "SELECT COUNT(*) FROM $OPT WHERE option_name LIKE 'mp_automator_%'")
[ "${OPTBEF:-0}" -ge 5 ] 2>/dev/null && ok "przed: opcje mp_automator_* istnieja ($OPTBEF, w tym P3.5)" || bad "brak opcji D przed uninstall ($OPTBEF)"

# KANARKI (obce — muszą przezyc uninstall D).
wp eval "add_option('zzz_canary_opt','canary123'); wp_schedule_single_event(time()+99999,'zzz_canary_cron');" >/dev/null 2>&1
wp db query "CREATE TABLE IF NOT EXISTS ${PFX}zzz_canary (id INT)" >/dev/null 2>&1
CANOPT0=$(q "SELECT COUNT(*) FROM $OPT WHERE option_name='zzz_canary_opt'")
CANTAB0=$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='${PFX}zzz_canary'")
CANCRON0=$(wp eval "echo wp_next_scheduled('zzz_canary_cron') ? '1':'0';" 2>/dev/null)
# Rodzenstwo C (musi przezyc — nic cudzego).
SIBTAB0=$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='${PFX}mp_service_cases'")
SIBOPT0=$(q "SELECT COUNT(*) FROM $OPT WHERE option_name='mp_intake_schema_version'")

# OPT-IN + uninstall TYLKO automatora (C/B zostaja => role wspoldzielone NIE znikaja).
wp option update mp_automator_delete_data 1 >/dev/null 2>&1
wp plugin uninstall mp-workflow-automator --deactivate --skip-delete >/dev/null 2>&1 \
	&& ok "uninstall automatora bez fatala" || bad "uninstall automatora pad"

# --- D ZNIKNELO ---
DTAB=$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name IN ('${PFX}mp_workflow_rules','${PFX}mp_case_sla','${PFX}mp_case_checklists','${PFX}mp_workflow_events')")
[ "${DTAB:-9}" = "0" ] && ok "wszystkie 4 tabele D skasowane" || bad "zostalo $DTAB tabel D"
DOPT=$(q "SELECT COUNT(*) FROM $OPT WHERE option_name LIKE 'mp_automator_%'")
[ "${DOPT:-9}" = "0" ] && ok "ZERO SLADU: brak opcji mp_automator_* (w tym P3.5 checklist/response)" || bad "zostalo $DOPT opcji D"
MARK=$(q "SELECT COUNT(*) FROM $OPT WHERE option_name='mp_module_automator'")
[ "${MARK:-9}" = "0" ] && ok "marker modulu mp_module_automator skasowany" || bad "marker D zostal"
DCRON=$(wp eval "echo wp_next_scheduled('mp_automator_sla_sweep') ? '1':'0';" 2>/dev/null)
[ "$DCRON" = "0" ] && ok "cron mp_automator_sla_sweep wyczyszczony" || bad "cron D zostal"

# --- KANARKI NIETKNIETE ---
CANOPT1=$(q "SELECT COUNT(*) FROM $OPT WHERE option_name='zzz_canary_opt'")
CANTAB1=$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='${PFX}zzz_canary'")
CANCRON1=$(wp eval "echo wp_next_scheduled('zzz_canary_cron') ? '1':'0';" 2>/dev/null)
{ [ "$CANOPT1" = "1" ] && [ "$CANTAB1" = "1" ] && [ "$CANCRON1" = "1" ]; } && ok "kanarki NIETKNIETE (obca opcja+tabela+cron)" || bad "uninstall ruszyl kanarki (opt=$CANOPT1 tab=$CANTAB1 cron=$CANCRON1)"

# --- RODZENSTWO C + wspoldzielone role NIETKNIETE ---
SIBTAB1=$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='${PFX}mp_service_cases'")
SIBOPT1=$(q "SELECT COUNT(*) FROM $OPT WHERE option_name='mp_intake_schema_version'")
{ [ "$SIBTAB1" = "$SIBTAB0" ] && [ "$SIBTAB1" = "1" ] && [ "$SIBOPT1" = "$SIBOPT0" ]; } && ok "rodzenstwo C (tabela+opcja) NIETKNIETE" || bad "uninstall D ruszyl artefakty C!"
ROLES=$(wp eval "echo (null!==get_role('mp_agent') && null!==get_role('mp_coordinator')) ? 'ZYJA':'ZNIKNELY';" 2>/dev/null)
[ "$ROLES" = "ZYJA" ] && ok "role wspoldzielone ZYJA (C/B aktywne => nie ostatni modul)" || bad "role wspoldzielone zdjete mimo aktywnych C/B!"
ADMCAP=$(wp eval "echo get_role('administrator')->has_cap('mp_system_admin') ? 'MA':'BRAK';" 2>/dev/null)
[ "$ADMCAP" = "MA" ] && ok "administrator dalej ma caps personelu (C/B zyja)" || bad "caps zdjete mimo aktywnych C/B"

# Przywroc poligon + posprzataj kanarki.
wp plugin activate mp-workflow-automator >/dev/null 2>&1
wp eval "delete_option('zzz_canary_opt'); wp_clear_scheduled_hook('zzz_canary_cron'); update_option('mp_automator_delete_data','0');" >/dev/null 2>&1
wp db query "DROP TABLE IF EXISTS ${PFX}zzz_canary" >/dev/null 2>&1
REBORN=$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='${PFX}mp_workflow_rules'")
[ "$REBORN" = "1" ] && ok "reaktywacja odtworzyla schemat D (poligon czysty)" || bad "reaktywacja nie odtworzyla tabel D"

echo "== SEKCJA 2: DEGRADED (C/B OFF => automator zyje, graceful) =="
# Wylacz C (intake) — hooki mp_case_* znikaja.
wp plugin deactivate mp-service-intake >/dev/null 2>&1
ALIVE=$(wp eval "echo 'alive';" 2>&1)
echo "$ALIVE" | grep -qiE "fatal|parse error" && bad "automator FATAL bez C: $ALIVE" || ok "automator zyje bez C (brak fatala)"
# get_context bez C => null (hook nieobecny), warunek nie-pasuje nie blad.
CTX=$(wp eval "\$c=apply_filters('mp_case_get_context', null, 1); echo null===\$c ? 'NULL':'INNE';" 2>/dev/null)
[ "$CTX" = "NULL" ] && ok "mp_case_get_context bez C => null (graceful)" || bad "context bez C nie null ($CTX)"
# sweep bez C nie crashuje.
SW=$(wp eval "do_action('mp_automator_sla_sweep'); echo 'swept';" 2>&1)
echo "$SW" | grep -q 'swept' && ! echo "$SW" | grep -qiE "fatal|parse error" && ok "sweep SLA bez C — brak crasha" || bad "sweep bez C crashnal: $SW"
# checklist toggle bez C => hook autoryzacji nieobecny => graceful fail (brak zapisu, brak fatala).
TOGG=$(wp eval --user=1 "\$_POST['case_id']='1'; \$_POST['step_key']='zebranie_danych'; \$_POST['completed']='1'; \$_REQUEST['_wpnonce']=\$_POST['_wpnonce']=wp_create_nonce('mp_automator_checklist_toggle'); MP\\Automator\\Checklists::handle_toggle();" 2>&1)
echo "$TOGG" | grep -qiE "fatal|parse error" && bad "toggle bez C FATAL: $TOGG" || ok "checklist toggle bez C — graceful (brak fatala)"
# Wylacz tez B — dalej zyje.
wp plugin deactivate mp-warranty-registry >/dev/null 2>&1
ALIVE2=$(wp eval "echo 'alive2';" 2>&1)
echo "$ALIVE2" | grep -q 'alive2' && ! echo "$ALIVE2" | grep -qiE "fatal|parse error" && ok "automator zyje bez C i B" || bad "automator padl bez C+B: $ALIVE2"
wp plugin activate mp-service-intake mp-warranty-registry >/dev/null 2>&1

echo "== SEKCJA 3: MACIERZ NEGATYWNA (mp_agent + anon => brak dostepu, zero mutacji/audytu) =="
# Konta + sprawa (dla toggle-ownership).
AG=$(wp user get dod_agent --field=ID 2>/dev/null); [ -z "$AG" ] && AG=$(wp user create dod_agent dod_ag@example.com --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
wp db query "DELETE FROM ${PFX}mp_workflow_events WHERE event_type IN ('SLA_RECALCULATED','EXPORT_GENERATED');" >/dev/null 2>&1

# recalc_sla (cap sysadmin): mp_agent => 403, brak audytu SLA_RECALCULATED.
wp eval --user="$AG" "\$_REQUEST['_wpnonce']=\$_POST['_wpnonce']=wp_create_nonce('mp_automator_recalc_sla'); MP\\Automator\\Admin\\SlaRecalcAction::handle();" >/dev/null 2>&1
RC=$(q "SELECT COUNT(*) FROM ${PFX}mp_workflow_events WHERE event_type='SLA_RECALCULATED'")
[ "${RC:-9}" = "0" ] && ok "recalc_sla: mp_agent zablokowany (brak audytu SLA_RECALCULATED)" || bad "recalc_sla: agent przeszedl! ($RC)"

# export_csv (cap koord/sysadmin): mp_agent => 403, brak audytu EXPORT_GENERATED.
OUT=$(wp eval --user="$AG" "\$_REQUEST['_wpnonce']=\$_POST['_wpnonce']=wp_create_nonce('mp_automator_export_csv'); MP\\Automator\\CsvExport::handle();" 2>/dev/null)
EC=$(q "SELECT COUNT(*) FROM ${PFX}mp_workflow_events WHERE event_type='EXPORT_GENERATED'")
{ ! echo "$OUT" | grep -q "Nr sprawy" && [ "${EC:-9}" = "0" ]; } && ok "export_csv: mp_agent zablokowany (brak CSV, brak audytu)" || bad "export_csv: agent dostal dane/audyt! (EC=$EC)"

# checklist_config (cap sysadmin): mp_agent => 403, opcja nietknieta.
CFGB=$(wp option get mp_automator_checklist_templates --format=json 2>/dev/null)
wp eval --user="$AG" "\$_POST['payload']=json_encode(array('naprawa'=>array(array('key'=>'hack','label'=>'H')))); \$_REQUEST['_wpnonce']=\$_POST['_wpnonce']=wp_create_nonce('mp_automator_checklist_config'); MP\\Automator\\ChecklistTemplates::handle_config();" >/dev/null 2>&1
CFGA=$(wp option get mp_automator_checklist_templates --format=json 2>/dev/null)
[ "$CFGB" = "$CFGA" ] && ok "checklist_config: mp_agent zablokowany (opcja nietknieta)" || bad "checklist_config: agent zmienil konfig!"

# response_config (cap sysadmin): mp_agent => 403, opcja nietknieta.
RCFGB=$(wp option get mp_automator_response_templates --format=json 2>/dev/null)
wp eval --user="$AG" "\$_POST['payload']=json_encode(array('naprawa'=>array(array('key'=>'hack','label'=>'H','body'=>'B')))); \$_REQUEST['_wpnonce']=\$_POST['_wpnonce']=wp_create_nonce('mp_automator_response_config'); MP\\Automator\\ResponseTemplates::handle_config();" >/dev/null 2>&1
RCFGA=$(wp option get mp_automator_response_templates --format=json 2>/dev/null)
[ "$RCFGB" = "$RCFGA" ] && ok "response_config: mp_agent zablokowany (opcja nietknieta)" || bad "response_config: agent zmienil konfig!"

# checklist_toggle: mp_agent NIE-wlasciciel => C blokuje (ownership) => brak zapisu.
O=$(wp mp case-create --kind=reklamacja --email=d@example.com --name='D' --serial=DOD-1 --document=FV/1 --date=2026-05-01 --desc=x 2>/dev/null)
CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2); TOK=$(echo "$O" | grep '^token=' | cut -d= -f2)
wp eval "MP\\Intake\\CaseRepo::verify('$TOK');" >/dev/null 2>&1
# NIE przydzielamy sprawy agentowi => nie jest wlascicielem.
wp eval --user="$AG" "\$_POST['case_id']='$CID'; \$_POST['step_key']='zebranie_danych'; \$_POST['completed']='1'; \$_REQUEST['_wpnonce']=\$_POST['_wpnonce']=wp_create_nonce('mp_automator_checklist_toggle'); MP\\Automator\\Checklists::handle_toggle();" >/dev/null 2>&1
TW=$(q "SELECT COUNT(*) FROM ${PFX}mp_case_checklists WHERE case_id=$CID")
[ "${TW:-9}" = "0" ] && ok "checklist_toggle: mp_agent NIE-wlasciciel => C blokuje => brak zapisu" || bad "toggle: nie-wlasciciel zapisal! ($TW)"

# anon (user 0) na endpointach z nopriv => brak mutacji.
OUT2=$(wp eval "\$_REQUEST['_wpnonce']=\$_POST['_wpnonce']=wp_create_nonce('mp_automator_export_csv'); MP\\Automator\\CsvExport::handle();" 2>/dev/null)
echo "$OUT2" | grep -q "Nr sprawy" && bad "export_csv anon: WYCIEKL CSV!" || ok "export_csv anon => brak eksportu"

# WP_DEBUG zero-notice: brak nowych Fatal/Warning/Notice/Deprecated Z KODU D w logu.
if [ -n "$LOG" ] && [ -f "$LOG" ]; then
	NEW=$(tail -n "+$((LOG0+1))" "$LOG" 2>/dev/null | grep -iE "Fatal|Warning|Notice|Deprecated" | grep -iE "mp-workflow-automator|MP\\\\Automator" | head -3)
	[ -z "$NEW" ] && ok "WP_DEBUG zero-notice: brak notice/fatal z kodu D podczas audytu" || bad "notice/fatal z D w logu: $NEW"
else
	echo "  SKIP WP_DEBUG log niedostepny (env bez debug) — zero-notice sprawdzane na dirty-env"
fi

echo ""
echo "WYNIK DoD D: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
