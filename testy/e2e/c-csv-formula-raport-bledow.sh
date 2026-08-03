#!/usr/bin/env bash
# ZYWY DOWOD (część 1, punkt 1 — waga KRYTYCZNA): raport bledow importu nie
# wypuszcza FORMULY do arkusza kalkulacyjnego.
#
# Wartosc szla z pliku klienta do raportu SUROWA. Administrator pobiera ten
# raport i otwiera w arkuszu — komorka zaczynajaca sie od znaku rownosci jest
# tam formula i WYKONA sie. Autor opisal te ochrone w bliźniaczym module jako
# „OBOWIAZKOWE (RCE u klienta)" i tam ja zastosowal; tutaj jej nie bylo.
#
# Sciezka wyzwolenia jest zwykla: ten sam numer seryjny dwa razy w jednym pliku
# => drugi wiersz odpada jako duplikat => trafia do raportu bledow.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

echo "== 0. PROBY KONTROLNE REGULY =="
# Najpierw: czy regula w ogole rozpoznaje formule i czy nie psuje zwyklych wartosci.
F=$(wp eval 'echo MP\Registry\Common\Csv::harden( "=1+1" );' 2>/dev/null | tr -d '\r')
Z=$(wp eval 'echo MP\Registry\Common\Csv::harden( "SN-AUD-1001" );' 2>/dev/null | tr -d '\r')
[ "$F" = "'=1+1" ] && ok "wartosc zaczynajaca sie od znaku rownosci dostaje apostrof" || bad "harden zwrocil '$F'"
[ "$Z" = "SN-AUD-1001" ] && ok "zwykly numer seryjny NIE jest zmieniany (brak falszywych alarmow)" || bad "zwykla wartosc zmieniona na '$Z'"
for ZNAK in '+' '-' '@'; do
	W=$(wp eval "echo MP\\Registry\\Common\\Csv::harden( \"${ZNAK}cmd\" );" 2>/dev/null | tr -d '\r')
	[ "$W" = "'${ZNAK}cmd" ] && ok "znak '$ZNAK' tez rozpoznany jako poczatek formuly" || bad "znak '$ZNAK' przepuszczony ($W)"
done

echo "== 1. TA SAMA REGULA W OBU MODULACH (jedno zrodlo, nie dwie kopie) =="
A=$(wp eval 'echo MP\Automator\Common\Csv::harden( "=2+2" );' 2>/dev/null | tr -d '\r')
[ "$A" = "'=2+2" ] && ok "modul automatu uzywa tej samej reguly" || bad "modul automatu zwrocil '$A'"

echo "== 2. WIERSZ RAPORTU: FORMULA UNIESZKODLIWIONA, KOLUMNY CALE =="
# Numer seryjny z separatorem w srodku — kolumny nie moga sie rozjechac.
WIERSZ=$(wp eval 'echo MP\Registry\Common\Csv::row( array( "3", "=1+1", "duplikat: serial juz istnieje" ) );' 2>/dev/null | tr -d '\r')
case "$WIERSZ" in *"'=1+1"*) ok "formula w wierszu raportu ma apostrof" ;; *) bad "wiersz bez ochrony: $WIERSZ" ;; esac
WIERSZ2=$(wp eval 'echo MP\Registry\Common\Csv::row( array( "4", "SN;Z-SREDNIKIEM", "blad" ) );' 2>/dev/null | tr -d '\r')
case "$WIERSZ2" in *'"SN;Z-SREDNIKIEM"'*) ok "wartosc ze srednikiem cytowana (kolumny sie nie rozjezdzaja)" ;; *) bad "brak cytowania: $WIERSZ2" ;; esac

echo "== 3. ZNACZNIK KODOWANIA W RAPORCIE BLEDOW =="
BOM=$(wp eval 'echo bin2hex( MP\Registry\Common\Csv::BOM );' 2>/dev/null | tr -d '[:space:]')
[ "$BOM" = "efbbbf" ] && ok "wspolna stala znacznika kodowania poprawna" || bad "znacznik = $BOM"
grep -q "Csv::BOM" "${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"/mp-warranty-registry/includes/Importer.php \
	&& ok "raport bledow importu zaczyna sie od znacznika (polskie znaki czytelne)" || bad "raport bledow nadal bez znacznika"

echo "== 4. ZERO KOPII REGULY W KODZIE =="
KOPIE=$(grep -rl "in_array( \$first, array( '=', '+', '-'" "${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"/mp-service-intake/includes "${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"/mp-warranty-registry/includes "${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"/mp-workflow-automator/includes 2>/dev/null | grep -cv "Common/Csv.php" || true)
[ "${KOPIE:-0}" = "0" ] && ok "regula zyje w jednym miejscu (brak kopii do rozjechania)" || bad "$KOPIE kopii reguly w kodzie"

echo "== 5. PELNY PRZELOT IMPORTU — dokladnie ta sciezka, ktora opisuje zgloszenie =="
# Ten sam numer seryjny dwa razy => drugi wiersz odpada jako duplikat => raport bledow.
KAT=$(wp eval 'echo wp_upload_dir()["basedir"];' 2>/dev/null | tr -d '[:space:]')
PLIK="$KAT/mp-test-formula.csv"
wp eval "file_put_contents( '$PLIK', \"serial;model;data_zakupu;koniec_gwarancji\n=1+1;Model X;2026-01-01;2030-01-01\n=1+1;Model X;2026-01-01;2030-01-01\n\" );" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_product_registry; DELETE FROM wp_mp_import_jobs;" >/dev/null 2>&1
wp mp import-products "$PLIK" >/dev/null 2>&1

RAPORT=$(wp eval "\$k = wp_upload_dir()['basedir'] . '/mp-imports'; \$p = glob( \$k . '/*.bledy.csv' ); echo \$p ? end( \$p ) : '';" 2>/dev/null | tr -d '[:space:]')
if [ -n "$RAPORT" ]; then
	TRESC=$(wp eval "echo file_get_contents( '$RAPORT' );" 2>/dev/null)
	case "$TRESC" in *"'=1+1"*) ok "POBRANY raport bledow ma formule z apostrofem (arkusz jej nie wykona)" ;; *) bad "raport zawiera SUROWA formule: $TRESC" ;; esac
	HEX=$(wp eval "echo bin2hex( substr( file_get_contents( '$RAPORT' ), 0, 3 ) );" 2>/dev/null | tr -d '[:space:]')
	[ "$HEX" = "efbbbf" ] && ok "raport zaczyna sie znacznikiem kodowania (polskie znaki czytelne w arkuszu)" || bad "brak znacznika na poczatku raportu ($HEX)"
else
	bad "nie powstal raport bledow — przelot niczego nie dowiodl"
fi
wp eval "@unlink( '$PLIK' );" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_product_registry; DELETE FROM wp_mp_import_jobs;" >/dev/null 2>&1

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
