#!/usr/bin/env bash
# ZYWY DOWOD Z2 (niezalezna kontrola wdrozenia 1.3.13, waga SREDNIA):
# ekran importu pokazywal dwie liczby, ktore czytalo sie jak sprzecznosc. Przy
# pliku 4-wierszowym z 3 bledami baner mowil „Import zakonczony: 4 z 4 wierszy,
# bledy: 3", a tabela obok „Zaimportowane / wszystkie = 1 / 4".
#
# ⛔ OBIE LICZBY BYLY POPRAWNE. Baner mowil o PRZETWORZONYCH (4 wiersze
# przerobione), tabela o WYNIKU (1 trafil do rejestru). Wada siedziala
# w NAPISIE: „4 z 4 wierszy" obiecuje wynik, a pokazuje postep — zwlaszcza ze
# przy pliku bez bledow brzmi identycznie („8 z 8 wierszy, bledy: 0").
# To TA SAMA pulapka, ktora naprawiono juz raz w naglowku kolumny tabeli
# („Wiersze" -> „Zaimportowane / wszystkie") — wtedy poprawiono EGZEMPLARZ,
# nie KLASE. Teraz napisy mowia wprost, co licza, i podaja obie liczby naraz.
#
# Kalibracja WBUDOWANA: A1/A2/A3 PADAJA na kodzie sprzed naprawy. Sekcja B to
# kontrola kierunku: znaczenie kolumn tabeli historii ma zostac NIETKNIETE.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_import_jobs; DELETE FROM wp_mp_product_registry" >/dev/null 2>&1

# Plik 1:1 ze scenariusza kontrolera: 4 wiersze danych, 3 celowe bledy.
# Wiersz 1 poprawny, 2 gwarancja przed zakupem, 3 duplikat, 4 zla data.
CSV=/tmp/z2-import.csv
cat > "$CSV" <<'CSVEOF'
serial;model;kategoria;dokument_zakupu;data_zakupu;gwarancja_do
SN-Z2-0001;Model Dobry;agd;FV/2026/1;2026-01-10;2028-01-10
SN-Z2-0002;Model Zly;agd;FV/2026/2;2026-05-01;2025-01-01
SN-Z2-0001;Model Duplikat;agd;FV/2026/3;2026-01-10;2028-01-10
SN-Z2-0004;Model Data;agd;FV/2026/4;NIE-DATA;2028-01-10
CSVEOF

# ⛔ Pola wyciagamy PHP-em, NIE pythonem — obraz wp-cli, na ktorym chodzi CI,
# nie ma pythona; test oparty na nim padlby wszedzie poza moja maszyna.
OUT=$(wp eval "\$j = MP\\Registry\\Importer::create_job_from_file( '$CSV' ); echo (int) ( \$j['job_id'] ?? 0 ), '|', (string) ( \$j['token'] ?? '' ), '|', (string) ( \$j['error'] ?? '' );" 2>/dev/null)
JOB="${OUT%%|*}"; RESZTA="${OUT#*|}"; TOK="${RESZTA%%|*}"
[ "$JOB" = "0" ] && JOB=""
[ -n "$JOB" ] && ok "0: job importu zalozony (id=$JOB)" || { bad "0: setup padl ($OUT)"; echo "── Z2: PASS=$PASS FAIL=$FAIL ──"; exit 1; }

# Mielimy do konca — dokladnie ta sama droga co JS (process_batch).
ZWROTKA=""
for i in 1 2 3 4 5 6 7 8; do
	# status|processed|success|errors — pusty 'success' = zwrotka sprzed naprawy
	ZWROTKA=$(wp eval "\$r = MP\\Registry\\Importer::process_batch( $JOB, '$TOK' ); echo (string) ( \$r['status'] ?? '' ), '|', (int) ( \$r['processed'] ?? 0 ), '|', ( array_key_exists( 'success', \$r ) ? (int) \$r['success'] : '' ), '|', (int) ( \$r['errors'] ?? 0 );" 2>/dev/null)
	S="${ZWROTKA%%|*}"
	[ "$S" = "done" ] && break
done
echo "     zwrotka koncowa: $ZWROTKA"

# Prawda z bazy: ile wierszy PRZYJAL rejestr.
W_REJESTRZE=$(q "SELECT COUNT(*) FROM wp_mp_product_registry")
SUCCESS_DB=$(q "SELECT success_rows FROM wp_mp_import_jobs WHERE id=$JOB")
echo "     w rejestrze: $W_REJESTRZE | success_rows w bazie: $SUCCESS_DB"

