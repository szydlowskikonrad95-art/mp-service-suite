#!/usr/bin/env bash
# ZYWY DOWOD P3.4 SLA-4 („Przelicz SLA" + nieretroaktywnosc): akcja admina
# admin_post_mp_automator_recalc_sla (backend-handler-only, BEZ menu) przelicza
# terminy OTWARTYCH spraw wg biezacego SlaConfig, NIE resetujac markerow.
#  (a) otwarte sprawy => NOWE terminy + nowa wersja polityki na wierszu
#  (b) TERMINALNE nietkniete (deadline NULL, stara wersja polityki)
#  (c) markery juz-wyslane NIE zresetowane => nastepny sweep = 0 dubli
#  (d) sprawa nowo-przeterminowana po przeliczeniu = 1 powiadomienie (nie reminder+eskalacja)
#  (e) audyt SLA_RECALCULATED (kto=actor_id / kiedy=created_at / ile=cases_touched)
#  (f) rola bez capability mp_system_admin => brak dostepu (403, zero przeliczenia)
#      + zly nonce => odrzucone.
# Handler wolany przez do_action('admin_post_...') z ustawionym userem+nonce (POST-owy
# tor admin-post.php). Exit z redirectu/wp_die konczy TYLKO eval — skutki (recompute+
# audyt) commituja sie wczesniej. pre_wp_mail=true => transport env-niezalezny.
# Exit 0 = OK.
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
# wywolanie handlera admin_post jako user $1, nonce $2 (valid|bad)
recalc_as() {
	local uid="$1" kind="${2:-valid}"
	wp eval "
		wp_set_current_user($uid);
		\$n = ('bad'==='$kind') ? 'zly-nonce' : wp_create_nonce('mp_automator_recalc_sla');
		\$_REQUEST['_wpnonce'] = \$n; \$_POST['_wpnonce'] = \$n;
		\$_REQUEST['action'] = 'mp_automator_recalc_sla';
		do_action('admin_post_mp_automator_recalc_sla');
	" >/dev/null 2>&1
}

# ── 0. Czysty stan + role + config startowy (policy=1, nowe=24h default) ──────
wp db query "DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_workflow_rules;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); delete_option("mp_automator_mail_templates"); delete_option("mp_automator_sla_core"); delete_option("mp_automator_sla_policy_version"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
COORD=$(wp user create swk swk@example.com --role=mp_coordinator --porcelain 2>/dev/null); [ -z "$COORD" ] && COORD=$(wp user get swk --field=ID 2>/dev/null)
ADM=$(wp user create sysadm sysadm@example.com --role=administrator --porcelain 2>/dev/null); [ -z "$ADM" ] && ADM=$(wp user get sysadm --field=ID 2>/dev/null)
wp eval "\$u=get_user_by('id',$ADM); \$u->add_cap('mp_system_admin');" >/dev/null 2>&1
LOW=$(wp user create lowpriv low@example.com --role=subscriber --porcelain 2>/dev/null); [ -z "$LOW" ] && LOW=$(wp user get lowpriv --field=ID 2>/dev/null)
HASCAP=$(wp eval "echo user_can($ADM,'mp_system_admin')?'1':'0'; echo user_can($LOW,'mp_system_admin')?'1':'0';" 2>/dev/null | tr -d '[:space:]')
[ "$HASCAP" = "10" ] && ok "role: sysadm MA mp_system_admin, lowpriv NIE" || bad "role zle skonfigurowane ($HASCAP)"

# ── 1. Sprawy startowe: OPEN + SENT(juz eskalowana) + TERMINAL + NEW(kotwica wstecz)
CID_OPEN=$(mkcase open@example.com REC-OPEN)                     # nowe, deadline w przyszlosci
DL_OPEN_0=$(q "SELECT deadline_at FROM wp_mp_case_sla WHERE case_id=$CID_OPEN")

