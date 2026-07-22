#!/usr/bin/env bash
# ZYWY DOWOD P3.3 reguly message_added: wiadomosc KLIENTA => mail do przypisanego
# AGENTA; wiadomosc STAFF => mail do KLIENTA (C sam nie maili). Warunek po
# author_type (wstrzykiwany do kontekstu). system => brak reguly => brak maila.
# Plus guard from===to (re-assign do tego samego agenta = zero redundantnego maila).
# Asercje na capture (CI bez Mailpita). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
CAP="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
capclear() { : > "$CAP"; }
caplast()  { tail -n 1 "$CAP" 2>/dev/null; }
capcount() { if [ -s "$CAP" ]; then grep -c '' "$CAP" 2>/dev/null; else echo 0; fi; }

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}
msg() { wp eval "MP\Intake\Messages::add($1, '$2', $3, 'tresc');" >/dev/null 2>&1; }

# ── 0. Czysty stan + seed domyslny (4 reguly) + agent + sprawa przydzielona ───
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_messages;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); delete_option("mp_automator_mail_templates"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
AG=$(wp user create msgag msgag@example.com --role=mp_agent --porcelain 2>/dev/null); [ -z "$AG" ] && AG=$(wp user get msgag --field=ID 2>/dev/null)
CID=$(mkcase msgkl@example.com MSG-1)
wp eval "apply_filters('mp_case_assign', null, $CID, $AG, 1);" >/dev/null 2>&1
[ "$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID")" = "$AG" ] && ok "przygotowanie: sprawa $CID przydzielona do agenta $AG" || bad "przydzial nieudany"

# ── 1. Wiadomosc KLIENTA => mail do AGENTA (message_from_client) ──────────────
capclear
msg "$CID" client null
L=$(caplast)
echo "$L" | grep -q "\"to\":\"msgag@example.com\"" && ok "wiadomosc klienta => mail do PRZYPISANEGO agenta" || bad "zly odbiorca dla wiad. klienta ($L)"
echo "$L" | grep -q 'Nowa wiadomość' && ok "szablon message_from_client zrenderowany" || bad "zly szablon"
TRG=$(q "SELECT payload FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='RULE_EXECUTED' AND payload LIKE '%message_from_client%'")
echo "$TRG" | grep -q '"trigger":"message_added"' && ok "log: trigger=message_added (nie zaszyty status_changed)" || bad "zly trigger w logu ($TRG)"
echo "$TRG" | grep -q '"recipient_ref":"agent"' && ok "recipient_ref=agent (NO-PII)" || bad "zly recipient_ref"

# ── 2. Wiadomosc STAFF => mail do KLIENTA (message_from_staff; C sam nie maili) ─
capclear
msg "$CID" staff "$AG"
L=$(caplast)
echo "$L" | grep -q "\"to\":\"msgkl@example.com\"" && ok "wiadomosc staff => mail do KLIENTA" || bad "zly odbiorca dla wiad. staff ($L)"
echo "$L" | grep -q 'Odpowiedź serwisu' && ok "szablon message_from_staff zrenderowany" || bad "zly szablon staff"

# ── 3. Wiadomosc SYSTEM => brak reguly => brak maila ─────────────────────────
capclear
msg "$CID" system null
[ "$(capcount)" = "0" ] && ok "wiadomosc system: brak reguly => zero maili" || bad "system wygenerowal mail!"

# ── 4. GUARD from===to: re-assign do TEGO SAMEGO agenta => brak maila ────────
capclear
wp eval "apply_filters('mp_case_assign', null, $CID, $AG, 1);" >/dev/null 2>&1
[ "$(capcount)" = "0" ] && ok "re-assign do tego samego agenta => ZERO redundantnego maila (guard from===to)" || bad "redundantny mail przy re-assign na tego samego!"

# ── Sprzatanie ────────────────────────────────────────────────────────────────
capclear
wp user delete "$AG" --yes >/dev/null 2>&1
echo ""
echo "D-P33C-MESSAGE: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
