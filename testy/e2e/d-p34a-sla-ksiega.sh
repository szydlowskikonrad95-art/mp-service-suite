#!/usr/bin/env bash
# ZYWY DOWOD P3.4 SLA-1 (ksiega): wiersz wp_mp_case_sla zakladany na mp_case_created
# (termin od status_changed_at), przeliczany przy zmianie statusu (markery NULL),
# terminal => deadline NULL, modyfikator priorytetu, warning=round(sla*0.25) (NIE w t=0).
# notify() SEND-THEN-CLAIM: mail + SLA_* na osi C + marker; brak koordynatora => MAIL_SKIPPED;
# wp_mail=false => MAIL_FAILED + retry, po 3 => MAIL_FAILED_FINAL + alarm. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
CAP="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
capclear() { : > "$CAP"; }
caplast()  { tail -n 1 "$CAP" 2>/dev/null; }

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Czysty stan + koordynator + szablony ──────────────────────────────────
wp db query "DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_workflow_rules;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); delete_option("mp_automator_mail_templates"); delete_option("mp_automator_mail_alert"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
COORD=$(wp user create koord koord@example.com --role=mp_coordinator --porcelain 2>/dev/null); [ -z "$COORD" ] && COORD=$(wp user get koord --field=ID 2>/dev/null)
ok "koordynator utworzony (id=$COORD, mp_coordinator)"

# ── 1. SlaConfig: godziny + warning=25% + modyfikator priorytetu ──────────────
CFG=$(wp eval 'echo wp_json_encode(MP\Automator\SlaConfig::for_status("nowe"));' 2>/dev/null)
echo "$CFG" | grep -q '"sla_hours":24' && ok "SLA nowe = 24h" || bad "zle SLA nowe ($CFG)"
echo "$CFG" | grep -q '"warning_hours":6' && ok "warning nowe = 6h (round 24*0.25 — NIE 24h, brak spamu w t=0)" || bad "zle warning ($CFG)"
DHI=$(wp eval 'echo MP\Automator\SlaConfig::deadline_for("nowe","2026-01-01 00:00:00","high");' 2>/dev/null)
[ "$DHI" = "2026-01-01 12:00:00" ] && ok "priorytet high => 24h ×0.5 = 12h (deadline +12h)" || bad "zly modyfikator high ($DHI)"
DTERM=$(wp eval 'echo var_export(MP\Automator\SlaConfig::deadline_for("zamknięte","2026-01-01 00:00:00","normal"), true);' 2>/dev/null)
[ "$DTERM" = "NULL" ] && ok "status terminalny => deadline_for NULL" || bad "terminal nie NULL ($DTERM)"

# ── 2. Wiersz na mp_case_created (termin od status_changed_at, markery NULL) ──
CID=$(mkcase sla@example.com SLAK-1)
ROW=$(q "SELECT CONCAT(status,'|',IFNULL(reminder_sent_at,'NULL'),'|',IFNULL(escalated_at,'NULL'),'|',sla_policy_version) FROM wp_mp_case_sla WHERE case_id=$CID")
[ "$ROW" = "nowe|NULL|NULL|1" ] && ok "wiersz SLA na created: nowe, markery NULL, policy=1" || bad "zly wiersz po created ($ROW)"
H=$(q "SELECT TIMESTAMPDIFF(HOUR, c.status_changed_at, s.deadline_at) FROM wp_mp_service_cases c, wp_mp_case_sla s WHERE c.id=$CID AND s.case_id=$CID")
[ "$H" = "24" ] && ok "deadline = status_changed_at + 24h" || bad "zly deadline ($H h)"

# ── 3. Prog warning NIE odpala w t=0 (deadline - warning > NOW) ───────────────
WF=$(q "SELECT (s.deadline_at - INTERVAL 6 HOUR > NOW()) FROM wp_mp_case_sla s WHERE case_id=$CID")
[ "$WF" = "1" ] && ok "prog przypomnienia (deadline-6h) JESZCZE nie minal w t=0 (zero spamu przy narodzinach)" || bad "przypomnienie odpaliloby w t=0!"

# ── 4. Reprovision przy zmianie statusu: nowy termin + markery WYZEROWANE ─────
# najpierw brudzimy marker, potem zmiana statusu ma go wyczyscic
wp db query "UPDATE wp_mp_case_sla SET reminder_sent_at=NOW() WHERE case_id=$CID" >/dev/null 2>&1
wp eval "apply_filters('mp_case_change_status', null, $CID, 'w naprawie', 'nowe', 1, null);" >/dev/null 2>&1
H2=$(q "SELECT TIMESTAMPDIFF(HOUR, c.status_changed_at, s.deadline_at) FROM wp_mp_service_cases c, wp_mp_case_sla s WHERE c.id=$CID AND s.case_id=$CID")
[ "$H2" = "120" ] && ok "reprovision: w naprawie => deadline +120h (nowy termin)" || bad "zly deadline po reprovision ($H2)"
RM=$(q "SELECT IFNULL(reminder_sent_at,'NULL') FROM wp_mp_case_sla WHERE case_id=$CID")
[ "$RM" = "NULL" ] && ok "reprovision WYZEROWAL marker reminder_sent_at (swiezy zegar)" || bad "marker nie wyzerowany ($RM)"

