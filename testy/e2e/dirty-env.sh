#!/usr/bin/env bash
# DoD C sekcja 4 — DIRTY-ENV: brudny WP, nie sterylny lab.
# - niestandardowy prefiks bazy (cms_x9_)
# - WP_DEBUG=true => ZERO notice/warning/deprecated/Fatal z NASZEGO kodu przy przeklikaniu
# - persistent object-cache ON (drop-in) => nasz kod nie Fataluje przy cache
# - degraded: aktywacja 3 wtyczek w KAZDEJ kolejnosci, brak brata = brak-danych, NIGDY Fatal
# Uruchamiany w dedykowanym jobie CI (install z prefiksem+debug+object-cache).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

LOG="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/debug.log"

# ── 1. Srodowisko: niestandardowy prefiks + object-cache ON ─────────────────
PREFIX=$(wp eval 'global $wpdb; echo $wpdb->prefix;' 2>/dev/null)
[ "$PREFIX" = "cms_x9_" ] && ok "niestandardowy prefiks bazy ($PREFIX)" || bad "prefiks nie cms_x9_ ($PREFIX)"
OC=$(wp eval 'echo wp_using_ext_object_cache() ? "1" : "0";' 2>/dev/null)
[ "$OC" = "1" ] && ok "persistent object-cache ON (drop-in aktywny)" || bad "object-cache OFF ($OC)"

# ── 2. Degraded: aktywacja w ODWROTNEJ kolejnosci, nigdy Fatal ──────────────
wp plugin deactivate mp-service-intake mp-warranty-registry mp-workflow-automator >/dev/null 2>&1
ORDER_OK=1
for p in mp-workflow-automator mp-warranty-registry mp-service-intake; do
	wp plugin activate "$p" >/dev/null 2>&1 || ORDER_OK=0
done
[ "$ORDER_OK" = "1" ] && ok "aktywacja 3 wtyczek w ODWROTNEJ kolejnosci — brak Fatal" || bad "aktywacja w odwrotnej kolejnosci Fatalowala"

# tylko intake (brak brata B/D) — degraded, nie Fatal
wp plugin deactivate mp-warranty-registry mp-workflow-automator >/dev/null 2>&1
DEG=$(wp eval "echo MP\Intake\Front\AccountPage::url() ? 'OK' : 'OK';" 2>&1)
echo "$DEG" | grep -qiE "fatal|error" && bad "degraded (tylko intake) Fatal: $DEG" || ok "degraded (tylko intake) — brak Fatal"
wp plugin activate mp-warranty-registry mp-workflow-automator >/dev/null 2>&1

# ── 3. Smoke: przeklikanie kodu przy WP_DEBUG (create/verify/render/admin) ──
: > "$LOG" 2>/dev/null
O1=$(wp mp case-create --kind=zapytanie --email='dirty@example.com' --name='Dirty' --desc='x' 2>/dev/null)
T1=$(echo "$O1" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$T1" >/dev/null 2>&1
UID1=$(wp user get 'dirty@example.com' --field=ID 2>/dev/null)
wp eval "wp_set_current_user($UID1); echo MP\Intake\Front\AccountPage::render();" >/dev/null 2>&1
wp eval "wp_set_current_user($UID1); echo MP\Intake\Front\AccountPage::render();" >/dev/null 2>&1
wp mp case-create --kind=reklamacja --email='dirty2@example.com' --serial='DIRTY-1' --document='FV/1' --date='2026-03-15' --desc='y' >/dev/null 2>&1
wp eval "wp_set_current_user(1); MP\Intake\Admin\UnverifiedScreen::render_page();" >/dev/null 2>&1
wp eval "MP\Intake\CaseRepo::unverified_cases();" >/dev/null 2>&1

# ── 4. WP_DEBUG: ZERO notice/warning/deprecated/Fatal z NASZEGO kodu ────────
NOISE=$(grep -iE "PHP (Notice|Warning|Deprecated|Fatal|Parse error)" "$LOG" 2>/dev/null | grep -E "mp-service-intake|mp-warranty-registry|mp-workflow-automator|lib/mp-common" | head -5)
if [ -z "$NOISE" ]; then
	ok "WP_DEBUG: ZERO notice/warning/deprecated z NASZEGO kodu przy przeklikaniu"
else
	bad "notice/warning z naszego kodu w debug.log:"
	echo "$NOISE" | sed 's/^/      /'
fi

echo
echo "WYNIK dirty-env: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