CID_SENT=$(mkcase sent@example.com REC-SENT); overdue "$CID_SENT"
capclear; sweep                                                 # retroaktywna => 1 eskalacja (markery set)
SENT_MAILS=$(capcount)
RESENT0=$(q "SELECT CONCAT(reminder_sent_at IS NOT NULL, escalated_at IS NOT NULL) FROM wp_mp_case_sla WHERE case_id=$CID_SENT")
[ "$SENT_MAILS" = "1" ] && [ "$RESENT0" = "11" ] && ok "sprawa SENT: 1 eskalacja przed przeliczeniem, markery ustawione" || bad "SENT zle ($SENT_MAILS mail, markery $RESENT0)"

CID_TERM=$(mkcase term@example.com REC-TERM)
wp eval "apply_filters('mp_case_change_status', null, $CID_TERM, 'zamknięte', 'nowe', 1, null);" >/dev/null 2>&1
POL_TERM0=$(q "SELECT sla_policy_version FROM wp_mp_case_sla WHERE case_id=$CID_TERM")
DL_TERM0=$(q "SELECT IFNULL(deadline_at,'NULL') FROM wp_mp_case_sla WHERE case_id=$CID_TERM")

CID_NEW=$(mkcase new@example.com REC-NEW)                        # nowe; kotwice C cofamy 10 dni wstecz
wp db query "UPDATE wp_mp_service_cases SET status_changed_at = NOW()-INTERVAL 10 DAY WHERE id=$CID_NEW" >/dev/null 2>&1
# jego wiersz SLA nadal ma deadline z prowizji (anchor=teraz => przyszlosc), markery NULL

# ── 2. Zmiana SlaConfig: nowe 24h -> 48h, policy 1 -> 2 ───────────────────────
wp eval 'update_option("mp_automator_sla_core", array("nowe"=>array("sla_hours"=>48))); update_option("mp_automator_sla_policy_version", 2);' >/dev/null 2>&1

# ── 3. (f) BRAK DOSTEPU: lowpriv i zly nonce NIE przeliczaja ──────────────────
recalc_as "$LOW" valid
recalc_as "$ADM" bad
POL_OPEN_GATE=$(q "SELECT sla_policy_version FROM wp_mp_case_sla WHERE case_id=$CID_OPEN")
EV_GATE=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SLA_RECALCULATED'")
[ "$POL_OPEN_GATE" = "1" ] && [ "$EV_GATE" = "0" ] && ok "(f) lowpriv/zly-nonce => ZERO przeliczenia (policy nietknieta, brak audytu)" || bad "(f) gate przepuscil! (policy=$POL_OPEN_GATE, ev=$EV_GATE)"

# ── 4. PRZELICZ SLA jako sysadmin (valid) ────────────────────────────────────
recalc_as "$ADM" valid

# (a) otwarte => nowe terminy + policy=2
DL_OPEN_1=$(q "SELECT deadline_at FROM wp_mp_case_sla WHERE case_id=$CID_OPEN")
POL_OPEN_1=$(q "SELECT sla_policy_version FROM wp_mp_case_sla WHERE case_id=$CID_OPEN")
GAP=$(q "SELECT TIMESTAMPDIFF(HOUR, status_changed_at, s.deadline_at) FROM wp_mp_service_cases c JOIN wp_mp_case_sla s ON s.case_id=c.id WHERE c.id=$CID_OPEN")
[ "$POL_OPEN_1" = "2" ] && [ "$DL_OPEN_1" != "$DL_OPEN_0" ] && [ "$GAP" = "48" ] && ok "(a) OPEN: deadline przeliczony (anchor+48h), policy=2 na wierszu" || bad "(a) OPEN zle (policy=$POL_OPEN_1 gap=${GAP}h zmiana=$([ "$DL_OPEN_1" != "$DL_OPEN_0" ] && echo tak || echo nie))"

# (b) terminalne nietkniete
POL_TERM1=$(q "SELECT sla_policy_version FROM wp_mp_case_sla WHERE case_id=$CID_TERM")
DL_TERM1=$(q "SELECT IFNULL(deadline_at,'NULL') FROM wp_mp_case_sla WHERE case_id=$CID_TERM")
[ "$POL_TERM1" = "$POL_TERM0" ] && [ "$DL_TERM1" = "NULL" ] && ok "(b) TERMINALNE nietkniete (policy=$POL_TERM1 stara, deadline NULL)" || bad "(b) terminalna ruszona! (policy $POL_TERM0->$POL_TERM1, dl=$DL_TERM1)"

