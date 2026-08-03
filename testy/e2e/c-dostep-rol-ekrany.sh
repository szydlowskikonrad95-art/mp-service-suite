#!/usr/bin/env bash
# ZYWY DOWOD (naprawa 2.25): koordynator nie ma MNIEJ ekranow niz jego podwladny.
#
# Role MP nie maja hierarchii (to projekt, nie usterka), a dwa ekrany mialy cap
# `mp_agent` wpisany na sztywno — wiec odbijaly koordynatora, czyli przelozonego
# osoby, ktora na nich pracuje. Dwa inne ekrany rozwiazaly to samo poprawnie
# (cap liczony dla biezacego uzytkownika) i to ten wzorzec rozciagamy.
#
# ⛔ Czego ten test PILNUJE, zeby naprawa nie poszla za daleko: import i wyjatki
# gwarancyjne maja zostac za `mp_system_admin` — tak wymaga zamowienie
# („wyjatki zatwierdzane przez uprawnionego administratora").
set -u

# Katalog repozytorium liczony ZE SCIEZKI SKRYPTU — w CI test chodzi z /tmp/wp,
# wiec sciezki wzgledne nie istnieja i grep dawal falszywe „FAIL" (wada pomiaru,
# nie produktu; zlapane w CI przy pierwszym przebiegu).
REPO="${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Konta rol (zakladane raz; hasla nieistotne — sprawdzamy uprawnienia, nie logowanie).
for R in mp_coordinator mp_agent mp_client; do
	wp user get "test-$R" >/dev/null 2>&1 || wp user create "test-$R" "test-$R@przyklad.pl" --role="$R" --user_pass="$(head -c 18 /dev/urandom | base64 | tr -d '/+=')" >/dev/null 2>&1
done

cap_dla() { wp eval "wp_set_current_user( get_user_by( 'login', 'test-$1' )->ID ); echo MP\\Intake\\Common\\Roles::menu_cap_for_current_user();" 2>/dev/null | tr -d '[:space:]'; }
moze()    { wp eval "wp_set_current_user( get_user_by( 'login', 'test-$1' )->ID ); echo current_user_can( '$2' ) ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]'; }
personel(){ wp eval "wp_set_current_user( get_user_by( 'login', 'test-$1' )->ID ); echo MP\\Intake\\Common\\Roles::current_user_is_staff() ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]'; }

echo "== 0. WADA, KTORA NAPRAWIAMY, BYLA REALNA =="
# Gdyby koordynator mial `mp_agent`, cala pozycja bylaby bezprzedmiotowa.
[ "$(moze mp_coordinator mp_agent)" = "nie" ] && ok "koordynator NIE ma capa pracownika (brak hierarchii — zrodlo wady)" || bad "koordynator ma mp_agent — zalozenie testu nieaktualne"

echo "== 1. BRAMKA PERSONELU =="
[ "$(personel mp_coordinator)" = "tak" ] && ok "koordynator uznany za personel" || bad "koordynator odrzucony przez bramke personelu"
[ "$(personel mp_agent)" = "tak" ]       && ok "pracownik uznany za personel"   || bad "pracownik odrzucony przez bramke personelu"
[ "$(personel mp_client)" = "nie" ]      && ok "klient NIE jest personelem (proba kontrolna)" || bad "klient przeszedl bramke personelu!"

echo "== 2. CAP MENU LICZONY DLA UZYTKOWNIKA =="
for R in mp_coordinator mp_agent; do
	CAP=$(cap_dla "$R")
	[ -n "$CAP" ] && [ "$(moze "$R" "$CAP")" = "tak" ] \
		&& ok "$R: menu dostaje cap, ktory FAKTYCZNIE ma ($CAP)" \
		|| bad "$R: cap menu = '$CAP', a uzytkownik go nie ma (ekran bylby ukryty)"
done
CAPK=$(cap_dla mp_client)
[ "$(moze mp_client "$CAPK")" = "nie" ] && ok "klient nie dostaje capa menu (ekrany personelu pozostaja ukryte)" || bad "klient dostal cap menu!"

echo "== 3. EKRANY, KTORE MIALY CAP NA SZTYWNO =="
NIEPOTW=$(wp eval "echo MP\\Intake\\Admin\\UnverifiedScreen::CAP;" 2>/dev/null | tr -d '[:space:]')
[ "$NIEPOTW" = "mp_agent" ] && ok "stala zgodnosci wstecz zachowana ($NIEPOTW)" || bad "stala CAP zmieniona ($NIEPOTW) — sprawdz zgodnosc wstecz"
grep -q "Roles::menu_cap_for_current_user()" "$REPO"/mp-service-intake/includes/Admin/UnverifiedScreen.php 2>/dev/null && ok "ekran niepotwierdzonych: cap menu dynamiczny" || bad "ekran niepotwierdzonych nadal z capem na sztywno"
grep -q "Roles::menu_cap_for_current_user()" "$REPO"/mp-warranty-registry/includes/Admin/ProductsScreen.php 2>/dev/null && ok "rejestr produktow: cap menu dynamiczny" || bad "rejestr produktow nadal z capem na sztywno"

echo "== 3b. POMIAR ZACHOWANIA: MENU REJESTRUJE SIE DLA KOORDYNATORA =="
MENU=$(wp eval "wp_set_current_user( get_user_by( 'login', 'test-mp_coordinator' )->ID ); global \$menu; \$menu = array(); MP\\Intake\\Admin\\UnverifiedScreen::add_menu(); MP\\Intake\\Admin\\CasesScreen::add_menu(); \$slugi = array(); foreach ( (array) \$menu as \$poz ) { \$slugi[] = \$poz[2] ?? ''; } echo implode( ',', \$slugi );" 2>/dev/null)
case "$MENU" in *mp-intake-unverified*) ok "koordynator DOSTAJE pozycje menu zgloszen niepotwierdzonych" ;; *) bad "menu koordynatora bez ekranu niepotwierdzonych ($MENU)" ;; esac
case "$MENU" in *mp-intake-cases*|*cases*) ok "koordynator ma tez ekran spraw (kontrola: pomiar w ogole widzi menu)" ;; *) bad "pomiar nie widzi zadnego menu — wynik wyzej nic nie znaczy" ;; esac

echo "== 4. GRANICA NAPRAWY — TO MA ZOSTAC ZAMKNIETE =="
grep -q "'mp_system_admin'" "$REPO"/mp-warranty-registry/includes/Admin/ImportScreen.php 2>/dev/null && ok "import zostaje za administratorem systemu (wymog zamowienia)" || bad "import stracil bramke administratora!"
grep -q "'mp_system_admin'" "$REPO"/mp-warranty-registry/includes/Admin/ExceptionsScreen.php 2>/dev/null && ok "wyjatki gwarancyjne zostaja za administratorem systemu" || bad "wyjatki straciły bramke administratora!"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
