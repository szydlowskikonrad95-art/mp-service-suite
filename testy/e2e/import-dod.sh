#!/usr/bin/env bash
# Testy DoD klocka B (karta B + K-C2): import 10k, kill-POLOWA-wznowienie,
# partia CSV->check, negatywne uprawnienia, snapshot-uninstall.
# Wymaga dzialajacego `wp` (żywy WP + baza). Chodzi tak samo na poligonie
# Dockera i w CI (job e2e-import). Exit 0 = wszystkie asercje przeszly.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

CSV=/tmp/mp-dod-10k.csv

# ── 0. Czysty stan modulu B ──────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_product_registry; DELETE FROM wp_mp_import_jobs; DELETE FROM wp_mp_product_events; DELETE FROM wp_mp_warranty_exceptions;" >/dev/null 2>&1

# ── 1. CSV: 10 000 wierszy danych (9970 OK + 20 pustych seriali + 10 duplikatow) ──
{
	printf '\xEF\xBB\xBF'   # BOM (parser ma go zdjac)
	echo "serial;model;partia;dokument_zakupu;data_zakupu;gwarancja_do"
	for i in $(seq 1 9970); do
		printf 'DOD-%06d;Żarówka DoD;PARTIA-DOD-7;FV/DOD/%d;15.03.2026;15.03.2028\n' "$i" "$i"
	done
	for i in $(seq 1 20); do
		echo ";BezSeriala;P;FV/E/$i;01.01.2026;01.01.2027"
	done
	for i in $(seq 1 10); do
		printf 'dod %06d;Duplikat;P;FV/D/%d;02.01.2026;02.01.2027\n' "$i" "$i"   # duplikat po normalizacji
	done
} > "$CSV"
LINES=$(( $(wc -l < "$CSV") - 1 ))
[ "$LINES" -eq 10000 ] && ok "CSV wygenerowany: 10000 wierszy danych" || bad "CSV ma $LINES wierszy"

# ── 2. Start importu + KILL -9 KLIENTA w polowie (K-C2: zabij klienta, nie serwer) ──
wp mp import-products "$CSV" > /tmp/mp-dod-import.log 2>&1 &
IMP_PID=$!
KILLED=0
for _ in $(seq 1 600); do
	P=$(q "SELECT COALESCE(MAX(processed_rows),0) FROM wp_mp_import_jobs")
	if [ "${P:-0}" -ge 3000 ]; then kill -9 "$IMP_PID" 2>/dev/null; KILLED=1; break; fi
	kill -0 "$IMP_PID" 2>/dev/null || break
	sleep 0.1
done
wait "$IMP_PID" 2>/dev/null
[ "$KILLED" -eq 1 ] && ok "klient zabity kill -9 w trakcie (processed=$P)" || bad "nie zdazono zabic (import skonczyl sie przy processed=$P) — test nie cwiczy wznowienia"

JOB=$(q "SELECT MAX(id) FROM wp_mp_import_jobs")
STATUS=$(q "SELECT status FROM wp_mp_import_jobs WHERE id=$JOB")
OLD_TOKEN=$(q "SELECT job_token FROM wp_mp_import_jobs WHERE id=$JOB")
[ "$STATUS" = "processing" ] && ok "job #$JOB po kill dalej processing (osierocony, nie zepsuty)" || bad "status po kill: $STATUS"

# Niezmiennik po crashu: ksiegowosc joba == realne wiersze w bazie (zero pol-zapisow).
ROWS=$(q "SELECT COUNT(*) FROM wp_mp_product_registry WHERE import_job_id=$JOB")
SUCC=$(q "SELECT success_rows FROM wp_mp_import_jobs WHERE id=$JOB")
[ "$ROWS" = "$SUCC" ] && ok "po crashu: success_rows($SUCC) == wiersze w bazie($ROWS) — transakcja batcha trzyma" || bad "rozjazd ksiegowosci: success=$SUCC vs rows=$ROWS"

# ── 3. Wznowienie od offsetu (wp mp import-resume = mechanika 'Wznow' z UI) ──
wp mp import-resume "$JOB" > /tmp/mp-dod-resume.log 2>&1 \
	&& ok "import-resume dokonczyl job" || bad "import-resume pad: $(tail -1 /tmp/mp-dod-resume.log)"

# Stary token (sprzed wznowienia) musi dostac odmowe.
OLD_REJ=$(wp eval "\$r = MP\Registry\Importer::process_batch($JOB, '$OLD_TOKEN'); echo \$r['status'];" 2>/dev/null)
[ "$OLD_REJ" = "error" ] && ok "stary token po wznowieniu odrzucony" || bad "stary token przeszedl: $OLD_REJ"

# ── 4. Wynik koncowy: liczby, zero duplikatow, raport bledow ──
read -r ST PR SU ER <<< "$(wp db query "SELECT status, processed_rows, success_rows, error_rows FROM wp_mp_import_jobs WHERE id=$JOB" --skip-column-names 2>/dev/null)"
[ "$ST" = "done" ] && [ "$PR" = "10000" ] && [ "$SU" = "9970" ] && [ "$ER" = "30" ] \
	&& ok "job done 10000/10000: success=9970, errors=30 (20 pustych + 10 duplikatow)" \
	|| bad "liczby joba: status=$ST processed=$PR success=$SU errors=$ER"

