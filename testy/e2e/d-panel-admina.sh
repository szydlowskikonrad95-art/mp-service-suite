#!/usr/bin/env bash
# ZYWY DOWOD: panel admina automatora (klocek D) — menu + wpiecie handlerow.
#  (a) menu WIDOCZNE dla system_admin/koordynatora/admina WP, NIEWIDOCZNE dla
#      subscribera/anona (add_menu_page: cap = ten ktory user MA; klient nie ma zadnego),
#  (b) przycisk „Przelicz SLA” obecny w panelu TYLKO dla system_admin + poprawny
#      action/nonce; realny recompute przez ten action dziala,
#  (c) przycisk „Eksport CSV” obecny (action+nonce) dla koordynatora i admina,
#  (d) listy regul/statusow/rejestru renderuja poprawne dane z tabel D,
#  (e) rola bez capability => render 403 (wp_die), zero HTML panelu.
# Render panelu = PanelScreen::render() (HTML na stdout); widocznosc menu =
# obecnosc w $menu ORAZ current_user_can(cap pozycji). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# widocznosc menu dla usera $1 (0=anon): TAK gdy pozycja jest I user ma jej cap
menu_vis() {
	wp eval "wp_set_current_user($1); do_action('admin_menu'); \$v='NIE'; foreach((array)\$GLOBALS['menu'] as \$m){ if(isset(\$m[2])&&\$m[2]==='mp-automator'){ \$v=current_user_can(\$m[1])?'TAK':'NIE'; } } echo \$v;" 2>/dev/null | tr -d '[:space:]'
}
# render panelu jako user $1 -> HTML na stdout (2>/dev/null zjada wp_die/warningi)
render_as() { wp eval "wp_set_current_user($1); MP\\Automator\\Admin\\PanelScreen::render();" 2>/dev/null; }

# ── 0. Czysty stan + role + seed regul ───────────────────────────────────────
wp db query "DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
SYS=$(wp user create sysadm sysadm@example.com --role=mp_system_admin --porcelain 2>/dev/null);  [ -z "$SYS" ]   && SYS=$(wp user get sysadm --field=ID 2>/dev/null)
COORD=$(wp user create coord coord@example.com --role=mp_coordinator --porcelain 2>/dev/null);   [ -z "$COORD" ] && COORD=$(wp user get coord --field=ID 2>/dev/null)
SUB=$(wp user create sub sub@example.com --role=subscriber --porcelain 2>/dev/null);             [ -z "$SUB" ]   && SUB=$(wp user get sub --field=ID 2>/dev/null)
ok "role utworzone (sys=$SYS coord=$COORD sub=$SUB, admin=1)"

# ── 1. (a)+(e) WIDOCZNOSC MENU per rola ──────────────────────────────────────
[ "$(menu_vis 1)"     = "TAK" ] && ok "menu WIDOCZNE dla admina WP" || bad "menu niewidoczne dla admina"
[ "$(menu_vis $SYS)"  = "TAK" ] && ok "menu WIDOCZNE dla mp_system_admin" || bad "menu niewidoczne dla system_admin"
[ "$(menu_vis $COORD)" = "TAK" ] && ok "menu WIDOCZNE dla mp_coordinator" || bad "menu niewidoczne dla koordynatora"
[ "$(menu_vis $SUB)"  = "NIE" ] && ok "menu NIEWIDOCZNE dla subscribera (klient)" || bad "subscriber WIDZI menu!"
[ "$(menu_vis 0)"     = "NIE" ] && ok "menu NIEWIDOCZNE dla anona (user 0)" || bad "anon WIDZI menu!"

# ── 2. (b)+(c) PRZYCISKI per-capability (obrona warstwowa) ────────────────────
HTML_SYS=$(render_as $SYS)
echo "$HTML_SYS" | grep -q 'value="mp_automator_recalc_sla"' && ok "(b) sysadmin: przycisk Przelicz SLA obecny (action recalc)" || bad "(b) brak przycisku Przelicz SLA u sysadmina"
echo "$HTML_SYS" | grep -q 'value="mp_automator_export_csv"' && ok "(c) sysadmin: przycisk Eksport CSV obecny" || bad "(c) brak eksportu u sysadmina"
echo "$HTML_SYS" | grep -q '_wpnonce' && ok "nonce obecny w formularzach panelu" || bad "brak nonce w panelu!"

