#!/usr/bin/env bash
# ZYWY DOWOD D1 (koordynator, 2026-08-05): podpowiedz ekranu regul uczy klucza
# `recipient_ref` ({"template_key":"...","recipient_ref":"agent"} —
# SettingsScreen.php:526), a silnik czytal TYLKO `recipient` z domyslna 'client'
# (RuleEngine.php:638). Regula powiadomienia utworzona DOKLADNIE wg podpowiedzi
# wysylala WEWNETRZNY szablon pracowniczy DO KLIENTA. FIX: `recipient_ref` jest
# pelnoprawnym aliasem `recipient` (jawny `recipient` wygrywa, gdy sa oba);
# regula bez zadnego klucza dziala jak dotad (domyslnie client — kompatybilnosc).
#
# Kalibracja WBUDOWANA: asserty A1/A2 PADAJA na kodzie sprzed naprawy (mail
# szedl do klienta, nie do pracownika). B i C to kontrole kierunku: jawny
# `recipient:client` oraz regula BEZ klucza odbiorcy dzialaja bez zmian.
# Izolacja: tabela regul czyszczona — w przebiegu zyje WYLACZNIE regula testowa
# (seedy domyslne tez mailuja pracownika i daloby to falszywa zielen).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

CAP="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
capclear() { : > "$CAP"; }
has_to()   { grep -q "\"to\":\"$1\"" "$CAP" 2>/dev/null; }

mkcase() { # $1=email $2=nazwa $3=serial → case_id (zweryfikowana)
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name="$2" --serial="$3" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\\Intake\\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}
cs_actor() { wp eval "apply_filters('mp_case_change_status', null, $1, '$2', '$3', $4);" >/dev/null 2>&1; }
# regula notify z zadana konfiguracja JSON (przez produkcyjne Rules::insert).
mkrule() { # $1=fragment PHP tablicy action_config
	wp eval "echo MP\\Automator\\Rules::insert(array('trigger_type'=>'status_changed','action_type'=>'notify','action_config'=>array($1),'priority'=>10,'enabled'=>1));" 2>/dev/null
}

# ── 0. Czysty stan: szablony z seedu, tabela regul PUSTA (izolacja) ──────────
# rate_counters TEZ: siedzi tam okno MailDedup — po resecie srv_counters numery
# SRV startuja od nowa, wiec mail z kolejnego przebiegu jest IDENTYCZNY jak
# z poprzedniego i dedup by go pominal (falszywa czerwien nie-z-tej-wady).
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_rate_counters;" >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); delete_option("mp_automator_mail_templates"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_workflow_rules" >/dev/null 2>&1

AGENT_MAIL='agent-d1@example.com'
AGENT=$(wp user get agentd1 --field=ID 2>/dev/null); [ -z "$AGENT" ] && AGENT=$(wp user create agentd1 "$AGENT_MAIL" --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
COORD=$(wp user get coordd1 --field=ID 2>/dev/null); [ -z "$COORD" ] && COORD=$(wp user create coordd1 'coord-d1@example.com' --role=mp_coordinator --user_pass=x --porcelain 2>/dev/null)

# ── A. KALIBRACJA D1: regula DOKLADNIE wg podpowiedzi ekranu ─────────────────
# {"template_key":"status_changed_staff","recipient_ref":"agent"} — jak w
# placeholderze „Powiadomienie: {"template_key":"...","recipient_ref":"agent"}".
RID=$(mkrule "'template_key'=>'status_changed_staff','recipient_ref'=>'agent'")
[ -n "$RID" ] && [ "$RID" != "0" ] && ok "A0: regula wg podpowiedzi zalozona (id=$RID)" || bad "A0: nie udalo sie zalozyc reguly"

CID_A=$(mkcase 'klient-d1a@example.com' 'Jan Klient' 'D1-A')
wp eval "apply_filters('mp_case_assign', null, $CID_A, $AGENT, 1);" >/dev/null 2>&1
[ "$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID_A")" = "$AGENT" ] && ok "A0b: sprawa przydzielona pracownikowi" || bad "A0b: przydzial nie chwycil"

capclear
cs_actor "$CID_A" 'w analizie' 'nowe' "$COORD"
has_to "$AGENT_MAIL" \
	&& ok "A1: mail poszedl do PRACOWNIKA (recipient_ref z podpowiedzi dziala)" \
	|| bad "A1: pracownik NIE dostal maila — recipient_ref zignorowany"
has_to 'klient-d1a@example.com' \
	&& bad "A2: WEWNETRZNY szablon pracowniczy poszedl DO KLIENTA (domyslka 'client' przykryla recipient_ref)" \
	|| ok "A2: klient nie dostal cudzego, wewnetrznego maila"

# ── B. KONTROLA: jawny recipient:client dziala bez zmian ─────────────────────
wp db query "DELETE FROM wp_mp_workflow_rules" >/dev/null 2>&1
mkrule "'template_key'=>'status_changed_client','recipient'=>'client'" >/dev/null
CID_B=$(mkcase 'klient-d1b@example.com' 'Ewa Klient' 'D1-B')
capclear
cs_actor "$CID_B" 'w analizie' 'nowe' "$COORD"
has_to 'klient-d1b@example.com' \
	&& ok "B1: jawny recipient:client — mail do klienta jak dotad" \
	|| bad "B1: jawny recipient:client przestal dzialac"

# ── C. KOMPATYBILNOSC WSTECZ: regula BEZ zadnego klucza odbiorcy => client ───
wp db query "DELETE FROM wp_mp_workflow_rules" >/dev/null 2>&1
mkrule "'template_key'=>'status_changed_client'" >/dev/null
CID_C=$(mkcase 'klient-d1c@example.com' 'Ola Klient' 'D1-C')
capclear
cs_actor "$CID_C" 'w analizie' 'nowe' "$COORD"
has_to 'klient-d1c@example.com' \
	&& ok "C1: regula bez klucza odbiorcy dalej mailuje klienta (domyslka zachowana)" \
	|| bad "C1: domyslka 'client' zepsuta — istniejace reguly bez klucza przestaly dzialac"

# ── D. Jawny recipient WYGRYWA, gdy podano oba klucze ────────────────────────
wp db query "DELETE FROM wp_mp_workflow_rules" >/dev/null 2>&1
mkrule "'template_key'=>'status_changed_client','recipient'=>'client','recipient_ref'=>'agent'" >/dev/null
CID_D=$(mkcase 'klient-d1d@example.com' 'Iga Klient' 'D1-D')
wp eval "apply_filters('mp_case_assign', null, $CID_D, $AGENT, 1);" >/dev/null 2>&1
capclear
cs_actor "$CID_D" 'w analizie' 'nowe' "$COORD"
has_to 'klient-d1d@example.com' \
	&& ok "D1: przy obu kluczach wygrywa jawny recipient (mail do klienta)" \
	|| bad "D1: recipient_ref przykryl jawny recipient"

wp db query "DELETE FROM wp_mp_workflow_rules" >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1

echo "── D1: PASS=$PASS FAIL=$FAIL ──"
if [ "$(( PASS + FAIL ))" -lt 7 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane min. 7."
	exit 2
fi
[ "$FAIL" -eq 0 ]
