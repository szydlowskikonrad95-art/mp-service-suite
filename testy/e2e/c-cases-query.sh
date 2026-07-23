#!/usr/bin/env bash
# ZYWY DOWOD PR-A (funkcja kontraktowa mp_cases_query w C): paginowana lista spraw
# do raportow/eksportu D. Sprawdza: pola zminimalizowane (RODO — ZERO kontaktu),
# closed_at/handling_seconds liczone dla statusow TERMINALNYCH, paginacja + cap 500,
# filtry (status/kind/daty), RESPEKT ROLI (koordynator/admin=wszystko, mp_agent=tylko
# swoje, subscriber/anon=pusto). Chodzi tak samo na poligonie i w CI e2e.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

ADMIN=1

# ── 0. Czysty stan + ZERO regul (auto-przydzial P3.1 nie moze mieszac w scope) ──
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

# Uzytkownicy testowi (idempotentnie).
AGENT=$(wp user get agentq --field=ID 2>/dev/null)
[ -z "$AGENT" ] && AGENT=$(wp user create agentq agentq@example.com --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
SUB=$(wp user get subq --field=ID 2>/dev/null)
[ -z "$SUB" ] && SUB=$(wp user create subq subq@example.com --role=subscriber --user_pass=x --porcelain 2>/dev/null)

# Helper: utworz+zweryfikuj sprawe, echo case_id.
mk() { # $1=kind $2=email $3=serial
	local out cid tok
	out=$(wp mp case-create --kind="$1" --email="$2" --name='Jan Kowalski' --serial="$3" --document='FV/2026/9' --date='2026-05-01' --desc='opis' --return-reason='zmiana zdania' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\\Intake\\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}
chs() { wp eval "apply_filters('mp_case_change_status', null, $1, '$2', '$3', $ADMIN, $4);" >/dev/null 2>&1; }

# ── 1. Dane: 4 zweryfikowane sprawy w roznych statusach ──────────────────────
A=$(mk reklamacja a@example.com SER-A)              # zostaje 'nowe' (NIE terminal)
B=$(mk naprawa    b@example.com SER-B)              # -> zaakceptowane (NIE terminal)
chs "$B" "w analizie" "nowe" "null"; chs "$B" "zaakceptowane" "w analizie" "null"
C=$(mk reklamacja c@example.com SER-C)              # -> ODRZUCONE z kodem (TERMINAL)
chs "$C" "w analizie" "nowe" "null"; chs "$C" "odrzucone" "w analizie" "'duplikat'"
D=$(mk zwrot      d@example.com SER-D)              # -> ZAMKNIETE (TERMINAL)
chs "$D" "w analizie" "nowe" "null"; chs "$D" "zamknięte" "w analizie" "null"

# przydziel sprawe B agentowi (przez kontrakt C)
wp eval "apply_filters('mp_case_assign', null, $B, $AGENT, $ADMIN);" >/dev/null 2>&1

VER=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE identity_status='verified'")
[ "$VER" = "4" ] && ok "seed: 4 zweryfikowane sprawy" || bad "seed zly (verified=$VER)"

# ── 2. Admin (scope_all): total=4 ────────────────────────────────────────────
T=$(wp eval --user=$ADMIN "echo (int) apply_filters('mp_cases_query', null, array(), 1, 500)['total'];" 2>/dev/null)
[ "$T" = "4" ] && ok "admin: total=4 (wszystkie sprawy)" || bad "admin total=$T (!=4)"

# rowna liczba wierszy jak total
R=$(wp eval --user=$ADMIN "echo count(apply_filters('mp_cases_query', null, array(), 1, 500)['rows']);" 2>/dev/null)
[ "$R" = "4" ] && ok "admin: 4 wiersze zwrocone" || bad "admin rows=$R"

# ── 3. Pola terminalne: odrzucone => closed_at + handling_seconds; kod obecny ──
ODCH=$(wp eval --user=$ADMIN 'foreach(apply_filters("mp_cases_query",null,array(),1,500)["rows"] as $x){ if($x["status"]==="odrzucone"){ echo ($x["closed_at"]!==null?"C":"-").($x["handling_seconds"]!==null?"H":"-").":".$x["rejection_reason_code"]; } }' 2>/dev/null)
[ "$ODCH" = "CH:duplikat" ] && ok "odrzucone: closed_at+handling+kod 'duplikat' ($ODCH)" || bad "odrzucone pola zle ($ODCH)"

# 'nowe' (NIE terminal): closed_at NULL, handling NULL
NOWE=$(wp eval --user=$ADMIN 'foreach(apply_filters("mp_cases_query",null,array(),1,500)["rows"] as $x){ if($x["status"]==="nowe"){ echo ($x["closed_at"]===null?"c":"C").($x["handling_seconds"]===null?"h":"H"); } }' 2>/dev/null)
[ "$NOWE" = "ch" ] && ok "'nowe' (nie-terminal): brak closed_at i handling ($NOWE)" || bad "'nowe' pola zle ($NOWE)"

# zamkniete (terminal) tez ma closed_at
ZAM=$(wp eval --user=$ADMIN 'foreach(apply_filters("mp_cases_query",null,array(),1,500)["rows"] as $x){ if($x["status"]==="zamknięte"){ echo ($x["closed_at"]!==null?"C":"-"); } }' 2>/dev/null)
[ "$ZAM" = "C" ] && ok "zamkniete (terminal): closed_at ustawione" || bad "zamkniete bez closed_at ($ZAM)"

# ── 4. MINIMALIZACJA (RODO): zwrotka NIE zawiera kontaktu ─────────────────────
JSON=$(wp eval --user=$ADMIN "echo wp_json_encode(apply_filters('mp_cases_query', null, array(), 1, 500));" 2>/dev/null)
echo "$JSON" | grep -qiE 'email|phone|kowalski|@example' && bad "PII WYCIEKA w zwrotce!" || ok "minimalizacja: brak email/telefon/imie/adresu w zwrotce"

# ── 5. Paginacja + cap 500 ───────────────────────────────────────────────────
P1=$(wp eval --user=$ADMIN "echo count(apply_filters('mp_cases_query', null, array(), 1, 2)['rows']);" 2>/dev/null)
P2=$(wp eval --user=$ADMIN "echo count(apply_filters('mp_cases_query', null, array(), 2, 2)['rows']);" 2>/dev/null)
P3=$(wp eval --user=$ADMIN "echo count(apply_filters('mp_cases_query', null, array(), 3, 2)['rows']);" 2>/dev/null)
[ "$P1" = "2" ] && [ "$P2" = "2" ] && [ "$P3" = "0" ] && ok "paginacja per_page=2: str1=2 str2=2 str3=0" || bad "paginacja zla ($P1/$P2/$P3)"
CAP=$(wp eval --user=$ADMIN "echo (int) apply_filters('mp_cases_query', null, array(), 1, 9999)['per_page'];" 2>/dev/null)
[ "$CAP" = "500" ] && ok "cap per_page: 9999 -> 500 (chunk kontraktu)" || bad "cap per_page zly ($CAP)"

# ── 6. Filtry ────────────────────────────────────────────────────────────────
FST=$(wp eval --user=$ADMIN "echo (int) apply_filters('mp_cases_query', null, array('status'=>'odrzucone'), 1, 500)['total'];" 2>/dev/null)
[ "$FST" = "1" ] && ok "filtr status=odrzucone: total=1" || bad "filtr status zly ($FST)"
FKI=$(wp eval --user=$ADMIN "echo (int) apply_filters('mp_cases_query', null, array('kind'=>'naprawa'), 1, 500)['total'];" 2>/dev/null)
[ "$FKI" = "1" ] && ok "filtr kind=naprawa: total=1" || bad "filtr kind zly ($FKI)"
FDF=$(wp eval --user=$ADMIN "echo (int) apply_filters('mp_cases_query', null, array('date_from'=>'2099-01-01'), 1, 500)['total'];" 2>/dev/null)
[ "$FDF" = "0" ] && ok "filtr date_from=2099: total=0 (przyszlosc)" || bad "filtr date_from zly ($FDF)"
FDT=$(wp eval --user=$ADMIN "echo (int) apply_filters('mp_cases_query', null, array('date_from'=>'2000-01-01','date_to'=>'2099-12-31'), 1, 500)['total'];" 2>/dev/null)
[ "$FDT" = "4" ] && ok "filtr zakres 2000..2099: total=4" || bad "filtr zakres zly ($FDT)"

# ── 7. RESPEKT ROLI ──────────────────────────────────────────────────────────
AG=$(wp eval --user=$AGENT "echo (int) apply_filters('mp_cases_query', null, array(), 1, 500)['total'];" 2>/dev/null)
[ "$AG" = "1" ] && ok "mp_agent: widzi TYLKO swoje (1 przydzielona)" || bad "agent scope zly ($AG, ma byc 1)"
AGST=$(wp eval --user=$AGENT 'foreach(apply_filters("mp_cases_query",null,array(),1,500)["rows"] as $x){ echo $x["status"]; }' 2>/dev/null)
[ "$AGST" = "zaakceptowane" ] && ok "mp_agent: to jego sprawa B (zaakceptowane)" || bad "agent widzi zla sprawe ($AGST)"
SU=$(wp eval --user=$SUB "echo (int) apply_filters('mp_cases_query', null, array(), 1, 500)['total'];" 2>/dev/null)
[ "$SU" = "0" ] && ok "subscriber: pusto (brak uprawnien)" || bad "subscriber cos widzi ($SU)!"
AN=$(wp eval "echo (int) apply_filters('mp_cases_query', null, array(), 1, 500)['total'];" 2>/dev/null)
[ "$AN" = "0" ] && ok "anon (user 0): pusto" || bad "anon cos widzi ($AN)!"

echo ""
echo "WYNIK: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
