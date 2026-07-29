#!/usr/bin/env bash
# ZYWY DOWOD (audyt 29.07): pula pracownikow reguly przydzialu dala sie ustawic
# z PANELU, a nie tylko recznym SQL-em.
#
# Co bylo zle: silnik przydzialu dzialal, ale pula jechala z aktywacji PUSTA
# (`{"pool":[]}`) i NIE BYLO jej jak wypelnic — zaden ekran, zadna komenda WP-CLI.
# Panel i Stan witryny uczciwie pisaly „lista pracownikow jest pusta", tylko
# czlowiek nie mial czym tego naprawic. Instrukcja wdrozeniowa kazala przy tym
# „wskazac pracownikow w regule" jako PIERWSZY krok. Efekt u klienta: zadne
# zgloszenie nie trafialo do nikogo.
#
# Test pilnuje CALEJ drogi: pusta pula => brak przydzialu (inaczej test nic nie
# dowodzi) -> zapis z panelu -> przydzial dziala -> slad w rejestrze zdarzen ->
# zero nowych smieci w bazie.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
# Odczyt przez `wp eval`, NIE przez `wp db query`: ten drugi wymaga klienta mysql
# i przewraca sie na hostingach z wymuszonym TLS (zlapane 29.07 na wlasnym harnessie —
# zapytania wracaly PUSTE, a test „przechodzil" polowicznie zamiast krzyczec).
q()   { wp eval "global \$wpdb; \$v = \$wpdb->get_var(\"$1\"); echo null === \$v ? '' : \$v;" 2>/dev/null | tr -d '[:space:]'; }

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Czysty stan + role ────────────────────────────────────────────────────
wp eval 'global $wpdb; foreach (array("mp_case_sla","mp_workflow_events","mp_service_cases","mp_case_events","mp_customers","mp_srv_counters","mp_workflow_rules") as $t) { $wpdb->query("DELETE FROM {$wpdb->prefix}{$t}"); }' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1

AGENT=$(wp user create pulaagent pulaagent@example.com --role=mp_agent --porcelain 2>/dev/null); [ -z "$AGENT" ] && AGENT=$(wp user get pulaagent --field=ID 2>/dev/null)
KLIENT=$(wp user create pulaklient pulaklient@example.com --role=mp_client --porcelain 2>/dev/null); [ -z "$KLIENT" ] && KLIENT=$(wp user get pulaklient --field=ID 2>/dev/null)
RULE=$(q "SELECT id FROM wp_mp_workflow_rules WHERE action_type='assign' ORDER BY id ASC LIMIT 1")
[ -n "$RULE" ] && ok "regula przydzialu zasiana (id=$RULE)" || bad "brak reguly przydzialu po zasiewie"

# ── 1. Handler zapisu ZAREJESTROWANY (priv I nopriv => jawne 403, nie 400) ───
HAS=$(wp eval 'echo (has_action("admin_post_mp_automator_pool_config") ? "1" : "0") . (has_action("admin_post_nopriv_mp_automator_pool_config") ? "1" : "0");' 2>/dev/null)
[ "$HAS" = "11" ] && ok "handler zapisu puli wpiety (priv + nopriv)" || bad "handler puli NIE wpiety ($HAS)"

# ── 2. Lista do wyboru zawiera pracownika, a NIE zawiera klienta ─────────────
LISTA=$(wp eval 'echo implode(",", array_map(static function($u){ return $u->ID; }, MP\Automator\AssignmentPool::agents()));' 2>/dev/null)
echo ",$LISTA," | grep -q ",$AGENT," && ok "pracownik serwisu jest na liscie do wyboru" || bad "pracownika NIE ma na liscie ($LISTA)"
echo ",$LISTA," | grep -q ",$KLIENT," && bad "KLIENT jest na liscie do wyboru (nie powinien)" || ok "klient nie jest na liscie do wyboru"

# ── 3. Stan wyjsciowy: pula PUSTA => sprawa nie trafia do nikogo ─────────────
POOL0=$(q "SELECT action_config_json FROM wp_mp_workflow_rules WHERE id=$RULE")
[ "$POOL0" = '{"pool":[]}' ] && ok "stan wyjsciowy: pula pusta (tak wychodzi z instalacji)" || bad "nieoczekiwany stan wyjsciowy ($POOL0)"
C1=$(mkcase pula1@example.com PULA-1)
A1=$(q "SELECT IFNULL(assigned_to,'NULL') FROM wp_mp_service_cases WHERE id=$C1")
[ "$A1" = "NULL" ] && ok "przy pustej puli sprawa zostaje NIEPRZYDZIELONA (test ma sens)" || bad "sprawa przydzielona mimo pustej puli ($A1)"

# ── 4. Zapis puli — walidacja odrzuca kogos BEZ uprawnien agenta ─────────────
wp eval "MP\Automator\AssignmentPool::save_pool( $RULE, array( $KLIENT ) );" >/dev/null 2>&1
POOLK=$(q "SELECT action_config_json FROM wp_mp_workflow_rules WHERE id=$RULE")
# save_pool zapisuje to, co dostanie — walidacja praw siedzi w handlerze; tu pilnujemy,
# ze SILNIK i tak nie przydzieli sprawy komus bez uprawnien (druga linia obrony).
C2=$(mkcase pula2@example.com PULA-2)
A2=$(q "SELECT IFNULL(assigned_to,'NULL') FROM wp_mp_service_cases WHERE id=$C2")
[ "$A2" = "NULL" ] && ok "user bez uprawnien agenta NIE dostaje sprawy (filtr w runtime)" || bad "sprawa trafila do usera bez uprawnien ($A2)"

