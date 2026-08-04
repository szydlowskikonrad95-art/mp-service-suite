#!/usr/bin/env bash
# ZYWY DOWOD (2.28): zapis „wstaw albo zaktualizuj" nie uzywa juz wycofanej funkcji VALUES().
#
# `VALUES()` w klauzuli ON DUPLICATE KEY UPDATE jest WYCOFANE od MySQL 8.0.20. Produkt
# uzywal jej w trzech miejscach: `RateLimit.php` (dwa) i `Checklists.php` (jedno, piec
# kolumn). Demo stoi na MariaDB, ktora tego nie wycofala — ale zamowienie dopuszcza
# MySQL 8 ROWNORZEDNIE, wiec na takim serwerze produkt szedlby na przestarzalej skladni.
#
# ⚠️ Zamiennik z aliasem wiersza (`INSERT ... AS nowy`) ODPADA: zna go MySQL 8.0.19+,
# ale NIE ZNA MariaDB. Przenosne jest tylko podanie wartosci drugi raz — i wlasnie
# ta zamiana jest tu sprawdzana.
#
# Ten test pilnuje, ze:
#   1. w kodzie nie ma juz ANI JEDNEGO uzycia wycofanej konstrukcji (kontrola statyczna),
#   2. okno licznika NIE jest przedluzane cudza proba w trakcie jego trwania,
#   3. po wygasnieciu okna zapisuje sie NOWA data konca, a nie „teraz" (tu najlatwiej
#      pomylic kolejnosc parametrow przy tej zamianie — i test to zlapie),
#   4. marker dedup po ponownym zgloszeniu dostaje SWIEZA date konca,
#   5. checklista: ponowne odhaczenie NADPISUJE etykiete, stan i znaczniki czasu.
#
# Wymaga zywego `wp`. Exit 0 = OK. Test sprzata po sobie (wspolna baza w CI).
set -u

REPO="${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

KLUCZ='e2e-228-okno'
CASE_ID=990228

sprzataj() {
	wp db query "DELETE FROM wp_mp_rate_counters WHERE rl_key='$KLUCZ';" >/dev/null 2>&1
	wp db query "DELETE FROM wp_mp_case_checklists WHERE case_id=$CASE_ID;" >/dev/null 2>&1
}

sprzataj

echo "== 1. KONTROLA STATYCZNA: zero uzyc wycofanej konstrukcji =="
# ⚠️ To JEDYNE sprawdzenie statyczne w tym tescie i mowimy o tym wprost: stanowisko stoi
# na MariaDB, ktora `VALUES()` przyjmuje bez slowa, wiec zachowania nie da sie tu zmierzyc.
# Roznice widac dopiero na MySQL 8.0.20+ (kontrola `mysql8` w CI).
# ⚠️ Zbior plikow skladamy przez `find`, NIE przez `grep --include`. Powod zlapany
# kalibracja: obraz wiersza polecen WordPressa ma grep z BusyBoksa, ktory opcji
# `--include` NIE ZNA — blad szedl do /dev/null, licznik wychodzil 0 i sprawdzenie
# przechodzilo na kodzie SPRZED naprawy. Wada pomiaru, nie produktu.
ILE=$(find "$REPO/mp-service-intake" "$REPO/mp-workflow-automator" "$REPO/mp-warranty-registry" "$REPO/lib" \
	-type f -name '*.php' -exec grep -n "VALUES([a-z_]*)" {} + 2>/dev/null \
	| grep -v '//' | wc -l | tr -d '[:space:]')
[ "$ILE" = "0" ] && ok "zero uzyc VALUES(kolumna) w kodzie" || bad "wycofana konstrukcja dalej w kodzie ($ILE wystapien)"

