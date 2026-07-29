#!/usr/bin/env bash
# ZYWY DOWOD (audyt 29.07): aktualizacja wtyczki PRZELICZA terminy spraw juz otwartych.
#
# Co bylo zle: `migration_2_warning_at()` dokladalo kolumne `warning_at` golym dbDelta,
# bez przeliczenia istniejacych wierszy. Sweep przypomnien wymaga `warning_at IS NOT NULL`,
# wiec KAZDA sprawa otwarta w chwili aktualizacji przestawala dostawac przypomnienie
# PRZED terminem — dostawala tylko eskalacje PO. Dotyczylo to dokladnie spraw stojacych
# w miejscu, czyli tych, dla ktorych ten mechanizm powstal. Naprawialo sie samo dopiero
# przy zmianie statusu albo po recznym „Przelicz SLA".
#
# Test odtwarza aktualizacje: sprawa otwarta -> `warning_at` wyzerowane i wersja schematu
# cofnieta (tak wyglada stan tuz po podmianie plikow) -> `maybe_upgrade()` -> termin
# ostrzezenia MUSI byc policzony.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp eval "global \$wpdb; \$v = \$wpdb->get_var(\"$1\"); echo null === \$v ? '' : \$v;" 2>/dev/null | tr -d '[:space:]'; }

# ── 0. Sprawa otwarta z policzonym terminem (stan wyjsciowy) ────────────────
OUT=$(wp mp case-create --kind=reklamacja --email=upgrade@example.com --name='T Test' --serial=UPG-1 --document='FV/2026/9' --date='2026-05-01' --desc='x' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
TOK=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp eval "MP\Intake\CaseRepo::verify('$TOK');" >/dev/null 2>&1

[ -n "$CID" ] && ok "sprawa testowa utworzona (id=$CID)" || bad "nie udalo sie utworzyc sprawy"

W0=$(q "SELECT warning_at FROM wp_mp_case_sla WHERE case_id=$CID")
[ -n "$W0" ] && ok "stan wyjsciowy: termin ostrzezenia policzony ($W0)" || bad "brak terminu ostrzezenia na starcie (test nic nie dowiedzie)"

# ── 1. Stan TUZ PO podmianie plikow: kolumna pusta, wersja schematu cofnieta ─
wp eval 'global $wpdb; $wpdb->query("UPDATE wp_mp_case_sla SET warning_at = NULL");' >/dev/null 2>&1
wp eval 'update_option(MP\Automator\Schema::VERSION_OPTION, (int) MP\Automator\Schema::LATEST - 1);' >/dev/null 2>&1

W1=$(q "SELECT IFNULL(warning_at,'') FROM wp_mp_case_sla WHERE case_id=$CID")
[ -z "$W1" ] && ok "stan po podmianie plikow: termin ostrzezenia pusty" || bad "nie udalo sie odtworzyc stanu po aktualizacji ($W1)"

# ── 2. SEDNO: sciezka aktualizacji przelicza terminy spraw JUZ otwartych ────
wp eval 'MP\Automator\Lifecycle::maybe_upgrade();' >/dev/null 2>&1

W2=$(q "SELECT IFNULL(warning_at,'') FROM wp_mp_case_sla WHERE case_id=$CID")
[ -n "$W2" ] \
	&& ok "SEDNO: po aktualizacji termin ostrzezenia policzony ($W2)" \
	|| bad "po aktualizacji termin ostrzezenia DALEJ pusty — sprawa nigdy nie dostanie przypomnienia przed terminem"

# ── 3. Przeliczenie NIE resetuje markerow wysylki (zero powtorzonych maili) ──
wp eval "global \$wpdb; \$wpdb->query(\"UPDATE wp_mp_case_sla SET reminder_sent_at = '2026-01-01 00:00:00' WHERE case_id=$CID\");" >/dev/null 2>&1
wp eval 'update_option(MP\Automator\Schema::VERSION_OPTION, (int) MP\Automator\Schema::LATEST - 1);' >/dev/null 2>&1
wp eval 'MP\Automator\Lifecycle::maybe_upgrade();' >/dev/null 2>&1

MARK=$(q "SELECT IFNULL(reminder_sent_at,'') FROM wp_mp_case_sla WHERE case_id=$CID")
[ "$MARK" = "2026-01-0100:00:00" ] \
	&& ok "przeliczenie nie rusza markera wysylki (stare powiadomienia nie wyjda drugi raz)" \
	|| bad "marker wysylki zmieniony przez przeliczenie ($MARK) — grozi powtorzonym mailem"

# ── 4. Bramka wersji dziala: drugie wejscie to juz no-op ────────────────────
WER=$(q "SELECT option_value FROM wp_options WHERE option_name='mp_automator_schema_version'")
LATEST=$(wp eval 'echo MP\Automator\Schema::LATEST;' 2>/dev/null | tr -d '[:space:]')
[ "$WER" = "$LATEST" ] \
	&& ok "wersja schematu podniesiona do $LATEST (kolejne wejscia do panelu nic nie przeliczaja)" \
	|| bad "wersja schematu po aktualizacji = $WER, oczekiwane $LATEST"

echo ""
echo "WYNIK UPGRADE-TERMINY: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
