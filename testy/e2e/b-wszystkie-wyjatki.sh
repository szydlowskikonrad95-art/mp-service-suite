#!/usr/bin/env bash
# ZYWY DOWOD (2.13): ekran wyjatkow gwarancyjnych pokazuje WSZYSTKIE udzielone wyjatki.
#
# Do 1.3.12 ta pozycja w menu nigdy nie pokazywala danych: otwarta bez wybranego
# produktu wyswietlala wyjasnienie i przycisk „Przejdz do Rejestru MP". Pod spodem
# siedzial prawdziwy brak — KAZDE zapytanie do tabeli wyjatkow filtrowalo po jednym
# produkcie, wiec administrator, ktory przyznal ich dwadziescia, nie mial jak ich
# przejrzec. Specyfikacja wymaga „historii zmian danych produktu i decyzji gwarancyjnych".
#
# Ten test pilnuje, ze:
#   1. czytnik widzi wyjatki z ROZNYCH produktow w jednym wyniku,
#   2. ekran otwarty z menu (bez produktu) pokazuje je oba, a nie slepy zaulek,
#   3. filtr rozdziela aktywne / cofniete / wszystkie,
#   4. „przeterminowany" liczy sie Z DATY (w bazie status dalej brzmi 'active'),
#   5. licznik i lista chodza po tym samym warunku (strona 2 nie klamie),
#   6. stronicowanie tnie wynik, a nie ucina go po cichu,
#   7. ekran POJEDYNCZEGO produktu dalej pokazuje wylacznie jego wyjatki (regresja).
#
# Wymaga zywego `wp`. Exit 0 = OK. Test sprzata po sobie (wspolna baza w CI).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

S1='WYJ-TEST-1'; N1='WYJTEST1'
S2='WYJ-TEST-2'; N2='WYJTEST2'

# Ekran otwarty Z MENU — bez wskazanego produktu. Mierzymy to, co zobaczy czlowiek.
ekran_wszystkich() {
	wp eval "wp_set_current_user( $ADM ); \$_GET = array( 'page' => 'mp-registry-exceptions', 'f_status' => '$1' ); ob_start(); MP\\Registry\\Admin\\ExceptionsScreen::render(); echo ob_get_clean();" 2>/dev/null
}

ekran_produktu() {
	wp eval "wp_set_current_user( $ADM ); \$_GET = array( 'page' => 'mp-registry-exceptions', 'product' => $1 ); ob_start(); MP\\Registry\\Admin\\ExceptionsScreen::render(); echo ob_get_clean();" 2>/dev/null
}

sprzataj() {
	for N in "$N1" "$N2"; do
		P=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$N';")
		if [ -n "$P" ]; then
			wp db query "DELETE FROM wp_mp_warranty_exceptions WHERE product_registry_id=$P;" >/dev/null 2>&1
			wp db query "DELETE FROM wp_mp_product_events WHERE product_registry_id=$P;" >/dev/null 2>&1
			wp db query "DELETE FROM wp_mp_product_registry WHERE id=$P;" >/dev/null 2>&1
		fi
	done
}

sprzataj

# ⛔ LEKCJA Z CI (4.08) — ten sam ksztalt co w `b-historia-egzemplarza.sh`.
# W CI testy ida po kolei na JEDNEJ bazie, a `uninstall-crony.sh` odinstalowuje po
# drodze trzy wtyczki — `Uninstall::remove_roles()` KASUJE wtedy role `mp_system_admin`.
# `wp user create --role=<nieistniejaca>` konczy sie bledem, konto NIE powstaje, a blad
# w /dev/null zostawial samo puste ID. Dlatego: czytamy kod wyjscia, pokazujemy blad,
# uzywamy istniejacego konta, a przy braku roli nadajemy samo UPRAWNIENIE (ekran
# sprawdza `current_user_can()`, nie nazwe roli).
#
# ⚠️ `konto` oddaje wynik ZMIENNA, nie przez `$( )` — podstawienie polecenia odpala
# podpowloke i lista zalozonych kont ginelaby razem z nia (sprzatanie nie kasowaloby nic).
ZALOZONE_KONTA=''
KONTO_ID=''

