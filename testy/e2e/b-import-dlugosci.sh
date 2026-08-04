#!/usr/bin/env bash
# ZYWY DOWOD (2.4 czesc a): import mowi, KTORE pole jest za dlugie i jaki jest limit.
#
# Produkt ZNA szerokosc kazdej kolumny i egzekwuje ja w formularzu
# (`Validator::validate_serial` — 2..100 znakow, dokladnie tyle, ile ma kolumna).
# DRUGIE drzwi do tej samej tabeli — import CSV — nie sprawdzaly dlugosci ani razu:
# numer o 249 znakach przechodzil przez parser i padal dopiero na ZAPISIE, a admin
# dostawal w raporcie „blad zapisu do bazy" — komunikat, ktory nie mowi, co poprawic.
# Granicy pilnowal silnik bazy, nie kod (zmierzone na zywym demie 3.08).
#
# ⛔ ZAKRES: to zamyka WYLACZNIE czesc (a). Czesc (b) — brak reguly dlugosci adresu
# e-mail na wszystkich sciezkach — siedzi w module zgloszen i jest osobna pozycja.
#
# Ten test pilnuje, ze:
#   1. za dlugi numer odpada w PARSERZE, z podana dlugoscia i limitem,
#   2. komunikat nie brzmi juz „blad zapisu do bazy" (to sedno pozycji),
#   3. limity zgadzaja sie z PRAWDZIWA szerokoscia kolumn (czytana z bazy),
#   4. dotyczy to wszystkich pol tekstowych, nie samego numeru,
#   5. za krotki numer tez odpada — tak samo jak w formularzu,
#   6. wiersz w granicach normy dalej wchodzi (bez uszczelniania na slepo).
#
# Wymaga zywego `wp`. Exit 0 = OK. Test sprzata po sobie (wspolna baza w CI).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Parser wolany wprost: jeden wiersz, jedna odpowiedz. `parse_row` dostaje komorki
# i mape kolumn — dokladnie to, co dostaje przy imporcie.
parsuj() {
	wp eval "
		\$map = array( 'serial' => 0, 'model' => 1, 'batch' => 2, 'purchase_doc' => 3 );
		\$w = MP\\Registry\\CsvParser::parse_row( array( '$1', '$2', '$3', '$4' ), \$map );
		echo empty( \$w['ok'] ) ? 'NIE: ' . \$w['error'] : 'TAK';
	" 2>/dev/null
}

powtorz() { wp eval "echo str_repeat( 'A', $1 );" 2>/dev/null | tr -d '[:space:]'; }

sprzataj() {
	wp db query "DELETE FROM wp_mp_product_registry WHERE serial_display LIKE 'DL-TEST%';" >/dev/null 2>&1
	wp db query "DELETE FROM wp_mp_import_jobs WHERE file_path LIKE '%dl-test-24a.csv';" >/dev/null 2>&1
}

sprzataj

echo "== 1. ZA DLUGI NUMER ODPADA W PARSERZE, Z LICZBAMI =="
DLUGI=$(powtorz 249)
WYNIK=$(parsuj "$DLUGI" 'Model' 'P-1' 'FV/1')
case "$WYNIK" in
	NIE:*) ok "wiersz odrzucony przez parser, nie przez baze" ;;
	*)     bad "za dlugi numer PRZESZEDL przez parser ($WYNIK)" ;;
esac
case "$WYNIK" in
	*249*) ok "komunikat podaje, ILE znakow ma pole (249)" ;;
	*)     bad "komunikat bez dlugosci pola: $WYNIK" ;;
esac
case "$WYNIK" in
	*100*) ok "komunikat podaje LIMIT (100)" ;;
	*)     bad "komunikat bez limitu: $WYNIK" ;;
esac
case "$WYNIK" in
	*"numer seryjny"*) ok "komunikat nazywa POLE po polsku" ;;
	*)                 bad "komunikat nie nazywa pola: $WYNIK" ;;
esac

echo "== 2. SEDNO: KONIEC Z KOMUNIKATEM 'BLAD ZAPISU DO BAZY' =="
# Pelna droga: plik -> zadanie -> przetworzenie -> raport bledow.
IMPORT=$(wp eval "
	\$csv = \"numer_seryjny;model\n\" . str_repeat( 'B', 249 ) . \";Model-DL\n\" . \"DL-TEST-OK;Model-OK\n\";
	\$tmp = wp_upload_dir()['basedir'] . '/dl-test-24a.csv';
	file_put_contents( \$tmp, \$csv );
	\$w = MP\\Registry\\Importer::create_job_from_file( \$tmp );
	if ( isset( \$w['error'] ) ) { echo 'BLAD:' . \$w['error']; return; }
	\$r = MP\\Registry\\Importer::process_batch( (int) \$w['job_id'], (string) ( \$w['token'] ?? '' ) );
	global \$wpdb;
	// Raport bledow to plik roboczy joba z koncowka .bledy.csv — dokladnie ten plik,
	// ktory administrator pobiera z ekranu importu. Kolumna error_report_path bywa
	// wypelniana dopiero przy zamknieciu zadania, wiec bierzemy obie drogi.
	// (Bez odwrotnych apostrofow: ten kod PHP siedzi w lancuchu w cudzyslowach,
	//  wiec powloka probowalaby je wykonac jako polecenie.)
	\$plik_roboczy = (string) \$wpdb->get_var( 'SELECT file_path FROM ' . \$wpdb->prefix . 'mp_import_jobs WHERE id = ' . (int) \$w['job_id'] );
	\$z_kolumny    = (string) \$wpdb->get_var( 'SELECT error_report_path FROM ' . \$wpdb->prefix . 'mp_import_jobs WHERE id = ' . (int) \$w['job_id'] );
	\$sciezka      = ( '' !== \$z_kolumny && file_exists( \$z_kolumny ) ) ? \$z_kolumny : \$plik_roboczy . '.bledy.csv';
	\$raport = ( '' !== \$sciezka && file_exists( \$sciezka ) ) ? file_get_contents( \$sciezka ) : '';
	echo \$plik_roboczy . '||' . wp_json_encode( \$r ) . '||' . \$raport;
" 2>/dev/null)
PLIK_ROBOCZY="${IMPORT%%||*}"
RESZTA="${IMPORT#*||}"
STAN="${RESZTA%%||*}"
RAPORT="${RESZTA#*||}"

case "$STAN" in
	*'"errors":1'*) ok "dokladnie jeden wiersz odrzucony (drugi wszedl)" ;;
	*)              bad "zla liczba odrzuconych ($STAN)" ;;
