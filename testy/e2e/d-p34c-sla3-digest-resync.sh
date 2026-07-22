#!/usr/bin/env bash
# ZYWY DOWOD P3.4 SLA-3 (resync + digest bez lawiny + tryb zaleglosci):
#  1) RESYNC po reaktywacji — markery w case_sla PRZEZYWAJA deactivate+activate;
#     sweep po reaktywacji NIE liczy od nowa juz wyslanych (0 dubli).
#  2) DIGEST bez lawiny — MASA spraw po terminie (>DIGEST_THRESHOLD) NIE wystrzeliwuje
#     seria osobnych maili: idzie JEDEN zbiorczy digest do koordynatora; kazda sprawa
#     i tak dostaje marker escalated_at + SLA_ESCALATED na osi C (os mowi prawde).
#  3) TRYB ZALEGLOSCI — idempotentnie, bez dubli (2. sweep = 0), oraz PONIZEJ progu
#     eskalacje ida per-sprawa (digest tylko dla masy).
# pre_wp_mail=true => transport env-niezalezny (filtr wp_mail i tak przechwytuje).
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

# ── 0. Czysty stan + koordynator + prog digestu ──────────────────────────────
wp db query "DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_workflow_rules;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); delete_option("mp_automator_mail_templates"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
COORD=$(wp user create swk swk@example.com --role=mp_coordinator --porcelain 2>/dev/null); [ -z "$COORD" ] && COORD=$(wp user get swk --field=ID 2>/dev/null)
THRESH=$(wp eval 'echo MP\Automator\Sla::DIGEST_THRESHOLD;' 2>/dev/null | tr -d '[:space:]')
ok "koordynator (id=$COORD), prog digestu=$THRESH"

# ── 1. RESYNC: markery przezywaja reaktywacje => sweep nie dubluje wyslanego ──
CID=$(mkcase rs1@example.com RSY-1); overdue "$CID"
capclear; sweep
[ "$(capcount)" = "1" ] && ok "retroaktywna => 1 eskalacja (baza pod resync)" || bad "oczek 1, jest $(capcount)"
RE=$(q "SELECT CONCAT(reminder_sent_at IS NOT NULL, escalated_at IS NOT NULL) FROM wp_mp_case_sla WHERE case_id=$CID")
[ "$RE" = "11" ] && ok "markery ustawione przed reaktywacja" || bad "markery zle ($RE)"
# REAKTYWACJA pluginu (deactivate = czysci crony; activate = role/schema/seed/cron) — NIE rusza markerow.
wp eval 'MP\Automator\Lifecycle::deactivate(); MP\Automator\Lifecycle::activate();' >/dev/null 2>&1
RE2=$(q "SELECT CONCAT(reminder_sent_at IS NOT NULL, escalated_at IS NOT NULL) FROM wp_mp_case_sla WHERE case_id=$CID")
[ "$RE2" = "11" ] && ok "RESYNC: markery PRZEZYLY reaktywacje (stan w tabeli, nie w pamieci)" || bad "reaktywacja zresetowala markery ($RE2)!"
capclear; sweep
[ "$(capcount)" = "0" ] && ok "RESYNC: sweep po reaktywacji NIE liczy od nowa (0 dubli wyslanych)" || bad "reaktywacja podwoila wysylke! ($(capcount))"

# ── 2. DIGEST bez lawiny: MASA (>prog) => JEDEN zbiorczy mail, nie seria ──────
N=$((THRESH + 3))                      # np. 8 gdy prog=5 => na pewno > prog
DIG_IDS=""
for i in $(seq 1 "$N"); do CID_I=$(mkcase "dg$i@example.com" "DGS-$i"); overdue "$CID_I"; DIG_IDS="$DIG_IDS $CID_I"; done
capclear; sweep
CNT=$(capcount)
[ "$CNT" = "1" ] && ok "DIGEST: $N spraw po terminie => 1 zbiorczy mail (nie $N osobnych = bez lawiny)" || bad "lawina/zle: $CNT maili (oczek 1 digest dla $N spraw)"
grep -q 'zbiorcza' "$CAP" 2>/dev/null && ok "DIGEST: temat zbiorczy (sla_escalation_digest), nie pojedynczy" || bad "to nie digest (brak tematu zbiorczego)"
# temat: "ESKALACJA zbiorcza: N zgloszen ..." — licznik N (ASCII int) = ile spraw scalono.
grep -q "zbiorcza: $N " "$CAP" 2>/dev/null && ok "DIGEST: temat raportuje dokladnie $N spraw (calosc scalona)" || bad "digest nie raportuje $N spraw w temacie"
ESC_OK=0; AXIS_OK=0
for cid in $DIG_IDS; do
	[ "$(q "SELECT escalated_at IS NOT NULL FROM wp_mp_case_sla WHERE case_id=$cid")" = "1" ] && ESC_OK=$((ESC_OK+1))
	[ "$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$cid AND event_type='SLA_ESCALATED'")" = "1" ] && AXIS_OK=$((AXIS_OK+1))
done
[ "$ESC_OK" = "$N" ] && ok "DIGEST: wszystkie $N spraw maja marker escalated_at (send-then-claim wsadowy)" || bad "tylko $ESC_OK/$N zajetych markerow"
[ "$AXIS_OK" = "$N" ] && ok "DIGEST: kazda z $N spraw ma SLA_ESCALATED na osi C (os mowi prawde: naprawde eskalowana)" || bad "tylko $AXIS_OK/$N zdarzen na osi"

# ── 3. TRYB ZALEGLOSCI: idempotencja (2. sweep = 0) ──────────────────────────
capclear; sweep
[ "$(capcount)" = "0" ] && ok "ZALEGLOSCI: 2. sweep => 0 maili (markery = idempotencja, bez dubli)" || bad "2. sweep dubluje! ($(capcount))"

# ── 4. PONIZEJ progu => eskalacje per-sprawa (digest tylko dla masy) ──────────
M=$((THRESH - 1)); [ "$M" -lt 1 ] && M=1
for i in $(seq 1 "$M"); do CID_S=$(mkcase "sm$i@example.com" "SML-$i"); overdue "$CID_S"; done
capclear; sweep
[ "$(capcount)" = "$M" ] && ok "PONIZEJ progu ($M<=$THRESH) => $M osobnych maili (bez digestu)" || bad "oczek $M osobnych, jest $(capcount)"

# ── Sprzatanie ────────────────────────────────────────────────────────────────
capclear; wp user delete "$COORD" --yes >/dev/null 2>&1
echo ""
echo "D-P34C-SLA3-DIGEST-RESYNC: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