konto() {
	LOGIN="$1"
	UPRAWNIENIE="$2"
	KONTO_ID=''
	MAIL="$LOGIN@b-wszystkie-wyjatki.test"

	ID=$(wp user get "$LOGIN" --field=ID 2>/dev/null | tr -d '[:space:]')

	if [ -z "$ID" ]; then
		WYNIK=$(wp user create "$LOGIN" "$MAIL" --porcelain 2>&1)
		KOD=$?
		ID=$(printf '%s' "$WYNIK" | tr -d '[:space:]' | grep -Eo '^[0-9]+$')

		if [ -z "$ID" ]; then
			bad "nie udalo sie zalozyc konta '$LOGIN' (kod $KOD): $WYNIK"
			return 1
		fi
	else
		echo "  --   konto '$LOGIN' juz istnieje (id=$ID) — uzywam istniejacego"
	fi

	ZALOZONE_KONTA="$ZALOZONE_KONTA $ID"

	if wp role exists "$UPRAWNIENIE" >/dev/null 2>&1; then
		wp user set-role "$ID" "$UPRAWNIENIE" >/dev/null 2>&1
	else
		echo "  --   rola '$UPRAWNIENIE' nie istnieje w tej bazie (poprzedni test ja usunal?) — nadaje samo uprawnienie"
		wp user add-cap "$ID" "$UPRAWNIENIE" >/dev/null 2>&1
	fi

	KONTO_ID="$ID"
}

konto wyj_adm mp_system_admin
ADM="$KONTO_ID"

# Bramka: konto ma NAPRAWDE dzialac na ekranie, inaczej test opowiadalby o pustej stronie.
if [ -n "$ADM" ]; then
	MOZE=$(wp eval "wp_set_current_user( $ADM ); echo current_user_can( 'mp_system_admin' ) ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]')
	[ "$MOZE" = "tak" ] || bad "konto $ADM nie ma uprawnienia 'mp_system_admin' (dostalo: '$MOZE')"
fi

for PARA in "$S1|$N1" "$S2|$N2"; do
	SER="${PARA%%|*}"; NOR="${PARA##*|}"
	wp db query "INSERT INTO wp_mp_product_registry
		(serial_display, serial_normalized, model, batch, category, purchase_document, purchase_date, warranty_until, source, archived, created_at, updated_at)
		VALUES ('$SER','$NOR','Model-$NOR','P-13','agd','FV/2026/13','2026-01-10','2027-01-10','csv_import',0,UTC_TIMESTAMP(),UTC_TIMESTAMP());" >/dev/null 2>&1
done

PID1=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$N1';")
PID2=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$N2';")

if [ -z "$PID1" ] || [ -z "$PID2" ] || [ -z "$ADM" ] || [ "$FAIL" -gt 0 ]; then
	bad "nie udalo sie przygotowac stanowiska (PID1=$PID1 PID2=$PID2 ADM=$ADM) — powod wyzej"
	for U in $ZALOZONE_KONTA; do wp user delete "$U" --yes >/dev/null 2>&1; done
	sprzataj
	echo "WYNIK: $PASS ok, $FAIL fail"
	exit 1
fi

echo "== 0. ZALOZENIE: wyjatki da sie nadac (bez tego test nie ma o czym mowic) =="
E1=$(wp eval "wp_set_current_user( $ADM ); \$r = MP\\Registry\\WarrantyExceptions::create( $PID1, null, 'Powod-pierwszy-213', null ); echo isset( \$r['id'] ) ? (int) \$r['id'] : 'ERR:'.\$r['error'];" 2>/dev/null | tr -d '[:space:]')
E2=$(wp eval "wp_set_current_user( $ADM ); \$r = MP\\Registry\\WarrantyExceptions::create( $PID2, null, 'Powod-drugi-213', null ); echo isset( \$r['id'] ) ? (int) \$r['id'] : 'ERR:'.\$r['error'];" 2>/dev/null | tr -d '[:space:]')
case "$E1$E2" in
	*ERR*) bad "nie udalo sie nadac wyjatkow ($E1 / $E2)" ;;
	*)     ok "dwa wyjatki nadane na DWA rozne produkty (#$E1, #$E2)" ;;
esac