# ── 5. Terminal => deadline NULL (sweep pomija) ──────────────────────────────
wp eval "apply_filters('mp_case_change_status', null, $CID, 'zamknięte', 'w naprawie', 1, null);" >/dev/null 2>&1
DL=$(q "SELECT IFNULL(deadline_at,'NULL') FROM wp_mp_case_sla WHERE case_id=$CID")
[ "$DL" = "NULL" ] && ok "status terminalny 'zamknięte' => deadline_at NULL" || bad "terminal ma deadline ($DL)"

# ── 6. notify(escalation): mail do koordynatora + SLA_ESCALATED na osi C + marker ─
CID2=$(mkcase sla2@example.com SLAK-2)
capclear
wp eval "MP\Automator\Sla::notify($CID2, 'escalation');" >/dev/null 2>&1
L=$(caplast)
echo "$L" | grep -q '"to":"koord@example.com"' && ok "eskalacja => mail do KOORDYNATORA" || bad "zly odbiorca eskalacji ($L)"
echo "$L" | grep -q 'ESKALACJA' && ok "szablon sla_escalation zrenderowany" || bad "zly szablon eskalacji"
SE=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID2 AND event_type='SLA_ESCALATED'")
[ "$SE" = "1" ] && ok "SLA_ESCALATED na osi sprawy (C, listener mp_sla_notified)" || bad "brak SLA_ESCALATED na osi ($SE)"
EM=$(q "SELECT IFNULL(escalated_at,'NULL') FROM wp_mp_case_sla WHERE case_id=$CID2")
[ "$EM" != "NULL" ] && ok "marker escalated_at ustawiony (send-then-claim)" || bad "marker nie ustawiony"
EV=$(q "SELECT payload FROM wp_mp_case_events WHERE case_id=$CID2 AND event_type='SLA_ESCALATED'")
echo "$EV" | grep -q 'koord@example.com' && bad "adres w evencie SLA (PII!)" || ok "SLA_ESCALATED bez adresu (NO-PII)"

# ── 7. notify(reminder) bez przydzialu => koordynator (fallback) + SLA_REMINDER_SENT ─
capclear
wp eval "MP\Automator\Sla::notify($CID2, 'reminder');" >/dev/null 2>&1
SR=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID2 AND event_type='SLA_REMINDER_SENT'")
[ "$SR" = "1" ] && ok "przypomnienie nieprzydzielonej => koordynator + SLA_REMINDER_SENT" || bad "brak SLA_REMINDER_SENT ($SR)"

# ── 8. Brak koordynatora => MAIL_SKIPPED + marker (nie retry) ─────────────────
wp user delete "$COORD" --yes >/dev/null 2>&1
CID3=$(mkcase sla3@example.com SLAK-3)
capclear
wp eval "MP\Automator\Sla::notify($CID3, 'escalation');" >/dev/null 2>&1
[ -z "$(caplast)" ] && ok "brak koordynatora => ZERO maila" || bad "mail poszedl bez koordynatora"
SK=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID3 AND event_type='MAIL_SKIPPED_NO_RECIPIENT'")
[ "$SK" = "1" ] && ok "MAIL_SKIPPED_NO_RECIPIENT (stan legalny)" || bad "brak MAIL_SKIPPED ($SK)"
MK=$(q "SELECT IFNULL(escalated_at,'NULL') FROM wp_mp_case_sla WHERE case_id=$CID3")
[ "$MK" != "NULL" ] && ok "marker ustawiony mimo braku odbiorcy (brak retry-spamu)" || bad "marker NULL => retry-spam"

# ── 9. wp_mail=false => MAIL_FAILED + attempts; po 3 => MAIL_FAILED_FINAL + alarm ─
COORD2=$(wp user create koord2 koord2@example.com --role=mp_coordinator --porcelain 2>/dev/null); [ -z "$COORD2" ] && COORD2=$(wp user get koord2 --field=ID 2>/dev/null)
CID4=$(mkcase sla4@example.com SLAK-4)
for i in 1 2 3; do wp eval "add_filter('pre_wp_mail','__return_false'); MP\Automator\Sla::notify($CID4, 'reminder');" >/dev/null 2>&1; done
MF=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID4 AND event_type='MAIL_FAILED'")
[ "$MF" = "2" ] && ok "2x MAIL_FAILED (proba 1-2, retry, marker NULL)" || bad "MAIL_FAILED=$MF (oczek 2)"
FIN=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID4 AND event_type='MAIL_FAILED_FINAL'")
[ "$FIN" = "1" ] && ok "3. proba => MAIL_FAILED_FINAL (marker na sile, koniec retry)" || bad "brak MAIL_FAILED_FINAL ($FIN)"
AL=$(q "SELECT option_value FROM wp_options WHERE option_name='mp_automator_mail_alert'")
[ "$AL" = "1" ] && ok "alarm admina ustawiony (panel pokaze notice)" || bad "brak alarmu admina ($AL)"

# ── Sprzatanie ────────────────────────────────────────────────────────────────
capclear; wp user delete "$COORD2" --yes >/dev/null 2>&1
echo ""
echo "D-P34A-SLA-KSIEGA: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