echo "== 2. OKNO LICZNIKA NIE JEST PRZEDLUZANE W TRAKCIE TRWANIA =="
P1=$(wp eval "echo MP\\Intake\\RateLimit::claim_window( '$KLUCZ', 600 ) ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]')
[ "$P1" = "tak" ] && ok "pierwsza rezerwacja przyznana" || bad "pierwsza rezerwacja odrzucona ($P1)"
KONIEC1=$(q "SELECT window_expires_at FROM wp_mp_rate_counters WHERE rl_key='$KLUCZ';")
[ -n "$KONIEC1" ] && ok "data konca okna zapisana ($KONIEC1)" || bad "brak daty konca okna"
wp eval "MP\\Intake\\RateLimit::claim_window( '$KLUCZ', 600 );" >/dev/null 2>&1
KONIEC2=$(q "SELECT window_expires_at FROM wp_mp_rate_counters WHERE rl_key='$KLUCZ';")
[ "$KONIEC2" = "$KONIEC1" ] && ok "druga proba NIE przedluzyla okna" || bad "okno przedluzone cudza proba ($KONIEC1 -> $KONIEC2)"
LICZNIK=$(q "SELECT hits FROM wp_mp_rate_counters WHERE rl_key='$KLUCZ';")
[ "$LICZNIK" = "2" ] && ok "licznik prob podbity do 2" || bad "licznik prob: $LICZNIK (oczekiwano 2)"

echo "== 3. PO WYGASNIECIU OKNA ZAPISUJE SIE NOWA DATA KONCA =="
# ⛔ Tu wlasnie stala funkcja VALUES(window_expires_at). Po zamianie na podany drugi raz
# parametr latwo bylo wpisac „teraz" zamiast konca NOWEGO okna — dlatego sprawdzamy,
# ze data jest w PRZYSZLOSCI i mniej wiecej o zadane okno dalej.
wp db query "UPDATE wp_mp_rate_counters SET window_expires_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL 1 HOUR) WHERE rl_key='$KLUCZ';" >/dev/null 2>&1
wp eval "MP\\Intake\\RateLimit::claim_window( '$KLUCZ', 600 );" >/dev/null 2>&1
ZA_ILE=$(q "SELECT TIMESTAMPDIFF(SECOND, UTC_TIMESTAMP(), window_expires_at) FROM wp_mp_rate_counters WHERE rl_key='$KLUCZ';")
if [ -n "$ZA_ILE" ] && [ "$ZA_ILE" -gt 500 ] 2>/dev/null && [ "$ZA_ILE" -le 600 ] 2>/dev/null; then
	ok "nowe okno konczy sie za ${ZA_ILE}s (zadane 600) — zapisano koniec okna, a nie chwile biezaca"
else
	bad "po wygasnieciu okna zapisano zla wartosc (do konca: ${ZA_ILE}s, oczekiwano ~600)"
fi
LICZNIK2=$(q "SELECT hits FROM wp_mp_rate_counters WHERE rl_key='$KLUCZ';")
[ "$LICZNIK2" = "1" ] && ok "licznik zresetowany do 1 wraz z nowym oknem" || bad "licznik po resecie: $LICZNIK2"

echo "== 4. MARKER DEDUP DOSTAJE SWIEZA DATE KONCA =="
KLUCZ_D=$(wp eval "\$m = new ReflectionMethod( 'MP\\Intake\\RateLimit', 'dedup_key' ); \$m->setAccessible( true ); echo \$m->invoke( null, 'SN-228', 'e2e228@przyklad.test', 'reklamacja' );" 2>/dev/null | tr -d '[:space:]')
if [ -z "$KLUCZ_D" ]; then
	bad "nie udalo sie policzyc klucza dedup"
else
	wp eval "MP\\Intake\\RateLimit::mark_submitted( 'e2e228@przyklad.test', 'SN-228', 'reklamacja' );" >/dev/null 2>&1
	wp db query "UPDATE wp_mp_rate_counters SET window_expires_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL 1 HOUR) WHERE rl_key='$KLUCZ_D';" >/dev/null 2>&1
	wp eval "MP\\Intake\\RateLimit::mark_submitted( 'e2e228@przyklad.test', 'SN-228', 'reklamacja' );" >/dev/null 2>&1
	ZA_ILE_D=$(q "SELECT TIMESTAMPDIFF(SECOND, UTC_TIMESTAMP(), window_expires_at) FROM wp_mp_rate_counters WHERE rl_key='$KLUCZ_D';")
	if [ -n "$ZA_ILE_D" ] && [ "$ZA_ILE_D" -gt 800 ] 2>/dev/null; then
		ok "ponowne zgloszenie przesunelo koniec markera w przyszlosc (${ZA_ILE_D}s)"
	else
		bad "marker dedup nie dostal swiezej daty (do konca: ${ZA_ILE_D}s)"
	fi
	wp db query "DELETE FROM wp_mp_rate_counters WHERE rl_key='$KLUCZ_D';" >/dev/null 2>&1
fi

echo "== 5. CHECKLISTA: PONOWNE ODHACZENIE NADPISUJE WSZYSTKIE POLA =="
odhacz() {
	wp eval "
		wp_set_current_user( 1 );
		\$m = new ReflectionMethod( 'MP\\Automator\\Checklists', 'upsert_state' );
		\$m->setAccessible( true );
		\$m->invoke( null, $CASE_ID, 'reklamacja', 'krok-228', '$1', $2 );
	" >/dev/null 2>&1
}
odhacz 'Etykieta PIERWSZA' 'false'
ETY1=$(q "SELECT step_label FROM wp_mp_case_checklists WHERE case_id=$CASE_ID AND step_key='krok-228';")
ZROB1=$(q "SELECT completed FROM wp_mp_case_checklists WHERE case_id=$CASE_ID AND step_key='krok-228';")
[ "$ETY1" = "EtykietaPIERWSZA" ] && ok "pierwszy zapis kroku checklisty" || bad "pierwszy zapis: '$ETY1'"
[ "$ZROB1" = "0" ] && ok "krok nieodhaczony" || bad "stan kroku: $ZROB1"
odhacz 'Etykieta DRUGA' 'true'
ETY2=$(q "SELECT step_label FROM wp_mp_case_checklists WHERE case_id=$CASE_ID AND step_key='krok-228';")
ZROB2=$(q "SELECT completed FROM wp_mp_case_checklists WHERE case_id=$CASE_ID AND step_key='krok-228';")
KTO=$(q "SELECT completed_by FROM wp_mp_case_checklists WHERE case_id=$CASE_ID AND step_key='krok-228';")
KIEDY=$(q "SELECT completed_at IS NOT NULL FROM wp_mp_case_checklists WHERE case_id=$CASE_ID AND step_key='krok-228';")
ILE_WIERSZY=$(q "SELECT COUNT(*) FROM wp_mp_case_checklists WHERE case_id=$CASE_ID AND step_key='krok-228';")
[ "$ETY2" = "EtykietaDRUGA" ] && ok "etykieta NADPISANA przy ponownym zapisie" || bad "etykieta po nadpisaniu: '$ETY2'"
[ "$ZROB2" = "1" ] && ok "stan odhaczenia nadpisany" || bad "stan po nadpisaniu: $ZROB2"
[ -n "$KTO" ] && [ "$KTO" != "NULL" ] && ok "zapisano, KTO odhaczyl ($KTO)" || bad "brak autora odhaczenia ('$KTO')"
[ "$KIEDY" = "1" ] && ok "zapisano, KIEDY odhaczono" || bad "brak znacznika czasu odhaczenia"
[ "$ILE_WIERSZY" = "1" ] && ok "dalej JEDEN wiersz — to aktualizacja, nie duplikat" || bad "wierszy dla kroku: $ILE_WIERSZY"

sprzataj

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