echo "== 1. CZYTNIK WIDZI WYJATKI Z ROZNYCH PRODUKTOW W JEDNYM WYNIKU =="
WID=$(wp eval "\$w = MP\\Registry\\Repo::all_exceptions( 'active', 1, 100 ); \$id = array(); foreach ( \$w['rows'] as \$r ) { \$id[] = (int) \$r['id']; } echo implode( ',', \$id );" 2>/dev/null | tr -d '[:space:]')
case ",$WID," in
	*",$E1,"*) OK1=1 ;;
	*)         OK1=0 ;;
esac
case ",$WID," in
	*",$E2,"*) OK2=1 ;;
	*)         OK2=0 ;;
esac
[ "$OK1" = "1" ] && [ "$OK2" = "1" ] \
	&& ok "jeden wynik obejmuje oba produkty (przed naprawa KAZDE zapytanie filtrowalo po jednym produkcie)" \
	|| bad "wynik nie obejmuje obu wyjatkow (widziane: '$WID', szukane: $E1 i $E2)"

SER_W=$(wp eval "\$w = MP\\Registry\\Repo::all_exceptions( 'active', 1, 100 ); foreach ( \$w['rows'] as \$r ) { if ( (int) \$r['id'] === $E1 ) { echo \$r['serial_display']; } }" 2>/dev/null | tr -d '[:space:]')
[ "$SER_W" = "$S1" ] && ok "wiersz niesie numer seryjny produktu, nie samo ID" || bad "brak numeru seryjnego w wyniku ('$SER_W')"

echo "== 2. EKRAN Z MENU POKAZUJE WSZYSTKIE, A NIE SLEPY ZAULEK =="
HTML=$(ekran_wszystkich all)
echo "$HTML" | grep -q "$S1" && echo "$HTML" | grep -q "$S2" \
	&& ok "ekran otwarty z menu pokazuje wyjatki OBU produktow" \
	|| bad "ekran z menu nie pokazuje wyjatkow (przed naprawa stal tam wylacznie przycisk do rejestru)"
echo "$HTML" | grep -q 'Powod-pierwszy-213' && ok "widac powod decyzji" || bad "powod decyzji niewidoczny"
echo "$HTML" | grep -q 'wyj_adm' && ok "widac, KTO nadal wyjatek" || bad "brak autora decyzji"
echo "$HTML" | grep -q 'Przejdź do Rejestru MP' && ok "droga do rejestru zachowana (opisana w instrukcji ADMIN.md)" || bad "zniknelo przejscie do rejestru — instrukcja przestalaby sie zgadzac"

echo "== 3. FILTR ROZDZIELA AKTYWNE OD COFNIETYCH =="
wp eval "wp_set_current_user( $ADM ); MP\\Registry\\WarrantyExceptions::revoke( $E2 );" >/dev/null 2>&1
HTML_A=$(ekran_wszystkich active)
echo "$HTML_A" | grep -q "$S1" && ok "widok 'aktywne' pokazuje aktywny" || bad "widok 'aktywne' zgubil aktywny wyjatek"
echo "$HTML_A" | grep -q "$S2" && bad "widok 'aktywne' pokazuje COFNIETY wyjatek" || ok "widok 'aktywne' nie pokazuje cofnietego"
HTML_C=$(ekran_wszystkich revoked)
echo "$HTML_C" | grep -q "$S2" && ok "widok 'cofniete' pokazuje cofniety" || bad "widok 'cofniete' nie pokazuje cofnietego"
echo "$HTML_C" | grep -q "$S1" && bad "widok 'cofniete' pokazuje AKTYWNY wyjatek" || ok "widok 'cofniete' nie pokazuje aktywnego"

echo "== 4. PRZETERMINOWANY LICZY SIE Z DATY, NIE ZE STATUSU W BAZIE =="
# Wprost SQL-em: WarrantyExceptions::create() nie przyjmie daty z przeszlosci,
# a wlasnie taki wiersz powstaje sam z uplywem czasu.
wp db query "INSERT INTO wp_mp_warranty_exceptions
	(product_registry_id, case_id, status, valid_from, valid_until, reason, created_by, created_at)
	VALUES ($PID1, NULL, 'active', '2026-01-01 00:00:00', '2026-02-01 00:00:00', 'Powod-przeterminowany-213', $ADM, '2026-01-01 00:00:00');" >/dev/null 2>&1
