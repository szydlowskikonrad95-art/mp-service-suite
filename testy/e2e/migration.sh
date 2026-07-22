#!/usr/bin/env bash
# DoD C sekcja 5 — MIGRACJA v0.2.0 -> v0.3.0 z realnymi danymi.
# Install v0.2.0 -> wpisz dane (registry) -> podmien pliki na v0.3.0 (BEZ reaktywacji,
# jak WP updater) -> admin_init odpala maybe_upgrade -> dane+schemat+cron+role+opcje przetrwaly.
# V020_SRC / V030_SRC = katalogi ze zbudowanymi wtyczkami (z kopiami Common).
set -u
: "${V020_SRC:?katalog wtyczek v0.2.0}"
: "${V030_SRC:?katalog wtyczek v0.3.0}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
has_table() { wp eval "global \$wpdb; echo \$wpdb->get_var(\"SHOW TABLES LIKE '\".\$wpdb->prefix.\"$1'\") ? '1' : '0';" 2>/dev/null; }

PDIR=$(wp eval 'echo WP_PLUGIN_DIR;' 2>/dev/null)
PFX=$(wp eval 'global $wpdb; echo $wpdb->prefix;' 2>/dev/null)
copy_plugins() {
	rm -rf "$PDIR"/mp-service-intake "$PDIR"/mp-warranty-registry "$PDIR"/mp-workflow-automator
	cp -r "$1"/mp-service-intake "$1"/mp-warranty-registry "$1"/mp-workflow-automator "$PDIR"/
}

# ── 1. v0.2.0: instalacja + aktywacja + dane ────────────────────────────────
copy_plugins "$V020_SRC"
wp plugin activate mp-service-intake mp-warranty-registry mp-workflow-automator >/dev/null 2>&1
CASES_BEFORE=$(has_table "mp_service_cases")
[ "$CASES_BEFORE" = "0" ] && ok "v0.2.0: brak tabeli intake (schemat wchodzi w v0.3.0)" || bad "v0.2.0 juz ma tabele intake ($CASES_BEFORE)"

# realne dane w registry (produkt)
wp db query "INSERT INTO ${PFX}mp_product_registry (serial_display, serial_normalized, model, batch, warranty_until, source, created_at, updated_at) VALUES ('MIG-1','MIG1','Model Mig','P1','2030-01-01','manual',UTC_TIMESTAMP(),UTC_TIMESTAMP())" >/dev/null 2>&1
PROD_BEFORE=$(q "SELECT COUNT(*) FROM ${PFX}mp_product_registry")
ROLE_BEFORE=$(wp eval 'echo get_role("mp_client") ? "1" : "0";' 2>/dev/null)
[ "${PROD_BEFORE:-0}" -ge 1 ] && ok "v0.2.0: dane registry wpisane (produkt MIG-1)" || bad "nie udalo sie wpisac danych registry"

# ── 2. Podmiana plikow na v0.3.0 — BEZ reaktywacji (jak WP updater) ─────────
copy_plugins "$V030_SRC"
# 3. admin_init odpala maybe_upgrade (upgrade bez reaktywacji)
wp eval 'do_action("admin_init");' >/dev/null 2>&1

# ── 4. Asercje: schemat stworzony, dane przetrwaly, role/cron/opcje ─────────
MISS=""
for t in mp_customers mp_service_cases mp_case_events mp_messages mp_attachments mp_consents mp_srv_counters; do
	[ "$(has_table "$t")" = "1" ] || MISS="$MISS $t"
done
[ -z "$MISS" ] && ok "upgrade BEZ reaktywacji: 7 tabel intake STWORZONYCH (maybe_upgrade)" || bad "brak tabel intake po upgrade:$MISS"

SV=$(wp option get mp_intake_schema_version 2>/dev/null)
[ "$SV" = "1" ] && ok "schema_version = 1 (migracja odnotowana)" || bad "schema_version = $SV"

PROD_AFTER=$(q "SELECT COUNT(*) FROM ${PFX}mp_product_registry")
{ [ -n "$PROD_AFTER" ] && [ "$PROD_AFTER" = "$PROD_BEFORE" ]; } && ok "dane registry PRZETRWALY upgrade ($PROD_AFTER)" || bad "dane registry zgubione (przed=$PROD_BEFORE po=$PROD_AFTER)"

ROLE_AFTER=$(wp eval 'echo get_role("mp_client") ? "1" : "0";' 2>/dev/null)
[ "$ROLE_AFTER" = "1" ] && ok "role przetrwaly upgrade (mp_client)" || bad "rola mp_client zniknela"

CRON=$(wp eval 'echo wp_next_scheduled("mp_intake_retention_sweep") ? "1" : "0";' 2>/dev/null)
[ "$CRON" = "1" ] && ok "cron retencji zaplanowany po upgrade" || bad "brak crona po upgrade"

# ── 5. Smoke na v0.3.0: pelny cykl dziala po migracji ──────────────────────
OUT=$(wp mp case-create --kind=zapytanie --email='mig@example.com' --desc='po migracji' 2>/dev/null)
T=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$T" >/dev/null 2>&1
VER=$(q "SELECT COUNT(*) FROM ${PFX}mp_service_cases WHERE identity_status='verified'")
[ "${VER:-0}" -ge 1 ] && ok "po migracji: pelny cykl sprawy dziala (create+verify)" || bad "cykl sprawy nie dziala po migracji ($VER)"

echo
echo "WYNIK migracja: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
