#!/usr/bin/env bash
# ZYWY DOWOD C7a (serial-reuse P2.3): flaga possible_duplicate.
# Ten sam produkt (serial w rejestrze) ma ZWERYFIKOWANA sprawe w 30 dni =>
# nowa sprawa dostaje possible_duplicate=1 (FLAGA dla operatora, nie blokada).
# Rozny produkt / serial nierejestrowany => brak flagi.
# CLI (bez HTTP). Chodzi na poligonie i w CI (e2e-import).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
cid() { echo "$1" | grep '^case_id=' | cut -d= -f2; }
tok() { echo "$1" | grep '^token=' | cut -d= -f2; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_product_registry; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

# Produkt w rejestrze (serial SR-1 => normalized SR1).
wp db query "INSERT INTO wp_mp_product_registry (serial_display, serial_normalized, model, batch, warranty_until, source, created_at, updated_at) VALUES ('SR-1','SR1','Model X','P1','2030-01-01','manual',UTC_TIMESTAMP(),UTC_TIMESTAMP())" >/dev/null 2>&1
PID=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='SR1'")
[ -n "$PID" ] && ok "produkt w rejestrze (id=$PID)" || bad "produkt nieutworzony"

# case1: ten sam serial, brak wczesniejszej zweryfikowanej => flaga 0
O1=$(wp mp case-create --kind=reklamacja --email='a@example.com' --serial='SR-1' --document='FV/1' --date='2026-03-15' --desc='x' 2>/dev/null)
CID1=$(cid "$O1"); T1=$(tok "$O1")
PD1=$(q "SELECT possible_duplicate FROM wp_mp_service_cases WHERE id=$CID1")
PROD1=$(q "SELECT product_registry_id FROM wp_mp_service_cases WHERE id=$CID1")
[ "$PROD1" = "$PID" ] && ok "case1 dopasowany do produktu ($PROD1)" || bad "case1 bez product_registry_id ($PROD1)"
[ "$PD1" = "0" ] && ok "case1 BEZ flagi (brak wczesniejszej zweryfikowanej sprawy)" || bad "case1 ma flage ($PD1)"
wp mp case-verify "$T1" >/dev/null 2>&1

# case2: TEN SAM serial, INNY email (dedup 15min go nie tyka - inny email) => flaga 1
O2=$(wp mp case-create --kind=reklamacja --email='b@example.com' --serial='SR-1' --document='FV/2' --date='2026-03-15' --desc='y' 2>/dev/null)
CID2=$(cid "$O2")
PD2=$(q "SELECT possible_duplicate FROM wp_mp_service_cases WHERE id=$CID2")
[ "$PD2" = "1" ] && ok "case2 FLAGA possible_duplicate=1 (ten sam produkt, wczesniejsza zweryfikowana w 30 dni)" || bad "case2 bez flagi ($PD2)"

# case3: serial NIEREJESTROWANY => brak dopasowania => flaga 0
O3=$(wp mp case-create --kind=reklamacja --email='c@example.com' --serial='NIEZNANY-9' --document='FV/3' --date='2026-03-15' --desc='z' 2>/dev/null)
CID3=$(cid "$O3")
PD3=$(q "SELECT possible_duplicate FROM wp_mp_service_cases WHERE id=$CID3")
PROD3=$(q "SELECT COALESCE(product_registry_id,'NULL') FROM wp_mp_service_cases WHERE id=$CID3")
{ [ "$PD3" = "0" ] && [ "$PROD3" = "NULL" ]; } && ok "case3 (serial nierejestrowany) BEZ flagi, bez produktu" || bad "case3: flaga=$PD3 produkt=$PROD3"

# licznik zweryfikowanych spraw dla produktu (tylko case1 zweryfikowany)
CNT=$(wp eval "echo MP\Intake\CaseRepo::verified_case_count_for_product($PID);" 2>/dev/null)
[ "$CNT" = "1" ] && ok "verified_case_count_for_product = 1 (case1 zweryfikowany; case2 jeszcze pending)" || bad "licznik zweryfikowanych = $CNT (oczekiwano 1)"

echo
echo "WYNIK C7a: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