E3=$(q "SELECT id FROM wp_mp_warranty_exceptions WHERE reason='Powod-przeterminowany-213';")
STAT=$(q "SELECT status FROM wp_mp_warranty_exceptions WHERE id=$E3;")
[ "$STAT" = "active" ] && ok "w bazie ten wiersz ma status 'active' (przeterminowanie NIE jest stanem w bazie)" || bad "status w bazie: '$STAT'"
HTML_P=$(ekran_wszystkich expired)
echo "$HTML_P" | grep -q 'Powod-przeterminowany-213' && ok "widok 'przeterminowane' go pokazuje" || bad "widok 'przeterminowane' go nie widzi"
echo "$HTML_P" | grep -q 'przeterminowany (wyliczone z daty)' && ok "etykieta mowi, ze to wyliczenie z daty" || bad "brak etykiety przeterminowania"
HTML_A2=$(ekran_wszystkich active)
echo "$HTML_A2" | grep -q 'Powod-przeterminowany-213' && bad "widok 'aktywne' pokazuje przeterminowany" || ok "widok 'aktywne' go nie pokazuje"

echo "== 5. LICZNIK I LISTA CHODZA PO TYM SAMYM WARUNKU =="
# ⚠️ Baza w CI jest WSPOLNA — innych wyjatkow moze byc dowolnie duzo, wiec nie
# porownujemy licznika z liczba wierszy wprost, tylko z min(licznik, per_page).
# Inaczej test padalby od cudzych danych, a nie od wady produktu.
for F in active revoked expired all; do
	ZGODA=$(wp eval "\$w = MP\\Registry\\Repo::all_exceptions( '$F', 1, 100 ); echo (int) ( count( \$w['rows'] ) === min( (int) \$w['total'], 100 ) ) . ':' . \$w['total'];" 2>/dev/null | tr -d '[:space:]')
	case "$ZGODA" in
		1:*) ok "filtr '$F': licznik zgodny z lista (wyjatkow: ${ZGODA#*:})" ;;
		*)   bad "filtr '$F': licznik rozjechany z lista ($ZGODA)" ;;
	esac
done

echo "== 6. STRONICOWANIE TNIE, A NIE UCINA PO CICHU =="
STR=$(wp eval "\$w = MP\\Registry\\Repo::all_exceptions( 'all', 1, 2 ); echo count( \$w['rows'] ) . '/' . \$w['total'];" 2>/dev/null | tr -d '[:space:]')
ILE_W="${STR%%/*}"; ILE_T="${STR##*/}"
[ "$ILE_W" = "2" ] && [ "$ILE_T" -ge 3 ] \
	&& ok "strona oddaje 2 wiersze, a licznik zna pelna liczbe ($STR)" \
	|| bad "stronicowanie: $STR (oczekiwano 2 wierszy i licznika >= 3)"
STR2=$(wp eval "\$w1 = MP\\Registry\\Repo::all_exceptions( 'all', 1, 2 ); \$w2 = MP\\Registry\\Repo::all_exceptions( 'all', 2, 2 ); echo (int) ( \$w1['rows'][0]['id'] !== ( \$w2['rows'][0]['id'] ?? 0 ) );" 2>/dev/null | tr -d '[:space:]')
[ "$STR2" = "1" ] && ok "strona 2 pokazuje inne wiersze niz strona 1" || bad "strona 2 powtarza stronę 1"

echo "== 7. EKRAN PRODUKTU DALEJ POKAZUJE WYLACZNIE JEGO WYJATKI (regresja) =="
HTML_1=$(ekran_produktu "$PID1")
echo "$HTML_1" | grep -q 'Powod-pierwszy-213' && ok "ekran produktu pokazuje jego wlasny wyjatek" || bad "ekran produktu zgubil wlasny wyjatek"
echo "$HTML_1" | grep -q 'Powod-drugi-213' && bad "ekran produktu pokazuje CUDZY wyjatek" || ok "ekran produktu nie miesza cudzych wyjatkow"
echo "$HTML_1" | grep -q 'Przyznaj wyjątek' && ok "formularz nadania wyjatku nietkniety" || bad "zniknal formularz nadania wyjatku"

# Sprzatanie po sobie — wspolna baza w CI.
sprzataj
# Kasujemy WYLACZNIE konta z tego przebiegu (wspolna baza w CI).
for U in $ZALOZONE_KONTA; do wp user delete "$U" --yes >/dev/null 2>&1; done

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
