#!/usr/bin/env bash
# ZYWY DOWOD (karta sprawy — AKCJE personelu): handlery admin-post CaseActions z
# BRAMKA capability + nonce (kartka krok 7 „kazda decyzja zapisuje sie w historii").
# Macierz uprawnien/nonce:
#  - mp_intake_case_status: staff (agent/koord/admin) zmienia status; optimistic-lock
#    (STATUS_CONFLICT przy nieaktualnym expected); NIE-staff=403 bez zmiany; zly nonce=bez zmiany.
#  - mp_intake_case_reply: staff dodaje wiadomosc 'staff'; pusta tresc=bez wpisu; NIE-staff=403.
#  - mp_intake_case_assign: TYLKO koordynator/admin; PRACOWNIK (mp_agent) 403 bez przydzialu
#    (rola/ownership); zly nonce=bez zmiany. Kazda udana akcja => wpis na osi (case_events).
# Handler konczy redirect/wp_die => eval sie urywa; asercje sprawdzaja SKUTEK w bazie. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ── 0. Czysty stan + uzytkownicy 3 rol (idempotentnie) ───────────────────────
wp db query "DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_case_checklists; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_workflow_rules;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

SUB=$(wp user get subq --field=ID 2>/dev/null);   [ -z "$SUB" ]   && SUB=$(wp user create subq subq@example.com --role=subscriber --user_pass=x --porcelain 2>/dev/null)
AGENT=$(wp user get agentq --field=ID 2>/dev/null); [ -z "$AGENT" ] && AGENT=$(wp user create agentq agentq@example.com --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
COORD=$(wp user get koordq --field=ID 2>/dev/null); [ -z "$COORD" ] && COORD=$(wp user create koordq koordq@example.com --role=mp_coordinator --user_pass=x --porcelain 2>/dev/null)

mk() { # $1=email $2=serial
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='Jan Kowalski' --serial="$2" --document='FV/2026/9' --date='2026-05-01' --desc='opis' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\\Intake\\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# Handlery admin-post wolane BEZPOSREDNIO (rejestracja hooka jest za is_admin(),
# ktore w wp-cli=false; admin-post.php wo+la te same metody). User + nonce w TYM
# SAMYM evalu (nonce per-user). Wzorzec jak d-p36-eksport (CsvExport::handle()).
do_status() { # $1=uid $2=case $3=new $4=expected $5=reason $6=nonce(valid|bad)
	wp eval "wp_set_current_user($1); \$n=('bad'==='$6')?'zly':wp_create_nonce('mp_intake_case_status'); \$_POST['_wpnonce']=\$n; \$_REQUEST['_wpnonce']=\$n; \$_POST['case_id']='$2'; \$_POST['new_status']='$3'; \$_POST['expected_status']='$4'; \$_POST['rejection_reason_code']='$5'; MP\\Intake\\Admin\\CaseActions::handle_status();" >/dev/null 2>&1
}
do_reply() { # $1=uid $2=case $3=body $4=nonce
	wp eval "wp_set_current_user($1); \$n=('bad'==='$4')?'zly':wp_create_nonce('mp_intake_case_reply'); \$_POST['_wpnonce']=\$n; \$_REQUEST['_wpnonce']=\$n; \$_POST['case_id']='$2'; \$_POST['body']='$3'; MP\\Intake\\Admin\\CaseActions::handle_reply();" >/dev/null 2>&1
}
do_assign() { # $1=uid $2=case $3=assignee $4=nonce
	wp eval "wp_set_current_user($1); \$n=('bad'==='$4')?'zly':wp_create_nonce('mp_intake_case_assign'); \$_POST['_wpnonce']=\$n; \$_REQUEST['_wpnonce']=\$n; \$_POST['case_id']='$2'; \$_POST['assignee']='$3'; MP\\Intake\\Admin\\CaseActions::handle_assign();" >/dev/null 2>&1
}

# status ma spacje w srodku ("w analizie") — NIE uzywaj q() (zjada spacje); tnij tylko konce.
st()  { wp db query "SELECT status FROM wp_mp_service_cases WHERE id=$1" --skip-column-names 2>/dev/null | tr -d '\n\r'; }
sc()  { q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$1 AND event_type='STATUS_CHANGED'"; }
msgc(){ q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$1"; }
asg() { q "SELECT IFNULL(assigned_to,'NULL') FROM wp_mp_service_cases WHERE id=$1"; }

CID=$(mk akcje@example.com AKC-1)
[ -n "$CID" ] && ok "seed: sprawa gotowa (id=$CID, status=$(st "$CID"))" || bad "seed: brak case_id"

# ── 1. ZMIANA STATUSU ────────────────────────────────────────────────────────
# 1a. staff (agent) + valid: nowe -> w analizie
do_status "$AGENT" "$CID" "w analizie" "nowe" "" valid
[ "$(st "$CID")" = "w analizie" ] && ok "status: agent+nonce zmienil nowe->w analizie" || bad "status: nie zmieniono ($(st "$CID"))"
[ "$(sc "$CID")" = "1" ] && ok "status: wpis STATUS_CHANGED na osi (kazda decyzja w historii)" || bad "status: brak/za duzo STATUS_CHANGED ($(sc "$CID"))"
ACT=$(q "SELECT actor_id FROM wp_mp_case_events WHERE case_id=$CID AND event_type='STATUS_CHANGED' ORDER BY id DESC LIMIT 1")
[ "$ACT" = "$AGENT" ] && ok "status: actor_id = zalogowany pracownik ($AGENT)" || bad "status: zly actor ($ACT != $AGENT)"

# 1b. optimistic-lock: nieaktualny expected='nowe' => STATUS_CONFLICT, bez zmiany
do_status "$AGENT" "$CID" "zaakceptowane" "nowe" "" valid
[ "$(st "$CID")" = "w analizie" ] && ok "status: optimistic-lock blokuje nieaktualny expected (STATUS_CONFLICT)" || bad "status: lock nie zadzialal ($(st "$CID"))"
[ "$(sc "$CID")" = "1" ] && ok "status: konflikt NIE dopisal zdarzenia" || bad "status: konflikt dopisal event ($(sc "$CID"))"

# 1c. NIE-staff (subscriber) + valid nonce => 403, bez zmiany
do_status "$SUB" "$CID" "zaakceptowane" "w analizie" "" valid
[ "$(st "$CID")" = "w analizie" ] && ok "status: subscriber = 403, brak zmiany (bramka capability)" || bad "status: subscriber zmienil status!! ($(st "$CID"))"

# 1d. staff ale ZLY nonce => bez zmiany
do_status "$AGENT" "$CID" "zaakceptowane" "w analizie" "" bad
[ "$(st "$CID")" = "w analizie" ] && ok "status: zly nonce = brak zmiany" || bad "status: zly nonce przeszedl!! ($(st "$CID"))"

# ── 2. ODPOWIEDZ DO KLIENTA ──────────────────────────────────────────────────
M0=$(msgc "$CID")
# 2a. staff (agent) + valid: dodaje wiadomosc 'staff'
do_reply "$AGENT" "$CID" "Odpowiedz-testowa-do-klienta" valid
M1=$(msgc "$CID")
[ "$M1" = "$((M0+1))" ] && ok "reply: agent+nonce dodal wiadomosc (msgs $M0->$M1)" || bad "reply: nie dodano wiadomosci ($M0->$M1)"
LAST=$(q "SELECT author_type FROM wp_mp_messages WHERE case_id=$CID ORDER BY id DESC LIMIT 1")
[ "$LAST" = "staff" ] && ok "reply: wiadomosc oznaczona jako 'staff'" || bad "reply: zly author_type ($LAST)"

# 2b. pusta tresc => bez wpisu
do_reply "$AGENT" "$CID" "" valid
[ "$(msgc "$CID")" = "$M1" ] && ok "reply: pusta tresc = brak nowej wiadomosci" || bad "reply: pusta tresc dodala wpis ($(msgc "$CID"))"

# 2c. NIE-staff (subscriber) => 403, bez wpisu
do_reply "$SUB" "$CID" "Haker-probuje-pisac" valid
[ "$(msgc "$CID")" = "$M1" ] && ok "reply: subscriber = 403, brak wiadomosci" || bad "reply: subscriber dodal wiadomosc!! ($(msgc "$CID"))"

# ── 3. PRZYDZIAL (rola: TYLKO koordynator/admin) ─────────────────────────────
# 3a. PRACOWNIK (mp_agent) = staff, ale NIE moze przydzielac => 403, bez zmiany
do_assign "$AGENT" "$CID" "$AGENT" valid
[ "$(asg "$CID")" = "NULL" ] && ok "assign: mp_agent = 403 (pracownik nie przydziela — rola/ownership)" || bad "assign: agent przydzielil!! ($(asg "$CID"))"

# 3b. koordynator + valid => przydzial ustawiony + CASE_ASSIGNED
do_assign "$COORD" "$CID" "$AGENT" valid
[ "$(asg "$CID")" = "$AGENT" ] && ok "assign: koordynator przydzielil sprawe agentowi" || bad "assign: koordynator nie przydzielil ($(asg "$CID"))"
CA=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CASE_ASSIGNED'")
[ "$CA" != "0" ] && ok "assign: wpis CASE_ASSIGNED na osi ($CA)" || bad "assign: brak CASE_ASSIGNED ($CA)"

# 3c. koordynator + ZLY nonce => bez zmiany (przydziel innemu, sprawdz ze zostal agent)
do_assign "$COORD" "$CID" "$COORD" bad
[ "$(asg "$CID")" = "$AGENT" ] && ok "assign: zly nonce = brak zmiany przydzialu" || bad "assign: zly nonce przeszedl!! ($(asg "$CID"))"

echo ""
echo "CASE-ACTIONS: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
