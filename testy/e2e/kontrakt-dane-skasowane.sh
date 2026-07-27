#!/usr/bin/env bash
# ZYWY DOWOD (audyt papierow 27.07): kontrakt `mp_cases_data_erased` byl MARTWY.
#
# Sygnal jest opisany w API-KONTRAKT.md, OWNERSHIP.md, EVENT_MODEL.md i na
# diagramie architektury; Rejestr ma gotowego sluchacza (cofa wyjatki gwarancyjne
# przypiete do spraw) — a NIKT go nigdy nie emitowal. Po odinstalowaniu Intake
# w pozostalych wtyczkach zostawaly wiersze wiszace na nieistniejacych sprawach,
# a dokumentacja obiecywala klientowi cos przeciwnego (ta sama klasa bledu co #14).
# FIX: uninstall C emituje sygnal PO skasowaniu tabel; D dostal brakujacego
# sluchacza (czysci terminy i checklisty, rejestr operacji ZOSTAJE — historia).
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ── 0. Emitent ISTNIEJE w kodzie uninstalla (bramka na regresje) ────────────
grep -q "do_action( 'mp_cases_data_erased' )" "$GITHUB_WORKSPACE/mp-service-intake/uninstall.php" \
	&& ok "uninstall Intake EMITUJE sygnal kontraktowy" \
	|| bad "uninstall NIE emituje mp_cases_data_erased (kontrakt znowu martwy)"

# ── 1. Stan wyjsciowy: wiersze D + wyjatek gwarancyjny na sprawe ────────────
# reklamacja WYMAGA serialu, dokumentu zakupu i daty (walidacja formularza) —
# bez nich sprawa w ogole nie powstaje i seed leci pusty.
O=$(wp mp case-create --kind=reklamacja --email='erased@example.com' --name='Ewa Erased' --desc='test kontraktu' --serial='MPERASED1' --document='FV/2026/900' --date='2026-05-01' 2>/dev/null)
CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2)
wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe' WHERE id=$CID" >/dev/null 2>&1
wp eval "MP\\Automator\\Sla::on_case_created($CID);" >/dev/null 2>&1
wp db query "INSERT INTO wp_mp_case_checklists (case_id, template_id, step_key, step_label, completed, completed_by, completed_at, created_at, updated_at)
	VALUES ($CID, 'reklamacja', 'krok_testowy', 'Krok testowy', 1, 1, UTC_TIMESTAMP(), UTC_TIMESTAMP(), UTC_TIMESTAMP())" >/dev/null 2>&1

SLA0=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID")
CHK0=$(q "SELECT COUNT(*) FROM wp_mp_case_checklists WHERE case_id=$CID")
{ [ "$SLA0" = "1" ] && [ "$CHK0" = "1" ]; } && ok "seed: Automator ma termin i checkliste tej sprawy" || bad "seed zly (sla=$SLA0 chk=$CHK0)"

EVENTS0=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events")

# ── 2. Sygnal => D czysci SWOJE wiersze przypiete do spraw ──────────────────
wp eval "do_action('mp_cases_data_erased');" >/dev/null 2>&1

SLA1=$(q "SELECT COUNT(*) FROM wp_mp_case_sla")
[ "$SLA1" = "0" ] && ok "terminy SLA wyczyszczone (zero wierszy na martwych sprawach)" || bad "terminy zostaly ($SLA1)"
CHK1=$(q "SELECT COUNT(*) FROM wp_mp_case_checklists")
[ "$CHK1" = "0" ] && ok "checklisty wyczyszczone" || bad "checklisty zostaly ($CHK1)"

# ── 3. Kontrola: rejestr operacji ZOSTAJE (historia, nie dane sprawy) ───────
EVENTS1=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events")
[ "${EVENTS1:-0}" -ge "${EVENTS0:-0}" ] 2>/dev/null \
	&& ok "rejestr operacji NIETKNIETY (historia dzialania automatyzacji zostaje)" \
	|| bad "rejestr operacji skasowany! ($EVENTS0 -> $EVENTS1)"

SLAD=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE payload LIKE '%cases_data_erased%'")
[ "${SLAD:-0}" -ge 1 ] 2>/dev/null && ok "sprzatanie zapisane w rejestrze" || bad "brak sladu sprzatania"

# ── 4. Rejestr: wyjatek gwarancyjny per sprawa cofniety, globalny zostaje ───
wp db query "INSERT INTO wp_mp_warranty_exceptions (product_registry_id, case_id, status, valid_from, reason, created_by, created_at)
	VALUES (1, 999999, 'active', UTC_TIMESTAMP(), 'test per-sprawa', 1, UTC_TIMESTAMP())" >/dev/null 2>&1
wp db query "INSERT INTO wp_mp_warranty_exceptions (product_registry_id, case_id, status, valid_from, reason, created_by, created_at)
	VALUES (1, NULL, 'active', UTC_TIMESTAMP(), 'test globalny', 1, UTC_TIMESTAMP())" >/dev/null 2>&1
wp eval "do_action('mp_cases_data_erased');" >/dev/null 2>&1

PER=$(q "SELECT COUNT(*) FROM wp_mp_warranty_exceptions WHERE case_id IS NOT NULL AND status='active'")
[ "${PER:-1}" = "0" ] && ok "wyjatki przypiete do spraw cofniete" || bad "wyjatek per-sprawa dalej aktywny ($PER)"
GLOB=$(q "SELECT COUNT(*) FROM wp_mp_warranty_exceptions WHERE case_id IS NULL AND status='active'")
[ "${GLOB:-0}" -ge 1 ] 2>/dev/null && ok "wyjatek GLOBALNY nietkniety (kontrakt)" || bad "skasowano wyjatek globalny! ($GLOB)"

echo ""
echo "WYNIK KONTRAKT-DANE-SKASOWANE: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
