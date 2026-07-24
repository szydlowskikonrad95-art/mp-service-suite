#!/usr/bin/env bash
# ZYWY DOWOD (przebieg krok 5 — „silnik regul NADAJE priorytet"): akcja reguly
# set_priority na case_created ustawia priorytet sprawy (kontrakt C mp_case_set_priority),
# loguje PRIORITY_CHANGED. Sprawa niepasujaca => priorytet domyslny 'normal'. Priorytet
# nadany PRZED wierszem SLA (RuleEngine hook=10 < Sla=20) => termin liczy sie z priorytetu
# (high => krotszy). Idempotencja + walidacja (INVALID_PRIORITY). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

mk() { # $1=kind $2=email $3=serial
	local out cid tok
	out=$(wp mp case-create --kind="$1" --email="$2" --name='Jan Kowalski' --serial="$3" --document='FV/2026/9' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\\Intake\\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Czysty stan + seed domyslny + reguła set_priority (rodzaj=reklamacja => high) ──
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
RID=$(wp eval "echo MP\\Automator\\Rules::insert(array('trigger_type'=>'case_created','condition_key'=>'rodzaj','condition_operator'=>'equals','condition_value'=>'reklamacja','action_type'=>'set_priority','action_config'=>array('priority'=>'high'),'priority'=>5,'enabled'=>1,'source'=>'user'));" 2>/dev/null)
[ -n "$RID" ] && ok "reguła set_priority zasiana (rodzaj=reklamacja => high, id=$RID)" || bad "reguła set_priority nie utworzona"

# ── 1. Sprawa PASUJACA (reklamacja) => silnik nadal priorytet high ───────────
A=$(mk reklamacja a@example.com PRIO-A)
PA=$(q "SELECT priority FROM wp_mp_service_cases WHERE id=$A")
[ "$PA" = "high" ] && ok "silnik NADAL priorytet 'high' sprawie pasujacej (reklamacja)" || bad "priorytet nie nadany ($PA)"
EV=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$A AND event_type='PRIORITY_CHANGED'")
[ "$EV" = "1" ] && ok "event PRIORITY_CHANGED zapisany w historii" || bad "brak/za duzo PRIORITY_CHANGED ($EV)"
RE=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$A AND event_type='RULE_EXECUTED' AND payload LIKE '%set_priority%'")
[ "$RE" != "0" ] && ok "RULE_EXECUTED set_priority (audyt D)" || bad "brak audytu set_priority ($RE)"

# ── 2. Sprawa NIEPASUJACA (zapytanie) => priorytet domyslny 'normal' ─────────
B=$(mk zapytanie b@example.com PRIO-B)
PB=$(q "SELECT priority FROM wp_mp_service_cases WHERE id=$B")
[ "$PB" = "normal" ] && ok "sprawa niepasujaca => priorytet domyslny 'normal' (silnik nie rusza)" || bad "priorytet niepasujacej zly ($PB)"
EVB=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$B AND event_type='PRIORITY_CHANGED'")
[ "$EVB" = "0" ] && ok "niepasujaca: ZERO PRIORITY_CHANGED" || bad "niepasujaca ma PRIORITY_CHANGED ($EVB)"

# ── 3. SLA odzwierciedla priorytet (high nadany PRZED policzeniem terminu) ────
# Kontrola: druga reklamacja przy WYLACZONEJ regule => normal; deadline high < normal.
DA=$(q "SELECT deadline_at FROM wp_mp_case_sla WHERE case_id=$A")
wp db query "UPDATE wp_mp_workflow_rules SET enabled=0 WHERE id=$RID" >/dev/null 2>&1
C=$(mk reklamacja c@example.com PRIO-C)
PC=$(q "SELECT priority FROM wp_mp_service_cases WHERE id=$C")
DC=$(q "SELECT deadline_at FROM wp_mp_case_sla WHERE case_id=$C")
[ "$PC" = "normal" ] && ok "reguła wylaczona => reklamacja C ma 'normal' (kontrola)" || bad "kontrola: C priorytet $PC"
if [ -n "$DA" ] && [ -n "$DC" ]; then
	[ "$DA" \< "$DC" ] && ok "SLA odzwierciedla priorytet: deadline high ($DA) < deadline normal ($DC) — priorytet nadany PRZED terminem" || bad "deadline high NIE krotszy (high=$DA normal=$DC)"
else
	bad "brak wierszy SLA do porownania (high=$DA normal=$DC)"
fi

# ── 4. Idempotencja + walidacja (kontrakt bezposrednio) ──────────────────────
UNCH=$(wp eval "\$r=apply_filters('mp_case_set_priority', null, $A, 'high', 0); echo (!empty(\$r['success']) && !empty(\$r['unchanged']))?'1':'0';" 2>/dev/null)
[ "$UNCH" = "1" ] && ok "idempotencja: ten sam priorytet => success + unchanged (bez nowego zdarzenia)" || bad "idempotencja zla ($UNCH)"
EV2=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$A AND event_type='PRIORITY_CHANGED'")
[ "$EV2" = "1" ] && ok "idempotencja: brak DODATKOWEGO PRIORITY_CHANGED (nadal 1)" || bad "idempotencja dopisala event ($EV2)"
INV=$(wp eval "\$r=apply_filters('mp_case_set_priority', null, $A, 'krytyczny', 0); echo (empty(\$r['success']) && 'INVALID_PRIORITY'===(\$r['error_code']??''))?'1':'0';" 2>/dev/null)
[ "$INV" = "1" ] && ok "walidacja: nieznany priorytet => INVALID_PRIORITY (odmowa)" || bad "walidacja priorytetu zla ($INV)"

echo ""
echo "D-P31-PRIORYTET: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
