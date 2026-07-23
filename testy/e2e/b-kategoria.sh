#!/usr/bin/env bash
# Etap 1 KATEGORIA produktu (kartka P1.2/P3.1) — Registry: kolumna + slownik +
# parser CSV + hak kontraktowy mp_product_category. Wymaga zywego `wp`.
# Chodzi tak samo na poligonie Dockera i w CI. Exit 0 = wszystkie asercje OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ── 0. Migracja v2: kolumna `category` istnieje (aktywacja odpala Schema::migrate) ──
COL=$(q "SHOW COLUMNS FROM wp_mp_product_registry LIKE 'category';")
[ -n "$COL" ] && ok "migracja v2: kolumna category istnieje" || bad "brak kolumny category (migracja v2)"

# ── 1. Slownik: sanitize (slug / etykieta / nieznane / puste) ──
S=$(wp eval 'echo MP\Registry\Categories::sanitize("Elektronika audio");' 2>/dev/null)
[ "$S" = "audio" ] && ok "sanitize: etykieta -> slug (audio)" || bad "sanitize etykieta: '$S'"
S=$(wp eval 'echo MP\Registry\Categories::sanitize("AGD drobne");' 2>/dev/null)
[ "$S" = "agd" ] && ok "sanitize: etykieta -> slug (agd)" || bad "sanitize agd: '$S'"
S=$(wp eval 'echo MP\Registry\Categories::sanitize("cos-obcego");' 2>/dev/null)
[ "$S" = "inne" ] && ok "sanitize: nieznane -> inne" || bad "sanitize nieznane: '$S'"
S=$(wp eval 'echo MP\Registry\Categories::sanitize("");' 2>/dev/null)
[ "$S" = "inne" ] && ok "sanitize: puste -> inne" || bad "sanitize puste: '$S'"

# ── 2. Parser CSV: kolumna kategoria + WSTECZNA ZGODNOSC (stary CSV bez niej -> inne) ──
P=$(wp eval '
 $h = MP\Registry\CsvParser::map_header( array( "serial", "model", "kategoria" ) );
 $r = MP\Registry\CsvParser::parse_row( array( "SN-KAT-1", "Model X", "elektronarzedzia" ), $h );
 echo isset( $r["row"]["category"] ) ? $r["row"]["category"] : "BRAK";' 2>/dev/null)
[ "$P" = "elektronarzedzia" ] && ok "parser: kolumna kategoria -> slug" || bad "parser kategoria: '$P'"
P=$(wp eval '
 $h = MP\Registry\CsvParser::map_header( array( "serial", "model" ) );
 $r = MP\Registry\CsvParser::parse_row( array( "SN-KAT-2", "Model Y" ), $h );
 echo isset( $r["row"]["category"] ) ? $r["row"]["category"] : "BRAK";' 2>/dev/null)
[ "$P" = "inne" ] && ok "parser: stary CSV bez kolumny -> inne (wsteczna zgodnosc)" || bad "parser wsteczna: '$P'"

# ── 3. Hak kontraktowy mp_product_category (Intake get_context -> os przydzialu D) ──
wp db query "DELETE FROM wp_mp_product_registry WHERE serial_normalized IN ('KATTEST1','KATTEST2');" >/dev/null 2>&1
wp db query "INSERT INTO wp_mp_product_registry (serial_display,serial_normalized,model,batch,category,source,created_at,updated_at) VALUES ('KAT-TEST-1','KATTEST1','M','B','elektronarzedzia','manual',NOW(),NOW());" >/dev/null 2>&1
PID=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='KATTEST1';")
H=$(wp eval "echo (string) apply_filters('mp_product_category', null, ${PID:-0});" 2>/dev/null)
[ "$H" = "elektronarzedzia" ] && ok "hak: zwraca kategorie produktu po ID" || bad "hak zwrot: '$H'"
H=$(wp eval "var_export( apply_filters('mp_product_category', null, 999999999) );" 2>/dev/null)
echo "$H" | grep -q "NULL" && ok "hak: brak produktu -> null (default, nie blad)" || bad "hak brak-produktu: '$H'"

# ── 4. Default kolumny 'inne' (istniejace wiersze po migracji bezpieczne) ──
wp db query "INSERT INTO wp_mp_product_registry (serial_display,serial_normalized,model,batch,source,created_at,updated_at) VALUES ('KAT-TEST-2','KATTEST2','M','B','manual',NOW(),NOW());" >/dev/null 2>&1
D=$(q "SELECT category FROM wp_mp_product_registry WHERE serial_normalized='KATTEST2';")
[ "$D" = "inne" ] && ok "kolumna DEFAULT 'inne' (wiersz bez jawnej kategorii)" || bad "default kolumny: '$D'"

# ── sprzatanie ──
wp db query "DELETE FROM wp_mp_product_registry WHERE serial_normalized IN ('KATTEST1','KATTEST2');" >/dev/null 2>&1

echo ""
echo "=== b-kategoria: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