esac
case "$RAPORT" in
	*"blad zapisu do bazy"*) bad "raport DALEJ mowi 'blad zapisu do bazy' — administrator nie wie, co poprawic" ;;
	'')                      bad "nie udalo sie odczytac raportu bledow" ;;
	*)                       ok "raport nie zaslania sie juz bledem zapisu do bazy" ;;
esac
case "$RAPORT" in
	*249*) ok "raport bledow podaje dlugosc pola (249)" ;;
	*)     bad "raport bez dlugosci: $(printf '%s' "$RAPORT" | head -c 160)" ;;
esac
WSZEDL=$(q "SELECT COUNT(*) FROM wp_mp_product_registry WHERE serial_display='DL-TEST-OK';")
[ "$WSZEDL" = "1" ] && ok "dobry wiersz z tego samego pliku wszedl normalnie" || bad "dobry wiersz nie wszedl ($WSZEDL)"

echo "== 3. LIMITY ZGADZAJA SIE Z PRAWDZIWA SZEROKOSCIA KOLUMN =="
# ⛔ Liczb nie wpisujemy: bierzemy je z `information_schema`, czyli z tego samego
# miejsca, ktore rozstrzyga w praktyce. Gdyby ktos poszerzyl kolumne i zapomnial
# o parserze (albo odwrotnie), ten blok to zlapie.
for PARA in "serial_display|serial" "model|model" "batch|batch" "purchase_document|purchase_doc"; do
	KOL="${PARA%%|*}"; POLE="${PARA##*|}"
	SZER=$(q "SELECT CHARACTER_MAXIMUM_LENGTH FROM information_schema.COLUMNS WHERE TABLE_NAME='wp_mp_product_registry' AND COLUMN_NAME='$KOL' AND TABLE_SCHEMA=DATABASE();")
	if [ -z "$SZER" ]; then
		bad "nie udalo sie odczytac szerokosci kolumny $KOL"
		continue
	fi
	NA_STYK=$(powtorz "$SZER")
	ZA_DUZO=$(powtorz $((SZER + 1)))
	case "$POLE" in
		serial) W1=$(parsuj "$NA_STYK" 'M' 'P' 'F');       W2=$(parsuj "$ZA_DUZO" 'M' 'P' 'F') ;;
		model)  W1=$(parsuj 'DL-TEST-A' "$NA_STYK" 'P' 'F'); W2=$(parsuj 'DL-TEST-A' "$ZA_DUZO" 'P' 'F') ;;
		batch)  W1=$(parsuj 'DL-TEST-A' 'M' "$NA_STYK" 'F'); W2=$(parsuj 'DL-TEST-A' 'M' "$ZA_DUZO" 'F') ;;
		*)      W1=$(parsuj 'DL-TEST-A' 'M' 'P' "$NA_STYK"); W2=$(parsuj 'DL-TEST-A' 'M' 'P' "$ZA_DUZO") ;;
	esac
	[ "$W1" = "TAK" ] && ok "$KOL: wartosc o dlugosci kolumny ($SZER) przechodzi" || bad "$KOL: wartosc rowna szerokosci kolumny ODRZUCONA ($W1)"
	case "$W2" in
		NIE:*) ok "$KOL: wartosc o jeden znak dluzsza odrzucona" ;;
		*)     bad "$KOL: wartosc dluzsza niz kolumna PRZESZLA ($W2)" ;;
	esac
done

echo "== 4. ZA KROTKI NUMER TEZ ODPADA (jak w formularzu) =="
KROTKI=$(parsuj 'A' 'Model' 'P-1' 'FV/1')
case "$KROTKI" in
	NIE:*) ok "jednoznakowy numer odrzucony — ta sama regula co na drugiej drodze wejscia" ;;
	*)     bad "jednoznakowy numer przeszedl ($KROTKI)" ;;
esac

echo "== 5. WIERSZ W NORMIE DALEJ WCHODZI (bez uszczelniania na slepo) =="
NORMA=$(parsuj 'DL-TEST-NORMA' 'Model-X' 'P-9' 'FV/2026/9')
[ "$NORMA" = "TAK" ] && ok "zwykly wiersz przechodzi bez zmian" || bad "zwykly wiersz odrzucony ($NORMA)"

sprzataj
# Plik wsadowy, roboczy plik zadania i raport bledow — zeby na stanowisku nie zostawal
# osad po kazdym przebiegu (katalog importow jest wspolny).
wp eval "
	\$p = wp_upload_dir()['basedir'] . '/dl-test-24a.csv';
	if ( file_exists( \$p ) ) { unlink( \$p ); }
	\$r = '$PLIK_ROBOCZY';
	if ( '' !== \$r && file_exists( \$r ) ) { unlink( \$r ); }
	if ( '' !== \$r && file_exists( \$r . '.bledy.csv' ) ) { unlink( \$r . '.bledy.csv' ); }
" >/dev/null 2>&1

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