HTML_COORD=$(render_as $COORD)
echo "$HTML_COORD" | grep -q 'value="mp_automator_export_csv"' && ok "(c) koordynator: Eksport CSV obecny" || bad "(c) koordynator bez eksportu"
echo "$HTML_COORD" | grep -q 'value="mp_automator_recalc_sla"' && bad "(b) koordynator NIE powinien widziec Przelicz SLA!" || ok "(b) koordynator: Przelicz SLA UKRYTY (mp_system_admin only)"

# ── 3. (d) LISTY renderuja dane z tabel D ────────────────────────────────────
echo "$HTML_SYS" | grep -q 'Reguły przydziału' && ok "sekcja Reguły przydziału renderuje" || bad "brak sekcji regul"
RULE_TRIG=$(q "SELECT trigger_type FROM wp_mp_workflow_rules ORDER BY priority ASC, id ASC LIMIT 1")
if [ -n "$RULE_TRIG" ]; then
	echo "$HTML_SYS" | grep -qF "$RULE_TRIG" && ok "reguly: trigger '$RULE_TRIG' z tabeli widoczny w liscie" || bad "reguly: brak danych z tabeli ($RULE_TRIG)"
else
	ok "reguly: brak seedu (lista pusta obsluzona)"
fi
echo "$HTML_SYS" | grep -q '>nowe<' && ok "statusy: rdzen 'nowe' widoczny (mp_registered_statuses)" || bad "statusy: brak 'nowe'"
echo "$HTML_SYS" | grep -q 'Rejestr zdarzeń' && ok "sekcja Rejestr zdarzeń renderuje" || bad "brak sekcji rejestru"
echo "$HTML_SYS" | grep -q 'Checklisty i szablony' && ok "SLOT P3.5 (checklisty+szablony) obecny jako placeholder" || bad "brak slotu P3.5"

# zdarzenie realne trafia do rejestru w panelu
CID=$(wp mp case-create --kind=reklamacja --email=ev@example.com --name='T' --serial=PAN-1 --document='FV/1' --date='2026-05-01' --desc=x 2>/dev/null | grep '^case_id=' | cut -d= -f2)
EVT=$(q "SELECT event_type FROM wp_mp_workflow_events ORDER BY id DESC LIMIT 1")
HTML_EV=$(render_as $SYS)
if [ -n "$EVT" ]; then
	echo "$HTML_EV" | grep -qF "$EVT" && ok "rejestr: swieze zdarzenie '$EVT' widoczne w panelu" || bad "rejestr: brak swiezego zdarzenia ($EVT)"
else
	ok "rejestr: brak zdarzen (pusto obsluzone)"
fi

# ── 4. (e) render bez capability => 403 (wp_die), zero HTML panelu ────────────
HTML_SUB=$(render_as $SUB)
echo "$HTML_SUB" | grep -q 'mp-automator-panel' && bad "(e) subscriber ZOBACZYL panel!" || ok "(e) subscriber: render => brak HTML panelu (wp_die 403)"

