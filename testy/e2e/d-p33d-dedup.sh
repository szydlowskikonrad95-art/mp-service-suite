#!/usr/bin/env bash
# ZYWY DOWOD P3.3 dedup-okno: identyczny mail (adresat+WYRENDEROWANA tresc) w oknie
# jest POMIJANY (MAIL_DEDUPED); dwie ROZNE informacje NIGDY nie sa dedupowane.
# Okno konfigurowalne per typ (wiadomosci 300 s, domyslne 60 s). Dedup = best-effort
# (transient) — dotyczy WYLACZNIE maili zdarzeniowych, nie gwarancji SLA (tabela).
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
CAP="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
capclear() { : > "$CAP"; }
capcount() { if [ -s "$CAP" ]; then grep -c '' "$CAP" 2>/dev/null; else echo 0; fi; }

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Okna dedupu (jednostkowo) ─────────────────────────────────────────────
W1=$(wp eval 'echo MP\Automator\MailDedup::window_for("status_changed_client");' 2>/dev/null)
[ "$W1" = "60" ] && ok "okno domyslne = 60 s (status_changed_client)" || bad "zle okno domyslne ($W1)"
W2=$(wp eval 'echo MP\Automator\MailDedup::window_for("message_from_client");' 2>/dev/null)
[ "$W2" = "300" ] && ok "okno wiadomosci = 300 s (anty-spam: 5 wiad w 3 min != 5 maili)" || bad "zle okno wiadomosci ($W2)"
# override z opcji
wp eval 'update_option("mp_automator_dedup_windows", array("status_changed_client"=>10));' >/dev/null 2>&1
W3=$(wp eval 'echo MP\Automator\MailDedup::window_for("status_changed_client");' 2>/dev/null)
[ "$W3" = "10" ] && ok "override z opcji dziala (10 s)" || bad "override nie zadzialal ($W3)"
wp eval 'delete_option("mp_automator_dedup_windows");' >/dev/null 2>&1

# claim: okno 0 = brak dedupu; drugi identyczny w oknie = false
C1=$(wp eval 'echo MP\Automator\MailDedup::claim("a@b.com","tresc X",0) ? "1":"0";' 2>/dev/null)
[ "$C1" = "1" ] && ok "okno=0 => dedup wylaczony (zawsze wolno)" || bad "okno=0 blokuje"
K1=$(wp eval 'echo MP\Automator\MailDedup::claim("z@b.com","body1",60) ? "1":"0";' 2>/dev/null)
K2=$(wp eval 'echo MP\Automator\MailDedup::claim("z@b.com","body1",60) ? "1":"0";' 2>/dev/null)
K3=$(wp eval 'echo MP\Automator\MailDedup::claim("z@b.com","body2",60) ? "1":"0";' 2>/dev/null)
{ [ "$K1" = "1" ] && [ "$K2" = "0" ] && [ "$K3" = "1" ]; } && ok "claim: 1. wolno, 2. identyczny=BLOK, inny body=wolno" || bad "claim zle dziala ($K1$K2$K3)"

# ── 1. Integracja: ten sam status_changed 2x w oknie => 1 mail + MAIL_DEDUPED ─
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); delete_option("mp_automator_mail_templates"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
CID=$(mkcase dedup@example.com DED-1)
capclear
wp eval "apply_filters('mp_case_change_status', null, $CID, 'w analizie', 'nowe', 1, null);" >/dev/null 2>&1
# ponowna IDENTYCZNA emisja status_changed (ten sam old->new, ta sama minuta => identyczny body)
wp eval "do_action('mp_case_status_changed', $CID, 'nowe', 'w analizie', 1);" >/dev/null 2>&1
[ "$(capcount)" = "1" ] && ok "2x identyczna zmiana w oknie => DOKLADNIE 1 mail (2. zdedupowany)" || bad "dedup nie zadzialal ($(capcount) maili)"
MD=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='MAIL_DEDUPED'")
[ "$MD" = "1" ] && ok "MAIL_DEDUPED zaksiegowany (audyt: czemu klient nie dostal 2. maila)" || bad "brak MAIL_DEDUPED ($MD)"

# ── 2. ROZNY status w oknie => osobny mail (rozne informacje NIGDY dedupowane) ─
capclear
wp eval "apply_filters('mp_case_change_status', null, $CID, 'zaakceptowane', 'w analizie', 1, null);" >/dev/null 2>&1
[ "$(capcount)" = "1" ] && ok "rozny status w oknie => osobny mail (inny body, nie dedupowany)" || bad "rozna informacja zdedupowana! ($(capcount))"

# NO-PII w MAIL_DEDUPED
PAY=$(q "SELECT payload FROM wp_mp_workflow_events WHERE event_type='MAIL_DEDUPED' LIMIT 1")
echo "$PAY" | grep -q 'dedup@example.com' && bad "adres w logu MAIL_DEDUPED (PII!)" || ok "MAIL_DEDUPED bez adresu (NO-PII)"

capclear
echo ""
echo "D-P33D-DEDUP: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
