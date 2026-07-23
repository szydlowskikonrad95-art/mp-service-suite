#!/usr/bin/env bash
# REGRESJA: Registry auto-migruje przy AKTUALIZACJI (admin_init -> maybe_upgrade),
# BEZ reaktywacji — spojnosc z Intake/Automator. BUG (zlapany audytem 24.07):
# mp-warranty-registry NIE mial maybe_upgrade -> update dodajacy migracje
# (v1->v2 kolumna `category`) zostawial STARY schemat -> `SELECT category` sypal
# bledem DB. Ten test pilnuje, ze migracja stosuje sie bez deaktywacji+aktywacji.
# Wymaga aktywnego mp-warranty-registry (biezacy kod). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

PFX=$(wp eval 'global $wpdb; echo $wpdb->prefix;' 2>/dev/null)
has_col() { wp eval "global \$wpdb; echo \$wpdb->get_var(\"SHOW COLUMNS FROM \".\$wpdb->prefix.\"mp_product_registry LIKE 'category'\") ? '1' : '0';" 2>/dev/null; }

# Docelowa wersja schematu z KODU (gate maybe_upgrade).
LATEST=$(wp eval 'echo (int) MP\Registry\Schema::LATEST;' 2>/dev/null)
{ [ -n "$LATEST" ] && [ "$LATEST" -ge 2 ]; } && ok "Schema::LATEST = $LATEST (>=2, migracja kategorii w kodzie)" || bad "brak/za niska Schema::LATEST ($LATEST)"

# ── 1. Symuluj STARY schemat (jak po update BEZ reaktywacji) ────────────────
wp option update mp_registry_schema_version 1 >/dev/null 2>&1
wp db query "ALTER TABLE ${PFX}mp_product_registry DROP COLUMN category" >/dev/null 2>&1
[ "$(has_col)" = "0" ] && ok "stan startowy: kolumna category USUNIETA + wersja=1 (stary schemat)" || bad "nie udalo sie zasymulowac starego schematu (kolumna nadal jest)"

# ── 2. admin_init odpala maybe_upgrade (upgrade BEZ reaktywacji) ────────────
wp eval 'do_action("admin_init");' >/dev/null 2>&1

# ── 3. Asercje: migracja zastosowana samoczynnie ───────────────────────────
SV=$(wp option get mp_registry_schema_version 2>/dev/null)
[ "$SV" = "$LATEST" ] && ok "registry_schema_version = $LATEST po admin_init (auto-migracja)" || bad "wersja = $SV (oczek. $LATEST) — maybe_upgrade NIE zadzialal"
[ "$(has_col)" = "1" ] && ok "kolumna category ODTWORZONA przez maybe_upgrade (bez reaktywacji)" || bad "kolumna category NADAL brak po admin_init — REGRESJA"

echo
echo "WYNIK registry-maybe-upgrade: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
