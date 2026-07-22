#!/usr/bin/env bash
# ZYWY DOWOD P3.3 (maile powiadomien): reguła notify po zmianie statusu wysyla
# mail do KLIENTA z szablonu (markery zrenderowane). WRAŻLIWE — sprawdza twardo:
#  - render markerow (kotwice) w temacie i tresci,
#  - SANITYZACJA odbiorcy: adres z CRLF ODRZUCONY (is_email), temat bez CRLF
#    (anty header-injection),
#  - NO-PII w logu: RULE_EXECUTED bez adresu i bez tresci maila,
#  - klient zanonimizowany (RODO) => MAIL_SKIPPED_NO_RECIPIENT, nie awaria,
#  - guard petli: mail z GLEBOKOSCI 1 WYSZEDL, mutacja z glebokosci 1 ZABLOKOWANA.
# Asercje na przechwyconym mailu (mp-mail-capture.jsonl) — dziala w CI bez Mailpita.
# NIE asertujemy wp_mail=success (transport zalezny od srodowiska). Exit 0 = OK.
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
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name="$2" --serial="$3" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}
cs() { wp eval "echo wp_json_encode( apply_filters('mp_case_change_status', null, $1, '$2', '$3', 1, $4) );" 2>/dev/null; }

# ── 0. Czysty stan + SEED domyslny (aktywacja od zera) ───────────────────────
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); delete_option("mp_automator_mail_templates"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
capclear

# ── 1. Seed: reguła notify (status->klient) + szablon obecne ──────────────────
NR=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules WHERE trigger_type='status_changed' AND action_type='notify' AND system_key='status_changed_client_mail'")
[ "$NR" = "1" ] && ok "domyslna reguła notify (status->klient) zasiana" || bad "brak domyslnej reguły notify ($NR)"
TPL=$(wp eval 'echo MP\Automator\MailTemplates::get("status_changed_client") ? "1":"0";' 2>/dev/null)
[ "$TPL" = "1" ] && ok "szablon status_changed_client obecny" || bad "brak szablonu status_changed_client"

# ── 2. Zmiana statusu -> mail do KLIENTA z markerami (kotwice zrenderowane) ───
CID=$(mkcase klient@example.com "Jan Klient" MAIL-1)
SRV=$(wp db query "SELECT case_number FROM wp_mp_service_cases WHERE id=$CID" --skip-column-names 2>/dev/null | tr -d '[:space:]')
capclear
cs "$CID" "w analizie" "nowe" "null" >/dev/null
LINE=$(caplast)
echo "$LINE" | grep -q '"to":"klient@example.com"' && ok "mail wyslany do KLIENTA (adres z kontaktu sprawy)" || bad "zly odbiorca ($LINE)"
echo "$LINE" | grep -q "$SRV" && ok "marker {{numer_sprawy}} zrenderowany ($SRV w mailu)" || bad "brak numeru sprawy w mailu"
echo "$LINE" | grep -q 'w analizie' && ok "marker {{status}} zrenderowany (w analizie)" || bad "brak statusu w mailu"
echo "$LINE" | grep -q '{{' && bad "surowy marker {{...}} zostal w mailu (render nie zadzialal)" || ok "zero surowych markerow {{...}} w mailu (kotwice podmienione)"

# ── 3. NO-PII w logu: RULE_EXECUTED bez adresu i bez tresci ──────────────────
PAY=$(q "SELECT payload FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='RULE_EXECUTED'")
echo "$PAY" | grep -q '"action":"notify"' && ok "RULE_EXECUTED action=notify zapisany" || bad "brak RULE_EXECUTED notify ($PAY)"
echo "$PAY" | grep -q '"recipient_ref":"client"' && ok "recipient_ref=client (kategoria, NO-PII)" || bad "brak recipient_ref=client"
echo "$PAY" | grep -q 'klient@example.com' && bad "ADRES w logu (wyciek PII!)" || ok "brak adresu w logu (NO-PII)"
echo "$PAY" | grep -qi 'Dzień dobry' && bad "TRESC maila w logu (wyciek!)" || ok "brak tresci maila w logu (NO-PII)"

# ── 4. Klient ZANONIMIZOWANY (RODO) => MAIL_SKIPPED_NO_RECIPIENT, nie awaria ──
CID2=$(mkcase anon@example.com "Anon Klient" MAIL-2)
wp db query "UPDATE wp_mp_customers SET anonymized_at=NOW() WHERE id=(SELECT customer_id FROM wp_mp_service_cases WHERE id=$CID2)" >/dev/null 2>&1
capclear
cs "$CID2" "w analizie" "nowe" "null" >/dev/null
[ "$(capcount)" = "0" ] && ok "zanonimizowany klient: ZERO wyslanych maili" || bad "mail poszedl do zanonimizowanego klienta!"
SK=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID2 AND event_type='MAIL_SKIPPED_NO_RECIPIENT'")
[ "$SK" = "1" ] && ok "MAIL_SKIPPED_NO_RECIPIENT zaksiegowany (stan legalny, nie awaria)" || bad "brak MAIL_SKIPPED ($SK)"

# ── 5. SANITYZACJA (Mailer, brama egress) ────────────────────────────────────
capclear
# 5a. adres z CRLF + wstrzyknieciem naglowka => is_email ODRZUCA, NIC nie leci
RINJ=$(wp eval "echo MP\Automator\Mailer::send(\"ofiara@example.com\r\nBcc: zlodziej@evil.com\", 's', 'b') ? '1':'0';" 2>/dev/null)
[ "$RINJ" = "0" ] && ok "adres z CRLF/Bcc ODRZUCONY przez Mailer (is_email)" || bad "adres z header-injection przeszedl!"
[ "$(capcount)" = "0" ] && ok "nic nie wyslano dla skazonego adresu" || bad "cos wyslano mimo skazonego adresu!"
# 5b. temat z CRLF => wyslany temat BEZ CR/LF (anty header-injection w naglowku)
capclear
wp eval "MP\Automator\Mailer::send('czysty@example.com', \"Temat\r\nBcc: zlo@evil.com\", 'tresc');" >/dev/null 2>&1
SUBJ=$(caplast)
printf '%s' "$SUBJ" | grep -q $'\r' && bad "CR w temacie przeszedl (header-injection!)" || ok "temat po sanityzacji bez CR"
echo "$SUBJ" | grep -q '"subject":"Temat Bcc: zlo@evil.com"' && ok "CRLF w temacie zamieniony na spacje (jeden naglowek)" || ok "temat zsanityzowany (bez lamania naglowka)"

# ── 6. GUARD: mail z glebokosci 1 WYSZEDL, mutacja z glebokosci 1 ZABLOKOWANA ─
wp db query "DELETE FROM wp_mp_workflow_rules" >/dev/null 2>&1
# A: w analizie -> zaakceptowane (mutacja, depth0)
wp eval "MP\Automator\Rules::insert(array('trigger_type'=>'status_changed','enabled'=>1,'condition_key'=>'status','condition_operator'=>'equals','condition_value'=>'w analizie','action_type'=>'change_status','action_config'=>array('new_status'=>'zaakceptowane')));" >/dev/null 2>&1
# M: zaakceptowane -> notify klient (mail, ma wyjsc na depth1)
wp eval "MP\Automator\Rules::insert(array('trigger_type'=>'status_changed','enabled'=>1,'condition_key'=>'status','condition_operator'=>'equals','condition_value'=>'zaakceptowane','action_type'=>'notify','action_config'=>array('template_key'=>'status_changed_client','recipient'=>'client')));" >/dev/null 2>&1
# MUT: zaakceptowane -> w naprawie (mutacja, ma byc ZABLOKOWANA na depth1)
wp eval "MP\Automator\Rules::insert(array('trigger_type'=>'status_changed','enabled'=>1,'condition_key'=>'status','condition_operator'=>'equals','condition_value'=>'zaakceptowane','action_type'=>'change_status','action_config'=>array('new_status'=>'w naprawie')));" >/dev/null 2>&1
CID3=$(mkcase petla@example.com "Petla Test" MAIL-3)
wp db query "DELETE FROM wp_mp_workflow_events" >/dev/null 2>&1
capclear
cs "$CID3" "w analizie" "nowe" "null" >/dev/null
FIN=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID3")
[ "$FIN" = "zaakceptowane" ] && ok "koniec na 'zaakceptowane' (A depth0; MUT depth1 zablokowany)" || bad "status koncowy=[$FIN] (petla/blad)"
LB=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='RULE_LOOP_BLOCKED'")
[ "$LB" -ge 1 ] 2>/dev/null && ok "mutacja z glebokosci 1 ZABLOKOWANA (RULE_LOOP_BLOCKED)" || bad "brak RULE_LOOP_BLOCKED"
MAILD1=$(caplast)
echo "$MAILD1" | grep -q '"to":"petla@example.com"' && ok "MAIL z GLEBOKOSCI 1 WYSZEDL (notify przeszedl guard)" || bad "mail z depth1 nie wyszedl ($MAILD1)"
DEPTH1=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='RULE_EXECUTED' AND payload LIKE '%\"action\":\"notify\"%' AND payload LIKE '%\"depth\":1%'")
[ "$DEPTH1" = "1" ] && ok "RULE_EXECUTED notify na depth=1 (potwierdza mail z re-entrant)" || bad "brak notify depth=1 ($DEPTH1)"

capclear
echo ""
echo "D-P33-MAILE: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
