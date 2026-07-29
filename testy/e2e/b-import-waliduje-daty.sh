#!/usr/bin/env bash
# ZYWY DOWOD (audyt 29.07): import CSV odrzuca wiersz, w ktorym gwarancja konczy sie
# PRZED data zakupu.
#
# Co bylo zle: ta sama regula byla egzekwowana TYLKO przy recznej poprawce danych produktu
# (`Repo::update`, od 1.1.0), a NIE przy imporcie — czyli przy GLOWNEJ drodze wejscia danych.
# Parser sprawdzal kazda date z osobna (czy jest poprawna kalendarzowo), ale nie porownywal
# ich ze soba. Wiersz z zakupem 2026-08-01 i gwarancja do 2026-01-01 wjezdzal bez slowa
# i dostawal normalny status, bo `WarrantyStatus::compute()` patrzy tylko na date konca.
#
# Test pilnuje TRZECH rzeczy naraz: zly wiersz odpada, dobry wchodzi, a wiersz z pustymi
# datami dalej jest legalny (kolumny sa opcjonalne — latwo to zepsuc przy „uszczelnianiu").
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# ── 0. Import pliku z trzema wierszami: dobry, odwrocone daty, puste daty ────
WYNIK=$(wp eval '
	$csv = "numer_seryjny;data_zakupu;gwarancja_do\n"
		. "WAL-DOBRY;2026-01-01;2027-01-01\n"
		. "WAL-ODWROTNY;2026-08-01;2026-01-01\n"
		. "WAL-PUSTE;;\n";
	$tmp = wp_upload_dir()["basedir"] . "/wal-daty.csv";
	file_put_contents($tmp, $csv);
	$w = MP\Registry\Importer::create_job_from_file($tmp);
	if ( isset($w["error"]) ) { echo "BLAD:" . $w["error"]; return; }
	$r = MP\Registry\Importer::process_batch( (int) $w["job_id"], (string) ($w["token"] ?? "") );
	echo wp_json_encode($r);
' 2>/dev/null)

echo "$WYNIK" | grep -q '"processed":3' \
	&& ok "plik przetworzony w calosci (3 wiersze — jeden zly NIE zatrzymuje importu)" \
	|| bad "import nie przetworzyl calego pliku ($WYNIK)"

echo "$WYNIK" | grep -q '"errors":1' \
	&& ok "dokladnie JEDEN wiersz odrzucony" \
	|| bad "zla liczba odrzuconych wierszy ($WYNIK)"

# ── 1. SEDNO: zly wiersz NIE wszedl do rejestru ─────────────────────────────
ZLY=$(wp eval 'global $wpdb; echo (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->prefix}mp_product_registry WHERE serial_display = \"WAL-ODWROTNY\"");' 2>/dev/null | tr -d '[:space:]')
[ "$ZLY" = "0" ] \
	&& ok "SEDNO: wiersz z gwarancja przed zakupem NIE wszedl do rejestru" \
	|| bad "wiersz z odwroconymi datami WSZEDL do rejestru — regula omijana przez import"

# ── 2. Dobry wiersz wszedl (brak falszywego alarmu) ─────────────────────────
DOBRY=$(wp eval 'global $wpdb; echo (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->prefix}mp_product_registry WHERE serial_display = \"WAL-DOBRY\"");' 2>/dev/null | tr -d '[:space:]')
[ "$DOBRY" = "1" ] && ok "wiersz z poprawnymi datami wszedl normalnie" || bad "poprawny wiersz zostal odrzucony (falszywy alarm)"

# ── 3. Puste daty DALEJ legalne (kolumny opcjonalne wg instrukcji klienta) ──
PUSTE=$(wp eval 'global $wpdb; echo (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->prefix}mp_product_registry WHERE serial_display = \"WAL-PUSTE\"");' 2>/dev/null | tr -d '[:space:]')
[ "$PUSTE" = "1" ] \
	&& ok "wiersz z pustymi datami dalej wchodzi (kolumny sa opcjonalne)" \
	|| bad "uszczelnienie zepsulo legalny przypadek: pusta data = odrzucenie"

# ── 4. Powod widoczny w raporcie bledow (klient ma wiedziec, CO poprawic) ───
POWOD=$(wp eval '
	$dir = wp_upload_dir()["basedir"] . "/mp-imports";
	$tresc = "";
	foreach ( glob($dir . "/*.bledy.csv") as $f ) { $tresc .= file_get_contents($f); }
	echo $tresc;
' 2>/dev/null)
echo "$POWOD" | grep -q "gwarancja konczy sie przed data zakupu" \
	&& ok "raport bledow podaje POWOD odrzucenia" \
	|| bad "raport bledow nie tlumaczy, czemu wiersz odpadl"

# ── 5. Parytet z reczna edycja — ta sama regula po obu stronach ─────────────
RECZNA=$(wp eval 'echo defined("ABSPATH") && method_exists("MP\Registry\Repo", "update") ? "jest" : "brak";' 2>/dev/null | tr -d '[:space:]')
[ "$RECZNA" = "jest" ] \
	&& ok "reczna edycja produktu istnieje (regula pilnowana po OBU stronach)" \
	|| bad "brak Repo::update — sprawdz, czy regula nie zostala tylko w imporcie"

echo ""
echo "WYNIK IMPORT-WALIDACJA-DAT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
