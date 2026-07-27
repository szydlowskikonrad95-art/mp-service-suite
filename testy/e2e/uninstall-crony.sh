#!/usr/bin/env bash
# ZYWY DOWOD (audytor spojnosci paczki, 27.07): odinstalowanie zostawialo CRONA.
#
# Kazda wtyczka planuje wlasne zadanie cykliczne (Intake — retencja zalacznikow
# i porzuconych zgloszen; Registry — sprzatanie importow; Automator — sweep SLA
# i dokanczanie przeliczen). Deaktywacja czyscila je poprawnie (petla po
# CRON_HOOKS), ale uninstall mial OSOBNA, recznie wpisana liste — i w dwoch
# wtyczkach byla PUSTA. Efekt: po odinstalowaniu wtyczki zaplanowane zadanie
# zostawalo w bazie WordPressa na zawsze, mimo ze OWNERSHIP.md obiecuje
# "warstwa (i) ZAWSZE: opcje techniczne, transienty, CRONY".
# Dotychczasowy test uninstalla sprawdzal tabele i opcje — cronow NIE dotykal,
# dlatego nikt tego nie zlapal.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

HAKI="mp_intake_retention_sweep mp_registry_imports_sweep mp_automator_sla_sweep"

# ── 0. Po aktywacji zadania SA zaplanowane (inaczej test nic nie dowodzi) ────
for hak in $HAKI; do
	ILE=$(wp cron event list --fields=hook --format=count --hook="$hak" 2>/dev/null || echo 0)
	[ "${ILE:-0}" -ge 1 ] 2>/dev/null \
		&& ok "stan wyjsciowy: $hak zaplanowany" \
		|| bad "stan wyjsciowy: BRAK $hak (aktywacja go nie zaplanowala?)"
done

# ── 1. Odinstalowanie WSZYSTKICH trzech wtyczek ─────────────────────────────
wp plugin deactivate mp-service-intake mp-warranty-registry mp-workflow-automator >/dev/null 2>&1
wp plugin uninstall mp-service-intake mp-warranty-registry mp-workflow-automator >/dev/null 2>&1

# ── 2. SEDNO: zero zaplanowanych zadan po odinstalowaniu ────────────────────
for hak in $HAKI; do
	ILE=$(wp cron event list --fields=hook --format=count --hook="$hak" 2>/dev/null || echo 0)
	[ "${ILE:-0}" = "0" ] \
		&& ok "$hak sprzatniety przy odinstalowaniu" \
		|| bad "$hak ZOSTAL w bazie po odinstalowaniu ($ILE) — zadanie-widmo"
done

# ── 3. Kontrola: w tabeli opcji nie ma sladu naszych hakow ──────────────────
SLAD=$(wp db query "SELECT COUNT(*) FROM wp_options WHERE option_name='cron' AND option_value LIKE '%mp_intake_%'" --skip-column-names 2>/dev/null | tr -d '[:space:]')
[ "${SLAD:-0}" = "0" ] \
	&& ok "wpis 'cron' w opcjach nie zawiera juz naszych hakow" \
	|| bad "haki MP dalej siedza w opcji 'cron' ($SLAD)"

echo ""
echo "WYNIK UNINSTALL-CRONY: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
