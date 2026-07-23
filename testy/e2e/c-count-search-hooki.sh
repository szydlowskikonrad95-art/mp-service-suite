#!/usr/bin/env bash
# ZYWY DOWOD kontraktu B->C (klaster listenerow C dla Rejestru):
#   mp_case_count_by_product  -> kolumna „Sprawy" (przez B-owy mp_serial_usage_count)
#   mp_customer_find_products -> wyszukiwarka „po kliencie" (kartka P2.6)
# Bez listenerow C: kolumna pokazuje „modul spraw nieaktywny", search po kliencie WYLACZONY.
# Sprawy UNVERIFIED nie licza sie (anty-wektor „spamer blokuje produkty"). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

mkcase() { # $1=email $2=serial ; echo case_id ; weryfikuje
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='Cnt Klient' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Listenery zarejestrowane (bez nich Rejestr „modul nieaktywny") ────────
L1=$(wp eval 'echo has_filter("mp_case_count_by_product") ? "1":"0";' 2>/dev/null)
L2=$(wp eval 'echo has_filter("mp_customer_find_products") ? "1":"0";' 2>/dev/null)
[ "$L1" = "1" ] && ok "listener mp_case_count_by_product zarejestrowany" || bad "brak listenera case_count"
[ "$L2" = "1" ] && ok "listener mp_customer_find_products zarejestrowany" || bad "brak listenera customer_find"

# ── 1. Produkt + brak spraw => total 0 ───────────────────────────────────────
wp db query "DELETE FROM wp_mp_product_registry WHERE serial_normalized='CNTSER1';" >/dev/null 2>&1
wp db query "INSERT INTO wp_mp_product_registry (serial_display,serial_normalized,model,batch,category,warranty_until,source,archived,created_at,updated_at) VALUES ('CNT-SER-1','CNTSER1','Cnt Model','P','audio','2030-01-01','manual',0,NOW(),NOW());" >/dev/null 2>&1
PID=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='CNTSER1';")
T0=$(wp eval "echo MP\Intake\CaseRepo::case_count_by_product($PID)['total'];" 2>/dev/null)
[ "${T0:-9}" = "0" ] && ok "produkt bez spraw => total 0" || bad "total bez spraw='$T0'"

# ── 2. Verified case => total 1, active 1 + kolumna Sprawy (lancuch B) = 1 ────
C1=$(mkcase cntklient@example.com CNT-SER-1)
CNT=$(wp eval "echo wp_json_encode(MP\Intake\CaseRepo::case_count_by_product($PID));" 2>/dev/null)
echo "$CNT" | grep -q '"total":1' && echo "$CNT" | grep -q '"active":1' && ok "verified case => total 1, active 1 ($CNT)" || bad "count po verified: $CNT"
USAGE=$(wp eval 'echo var_export(apply_filters("mp_serial_usage_count", null, "CNT-SER-1"), true);' 2>/dev/null)
[ "$USAGE" = "1" ] && ok "kolumna Sprawy = 1 przez mp_serial_usage_count B-C, nie brak-danych" || bad "serial_usage_count=$USAGE oczek 1"

# ── 3. Zamkniecie => active 0, closed 1 ──────────────────────────────────────
wp db query "UPDATE wp_mp_service_cases SET status='zamknięte' WHERE id=$C1;" >/dev/null 2>&1
CNT2=$(wp eval "echo wp_json_encode(MP\Intake\CaseRepo::case_count_by_product($PID));" 2>/dev/null)
echo "$CNT2" | grep -q '"active":0' && echo "$CNT2" | grep -q '"closed":1' && ok "po zamknieciu => active 0, closed 1 ($CNT2)" || bad "count po zamknieciu: $CNT2"

# ── 4. Wyszukiwarka po kliencie (P2.6) => zwraca produkt ──────────────────────
F=$(wp eval "echo wp_json_encode(MP\Intake\CaseRepo::find_products_for_customer('cntklient'));" 2>/dev/null)
echo "$F" | grep -q "\"ids\":\[$PID\]" && ok "find_products_for_customer(cntklient) => produkt $PID (P2.6 klient)" || bad "find_products: $F (oczek. ids=[$PID])"
F2=$(wp eval "echo wp_json_encode(MP\Intake\CaseRepo::find_products_for_customer('niematakiego-xyz'));" 2>/dev/null)
echo "$F2" | grep -q '"ids":\[\]' && ok "obcy klient => brak produktow (nie wycieka)" || bad "find obcy: $F2"

# ── 5. UNVERIFIED nie liczy sie (anty-spam) ──────────────────────────────────
wp mp case-create --kind=reklamacja --email=cntspam@example.com --name='Spam' --serial=CNT-SER-1 --document='FV/2' --date='2026-05-01' --desc='x' >/dev/null 2>&1
T3=$(wp eval "echo MP\Intake\CaseRepo::case_count_by_product($PID)['total'];" 2>/dev/null)
[ "${T3:-9}" = "1" ] && ok "sprawa UNVERIFIED nie wliczona (total dalej 1)" || bad "unverified policzone (total=$T3)"

# ── sprzatanie ───────────────────────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_product_registry WHERE serial_normalized='CNTSER1';" >/dev/null 2>&1

echo ""
echo "=== c-count-search-hooki: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