TOTAL=$(q "SELECT COUNT(*) FROM wp_mp_product_registry")
DIST=$(q "SELECT COUNT(DISTINCT serial_normalized) FROM wp_mp_product_registry")
[ "$TOTAL" = "9970" ] && [ "$TOTAL" = "$DIST" ] && ok "baza: 9970 wierszy, zero duplikatow po normalizacji" || bad "baza: total=$TOTAL distinct=$DIST"

REPORT=$(q "SELECT CONCAT(file_path,'.bledy.csv') FROM wp_mp_import_jobs WHERE id=$JOB")
RLINES=$(wp eval "echo count(array_filter(file('$REPORT') ?: []));" 2>/dev/null)
[ "$RLINES" = "31" ] && ok "raport bledow: 30 wierszy + naglowek" || bad "raport bledow ma $RLINES linii (oczekiwane 31)"

# ── 5. Partia: CSV -> rejestr -> zwrotka mp_warranty_check (test partii DoD) ──
BATCH=$(wp eval "\$c = apply_filters('mp_warranty_check', null, 'DOD-000001', null, null); echo \$c['batch'];" 2>/dev/null)
[ "$BATCH" = "PARTIA-DOD-7" ] && ok "partia z CSV wraca w mp_warranty_check (dziedziczona przez sprawe)" || bad "partia: '$BATCH'"

# ── 6. Negatywne uprawnienia (agent/klient/anonim nie dotkna wyjatkow ani archiwum) ──
wp user get mp-dod-agent >/dev/null 2>&1 || wp user create mp-dod-agent agent-dod@example.com --role=mp_agent --user_pass=x >/dev/null 2>&1
PID1=$(q "SELECT id FROM wp_mp_product_registry ORDER BY id LIMIT 1")
for U in "--user=mp-dod-agent" ""; do
	WHO=${U:-anonim}
	R=$(wp eval "\$r = MP\Registry\WarrantyExceptions::create($PID1, null, 'proba', null); echo isset(\$r['error']) ? 'DENIED' : 'ALLOWED';" $U 2>/dev/null)
	[ "$R" = "DENIED" ] && ok "wyjatek: $WHO dostaje odmowe" || bad "wyjatek: $WHO PRZESZEDL"
	R=$(wp eval "\$r = MP\Registry\Archive::archive($PID1); echo is_array(\$r) ? 'DENIED' : 'ALLOWED';" $U 2>/dev/null)
	[ "$R" = "DENIED" ] && ok "archiwum: $WHO dostaje odmowe" || bad "archiwum: $WHO PRZESZEDL"
done

# ── 7. Snapshot-uninstall (default OFF: dane zostaja, role/opcje znikaja; opt-in: tabele znikaja) ──
wp plugin uninstall mp-warranty-registry mp-service-intake mp-workflow-automator --deactivate --skip-delete >/dev/null 2>&1 \
	&& ok "uninstall x3 przeszedl bez fatala" || bad "uninstall pad"
T=$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name LIKE 'wp\\_mp\\_%'")
[ "${T:-0}" -ge 4 ] && ok "default OFF: tabele wp_mp_* ZOSTALY ($T) — dane klienta nieruszone" || bad "default OFF skasowal tabele! ($T)"
ROLES=$(wp eval "echo implode(',', array_filter(array_keys(MP\Common\Roles::ROLES ?? []), fn(\$r) => null !== get_role(\$r)));" 2>/dev/null)
[ -z "$ROLES" ] && ok "role mp_* zdjete przez ostatni modul" || bad "role zostaly: $ROLES"
ADMCAP=$(wp eval "echo get_role('administrator')->has_cap('mp_system_admin') ? 'MA' : 'BRAK';" 2>/dev/null)
[ "$ADMCAP" = "BRAK" ] && ok "caps personelu zdjete z administratora" || bad "administrator dalej ma mp_system_admin"
OPTS=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name LIKE 'mp\\_module\\_%' OR option_name LIKE 'mp\\_%\\_delete\\_data'")
[ "${OPTS:-9}" = "0" ] && ok "markery modulow i opcje techniczne skasowane" || bad "zostalo $OPTS opcji technicznych"

wp plugin activate mp-warranty-registry mp-service-intake mp-workflow-automator >/dev/null 2>&1
wp option update mp_registry_delete_data 1 >/dev/null 2>&1
wp plugin uninstall mp-warranty-registry --deactivate --skip-delete >/dev/null 2>&1
T2=$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name LIKE 'wp\\_mp\\_product%' OR table_schema=DATABASE() AND table_name IN ('wp_mp_import_jobs','wp_mp_warranty_exceptions')")
[ "${T2:-9}" = "0" ] && ok "opt-in delete_data: tabele B skasowane" || bad "opt-in: zostalo $T2 tabel B"
VOPT=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name LIKE 'mp\\_registry\\_schema%'")
[ "${VOPT:-9}" = "0" ] && ok "opcja wersji schematu umarla razem z tabelami" || bad "opcja wersji schematu zostala"

# Odtworzenie stanu poligonu (nie zostawiamy rozgrzebanego WP).
wp plugin activate mp-warranty-registry >/dev/null 2>&1

echo
echo "WYNIK DoD: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
