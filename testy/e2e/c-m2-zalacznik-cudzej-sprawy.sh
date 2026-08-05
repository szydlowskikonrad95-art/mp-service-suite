#!/usr/bin/env bash
# ZYWY DOWOD M2 (koordynator, 2026-08-05): Attachments::can_access przepuszczal
# KAZDEGO mp_agent do zalacznika DOWOLNEJ sprawy, podczas gdy karte cudzej
# sprawy odbija NOT_CASE_OWNER — zalacznik (zdjecie, skan dokumentu zakupu)
# byl boczna furtka do cudzych danych. FIX: personel przechodzi przez TEN SAM
# kod co lista i karta (CaseRepo::can_current_user_see): pracownik widzi
# zalaczniki TYLKO swojej przydzielonej sprawy; koordynator/admin bez zmian;
# klient bez zmian (wlasciciel przez konto — kryje to c4-zalaczniki.sh).
#
# Kalibracja WBUDOWANA: assert A1 PADA na kodzie sprzed naprawy (pracownik2
# przechodzil do sprawy pracownika1). Bramka mierzona przez can_access_case —
# dokladnie ta funkcja napedza serve() i jego 403 (wzorzec c4-zalaczniki.sh).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

gate() { # $1=user_id $2=case_id → TAK/NIE
	wp eval "wp_set_current_user($1); echo MP\\Intake\\Attachments::can_access_case($2) ? 'TAK' : 'NIE';" 2>/dev/null
}
mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name="$2" --serial="$3" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\\Intake\\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_workflow_rules;" >/dev/null 2>&1

A1=$(wp user get m2agent1 --field=ID 2>/dev/null); [ -z "$A1" ] && A1=$(wp user create m2agent1 'm2a1@example.com' --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
A2=$(wp user get m2agent2 --field=ID 2>/dev/null); [ -z "$A2" ] && A2=$(wp user create m2agent2 'm2a2@example.com' --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
KO=$(wp user get m2koord --field=ID 2>/dev/null); [ -z "$KO" ] && KO=$(wp user create m2koord 'm2k@example.com' --role=mp_coordinator --user_pass=x --porcelain 2>/dev/null)

CID1=$(mkcase 'm2-klient1@example.com' 'Jan M2' 'M2-1')
CID2=$(mkcase 'm2-klient2@example.com' 'Ewa M2' 'M2-2')
wp eval "apply_filters('mp_case_assign', null, $CID1, $A1, 1); apply_filters('mp_case_assign', null, $CID2, $A2, 1);" >/dev/null 2>&1
[ "$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID1")" = "$A1" ] \
	&& [ "$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$CID2")" = "$A2" ] \
	&& ok "0: sprawa 1 -> pracownik1, sprawa 2 -> pracownik2" || bad "0: przydzialy nie chwycily"

# ── A. KALIBRACJA M2: pracownik2 do zalacznika sprawy PRACOWNIKA1 ────────────
[ "$(gate "$A2" "$CID1")" = "NIE" ] \
	&& ok "A1: pracownik2 NIE wejdzie do zalacznika cudzej sprawy (jak karta: NOT_CASE_OWNER)" \
	|| bad "A1: pracownik2 przechodzi do zalacznika sprawy pracownika1 — boczna furtka zyje"

# ── B. Kontrole kierunku: wlasna sprawa, koordynator, admin, anonim ──────────
[ "$(gate "$A2" "$CID2")" = "TAK" ] && ok "B1: pracownik2 do WLASNEJ sprawy — wchodzi" || bad "B1: pracownik stracil dostep do wlasnej sprawy"
[ "$(gate "$A1" "$CID1")" = "TAK" ] && ok "B2: pracownik1 do wlasnej sprawy — wchodzi" || bad "B2: pracownik1 stracil dostep do wlasnej sprawy"
[ "$(gate "$KO" "$CID1")" = "TAK" ] && ok "B3: koordynator do dowolnej sprawy — bez zmian" || bad "B3: koordynator stracil dostep"
[ "$(gate 1 "$CID1")" = "TAK" ] && ok "B4: administrator do dowolnej sprawy — bez zmian" || bad "B4: administrator stracil dostep"
[ "$(gate 0 "$CID1")" = "NIE" ] && ok "B5: anonim odbity — bez zmian" || bad "B5: anonim przechodzi!"

echo "── M2: PASS=$PASS FAIL=$FAIL ──"
if [ "$(( PASS + FAIL ))" -lt 7 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane 7."
	exit 2
fi
[ "$FAIL" -eq 0 ]
