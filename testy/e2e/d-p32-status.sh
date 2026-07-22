#!/usr/bin/env bash
# ZYWY DOWOD P3.2 (mp_case_change_status w C — domyka luke #9): zmiana statusu
# wg STATE_MACHINE.md — optimistic-lock, wejscie w 'odrzucone' wymaga kodu, reopen
# z terminalnego TYLKO do 'w analizie', status wlasny z mp_registered_statuses,
# emisja mp_case_status_changed PO COMMIT. Chodzi tak samo na poligonie i w CI.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
cs()  { wp eval "echo wp_json_encode( apply_filters('mp_case_change_status', null, $1, '$2', '$3', 1, $4) );" 2>/dev/null; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

# ── Zweryfikowana sprawa (status='nowe') ─────────────────────────────────────
OUT=$(wp mp case-create --kind=reklamacja --email='st@example.com' --name='S T' --serial='ST-1' --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
TOK=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp eval "MP\Intake\CaseRepo::verify('$TOK');" >/dev/null 2>&1
[ "$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")" = "nowe" ] && ok "sprawa 'nowe' (case_id=$CID)" || bad "sprawa nie 'nowe'"

# ── 1. Przejscie nowe->w analizie + event STATUS_CHANGED + emisja akcji PO COMMIT ──
FIRED=$(wp eval "add_action('mp_case_status_changed', function(\$c,\$o,\$n,\$a){ echo 'FIRED:'.\$o.'>'.\$n; }, 10, 4); apply_filters('mp_case_change_status', null, $CID, 'w analizie', 'nowe', 1, null);" 2>/dev/null)
echo "$FIRED" | grep -q 'FIRED:nowe>w analizie' && ok "mp_case_status_changed wyemitowany PO COMMIT (nowe>w analizie)" || bad "akcja nie wyemitowana ($FIRED)"
[ "$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")" = "wanalizie" ] && ok "status w bazie = 'w analizie'" || bad "status nie zmieniony"
SC=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='STATUS_CHANGED'")
[ "$SC" = "1" ] && ok "event STATUS_CHANGED zapisany (oś czasu)" || bad "brak STATUS_CHANGED ($SC)"

# ── 2. Optimistic-lock: zly expected => STATUS_CONFLICT (nic nie zmienia) ─────
R=$(cs "$CID" "zaakceptowane" "nowe" "null")
echo "$R" | grep -q 'STATUS_CONFLICT' && ok "optimistic-lock: zly expected => STATUS_CONFLICT" || bad "conflict nie wykryty ($R)"
[ "$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")" = "wanalizie" ] && ok "status niezmieniony po konflikcie" || bad "status zmieniony mimo konfliktu!"

# ── 3. 'odrzucone' BEZ kodu => REJECTION_REASON_REQUIRED ─────────────────────
R=$(cs "$CID" "odrzucone" "w analizie" "null")
echo "$R" | grep -q 'REJECTION_REASON_REQUIRED' && ok "'odrzucone' bez kodu ODRZUCONE (wymog kodu)" || bad "odrzucone bez kodu przeszlo ($R)"

# ── 4. 'odrzucone' Z kodem => sukces + kod w kolumnie i evencie ──────────────
R=$(cs "$CID" "odrzucone" "w analizie" "'duplikat'")
echo "$R" | grep -q '"success":true' && ok "'odrzucone' z kodem: sukces" || bad "odrzucone z kodem nieudane ($R)"
[ "$(q "SELECT rejection_reason_code FROM wp_mp_service_cases WHERE id=$CID")" = "duplikat" ] && ok "rejection_reason_code zapisany (duplikat)" || bad "brak kodu w kolumnie"
RC=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='STATUS_CHANGED' AND payload LIKE '%duplikat%'")
[ "$RC" -ge 1 ] 2>/dev/null && ok "kod w payloadzie eventu" || bad "brak kodu w evencie"

# ── 5. Z terminalnego 'odrzucone': reopen TYLKO do 'w analizie' ──────────────
R=$(cs "$CID" "w naprawie" "odrzucone" "null")
echo "$R" | grep -q 'INVALID_TRANSITION' && ok "z 'odrzucone' do 'w naprawie' ZABRONIONE (INVALID_TRANSITION)" || bad "zla zmiana z terminala przeszla ($R)"
R=$(cs "$CID" "w analizie" "odrzucone" "null")
echo "$R" | grep -q '"success":true' && ok "REOPEN 'odrzucone'->'w analizie' dozwolony" || bad "reopen nieudany ($R)"
RRC=$(q "SELECT rejection_reason_code FROM wp_mp_service_cases WHERE id=$CID")
{ [ -z "$RRC" ] || [ "$RRC" = "NULL" ]; } && ok "reopen wyczyścił rejection_reason_code" || bad "kod odrzucenia zostal po reopen ($RRC)"

# ── 6. Nieznany status => INVALID_STATUS ─────────────────────────────────────
R=$(cs "$CID" "fikcyjny_status" "w analizie" "null")
echo "$R" | grep -q 'INVALID_STATUS' && ok "nieznany status => INVALID_STATUS" || bad "nieznany status przeszedl ($R)"

# ── 7. Status WLASNY z mp_registered_statuses => walidacja go akceptuje ───────
CUSTOM=$(wp eval "add_filter('mp_registered_statuses', function(\$s){ \$s['ekspertyza_zewnetrzna']=array('label'=>'Ekspertyza','terminal'=>false); return \$s; }); echo wp_json_encode( apply_filters('mp_case_change_status', null, $CID, 'ekspertyza_zewnetrzna', 'w analizie', 1, null) );" 2>/dev/null)
echo "$CUSTOM" | grep -q '"success":true' && ok "status własny (mp_registered_statuses) zaakceptowany przez walidator C" || bad "status własny odrzucony ($CUSTOM)"

# ── 8. Nieistniejąca sprawa => CASE_NOT_FOUND ────────────────────────────────
R=$(cs "999999" "w analizie" "nowe" "null")
echo "$R" | grep -q 'CASE_NOT_FOUND' && ok "nieistniejąca sprawa => CASE_NOT_FOUND" || bad "nieistniejąca przeszla ($R)"

echo ""
echo "D-P32-STATUS: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