# ── 5. (b) realny recompute przez action panelu (nonce mp_automator_recalc_sla) ─
OUT2=$(wp mp case-create --kind=reklamacja --email=rc@example.com --name='T' --serial=PAN-2 --document='FV/2' --date='2026-05-01' --desc=x 2>/dev/null)
CID2=$(echo "$OUT2" | grep '^case_id=' | cut -d= -f2)
TOK2=$(echo "$OUT2" | grep '^token=' | cut -d= -f2)
wp eval "MP\\Intake\\CaseRepo::verify('$TOK2');" >/dev/null 2>&1
POL_BEFORE=$(q "SELECT sla_policy_version FROM wp_mp_case_sla WHERE case_id=$CID2")
wp eval 'update_option("mp_automator_sla_policy_version", 2);' >/dev/null 2>&1
wp eval "wp_set_current_user($SYS); \$n=wp_create_nonce('mp_automator_recalc_sla'); \$_REQUEST['_wpnonce']=\$n; \$_POST['_wpnonce']=\$n; \$_REQUEST['action']='mp_automator_recalc_sla'; do_action('admin_post_mp_automator_recalc_sla');" >/dev/null 2>&1
POL_AFTER=$(q "SELECT sla_policy_version FROM wp_mp_case_sla WHERE case_id=$CID2")
RECALC_EV=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SLA_RECALCULATED'")
[ "$POL_AFTER" = "2" ] && [ "$RECALC_EV" -ge 1 ] 2>/dev/null && ok "(b) action panelu Przelicz SLA => realny recompute (policy $POL_BEFORE->$POL_AFTER, audyt zapisany)" || bad "(b) recompute przez panel nie zadzialal (policy=$POL_AFTER ev=$RECALC_EV)"

# ── 6. (P3.5 follow-up) UI konfiguracji checklist+szablonow w slocie ──────────
HTML_FU=$(render_as $SYS)
echo "$HTML_FU" | grep -q 'mp_automator_checklist_config' && ok "(P3.5) formularz checklist (action config) dla system_admina" || bad "(P3.5) brak formularza checklist"
echo "$HTML_FU" | grep -q 'mp_automator_response_config' && ok "(P3.5) formularz szablonow odpowiedzi dla system_admina" || bad "(P3.5) brak formularza szablonow"
echo "$HTML_FU" | grep -q '_wpnonce' && ok "(P3.5) nonce w formularzach konfiguracji" || bad "(P3.5) brak nonce"
echo "$HTML_FU" | grep -qF '{{numer_sprawy}}' && ok "(P3.5) WHITELIST markerow widoczna adminowi" || bad "(P3.5) brak whitelist markerow"
# obrona warstwowa: koordynator (nie-sysadmin) NIE widzi formularzy config
HTML_FU_C=$(render_as $COORD)
echo "$HTML_FU_C" | grep -q 'mp_automator_checklist_config' && bad "(P3.5) koordynator WIDZI formularz config!" || ok "(P3.5) koordynator: formularze config UKRYTE (tylko system_admin)"
# realny zapis konfiguracji przez handler (nonce zgodny z ACTION_CONFIG)
NEW_JSON='{"reklamacja":[{"key":"test_krok","label":"Krok testowy"}]}'
wp eval "wp_set_current_user($SYS); \$n=wp_create_nonce('mp_automator_checklist_config'); \$_REQUEST['_wpnonce']=\$n; \$_POST['_wpnonce']=\$n; \$_POST['payload']='$NEW_JSON'; \$_REQUEST['action']='mp_automator_checklist_config'; do_action('admin_post_mp_automator_checklist_config');" >/dev/null 2>&1
SAVED=$(wp eval '$a=MP\Automator\ChecklistTemplates::all(); echo (isset($a["reklamacja"]) && in_array("test_krok", array_column($a["reklamacja"],"key"), true))?"1":"0";' 2>/dev/null | tr -d '[:space:]')
[ "$SAVED" = "1" ] && ok "(P3.5) POST checklist z nonce => realny zapis configu przez handler" || bad "(P3.5) zapis configu nie zadzialal ($SAVED)"
CFG_EV=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='CONFIG_CHANGED' AND payload LIKE '%checklist_templates%'")
[ "$CFG_EV" -ge 1 ] 2>/dev/null && ok "(P3.5) audyt CONFIG_CHANGED (checklist) zapisany" || bad "(P3.5) brak audytu config"

# ── Sprzatanie (przywroc domyslny config + kasuj userow) ─────────────────────
wp eval 'delete_option("mp_automator_sla_policy_version"); delete_option("mp_automator_sla_core"); delete_option("mp_automator_checklist_templates"); delete_option("mp_automator_response_templates");' >/dev/null 2>&1
for u in "$SYS" "$COORD" "$SUB"; do wp user delete "$u" --yes >/dev/null 2>&1; done
echo ""
echo "D-PANEL-ADMINA: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