# (c) markery SENT nie zresetowane
RESENT1=$(q "SELECT CONCAT(reminder_sent_at IS NOT NULL, escalated_at IS NOT NULL) FROM wp_mp_case_sla WHERE case_id=$CID_SENT")
POL_SENT1=$(q "SELECT sla_policy_version FROM wp_mp_case_sla WHERE case_id=$CID_SENT")
[ "$RESENT1" = "11" ] && [ "$POL_SENT1" = "2" ] && ok "(c) SENT: markery NIE zresetowane (11) mimo przeliczenia (policy=2)" || bad "(c) markery ruszone! ($RESENT1, policy=$POL_SENT1)"

# (e) audyt SLA_RECALCULATED (kto/kiedy/ile)
EV=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SLA_RECALCULATED'")
EV_ACTOR=$(q "SELECT actor_id FROM wp_mp_workflow_events WHERE event_type='SLA_RECALCULATED' ORDER BY id DESC LIMIT 1")
EV_CNT=$(wp eval '$r=$GLOBALS["wpdb"]->get_var("SELECT payload FROM wp_mp_workflow_events WHERE event_type=\"SLA_RECALCULATED\" ORDER BY id DESC LIMIT 1"); $d=json_decode($r,true); echo (int)($d["cases_touched"]??-1);' 2>/dev/null | tr -d '[:space:]')
[ "$EV" = "1" ] && [ "$EV_ACTOR" = "$ADM" ] && [ "$EV_CNT" = "3" ] && ok "(e) audyt SLA_RECALCULATED: 1 event, actor=sysadm, cases_touched=3 (OPEN+SENT+NEW, TERM pominiety)" || bad "(e) audyt zly (ev=$EV actor=$EV_ACTOR/$ADM ile=$EV_CNT)"

# ── 5. (c+d) sweep PO przeliczeniu: SENT bez dubla, NEW nowo-przeterminowana=1 ─
NEW_ESC_before=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID_NEW AND event_type='SLA_ESCALATED'")
SENT_ESC_before=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID_SENT AND event_type='SLA_ESCALATED'")
capclear; sweep
POST=$(capcount)
NEW_MAIL_R=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID_NEW AND event_type='SLA_REMINDER_SENT'")
NEW_MAIL_E=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID_NEW AND event_type='SLA_ESCALATED'")
SENT_ESC_after=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID_SENT AND event_type='SLA_ESCALATED'")
[ "$POST" = "1" ] && ok "(c+d) sweep po przeliczeniu => 1 mail lacznie (tylko nowo-przeterminowana, SENT bez dubla)" || bad "(c+d) sweep wyslal $POST (oczek 1)"
[ "$NEW_MAIL_E" = "1" ] && [ "$NEW_MAIL_R" = "0" ] && ok "(d) NEW nowo-przeterminowana => 1 eskalacja, 0 przypomnien (flaga #8, nie dubel)" || bad "(d) NEW zle (R=$NEW_MAIL_R E=$NEW_MAIL_E)"
[ "$SENT_ESC_after" = "$SENT_ESC_before" ] && ok "(c) SENT: BRAK ponownej eskalacji po przeliczeniu (oś audytu bez dubla)" || bad "(c) SENT zdublowana eskalacja! ($SENT_ESC_before->$SENT_ESC_after)"

# ── Sprzatanie ────────────────────────────────────────────────────────────────
# KRYTYCZNE: przywroc DOMYSLNY SlaConfig (nowe=24h, policy=1) — inaczej ten test
# truje kolejne w wspoldzielonym srodowisku CI (d-seed/blok-s zakladaja defaulty).
wp eval 'delete_option("mp_automator_sla_core"); delete_option("mp_automator_sla_policy_version");' >/dev/null 2>&1
capclear; for u in "$COORD" "$ADM" "$LOW"; do wp user delete "$u" --yes >/dev/null 2>&1; done
echo ""
echo "D-P34D-PRZELICZ: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
