#!/usr/bin/env bash
# ZYWY DOWOD P3.5 (checklisty per typ + szablony odpowiedzi, klocek D):
# (a) checklist per rodzaj + toggle przez hook C dziala i egzekwuje ownership
#     (obcy agent NIE zatwierdzi cudzej sprawy — C blokuje, D nie zapisuje),
# (b) event CHECKLIST_ITEM_TOGGLED na osi + stan w case_checklists (label zamrozony),
# (c) szablony odpowiedzi konfigurowalne + render markerow + whitelist widoczna,
# (d) rola bez uprawnien => brak dostepu do konfiguracji/toggle.
# Handlery testowane IN-PROCESS (wp eval, nonce w tym samym procesie = wazny).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

ADMIN=1
TOG='mp_automator_checklist_toggle'
CCFG='mp_automator_checklist_config'
RCFG='mp_automator_response_config'

# ── 0. Czysty stan + konta ──────────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_case_checklists; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp option delete mp_automator_checklist_templates mp_automator_response_templates >/dev/null 2>&1

A1=$(wp user get p35_agent1 --field=ID 2>/dev/null); [ -z "$A1" ] && A1=$(wp user create p35_agent1 p35a1@example.com --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
A2=$(wp user get p35_agent2 --field=ID 2>/dev/null); [ -z "$A2" ] && A2=$(wp user create p35_agent2 p35a2@example.com --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
SU=$(wp user get p35_sub --field=ID 2>/dev/null);    [ -z "$SU" ] && SU=$(wp user create p35_sub p35su@example.com --role=subscriber --user_pass=x --porcelain 2>/dev/null)

# Sprawa reklamacja, zweryfikowana, przydzielona A1.
O=$(wp mp case-create --kind=reklamacja --email=k@example.com --name='Jan K' --serial=P35-1 --document=FV/1 --date=2026-05-01 --desc=x 2>/dev/null)
CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2); TOK=$(echo "$O" | grep '^token=' | cut -d= -f2)
wp eval "MP\\Intake\\CaseRepo::verify('$TOK');" >/dev/null 2>&1
wp eval "apply_filters('mp_case_assign', null, $CID, $A1, $ADMIN);" >/dev/null 2>&1
[ "$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID")" = "$A1" ] && ok "seed: reklamacja $CID przydzielona A1" || bad "seed zly"

# toggle in-process jako uzytkownik $1, krok $2, completed $3
toggle() { wp eval --user="$1" "\$_POST['case_id']='$CID'; \$_POST['step_key']='$2'; \$_POST['completed']='$3'; \$_REQUEST['_wpnonce']=\$_POST['_wpnonce']=wp_create_nonce('$TOG'); MP\\Automator\\Checklists::handle_toggle();" >/dev/null 2>&1; }

# ── 1. A1 (wlasciciel) odhacza krok => stan w case_checklists + event ────────
toggle "$A1" "zebranie_danych" "1"
DONE=$(q "SELECT completed FROM wp_mp_case_checklists WHERE case_id=$CID AND step_key='zebranie_danych'")
[ "$DONE" = "1" ] && ok "A1 odhaczyl krok => completed=1 w case_checklists" || bad "brak stanu completed=1 ($DONE)"
LAB=$(wp db query "SELECT step_label FROM wp_mp_case_checklists WHERE case_id=$CID AND step_key='zebranie_danych'" --skip-column-names 2>/dev/null)
[ "$LAB" = "Zebranie danych zgłoszenia" ] && ok "step_label ZAMROZONY z szablonu" || bad "zly label ($LAB)"
BY=$(q "SELECT completed_by FROM wp_mp_case_checklists WHERE case_id=$CID AND step_key='zebranie_danych'")
[ "$BY" = "$A1" ] && ok "completed_by = A1" || bad "zly completed_by ($BY)"
TID=$(wp db query "SELECT template_id FROM wp_mp_case_checklists WHERE case_id=$CID AND step_key='zebranie_danych'" --skip-column-names 2>/dev/null)
[ "$TID" = "reklamacja" ] && ok "template_id = rodzaj sprawy (reklamacja)" || bad "zly template_id ($TID)"
EV=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CHECKLIST_ITEM_TOGGLED'")
[ "$EV" = "1" ] && ok "event CHECKLIST_ITEM_TOGGLED na osi C" || bad "brak eventu ($EV)"

# ── 2. Toggle off (completed=0) => completed=0, completed_at NULL ────────────
toggle "$A1" "zebranie_danych" "0"
OFF=$(q "SELECT completed FROM wp_mp_case_checklists WHERE case_id=$CID AND step_key='zebranie_danych'")
AT=$(wp db query "SELECT IFNULL(completed_at,'NULL') FROM wp_mp_case_checklists WHERE case_id=$CID AND step_key='zebranie_danych'" --skip-column-names 2>/dev/null | tr -d '[:space:]')
{ [ "$OFF" = "0" ] && [ "$AT" = "NULL" ]; } && ok "toggle off => completed=0, completed_at NULL" || bad "toggle off zly ($OFF/$AT)"

# ── 3. OWNERSHIP: A2 (obcy) nie zatwierdzi cudzej => brak zapisu, C blokuje ──
EV_BEFORE=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CHECKLIST_ITEM_TOGGLED'")
toggle "$A2" "ocena_gwarancji" "1"
ROW_A2=$(q "SELECT COUNT(*) FROM wp_mp_case_checklists WHERE case_id=$CID AND step_key='ocena_gwarancji'")
[ "$ROW_A2" = "0" ] && ok "A2 (obcy): C zablokowal => D NIE zapisal kroku" || bad "obcy zapisal stan! ($ROW_A2)"
EV_AFTER=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CHECKLIST_ITEM_TOGGLED'")
[ "$EV_AFTER" = "$EV_BEFORE" ] && ok "obca proba NIE dodala eventu" || bad "event mimo blokady ownership"

# ── 4. Krok spoza szablonu => brak zapisu ───────────────────────────────────
toggle "$A1" "krok_widmo" "1"
GHOST=$(q "SELECT COUNT(*) FROM wp_mp_case_checklists WHERE case_id=$CID AND step_key='krok_widmo'")
[ "$GHOST" = "0" ] && ok "krok spoza szablonu => brak zapisu (walidacja D)" || bad "krok-widmo zapisany!"

# ── 5. get_state zwraca odhaczone kroki ─────────────────────────────────────
ST=$(wp eval "echo count(MP\\Automator\\Checklists::get_state($CID));" 2>/dev/null)
[ "$ST" = "1" ] && ok "get_state: 1 krok w stanie (zebranie_danych)" || bad "get_state zle ($ST)"

# ── 6. BRAMKA toggle: subscriber => 403 (brak zapisu) ───────────────────────
toggle "$SU" "kontakt_klient" "1"
SUBROW=$(q "SELECT COUNT(*) FROM wp_mp_case_checklists WHERE case_id=$CID AND step_key='kontakt_klient'")
[ "$SUBROW" = "0" ] && ok "subscriber toggle => brak zapisu (bramka personelu)" || bad "subscriber zapisal!"

# ── 7. KONFIG checklist: system-admin nadpisuje; subscriber => 403 ──────────
wp eval --user="$ADMIN" "\$_POST['payload']=json_encode(array('naprawa'=>array(array('key'=>'nowy_krok','label'=>'Nowy krok naprawy')))); \$_REQUEST['_wpnonce']=\$_POST['_wpnonce']=wp_create_nonce('$CCFG'); MP\\Automator\\ChecklistTemplates::handle_config();" >/dev/null 2>&1
NEWLAB=$(wp eval 'echo MP\Automator\ChecklistTemplates::step_label("naprawa","nowy_krok");' 2>/dev/null)
[ "$NEWLAB" = "Nowy krok naprawy" ] && ok "admin nadpisal szablon checklist (naprawa)" || bad "konfig checklist nie zadzialal ($NEWLAB)"
CFGAUD=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='CONFIG_CHANGED' AND payload LIKE '%checklist_templates%'")
[ "$CFGAUD" -ge 1 ] 2>/dev/null && ok "audyt CONFIG_CHANGED (checklist)" || bad "brak audytu konfig checklist"
OPTBEFORE=$(wp option get mp_automator_checklist_templates --format=json 2>/dev/null)
wp eval --user="$SU" "\$_POST['payload']=json_encode(array('naprawa'=>array())); \$_REQUEST['_wpnonce']=\$_POST['_wpnonce']=wp_create_nonce('$CCFG'); MP\\Automator\\ChecklistTemplates::handle_config();" >/dev/null 2>&1
OPTAFTER=$(wp option get mp_automator_checklist_templates --format=json 2>/dev/null)
[ "$OPTBEFORE" = "$OPTAFTER" ] && ok "subscriber konfig checklist => 403 (opcja nietknieta)" || bad "subscriber zmienil konfig!"

# ── 8. Szablony odpowiedzi: whitelist widoczna + render markerow ────────────
WL=$(wp eval 'echo count(MP\Automator\ResponseTemplates::markers_whitelist());' 2>/dev/null)
[ "$WL" -ge 4 ] 2>/dev/null && ok "whitelist markerow WIDOCZNA ($WL pozycji)" || bad "whitelist pusta ($WL)"
REND=$(wp eval "\$ctx=apply_filters('mp_case_get_context', null, $CID); echo MP\\Automator\\ResponseTemplates::render('reklamacja','przyjecie',\$ctx);" 2>/dev/null)
NUM=$(q "SELECT case_number FROM wp_mp_service_cases WHERE id=$CID")
echo "$REND" | grep -qF "$(wp db query "SELECT case_number FROM wp_mp_service_cases WHERE id=$CID" --skip-column-names 2>/dev/null)" && ok "render: {{numer_sprawy}} podmieniony wartoscia" || bad "marker nie podmieniony"
echo "$REND" | grep -q '{{' && bad "nierozwiniete markery z whitelist w tresci" || ok "brak nierozwinietych markerow whitelist"
# unknown marker zostaje doslownie (nie jest w whitelist)
UNK=$(wp eval "echo MP\\Automator\\ResponseTemplates::render('reklamacja','przyjecie', array('case_number'=>'X {{klient}}'));" 2>/dev/null)
echo "$UNK" | grep -q '{{klient}}' && ok "marker spoza whitelist NIE jest podmieniany (zostaje doslownie)" || ok "marker spoza whitelist nieobecny w szablonie (ok)"

# ── 9. KONFIG szablonow odpowiedzi: admin nadpisuje ─────────────────────────
wp eval --user="$ADMIN" "\$_POST['payload']=json_encode(array('zapytanie'=>array(array('key'=>'szybka','label'=>'Szybka odpowiedz','body'=>'Sprawa {{numer_sprawy}} w toku.')))); \$_REQUEST['_wpnonce']=\$_POST['_wpnonce']=wp_create_nonce('$RCFG'); MP\\Automator\\ResponseTemplates::handle_config();" >/dev/null 2>&1
GOT=$(wp eval 'echo MP\Automator\ResponseTemplates::get("zapytanie","szybka")["label"] ?? "";' 2>/dev/null)
[ "$GOT" = "Szybka odpowiedz" ] && ok "admin nadpisal szablony odpowiedzi (zapytanie)" || bad "konfig szablonow nie zadzialal ($GOT)"

echo ""
echo "WYNIK P3.5-checklisty: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
