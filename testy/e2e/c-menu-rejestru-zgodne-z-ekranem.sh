#!/usr/bin/env bash
# ZYWY DOWOD (soczewka S4, znalezisko 5): menu rejestru pokazuje sie tylko temu,
# kogo ekran wpusci.
#
# CO BYLO ZLE: pozycja „Rejestr MP" rejestrowala sie z capem z `menu_cap_for_current_user()`,
# ktory zwraca PIERWSZE uprawnienie z CALEGO personelu — koordynatorowi zwracal jego
# wlasne, wiec widzial pozycje w menu. Ekran dwadziescia linii nizej sprawdzal CO INNEGO
# (`mp_agent` albo `mp_system_admin`) i konczyl `wp_die( "Brak uprawnien do rejestru
# produktow." )`. Koordynator widzial drzwi, otwieral je i dostawal odmowe — nie wiedzac,
# czy to awaria, czy tak ma byc.
#
# ⛔ TEN TEST MIERZY OBIE STRONY. Naprawa, ktora chowa menu WSZYSTKIM, przechodzi polowe
#    kontroli i odbiera dostep tym, ktorzy go mieli. Dlatego tyle samo kontroli pilnuje,
#    ze pracownik i administrator DALEJ maja pozycje i DALEJ wchodza.
#
# ⛔ Zawezenia dostepu ponad dokumentacje NIE ROBIMY. Lista `REGISTRY_CAPS` jest przepisana
#    z warunku, ktory juz stal w ekranie — kto wchodzil, wchodzi dalej.
set -u

REPO="${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

for R in mp_coordinator mp_agent mp_system_admin; do
	wp user get "rej-$R" >/dev/null 2>&1 || \
		wp user create "rej-$R" "rej-$R@przyklad.pl" --role="$R" \
			--user_pass="$(head -c 18 /dev/urandom | base64 | tr -d '/+=')" >/dev/null 2>&1
done
ID_K=$(wp user get rej-mp_coordinator --field=ID)
ID_A=$(wp user get rej-mp_agent --field=ID)
ID_S=$(wp user get rej-mp_system_admin --field=ID)

# Cap, z ktorym pozycja menu bylaby zarejestrowana dla danego uzytkownika,
# oraz to, czy ten uzytkownik ten cap MA — czyli czy zobaczy pozycje w menu.
widzi_menu() {
	wp eval "wp_set_current_user( $1 );
		\$cap = MP\\Registry\\Common\\Roles::registry_menu_cap();
		echo current_user_can( \$cap ) ? 'TAK' : 'NIE';" 2>/dev/null
}
wpuszczony() {
	wp eval "wp_set_current_user( $1 );
		echo MP\\Registry\\Common\\Roles::can_current_user_see_registry() ? 'TAK' : 'NIE';" 2>/dev/null
}

echo "== A. KONIEC Z DRZWIAMI, KTORE ODSYLAJA — koordynator =="
M=$(widzi_menu "$ID_K"); W=$(wpuszczony "$ID_K")
[ "$M" = "NIE" ] && ok "koordynator NIE widzi pozycji „Rejestr MP\" w menu" \
	|| bad "koordynator dalej widzi pozycję, której ekran go nie wpuści"
[ "$W" = "NIE" ] && ok "koordynator dalej nie wchodzi na ekran (wejście z palca w adres odbite)" \
	|| bad "koordynator zostałby WPUSZCZONY — naprawa poszła nie w tę stronę"
[ "$M" = "$W" ] && ok "menu i ekran mówią koordynatorowi TO SAMO ($M)" \
	|| bad "menu mówi $M, a ekran $W — rozjazd trwa"