# ── A. NAPIS BANERA: mowi CO liczy i podaje OBIE liczby ─────────────────────
IFS='|' read -r _ PROCESSED SUCC BLEDY_Z <<EOF2
$ZWROTKA
EOF2
[ -n "$SUCC" ] || SUCC=$(( PROCESSED - BLEDY_Z ))   # zwrotka sprzed naprawy nie ma pola 'success'

# Skladamy napis DOKLADNIE tak, jak robi to JS: wzorzec z i18n + te same argumenty.
# Kolejnosc argumentow po naprawie: przetworzone, wszystkie, zaimportowane, bledy.
BANER=$(wp eval "
	\$m = new ReflectionMethod( 'MP\\Registry\\Admin\\ImportScreen', 'js_config' );
	\$m->setAccessible( true ); \$c = \$m->invoke( null );
	\$w = (string) \$c['i18n']['done'];
	\$ile = substr_count( \$w, '%' ) - substr_count( \$w, '%%' );
	echo 4 === \$ile
		? sprintf( \$w, $PROCESSED, 4, $SUCC, $BLEDY_Z )
		: sprintf( \$w, $PROCESSED, 4, $BLEDY_Z );" 2>/dev/null)
echo "     baner: $BANER"

case "$BANER" in
	*"przetworzono $PROCESSED z 4"*|*"Przetworzono $PROCESSED z 4"*)
		ok "A1: baner mowi WPROST, ze liczy przetworzone" ;;
	*) bad "A1: baner nie nazywa liczby przetworzonych: $BANER" ;;
esac
case "$BANER" in
	*"zaimportowano $W_REJESTRZE"*)
		ok "A2: baner podaje WYNIK ($W_REJESTRZE) bez zagladania do tabeli" ;;
	*) bad "A2: baner nie podaje liczby zaimportowanych ($W_REJESTRZE): $BANER" ;;
esac
# Kontrolna na sedno wady: przy pliku Z BLEDAMI napis NIE moze brzmiec tak samo
# jak przy pliku bez bledow, czyli „N z N wierszy, bledy" bez slowa o wyniku.
case "$BANER" in
	*"4 z 4 wierszy, błędy"*) bad "A3: napis dalej czyta sie jak wszystko-weszlo: $BANER" ;;
	*) ok "A3: zniknal mylacy wzorzec 'N z N wierszy, bledy'" ;;
esac

[ "$SUCC" = "$SUCCESS_DB" ] && [ "$SUCC" = "$W_REJESTRZE" ] \
	&& ok "A4: liczba zaimportowanych zgodna z baza i rejestrem ($SUCC)" \
	|| bad "A4: rozjazd (zwrotka=$SUCC, baza=$SUCCESS_DB, rejestr=$W_REJESTRZE)"
[ "$BLEDY_Z" = "3" ] && ok "A5: liczba bledow bez zmian (3)" || bad "A5: spodziewane 3 bledy, jest $BLEDY_Z"

# ── B. KONTROLA KIERUNKU: tabela historii ma znaczyc TO SAMO co dotad ────────
HTML=$(wp eval "
	\$m = new ReflectionMethod( 'MP\\Registry\\Admin\\ImportScreen', 'render_history' );
	\$m->setAccessible( true ); ob_start(); \$m->invoke( null ); echo ob_get_clean();" 2>/dev/null)
echo "$HTML" | grep -q "Zaimportowane / wszystkie" \
	&& ok "B1: naglowek kolumny tabeli nietkniety" || bad "B1: zmieniono naglowek kolumny historii"
echo "$HTML" | grep -q "$W_REJESTRZE / 4" \
	&& ok "B2: tabela dalej pokazuje $W_REJESTRZE / 4 (znaczenie kolumn bez zmian)" \
	|| bad "B2: tabela nie pokazuje '$W_REJESTRZE / 4'"

wp db query "DELETE FROM wp_mp_import_jobs; DELETE FROM wp_mp_product_registry" >/dev/null 2>&1
rm -f "$CSV"

echo "── Z2: PASS=$PASS FAIL=$FAIL ──"
if [ "$(( PASS + FAIL ))" -lt 8 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane 8."
	exit 2
fi
[ "$FAIL" -eq 0 ]
