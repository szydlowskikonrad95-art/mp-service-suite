#!/usr/bin/env bash
# ZYWY DOWOD B5 (kartka l.50: „brak mozliwosci usuniecia produktu powiazanego z aktywna sprawa").
# Registry Archive::archive() pyta hakiem `mp_product_active_cases_count` (listener w Intake, C).
#   >0 aktywnych spraw => ODMOWA · 0 => archiwizacja (soft-delete: archived=1 + deleted_at)
#   brak listenera (Intake off) => FAIL-CLOSED (has_filter false => odmowa „na slowo").
# Aktywna = status poza TERMINAL_STATUSES (zamkniete/odrzucone).
# Wymaga zywego `wp`. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Tworzy+weryfikuje sprawe z serialem (podpina product_registry_id). Echo: case_id.
mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# Admin systemu (Archive wymaga cap mp_system_admin; rola niesie cap o tej samej nazwie).
ADM=$(wp user create b5_adm b5_adm@example.com --role=mp_system_admin --porcelain 2>/dev/null)
[ -z "$ADM" ] && ADM=$(wp user get b5_adm --field=ID 2>/dev/null)

# Czysty stan.
wp db query "DELETE FROM wp_mp_product_registry WHERE serial_normalized IN ('B5ACTIVE','B5FREE');" >/dev/null 2>&1

# ── 1. Produkt z AKTYWNA sprawa => archiwizacja ODMOWIONA ─────────────────────
wp db query "INSERT INTO wp_mp_product_registry (serial_display,serial_normalized,model,batch,category,warranty_until,source,archived,created_at,updated_at) VALUES ('B5ACTIVE','B5ACTIVE','Radio','P1','audio','2030-01-01','manual',0,NOW(),NOW());" >/dev/null 2>&1
PID_A=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='B5ACTIVE';")
C1=$(mkcase b5active@example.com B5ACTIVE)
CNT=$(wp eval "echo MP\Intake\CaseRepo::active_cases_count_for_product($PID_A);" 2>/dev/null)
[ "${CNT:-0}" -ge 1 ] && ok "listener liczy AKTYWNA sprawe produktu (count=$CNT)" || bad "count aktywnych='$CNT' (oczek. >=1)"
R1=$(wp eval "\$r=MP\Registry\Archive::archive($PID_A); echo is_array(\$r)?'ERR':'OK';" --user="$ADM" 2>/dev/null)
[ "$R1" = "ERR" ] && ok "archiwizacja ODMOWIONA (produkt ma aktywna sprawe)" || bad "archiwizacja nie odmowila: '$R1'"
ARCH_A=$(q "SELECT archived FROM wp_mp_product_registry WHERE id=$PID_A;")
[ "$ARCH_A" = "0" ] && ok "produkt NIE zarchiwizowany (archived=0)" || bad "produkt archived='$ARCH_A' (oczek. 0)"

# ── 2. Zamkniecie sprawy (terminalna) => count=0 => archiwizacja PRZECHODZI ────
wp db query "UPDATE wp_mp_service_cases SET status='zamknięte' WHERE id=$C1;" >/dev/null 2>&1
CNT2=$(wp eval "echo MP\Intake\CaseRepo::active_cases_count_for_product($PID_A);" 2>/dev/null)
[ "${CNT2:-9}" -eq 0 ] && ok "po zamknieciu sprawy count=0 (terminalna nie liczy)" || bad "count po zamknieciu='$CNT2' (oczek. 0)"
R2=$(wp eval "\$r=MP\Registry\Archive::archive($PID_A); echo is_array(\$r)?('ERR:'.\$r['error']):'OK';" --user="$ADM" 2>/dev/null)
[ "$R2" = "OK" ] && ok "archiwizacja PRZESZLA (brak aktywnych spraw)" || bad "archiwizacja nie przeszla: '$R2'"
ARCH_A2=$(q "SELECT archived FROM wp_mp_product_registry WHERE id=$PID_A;")
[ "$ARCH_A2" = "1" ] && ok "produkt zarchiwizowany (archived=1)" || bad "produkt archived='$ARCH_A2' (oczek. 1)"
DEL=$(q "SELECT COUNT(*) FROM wp_mp_product_registry WHERE id=$PID_A AND deleted_at IS NOT NULL;")
[ "${DEL:-0}" -ge 1 ] && ok "deleted_at ustawione (miekkie usuwanie)" || bad "deleted_at nie ustawione"

# ── 3. Produkt BEZ spraw => od razu archiwizowalny ───────────────────────────
wp db query "INSERT INTO wp_mp_product_registry (serial_display,serial_normalized,model,batch,category,warranty_until,source,archived,created_at,updated_at) VALUES ('B5FREE','B5FREE','Toster','P2','agd','2030-01-01','manual',0,NOW(),NOW());" >/dev/null 2>&1
PID_F=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='B5FREE';")
R3=$(wp eval "\$r=MP\Registry\Archive::archive($PID_F); echo is_array(\$r)?'ERR':'OK';" --user="$ADM" 2>/dev/null)
[ "$R3" = "OK" ] && ok "produkt bez spraw archiwizowalny" || bad "produkt bez spraw: '$R3'"

# ── 4. FAIL-CLOSED: bez listenera => odmowa nawet dla wolnego produktu ────────
wp db query "UPDATE wp_mp_product_registry SET archived=0, deleted_at=NULL WHERE id=$PID_F;" >/dev/null 2>&1
R4=$(wp eval "remove_all_filters('mp_product_active_cases_count'); \$r=MP\Registry\Archive::archive($PID_F); echo is_array(\$r)?'ERR':'OK';" --user="$ADM" 2>/dev/null)
[ "$R4" = "ERR" ] && ok "FAIL-CLOSED: bez listenera archiwizacja ODMOWIONA" || bad "fail-closed nie zadzialal: '$R4'"

# Sprzatanie.
wp db query "DELETE FROM wp_mp_product_registry WHERE serial_normalized IN ('B5ACTIVE','B5FREE');" >/dev/null 2>&1
wp user delete "$ADM" --yes >/dev/null 2>&1

echo ""
echo "=== b5-usuwanie-produktu: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