echo "== B. NIKT NIE STRACIL DOSTEPU — bez tego naprawa odbiera funkcję =="
for PARA in "$ID_A:pracownik" "$ID_S:administrator"; do
	KTO=${PARA%%:*}; NAZWA=${PARA##*:}
	M=$(widzi_menu "$KTO"); W=$(wpuszczony "$KTO")
	[ "$M" = "TAK" ] && ok "$NAZWA dalej WIDZI pozycję „Rejestr MP\"" \
		|| bad "$NAZWA stracił pozycję w menu — naprawa poszła za daleko"
	[ "$W" = "TAK" ] && ok "$NAZWA dalej WCHODZI na ekran rejestru" \
		|| bad "$NAZWA stracił dostęp do rejestru — naprawa poszła za daleko"
	[ "$M" = "$W" ] && ok "menu i ekran mówią $NAZWA TO SAMO ($M)" \
		|| bad "$NAZWA: menu $M, ekran $W — rozjazd"
done

echo "== C. JEDNO ZRODLO, NIE DWA =="
JEDNO=$(grep -c "Roles::can_current_user_see_registry()" "$REPO/mp-warranty-registry/includes/Admin/ProductsScreen.php")
[ "$JEDNO" -ge 1 ] && ok "ekran pyta wspólnej funkcji, a nie własnej pary current_user_can" \
	|| bad "ekran dalej sprawdza uprawnienia po swojemu"
STARE=$(grep -c "current_user_can( 'mp_agent' ) && ! current_user_can( 'mp_system_admin' )" "$REPO/mp-warranty-registry/includes/Admin/ProductsScreen.php" || true)
[ "$STARE" -eq 0 ] && ok "stary, osobny warunek ekranu zniknął (nie ma dwóch reguł obok siebie)" \
	|| bad "stary warunek został — będą dwie reguły na jedne drzwi"
MENU=$(grep -c "Roles::registry_menu_cap()" "$REPO/mp-warranty-registry/includes/Admin/ProductsScreen.php")
[ "$MENU" -ge 1 ] && ok "menu bierze cap z listy rejestru, nie z listy całego personelu" \
	|| bad "menu dalej liczy cap z STAFF_CAPS"

# ⛔⛔ KONTROLA ZRODLA — najwazniejsza w tym pliku.
#    `mp-*/includes/Common/` jest GENEROWANE przez build/build.sh i GITIGNOROWANE.
#    Edycja kopii dziala na stanowisku i znika przy pierwszym buildzie — czyli test
#    swieci na zielono, a do klienta nie trafia nic. Raz juz w to wdepnelismy (5.08).
#    Dlatego pytamy o ZRODLO: lib/mp-common/src/Roles.php.
grep -q "REGISTRY_CAPS" "$REPO/lib/mp-common/src/Roles.php" \
	&& ok "zmiana stoi w ŹRÓDLE (lib/mp-common/src/Roles.php), a nie w kopii generowanej" \
	|| bad "zmiany NIE MA w źródle — build ją skasuje, a klient jej nie zobaczy"
# ⚠️ Pytamy o ZNACZNIK, nie o gita — `git` nie istnieje w kontenerze testowym
#    (zmierzone: „git: command not found"). Znacznik `@generated` wstawia sam build,
#    wiec jego obecnosc dowodzi, ze to KOPIA, a nie plik zrodlowy.
grep -q "@generated" "$REPO/mp-warranty-registry/includes/Common/Roles.php" \
	&& ok "[kontrolna] kopia w includes/Common niesie znacznik @generated — test pytał o właściwy plik" \
	|| bad "[kontrolna] kopia bez znacznika @generated — założenie tej kontroli upadło"

# ⛔ PROBA KONTROLNA: lista rejestru NIE zawezila sie ponad to, co bylo w ekranie.
LISTA=$(wp eval 'echo implode( ",", MP\Registry\Common\Roles::REGISTRY_CAPS );' 2>/dev/null)
[ "$LISTA" = "mp_agent,mp_system_admin" ] \
	&& ok "[kontrolna] lista uprawnień rejestru = dokładnie to, co stało w ekranie ($LISTA)" \
	|| bad "[kontrolna] lista uprawnień to '$LISTA' — dostęp został zmieniony, a nie miał"

echo
echo "PASS=$PASS FAIL=$FAIL"
if [ "$(( PASS + FAIL ))" -lt 15 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane min. 15."
	exit 2
fi
[ "$FAIL" -eq 0 ] || exit 1
