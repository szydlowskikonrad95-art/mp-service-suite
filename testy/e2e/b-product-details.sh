#!/usr/bin/env bash
# ZYWY DOWOD (karta sprawy — sekcja Produkt+Gwarancja): kontrakt B->C `mp_product_details`.
# Registry (B) wystawia detale produktu po ID dla karty w C (luzne wiazanie, C nie siega
# w tabele B). Sprawdza: zwrotka {id,serial,model,batch,purchase_document,purchase_date,
# warranty_until,warranty_status,archived} · status gwarancji z daty (aktywna/wygasla/
# brak_danych — BEZ weryfikacji dokumentu) · archived flaga · id=0/nieistniejacy => null.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ── 0. Czysty rejestr + 3 produkty (aktywny / wygasly / bez daty+archived) ────
wp db query "DELETE FROM wp_mp_product_registry;" >/dev/null 2>&1

wp db query "INSERT INTO wp_mp_product_registry (serial_display,serial_normalized,model,batch,purchase_document,purchase_date,warranty_until,source,archived,created_at,updated_at) VALUES ('PD-AKT-1','PDAKT1','Wiertarka X','B7','FV/2026/50','2026-01-10','2035-01-10','manual',0,NOW(),NOW());" >/dev/null 2>&1
PID_AKT=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='PDAKT1'")
wp db query "INSERT INTO wp_mp_product_registry (serial_display,serial_normalized,model,batch,purchase_document,purchase_date,warranty_until,source,archived,created_at,updated_at) VALUES ('PD-EXP-1','PDEXP1','Szlifierka Y','B8','FV/2020/9','2020-02-01','2021-02-01','manual',0,NOW(),NOW());" >/dev/null 2>&1
PID_EXP=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='PDEXP1'")
wp db query "INSERT INTO wp_mp_product_registry (serial_display,serial_normalized,model,batch,source,archived,created_at,updated_at) VALUES ('PD-ARCH-1','PDARCH1','Radio Z','B9','manual',1,NOW(),NOW());" >/dev/null 2>&1
PID_ARCH=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='PDARCH1'")

[ -n "$PID_AKT" ] && [ -n "$PID_EXP" ] && [ -n "$PID_ARCH" ] && ok "seed: 3 produkty (akt=$PID_AKT exp=$PID_EXP arch=$PID_ARCH)" || bad "seed produktow zly"

# ── 1. Filtr zarejestrowany ──────────────────────────────────────────────────
HAS=$(wp eval "echo has_filter('mp_product_details')?'1':'0';" 2>/dev/null)
[ "$HAS" = "1" ] && ok "mp_product_details: filtr zarejestrowany (B aktywne)" || bad "brak filtra mp_product_details ($HAS)"

# ── 2. Aktywny: struktura + pola + status 'aktywna' ──────────────────────────
JAKT=$(wp eval "echo wp_json_encode(apply_filters('mp_product_details', null, $PID_AKT));" 2>/dev/null)
for k in id serial model batch purchase_document purchase_date warranty_until warranty_status archived; do
	echo "$JAKT" | grep -q "\"$k\"" || bad "mp_product_details: brak pola '$k' ($JAKT)"
done
echo "$JAKT" | grep -q '"serial":"PD-AKT-1"' && ok "aktywny: serial_display przekazany (PD-AKT-1)" || bad "aktywny: zly serial ($JAKT)"
echo "$JAKT" | grep -q '"model":"Wiertarka X"' && ok "aktywny: model przekazany" || bad "aktywny: zly model ($JAKT)"
echo "$JAKT" | grep -q '"purchase_document":"FV\\/2026\\/50"' && ok "aktywny: dokument zakupu przekazany" || bad "aktywny: zly dokument ($JAKT)"
echo "$JAKT" | grep -q '"warranty_status":"aktywna"' && ok "aktywny: status gwarancji = aktywna (data 2035 > dzis)" || bad "aktywny: zly status ($JAKT)"
echo "$JAKT" | grep -q '"archived":false' && ok "aktywny: archived=false" || bad "aktywny: zle archived ($JAKT)"

# ── 3. Wygasly: status 'wygasla' ─────────────────────────────────────────────
JEXP=$(wp eval "echo wp_json_encode(apply_filters('mp_product_details', null, $PID_EXP));" 2>/dev/null)
echo "$JEXP" | grep -q '"warranty_status":"wygasla"' && ok "wygasly: status = wygasla (data 2021 < dzis)" || bad "wygasly: zly status ($JEXP)"

# ── 4. Archived + brak daty gwarancji: status 'brak_danych' + archived=true ──
JARCH=$(wp eval "echo wp_json_encode(apply_filters('mp_product_details', null, $PID_ARCH));" 2>/dev/null)
echo "$JARCH" | grep -q '"warranty_status":"brak_danych"' && ok "archived: brak warranty_until => status brak_danych" || bad "archived: zly status ($JARCH)"
echo "$JARCH" | grep -q '"archived":true' && ok "archived: flaga archived=true" || bad "archived: zle archived ($JARCH)"

# ── 5. Degradacja: id=0 i nieistniejacy => null (kontrakt „brak = default") ──
D0=$(wp eval "echo var_export(apply_filters('mp_product_details', null, 0), true);" 2>/dev/null)
[ "$D0" = "NULL" ] && ok "id=0 => null (brak produktu)" || bad "id=0 nie null ($D0)"
DNX=$(wp eval "echo var_export(apply_filters('mp_product_details', null, 987654), true);" 2>/dev/null)
[ "$DNX" = "NULL" ] && ok "nieistniejacy id => null" || bad "nieistniejacy nie null ($DNX)"

echo ""
echo "PRODUCT-DETAILS: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
