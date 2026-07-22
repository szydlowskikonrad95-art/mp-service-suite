#!/usr/bin/env bash
# ZYWY DOWOD C-hooki dla D (prereq P3.1): funkcje kontraktowe C, ktorych D uzywa —
# mp_case_get_context (fakty do regul/maili) + mp_case_assign (przydzial; assigned_to
# nalezy do C, D wola przez hook). Wolane przez PRAWDZIWE apply_filters (dowod, ze
# hooki wpiete w Plugin::boot). Chodzi tak samo na poligonie i w CI. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ── 0. Czysty stan + użytkownicy testowi ─────────────────────────────────────
wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

AGENT=$(wp user create dhook_agent dhook_agent@example.com --role=mp_agent --porcelain 2>/dev/null)
[ -z "$AGENT" ] && AGENT=$(wp user get dhook_agent --field=ID 2>/dev/null)
CLIENT=$(wp user create dhook_client dhook_client@example.com --role=subscriber --porcelain 2>/dev/null)
[ -z "$CLIENT" ] && CLIENT=$(wp user get dhook_client --field=ID 2>/dev/null)
[ -n "$AGENT" ] && [ -n "$CLIENT" ] && ok "użytkownicy testowi: agent=$AGENT (mp_agent), non-agent=$CLIENT (subscriber)" || bad "brak userów testowych"

# ── 1. Zweryfikowana sprawa (narodziny wg flow: create -> verify) ────────────
OUT=$(wp mp case-create --kind=reklamacja --email='ala@example.com' --name='Ala Kowalska' --serial='DHK-1' --document='FV/2026/9' --date='2026-05-10' --desc='Test hooka' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
TOKEN=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp eval "MP\Intake\CaseRepo::verify('$TOKEN');" >/dev/null 2>&1
STAT=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
[ "$STAT" = "nowe" ] && ok "sprawa zweryfikowana (case_id=$CID, status=nowe)" || bad "sprawa nie zweryfikowana (status=$STAT)"

# ── 2. mp_case_get_context: fakty + kontakt runtime + kategoria=null (B bez kategorii) ──
CTX=$(wp eval "echo wp_json_encode( apply_filters('mp_case_get_context', 'x', $CID) );" 2>/dev/null)
echo "$CTX" | grep -q '"rodzaj":"reklamacja"' && ok "get_context: rodzaj=reklamacja" || bad "get_context zły rodzaj ($CTX)"
echo "$CTX" | grep -q '"status":"nowe"' && ok "get_context: status=nowe" || bad "get_context zły status"
echo "$CTX" | grep -q '"priority":"normal"' && ok "get_context: priority=normal (default)" || bad "get_context zły priority"
echo "$CTX" | grep -qE '"kontakt":\{[^}]*"email":"ala@example.com"' && ok "get_context: kontakt.email runtime (do maili)" || bad "get_context brak kontaktu"
echo "$CTX" | grep -q '"kategoria":null' && ok "get_context: kategoria=null (B nie ma kategorii — graceful, frozen zasada)" || bad "get_context kategoria nie null ($CTX)"

# NO-PII-IN-LOG kontrola: kontakt NIE trafia do case_events przy zwyklej operacji.
LEAK=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND payload LIKE '%ala@example.com%'")
[ "$LEAK" = "0" ] && ok "kontakt NIE wyciekł do eventów (get_context = tylko runtime)" || bad "adres w evencie!"

# ── 3. mp_case_get_context nieistniejącej sprawy => 'not_found' ───────────────
NF=$(wp eval "echo apply_filters('mp_case_get_context', 'zle', 999999);" 2>/dev/null | tr -d '[:space:]')
[ "$NF" = "not_found" ] && ok "get_context nieistniejącej sprawy => 'not_found'" || bad "get_context zwrocil '$NF' zamiast not_found"

# ── 4. mp_case_assign: do mp_agent = sukces + assigned_to + event CASE_ASSIGNED ──
AS=$(wp eval "echo wp_json_encode( apply_filters('mp_case_assign', null, $CID, $AGENT, 1) );" 2>/dev/null)
echo "$AS" | grep -q '"success":true' && ok "assign do mp_agent: success" || bad "assign nieudany ($AS)"
DB_ASG=$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID")
[ "$DB_ASG" = "$AGENT" ] && ok "assigned_to zapisane w tabeli C ($DB_ASG)" || bad "assigned_to w DB = $DB_ASG (oczekiwano $AGENT)"
EVA=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CASE_ASSIGNED'")
[ "$EVA" = "1" ] && ok "event CASE_ASSIGNED zapisany (oś czasu sprawy)" || bad "brak eventu CASE_ASSIGNED (jest $EVA)"
EVPAY=$(q "SELECT payload FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CASE_ASSIGNED' ORDER BY id DESC LIMIT 1")
echo "$EVPAY" | grep -qE "\"to\":$AGENT" && ok "payload CASE_ASSIGNED: to=$AGENT ($EVPAY)" || bad "zły payload ($EVPAY)"

# ── 5. get_context PO przydziale pokazuje assigned_to ────────────────────────
CTX2=$(wp eval "echo wp_json_encode( apply_filters('mp_case_get_context', 'x', $CID) );" 2>/dev/null)
echo "$CTX2" | grep -qE "\"assigned_to\":$AGENT" && ok "get_context po assign: assigned_to=$AGENT" || bad "get_context nie widzi przydziału ($CTX2)"

# ── 6. Walidacja negatywna: przydział do non-agenta = INVALID_ASSIGNEE ───────
ASN=$(wp eval "echo wp_json_encode( apply_filters('mp_case_assign', null, $CID, $CLIENT, 1) );" 2>/dev/null)
echo "$ASN" | grep -q 'INVALID_ASSIGNEE' && ok "assign do non-agenta ODRZUCONY (INVALID_ASSIGNEE)" || bad "assign do non-agenta przeszedł! ($ASN)"

# ── 7. Przydział nieistniejącej sprawy = CASE_NOT_FOUND ──────────────────────
ASX=$(wp eval "echo wp_json_encode( apply_filters('mp_case_assign', null, 999999, $AGENT, 1) );" 2>/dev/null)
echo "$ASX" | grep -q 'CASE_NOT_FOUND' && ok "assign nieistniejącej sprawy ODRZUCONY (CASE_NOT_FOUND)" || bad "assign nieistniejącej przeszedł! ($ASX)"

# ── Sprzątanie userów + podsumowanie ─────────────────────────────────────────
wp user delete "$AGENT" --yes >/dev/null 2>&1
wp user delete "$CLIENT" --yes >/dev/null 2>&1
echo ""
echo "D-HOOKI-C: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
