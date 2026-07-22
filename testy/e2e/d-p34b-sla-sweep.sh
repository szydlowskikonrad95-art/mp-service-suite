#!/usr/bin/env bash
# ZYWY DOWOD P3.4 SLA-2 (sweep): cron wybiera sprawy wymagalne i wola Sla::notify.
# warning_at liczone przy provision. Miniony prog => przypomnienie; miniony termin =>
# eskalacja. Markery daja IDEMPOTENCJE (2. sweep = 0 maili). GET_LOCK = jeden przebieg
# naraz (drugi wychodzi). Niewymagalne / terminalne => pominiete. pre_wp_mail=true =>
# transport env-niezalezny (capture i tak zapisuje). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
CAP="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
capclear() { : > "$CAP"; }
capcount() { if [ -s "$CAP" ]; then grep -c '' "$CAP" 2>/dev/null; else echo 0; fi; }
sweep()   { wp eval "add_filter('pre_wp_mail','__return_true'); MP\Automator\Sweep::run();" >/dev/null 2>&1; }

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}
overdue() { wp db query "UPDATE wp_mp_case_sla SET deadline_at=NOW()-INTERVAL 1 HOUR, warning_at=NOW()-INTERVAL 2 HOUR WHERE case_id=$1" >/dev/null 2>&1; }

# ── 0. Czysty stan + koordynator ─────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_workflow_rules;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); delete_option("mp_automator_mail_templates"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
COORD=$(wp user create swk swk@example.com --role=mp_coordinator --porcelain 2>/dev/null); [ -z "$COORD" ] && COORD=$(wp user get swk --field=ID 2>/dev/null)
ok "koordynator (id=$COORD)"

# ── 1. warning_at liczone przy provision (deadline - warning_hours) ───────────
CID=$(mkcase sw1@example.com SWP-1)
WH=$(q "SELECT TIMESTAMPDIFF(HOUR, warning_at, deadline_at) FROM wp_mp_case_sla WHERE case_id=$CID")
[ "$WH" = "6" ] && ok "warning_at = deadline - 6h (25% okna nowe) zapisane przy provision" || bad "zle warning_at ($WH h)"

# ── 2. Niewymagalne (termin w przyszlosci) => sweep NIE wysyla ────────────────
capclear; sweep
[ "$(capcount)" = "0" ] && ok "sprawa niewymagalna (termin w przyszlosci) => sweep nic nie wysyla" || bad "sweep wyslal dla niewymagalnej!"

# ── 3. Miniony termin => przypomnienie + eskalacja + markery + SLA_* na osi ───
overdue "$CID"
capclear; sweep
[ "$(capcount)" = "2" ] && ok "miniony termin => 2 maile (przypomnienie + eskalacja)" || bad "sweep wyslal $(capcount) (oczek 2)"
RE=$(q "SELECT CONCAT(reminder_sent_at IS NOT NULL, escalated_at IS NOT NULL) FROM wp_mp_case_sla WHERE case_id=$CID")
[ "$RE" = "11" ] && ok "markery reminder_sent_at + escalated_at ustawione (send-then-claim)" || bad "markery nie ustawione ($RE)"
SC=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type IN ('SLA_REMINDER_SENT','SLA_ESCALATED')")
[ "$SC" = "2" ] && ok "SLA_REMINDER_SENT + SLA_ESCALATED na osi sprawy (C)" || bad "brak eventow SLA na osi ($SC)"
SR=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SWEEP_RUN'")
[ "$SR" -ge 1 ] 2>/dev/null && ok "SWEEP_RUN zaksiegowany (audyt przebiegu)" || bad "brak SWEEP_RUN"

# ── 4. IDEMPOTENCJA: drugi sweep => 0 maili (markery odsiewaja) ──────────────
capclear; sweep
[ "$(capcount)" = "0" ] && ok "2. sweep => 0 maili (markery w tabeli = idempotencja)" || bad "2. sweep wyslal dubel! ($(capcount))"

# ── 5. GET_LOCK: gdy zamek trzymany przez inne polaczenie => sweep wychodzi ───
CID2=$(mkcase sw2@example.com SWP-2); overdue "$CID2"
capclear
# tlo: osobne polaczenie trzyma zamek 4 s
wp eval 'global $wpdb; $wpdb->get_var("SELECT GET_LOCK(\"mp_sla_sweep\", 5)"); sleep(4);' >/dev/null 2>&1 &
BG=$!
sleep 1  # daj tlu zdobyc zamek
sweep    # ten przebieg powinien wyjsc od razu (zamek zajety)
LOCKED=$(capcount)
wait "$BG" 2>/dev/null
[ "$LOCKED" = "0" ] && ok "sweep przy zajetym GET_LOCK => WYCHODZI (0 maili, brak dubla przebiegu)" || bad "sweep dzialal mimo zajetego zamka! ($LOCKED)"
# po zwolnieniu zamka kolejny sweep obsluguje sprawe
capclear; sweep
[ "$(capcount)" = "2" ] && ok "po zwolnieniu zamka nastepny sweep obsluguje zalegla sprawe" || bad "sprawa nieobsluzona po zwolnieniu zamka ($(capcount))"

# ── 6. Terminalna (deadline NULL) => sweep pomija ────────────────────────────
CID3=$(mkcase sw3@example.com SWP-3)
wp eval "apply_filters('mp_case_change_status', null, $CID3, 'zamknięte', 'nowe', 1, null);" >/dev/null 2>&1
capclear; sweep
[ "$(capcount)" = "0" ] && ok "sprawa terminalna (deadline NULL) => sweep pomija" || bad "sweep ruszyl terminalna!"

# ── 7. CRON: interwal 5-min zarejestrowany + sweep planowalny + odpala sie ───
INT=$(wp eval 'echo isset(apply_filters("cron_schedules", array())["mp_automator_5min"]) ? "1":"0";' 2>/dev/null)
[ "$INT" = "1" ] && ok "interwal 5-min (mp_automator_5min) zarejestrowany w cron_schedules" || bad "brak interwalu 5-min"
wp eval 'MP\Automator\Sweep::schedule();' >/dev/null 2>&1
NX=$(wp eval 'echo wp_next_scheduled("mp_automator_sla_sweep") ? "1":"0";' 2>/dev/null)
[ "$NX" = "1" ] && ok "sweep zaplanowany (wp_next_scheduled mp_automator_sla_sweep)" || bad "sweep nie zaplanowany"
# odpalenie przez WP-Cron (jak kontener cron) — sprawa zalegla obsluzona
CID4=$(mkcase sw4@example.com SWP-4); overdue "$CID4"
capclear
wp eval "add_filter('pre_wp_mail','__return_true'); do_action('mp_automator_sla_sweep');" >/dev/null 2>&1
[ "$(capcount)" = "2" ] && ok "hak crona mp_automator_sla_sweep odpala Sweep::run (obsluga zaleglej)" || bad "hak crona nie zadzialal ($(capcount))"

# ── Sprzatanie ────────────────────────────────────────────────────────────────
capclear; wp user delete "$COORD" --yes >/dev/null 2>&1
echo ""
echo "D-P34B-SLA-SWEEP: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