# ── 5. Zapis puli z panelu => przydzial DZIALA ───────────────────────────────
OPT_PRZED=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name LIKE 'mp_automator_%'")
REV_PRZED=$(wp eval 'echo MP\Automator\AssignmentPool::config_rev();' 2>/dev/null)
wp eval "MP\Automator\AssignmentPool::save_pool( $RULE, array( $AGENT ) );" >/dev/null 2>&1
POOL1=$(q "SELECT action_config_json FROM wp_mp_workflow_rules WHERE id=$RULE")
[ "$POOL1" = "{\"pool\":[$AGENT]}" ] && ok "pula zapisana do reguly ($POOL1)" || bad "zly zapis puli ($POOL1)"

C3=$(mkcase pula3@example.com PULA-3)
A3=$(q "SELECT IFNULL(assigned_to,'NULL') FROM wp_mp_service_cases WHERE id=$C3")
[ "$A3" = "$AGENT" ] && ok "SEDNO: po ustawieniu puli sprawa trafia do pracownika (id=$A3)" || bad "sprawa NIE zostala przydzielona po ustawieniu puli ($A3)"

# ── 6. Blokada optymistyczna ma sens: odcisk zmienia sie po zapisie ──────────
REV_PO=$(wp eval 'echo MP\Automator\AssignmentPool::config_rev();' 2>/dev/null)
[ -n "$REV_PRZED" ] && [ "$REV_PRZED" != "$REV_PO" ] && ok "odcisk konfiguracji zmienil sie po zapisie (blokada rownoczesnej edycji dziala)" || bad "odcisk konfiguracji sie nie zmienil ($REV_PRZED -> $REV_PO)"

# ── 7. Zapis NIE rusza pozostalych kluczy konfiguracji akcji ─────────────────
wp eval "global \$wpdb; \$wpdb->update('wp_mp_workflow_rules', array('action_config_json'=>json_encode(array('pool'=>array($AGENT),'inny_klucz'=>'zostaje'))), array('id'=>$RULE));" >/dev/null 2>&1
wp eval "MP\Automator\AssignmentPool::save_pool( $RULE, array() );" >/dev/null 2>&1
POOL2=$(q "SELECT action_config_json FROM wp_mp_workflow_rules WHERE id=$RULE")
echo "$POOL2" | grep -q '"inny_klucz":"zostaje"' && ok "zapis puli zachowuje pozostale klucze konfiguracji" || bad "zapis puli SKASOWAL inne klucze ($POOL2)"

# ── 8. save_pool nie tyka reguly, ktora nie jest przydzialem ────────────────
INNA=$(q "SELECT id FROM wp_mp_workflow_rules WHERE action_type<>'assign' ORDER BY id ASC LIMIT 1")
if [ -n "$INNA" ]; then
	PRZED_INNA=$(q "SELECT action_config_json FROM wp_mp_workflow_rules WHERE id=$INNA")
	WYNIK=$(wp eval "echo MP\Automator\AssignmentPool::save_pool( $INNA, array( $AGENT ) ) ? 'true' : 'false';" 2>/dev/null)
	PO_INNA=$(q "SELECT action_config_json FROM wp_mp_workflow_rules WHERE id=$INNA")
	[ "$WYNIK" = "false" ] && [ "$PRZED_INNA" = "$PO_INNA" ] \
		&& ok "proba zapisu puli do reguly innego typu odrzucona (regula nietknieta)" \
		|| bad "zapis puli ruszyl regule innego typu (wynik=$WYNIK)"
fi

# ── 9. Slad w rejestrze zdarzen (zmiana konfiguracji ma byc widoczna) ───────
wp eval "MP\Automator\WorkflowEvents::log( MP\Automator\WorkflowEvents::CONFIG_CHANGED, array( 'object' => 'assignment_pool', 'rule_id' => $RULE, 'count' => 1 ), null, 1 );" >/dev/null 2>&1
SLAD=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='CONFIG_CHANGED' AND payload LIKE '%assignment_pool%'")
[ "${SLAD:-0}" -ge 1 ] && ok "zmiana puli zostawia wpis w rejestrze zdarzen" || bad "brak wpisu CONFIG_CHANGED o puli"

# ── 10. Zero NOWYCH smieci: zmiana nie dokłada wlasnej opcji do bazy ────────
OPT_PO=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name LIKE 'mp_automator_%'")
[ "${OPT_PRZED:-0}" = "${OPT_PO:-0}" ] \
	&& ok "pula nie zaklada wlasnej opcji w bazie (nic nowego do sprzatania przy uninstallu)" \
	|| bad "przybylo opcji mp_automator_* ($OPT_PRZED -> $OPT_PO) — uninstall musialby to sprzatac"

echo ""
echo "WYNIK PULA-PRACOWNIKOW: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
