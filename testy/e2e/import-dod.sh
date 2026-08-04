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

# ── 4b. D2 (RODO retencja): finish kasuje zrodlowy CSV, raport ZOSTAJE; cron sprzata sieroty ─
SRCFILE=$(q "SELECT file_path FROM wp_mp_import_jobs WHERE id=$JOB")
SRCEX=$(wp eval "echo file_exists('$SRCFILE') ? '1' : '0';" 2>/dev/null)
[ "$SRCEX" = "0" ] && ok "D2: zrodlowy CSV skasowany po finish (PII nie zostaje na dysku)" || bad "D2: zrodlowy CSV ZOSTAL po finish ($SRCFILE)"
[ "$RLINES" = "31" ] && ok "D2: raport .bledy.csv przetrwal finish (admin pobiera przez handle_report)" || bad "D2: raport zniknal po finish"
# Cron retencji: sierota starsza niz prog kasowana, guardy chronione.
SWDEL=$(wp eval '
$d = rtrim(wp_upload_dir()["basedir"],"/")."/mp-imports";
file_put_contents($d."/d2-orphan.csv","x"); touch($d."/d2-orphan.csv", time()-2*DAY_IN_SECONDS);
$n = MP\Registry\Importer::sweep_import_files(DAY_IN_SECONDS);
echo (file_exists($d."/d2-orphan.csv")?"ZOSTAL":"SKASOWANA")."|".((file_exists($d."/.htaccess")&&file_exists($d."/index.php"))?"GUARD-OK":"GUARD-USZK");
' 2>/dev/null)
[ "$SWDEL" = "SKASOWANA|GUARD-OK" ] && ok "D2: cron sweep kasuje sierote >24h, chroni guardy katalogu" || bad "D2: sweep zle zadzialal ($SWDEL)"

# ── 5. Partia: CSV -> rejestr -> zwrotka mp_warranty_check (test partii DoD) ──
BATCH=$(wp eval "\$c = apply_filters('mp_warranty_check', null, 'DOD-000001', null, null); echo \$c['batch'];" 2>/dev/null)
[ "$BATCH" = "PARTIA-DOD-7" ] && ok "partia z CSV wraca w mp_warranty_check (dziedziczona przez sprawe)" || bad "partia: '$BATCH'"

# ── 5b. PRZYKLAD DOLACZONY DO WTYCZKI: klient klika „Pobierz przykladowy CSV" i importuje go ──
# Sens: plik z przyklady/ jedzie w ZIP-ie i jest linkowany z ekranu importu. Jesli kiedys
# przestanie sie importowac (zmiana parsera, slownika kategorii, formatu dat), klient dostanie
# przyklad ktory NIE dziala. Tu przechodzi PELNA droga na zywym WP, nie tylko przez parser.
SAMPLE=$(wp eval "echo plugin_dir_path( MP_REGISTRY_FILE ) . 'przyklady/przyklad-import-produktow.csv';" 2>/dev/null)
if [ -n "$SAMPLE" ] && [ -f "$SAMPLE" ]; then
	ok "przyklad znaleziony w katalogu wtyczki ($(basename "$SAMPLE"))"
	wp mp import-products "$SAMPLE" > /tmp/mp-sample-import.log 2>&1
	SJOB=$(q "SELECT MAX(id) FROM wp_mp_import_jobs")
	SROWS=$(q "SELECT success_rows FROM wp_mp_import_jobs WHERE id=$SJOB")
	SERR=$(q "SELECT error_rows FROM wp_mp_import_jobs WHERE id=$SJOB")
	[ "$SROWS" = "8" ] && [ "$SERR" = "0" ] && ok "przyklad zaimportowany w calosci: 8 wierszy, 0 bledow" || bad "przyklad: success=$SROWS bledy=$SERR (oczekiwano 8/0)"

	# Zrodlo MUSI przetrwac (D2 kasuje kopie w uploads, nie plik wtyczki — inaczej
	# pierwszy import zjadalby dolaczony przyklad).
	[ -f "$SAMPLE" ] && ok "D2: plik-przyklad w katalogu wtyczki przetrwal import" || bad "D2: import SKASOWAL dolaczony przyklad"

	# Data w formacie polskiego Excela (15.02.2026) sprowadzona do Y-m-d.
	SDATE=$(q "SELECT purchase_date FROM wp_mp_product_registry WHERE serial_normalized='SNAGD2001'")
	[ "$SDATE" = "2026-02-15" ] && ok "data d.m.Y z przykladu znormalizowana do $SDATE" || bad "data z przykladu: '$SDATE'"

	# Kategoria podana ETYKIETA ("Elektronika audio" / "AGD drobne") zapisana jako slug.
	SCAT=$(q "SELECT category FROM wp_mp_product_registry WHERE serial_normalized='SNAUD1002'")
	SCAT2=$(q "SELECT category FROM wp_mp_product_registry WHERE serial_normalized='SNAGD2002'")
	[ "$SCAT" = "audio" ] && [ "$SCAT2" = "agd" ] && ok "kategoria z etykiety zapisana slugiem (audio/agd)" || bad "kategoria z etykiety: '$SCAT'/'$SCAT2'"

	# Wiersz minimalny (tylko serial + model): kategoria = fallback, daty puste.
	SMIN=$(q "SELECT CONCAT(category,'|',IFNULL(purchase_date,'NULL'),'|',IFNULL(warranty_until,'NULL')) FROM wp_mp_product_registry WHERE serial_normalized='SNOTH4001'")
	[ "$SMIN" = "inne|NULL|NULL" ] && ok "wiersz minimalny: kategoria=inne, daty puste" || bad "wiersz minimalny: '$SMIN'"

	# Przyklad pokazuje OBA stany gwarancji — aktywna i wygasla (widoczne plakietki w adminie).
	SACT=$(wp eval "\$c = apply_filters('mp_warranty_check', null, 'SN-AUD-1001', null, null); echo \$c['status'];" 2>/dev/null)
	SEXP=$(wp eval "\$c = apply_filters('mp_warranty_check', null, 'SN-AUD-1003', null, null); echo \$c['status'];" 2>/dev/null)
	[ "$SACT" = "aktywna" ] && [ "$SEXP" = "wygasla" ] && ok "przyklad pokazuje oba stany gwarancji (aktywna + wygasla)" || bad "stany gwarancji z przykladu: '$SACT'/'$SEXP'"

	# Serial z myslnikami rozpoznawany po normalizacji (tak jak w opisie dla klienta).
	SNORM=$(wp eval "\$c = apply_filters('mp_warranty_check', null, 'sn aud 1001', null, null); echo \$c['status'];" 2>/dev/null)
	[ "$SNORM" = "aktywna" ] && ok "'sn aud 1001' = 'SN-AUD-1001' (normalizacja serialu dziala na zywo)" || bad "normalizacja serialu: '$SNORM'"
else
	bad "nie znaleziono przykladu przyklady/przyklad-import-produktow.csv w katalogu wtyczki"
fi

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

# ── 6b. BRAMKA ARCHIWIZACJI: aktywna sprawa blokuje archiwum (2.17) ─────────
# Audyt wymienia `Archive` wsrod klas bez ani jednego testu i pisze o niej wprost:
# „jedyna rzecz w produkcie zrobiona wzorcowo, i nietestowana". Dotad sprawdzalismy
# tu WYLACZNIE odmowe dla agenta i anonima (punkt 6 wyzej) — czyli uprawnienia.
# SAMA BRAMKA (nie archiwizuj produktu, ktory ma otwarta sprawe) nie byla pilnowana
# nigdzie: ani liczba spraw, ani odmowa przy niejednoznacznej odpowiedzi modulu
# spraw, ani odmiana komunikatu przez przypadki.
# Liczbe aktywnych spraw podajemy filtrem — bramka pyta o nia kontraktem, wiec
# test nie musi zakladac spraw w bazie ani niczego po sobie sprzatac.
ARCH=$(wp eval '
	$pid = (int) $GLOBALS["wpdb"]->get_var( "SELECT id FROM wp_mp_product_registry ORDER BY id LIMIT 1" );
	wp_set_current_user( 1 );
	$u = wp_get_current_user();
	$u->add_cap( "mp_system_admin" );

	$wynik = array( "pid" => $pid );
	$probuj = static function ( $ile ) use ( $pid ) {
		$f = static function () use ( $ile ) { return $ile; };
		add_filter( "mp_product_active_cases_count", $f, 99 );
		$r = MP\Registry\Archive::archive( $pid );
		remove_filter( "mp_product_active_cases_count", $f, 99 );
		return is_array( $r ) ? (string) $r["error"] : "ARCHIWUM";
	};

	$wynik["blokada_1"]  = $probuj( 1 );
	$wynik["blokada_3"]  = $probuj( 3 );
	$wynik["blokada_5"]  = $probuj( 5 );
	$wynik["niepewne"]   = $probuj( "nie wiem" );
	$wynik["bez_spraw"]  = $probuj( 0 );
	$wynik["w_bazie"]    = (string) $GLOBALS["wpdb"]->get_var( "SELECT archived FROM wp_mp_product_registry WHERE id = " . $pid );
	$wynik["juz_w_arch"] = $probuj( 0 );

	// Sprzatanie: produkt wraca poza archiwum, uprawnienie zdjete z konta.
	$GLOBALS["wpdb"]->query( "UPDATE wp_mp_product_registry SET archived = 0 WHERE id = " . $pid );
	$u->remove_cap( "mp_system_admin" );

	echo wp_json_encode( $wynik, JSON_UNESCAPED_UNICODE );
' 2>/dev/null)

echo "$ARCH" | grep -qF 'Produkt ma 1 aktywną sprawę' \
	&& ok "archiwizacja: 1 otwarta sprawa BLOKUJE i mowi to poprawna polszczyzna" \
	|| bad "bramka archiwizacji przy 1 sprawie ($ARCH)"
echo "$ARCH" | grep -qF 'Produkt ma 3 aktywne sprawy' \
	&& ok "archiwizacja: 3 sprawy — odmiana przez przypadki (2-4)" \
	|| bad "zla odmiana przy 3 sprawach ($ARCH)"
echo "$ARCH" | grep -qF 'Produkt ma 5 aktywnych spraw' \
	&& ok "archiwizacja: 5 spraw — odmiana przez przypadki (5+)" \
	|| bad "zla odmiana przy 5 sprawach ($ARCH)"
echo "$ARCH" | grep -q 'FAIL-CLOSED' \
	&& ok "archiwizacja: niejednoznaczna odpowiedz modulu spraw => ODMOWA (fail-closed)" \
	|| bad "niejednoznaczna odpowiedz nie zatrzymala archiwizacji ($ARCH)"
echo "$ARCH" | grep -q '"bez_spraw":"ARCHIWUM"' \
	&& ok "archiwizacja: zero aktywnych spraw => produkt idzie do archiwum" \
	|| bad "bramka blokuje TAKZE produkt bez spraw ($ARCH)"
echo "$ARCH" | grep -q '"w_bazie":"1"' \
	&& ok "archiwizacja zapisala sie w bazie (nie tylko zwrocila zgode)" \
	|| bad "produkt nie trafil do archiwum w bazie ($ARCH)"
echo "$ARCH" | grep -qF 'już w archiwum' \
	&& ok "archiwizacja drugi raz => grzeczna odmowa zamiast cichego powtorzenia" \
	|| bad "powtorna archiwizacja nie jest wychwytywana ($ARCH)"
ARCH_ZOST=$(q "SELECT COUNT(*) FROM wp_mp_product_registry WHERE archived=1")
[ "${ARCH_ZOST:-9}" = "0" ] \
	&& ok "test przywrocil produkt poza archiwum (nic nie zostaje po sobie)" \
	|| bad "produkt zostal w archiwum ($ARCH_ZOST) — nastepny test dostanie inny stan"

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
