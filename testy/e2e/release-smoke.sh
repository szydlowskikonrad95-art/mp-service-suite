#!/usr/bin/env bash
# DoD C sekcja 6 — RELEASE-SMOKE: testuj ARTEFAKT (ZIP), nie katalog dev.
# Instaluj z ZIP -> aktywuj 3 w odwrotnej kolejnosci -> klik kluczowych ekranow
# z WP_DEBUG -> deaktywuj -> uninstall (opt-in) -> grep-zero (tabele/opcje/role).
# + integralnosc ZIP (zero plikow dev) + wersja spojna (header == readme Stable tag).
# DIST_DIR = katalog z ZIP-ami (build/dist). Uruchamiany w CI job release-smoke.
set -u
: "${DIST_DIR:?katalog z ZIP-ami wtyczek}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
has_table() { wp eval "global \$wpdb; echo \$wpdb->get_var(\"SHOW TABLES LIKE '\".\$wpdb->prefix.\"$1'\") ? '1' : '0';" 2>/dev/null; }

LOG="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/debug.log"
PFX=$(wp eval 'global $wpdb; echo $wpdb->prefix;' 2>/dev/null)

# ── 1. Instalacja z ZIP w ODWROTNEJ kolejnosci + aktywacja ──────────────────
for z in mp-workflow-automator mp-warranty-registry mp-service-intake; do
	wp plugin install "$DIST_DIR/$z.zip" --force >/dev/null 2>&1
done
wp plugin activate mp-workflow-automator mp-warranty-registry mp-service-intake >/dev/null 2>&1
ACT=$(wp plugin list --status=active --field=name 2>/dev/null | grep -c "^mp-")
[ "$ACT" = "3" ] && ok "3 wtyczki z ZIP zainstalowane+aktywne (odwrotna kolejnosc)" || bad "aktywnych mp-: $ACT"
BI=$(wp eval 'echo file_exists(WP_PLUGIN_DIR."/mp-service-intake/BUILD-INFO.json") ? "1" : "0";' 2>/dev/null)
[ "$BI" = "1" ] && ok "BUILD-INFO.json w paczce (artefakt CI, nie dev)" || bad "brak BUILD-INFO.json"
[ "$(has_table mp_service_cases)" = "1" ] && ok "schemat utworzony przy aktywacji z ZIP" || bad "brak tabel po aktywacji z ZIP"

# ── 2. WP_DEBUG smoke: przeklikanie kluczowych ekranow ─────────────────────
: > "$LOG" 2>/dev/null
O=$(wp mp case-create --kind=zapytanie --email='smoke@example.com' --desc='x' 2>/dev/null)
T=$(echo "$O" | grep '^token=' | cut -d= -f2); wp mp case-verify "$T" >/dev/null 2>&1
UID1=$(wp user get 'smoke@example.com' --field=ID 2>/dev/null)
wp eval "wp_set_current_user($UID1); echo MP\Intake\Front\AccountPage::render();" >/dev/null 2>&1
wp eval "wp_set_current_user(1); MP\Intake\Admin\UnverifiedScreen::render_page();" >/dev/null 2>&1
NOISE=$(grep -iE "PHP (Notice|Warning|Deprecated|Fatal|Parse error)" "$LOG" 2>/dev/null | grep -E "mp-service-intake|mp-warranty-registry|mp-workflow-automator" | head -3)
[ -z "$NOISE" ] && ok "WP_DEBUG smoke z ZIP: ZERO notice z naszego kodu" || { bad "notice z naszego kodu:"; echo "$NOISE" | sed 's/^/      /'; }

# ── 3. Integralnosc ZIP: zero plikow dev ────────────────────────────────────
DEV=$(for z in mp-service-intake mp-warranty-registry mp-workflow-automator; do unzip -l "$DIST_DIR/$z.zip"; done | grep -icE "testy/|/\.git|vendor/|node_modules|phpunit\.xml|\.distignore|composer\.lock|\.DS_Store")
[ "$DEV" = "0" ] && ok "ZIP-y bez plikow dev (.git/testy/vendor/node_modules)" || bad "pliki dev w ZIP: $DEV"

# ── 4. Wersja spojna per plugin (naglowek Version == readme Stable tag) ─────
VOK=1
for p in mp-service-intake mp-warranty-registry mp-workflow-automator; do
	H=$(grep -iE "^\s*\*\s*Version:" "$(wp eval 'echo WP_PLUGIN_DIR;' 2>/dev/null)/$p/$p.php" | head -1 | sed 's/.*[Vv]ersion:\s*//' | tr -d '[:space:]')
	R=$(grep -iE "Stable tag:" "$(wp eval 'echo WP_PLUGIN_DIR;' 2>/dev/null)/$p/readme.txt" | head -1 | sed 's/.*[Tt]ag:\s*//' | tr -d '[:space:]')
	{ [ -n "$H" ] && [ "$H" = "$R" ]; } || { VOK=0; echo "      $p: header=$H readme=$R"; }
done
[ "$VOK" = "1" ] && ok "wersja spojna per plugin (Version == Stable tag)" || bad "rozjazd wersji header vs readme"

# ── 5. Uninstall grep-zero (opt-in delete-data) ─────────────────────────────
wp option update mp_intake_delete_data 1 >/dev/null 2>&1
wp option update mp_registry_delete_data 1 >/dev/null 2>&1
wp plugin deactivate mp-service-intake mp-warranty-registry mp-workflow-automator >/dev/null 2>&1
for p in mp-service-intake mp-warranty-registry mp-workflow-automator; do wp plugin uninstall "$p" >/dev/null 2>&1; done
TBL=$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name LIKE '${PFX}mp\\_%'")
OPT=$(q "SELECT COUNT(*) FROM ${PFX}options WHERE option_name LIKE 'mp\\_%' OR option_name LIKE '\\_transient\\_mp\\_%' OR option_name LIKE '\\_transient\\_timeout\\_mp\\_%'")
ROL=$(wp eval 'echo ( get_role("mp_client") || get_role("mp_agent") || get_role("mp_system_admin") || get_role("mp_coordinator") ) ? "1" : "0";' 2>/dev/null)
{ [ "${TBL:-1}" = "0" ] && [ "${OPT:-1}" = "0" ] && [ "$ROL" = "0" ]; } && ok "uninstall grep-zero: brak tabel/opcji mp_ i rol mp_*" || bad "slad po uninstall: tabele=$TBL opcje=$OPT role=$ROL"

echo
echo "WYNIK release-smoke: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
