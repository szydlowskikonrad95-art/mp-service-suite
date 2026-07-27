#!/usr/bin/env bash
# ZYWY DOWOD (audyt cyklu zycia 27.07): cron, ktory raz zniknal, NIE WRACAL.
#
# Zadania cykliczne byly planowane WEWNATRZ bramki wersji schematu w maybe_upgrade():
#   if ( wersja >= LATEST ) return;   <-- wyjscie w pierwszej linii
#   ... wp_schedule_event( ... )      <-- nigdy nie wykonane na ustabilizowanej instalacji
# Skutek: gdy zadanie znika z listy WordPressa z przyczyny SPOZA wtyczki (migracja
# hostingu, wtyczka optymalizujaca kasujaca "nieznane" zadania, przywrocenie starszej
# kopii tabeli opcji), NIC go nie odtwarza — az admin recznie wylaczy i wlaczy wtyczke.
# A te zadania sprzataja DANE OSOBOWE: zalaczniki i porzucone zgloszenia (Intake)
# oraz pliki CSV z serialami i nazwiskami (Registry). Ich cicha smierc = dane zostaja
# na zawsze, a system wyglada na sprawny.
# Automator mial ten wzorzec naprawiony po realnej awarii; Intake i Registry NIE.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

zaplanowany() { wp cron event list --fields=hook --format=count --hook="$1" 2>/dev/null || echo 0; }

HAKI="mp_intake_retention_sweep mp_registry_imports_sweep mp_automator_sla_sweep"

# ── 0. Stan wyjsciowy: wszystkie 3 zadania zaplanowane ──────────────────────
for h in $HAKI; do
	[ "$(zaplanowany "$h")" -ge 1 ] 2>/dev/null && ok "stan wyjsciowy: $h zaplanowany" || bad "stan wyjsciowy: brak $h"
done

# ── 1. SYMULACJA AWARII: ktos kasuje zadania (np. wtyczka optymalizujaca) ───
for h in $HAKI; do wp cron event delete "$h" >/dev/null 2>&1; done
ZNIKNELY=0
for h in $HAKI; do [ "$(zaplanowany "$h")" = "0" ] && ZNIKNELY=$((ZNIKNELY+1)); done
[ "$ZNIKNELY" = "3" ] && ok "symulacja: wszystkie 3 zadania skasowane" || bad "nie udalo sie skasowac zadan ($ZNIKNELY/3)"

# ── 2. SEDNO: samo wejscie do panelu (admin_init) MUSI je odtworzyc ─────────
# Wersja schematu jest juz aktualna, wiec maybe_upgrade() wychodzi wczesnie —
# planowanie crona musi byc PRZED ta bramka, inaczej nic sie nie odtworzy.
wp eval '
	MP\Intake\Lifecycle::maybe_upgrade();
	MP\Registry\Lifecycle::maybe_upgrade();
	MP\Automator\Lifecycle::maybe_upgrade();
' >/dev/null 2>&1

for h in $HAKI; do
	[ "$(zaplanowany "$h")" -ge 1 ] 2>/dev/null \
		&& ok "$h ODTWORZONY bez reaktywacji wtyczki" \
		|| bad "$h NIE wrocil — sprzatanie danych milczy na zawsze"
done

# ── 3. Diagnostyka WIDZI brak zadania (zeby awaria nie byla cicha) ──────────
for h in $HAKI; do wp cron event delete "$h" >/dev/null 2>&1; done

ST_INTAKE=$(wp eval 'echo MP\Intake\Admin\SiteHealthTests::test_cron_retencji()["status"] ?? "brak";' 2>/dev/null | tr -d '[:space:]')
[ "$ST_INTAKE" = "critical" ] && ok "Stan witryny (Intake) krzyczy o braku sprzatania" || bad "Intake: diagnostyka milczy ($ST_INTAKE)"

ST_REG=$(wp eval 'echo MP\Registry\Admin\SiteHealthTests::test_cron_importow()["status"] ?? "brak";' 2>/dev/null | tr -d '[:space:]')
[ "$ST_REG" = "critical" ] && ok "Stan witryny (Rejestr) krzyczy o braku sprzatania" || bad "Rejestr: diagnostyka milczy ($ST_REG)"

# ── 4. Przywroc stan i potwierdz, ze diagnostyka znow jest zielona ──────────
wp eval '
	MP\Intake\Lifecycle::maybe_upgrade();
	MP\Registry\Lifecycle::maybe_upgrade();
	MP\Automator\Lifecycle::maybe_upgrade();
' >/dev/null 2>&1
ST_OK=$(wp eval 'echo MP\Intake\Admin\SiteHealthTests::test_cron_retencji()["status"] ?? "brak";' 2>/dev/null | tr -d '[:space:]')
[ "$ST_OK" = "good" ] && ok "po odtworzeniu diagnostyka wraca na zielono" || bad "diagnostyka nie wraca do good ($ST_OK)"

echo ""
echo "WYNIK CRON-ODTWARZA-SIE: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
