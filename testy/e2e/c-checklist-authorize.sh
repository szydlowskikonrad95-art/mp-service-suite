#!/usr/bin/env bash
# ZYWY DOWOD PR-A (funkcja kontraktowa mp_case_checklist_authorize w C): C egzekwuje
# WLASNOSC/ROLE dla toggle checklisty + emituje CHECKLIST_ITEM_TOGGLED {step_key,
# completed, actor_id}. mp_agent -> TYLKO wlasna sprawa; koordynator/admin -> dowolna;
# subscriber -> FORBIDDEN; brak sprawy -> CASE_NOT_FOUND; pusty krok -> INVALID_STEP.
# Kolejnosc: hook autoryzuje (event powstaje), D dopiero PO OK zapisuje stan u siebie.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
auth(){ wp eval "echo wp_json_encode( apply_filters('mp_case_checklist_authorize', null, $1, '$2', $3, $4) );" 2>/dev/null; }

ADMIN=1

# ── 0. Czysty stan + konta ──────────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

A1=$(wp user get chk_agent1 --field=ID 2>/dev/null); [ -z "$A1" ] && A1=$(wp user create chk_agent1 chk_a1@example.com --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
A2=$(wp user get chk_agent2 --field=ID 2>/dev/null); [ -z "$A2" ] && A2=$(wp user create chk_agent2 chk_a2@example.com --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
CO=$(wp user get chk_coord --field=ID 2>/dev/null);  [ -z "$CO" ] && CO=$(wp user create chk_coord chk_co@example.com --role=mp_coordinator --user_pass=x --porcelain 2>/dev/null)
SU=$(wp user get chk_sub --field=ID 2>/dev/null);    [ -z "$SU" ] && SU=$(wp user create chk_sub chk_su@example.com --role=subscriber --user_pass=x --porcelain 2>/dev/null)

# ── 1. Sprawa zweryfikowana przydzielona agentowi A1 ────────────────────────
O=$(wp mp case-create --kind=reklamacja --email=k@example.com --name='Jan K' --serial=CHK-1 --document=FV/1 --date=2026-05-01 --desc=x 2>/dev/null)
CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2); TOK=$(echo "$O" | grep '^token=' | cut -d= -f2)
wp eval "MP\\Intake\\CaseRepo::verify('$TOK');" >/dev/null 2>&1
wp eval "apply_filters('mp_case_assign', null, $CID, $A1, $ADMIN);" >/dev/null 2>&1
[ "$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID")" = "$A1" ] && ok "seed: sprawa $CID przydzielona A1" || bad "seed: przydzial nie zadzialal"

EV0=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CHECKLIST_ITEM_TOGGLED'")

# ── 2. A1 na WLASNEJ sprawie => success + event ─────────────────────────────
R=$(auth "$CID" "zebranie_danych" "true" "$A1")
echo "$R" | grep -q '"success":true' && ok "A1 (wlasciciel) => success" || bad "A1 nie przeszedl ($R)"
EV1=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CHECKLIST_ITEM_TOGGLED'")
[ "$EV1" = "$((EV0+1))" ] && ok "event CHECKLIST_ITEM_TOGGLED zapisany na osi" || bad "brak eventu ($EV0->$EV1)"
# payload {step_key, completed, actor_id}
PL=$(wp db query "SELECT payload FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CHECKLIST_ITEM_TOGGLED' ORDER BY id DESC LIMIT 1" --skip-column-names 2>/dev/null)
{ echo "$PL" | grep -q '"step_key":"zebranie_danych"' && echo "$PL" | grep -q '"completed":true' && echo "$PL" | grep -q "\"actor_id\":$A1"; } && ok "payload = {step_key, completed, actor_id}" || bad "zly payload ($PL)"

# ── 3. A2 (INNY agent) na cudzej sprawie => NOT_CASE_OWNER, BEZ eventu ───────
R=$(auth "$CID" "zebranie_danych" "true" "$A2")
echo "$R" | grep -q 'NOT_CASE_OWNER' && ok "A2 (nie-wlasciciel) => NOT_CASE_OWNER" || bad "A2 nie zablokowany ($R)"
EV2=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CHECKLIST_ITEM_TOGGLED'")
[ "$EV2" = "$EV1" ] && ok "obca proba NIE zapisala eventu" || bad "event mimo blokady ($EV1->$EV2)"

# ── 4. Koordynator => success na DOWOLNEJ sprawie ───────────────────────────
R=$(auth "$CID" "kontakt_klient" "true" "$CO")
echo "$R" | grep -q '"success":true' && ok "koordynator => success (dowolna sprawa)" || bad "koordynator nie przeszedl ($R)"

# ── 5. Subscriber => FORBIDDEN ──────────────────────────────────────────────
R=$(auth "$CID" "zebranie_danych" "true" "$SU")
echo "$R" | grep -q 'FORBIDDEN' && ok "subscriber => FORBIDDEN (nie personel)" || bad "subscriber nie zablokowany ($R)"

# ── 6. Nieistniejaca sprawa => CASE_NOT_FOUND ───────────────────────────────
R=$(auth "99999" "zebranie_danych" "true" "$CO")
echo "$R" | grep -q 'CASE_NOT_FOUND' && ok "brak sprawy => CASE_NOT_FOUND" || bad "brak CASE_NOT_FOUND ($R)"

# ── 7. Pusty step_key => INVALID_STEP ───────────────────────────────────────
R=$(auth "$CID" "" "true" "$A1")
echo "$R" | grep -q 'INVALID_STEP' && ok "pusty krok => INVALID_STEP" || bad "brak INVALID_STEP ($R)"

# ── 8. completed=false tez autoryzowane (odznaczenie) ───────────────────────
R=$(auth "$CID" "zebranie_danych" "false" "$A1")
{ echo "$R" | grep -q '"success":true'; } && ok "toggle off (completed=false) autoryzowany" || bad "toggle off nie przeszedl ($R)"
PLF=$(wp db query "SELECT payload FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CHECKLIST_ITEM_TOGGLED' ORDER BY id DESC LIMIT 1" --skip-column-names 2>/dev/null)
echo "$PLF" | grep -q '"completed":false' && ok "payload completed=false" || bad "zly payload off ($PLF)"

echo ""
echo "WYNIK c-checklist-authorize: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
