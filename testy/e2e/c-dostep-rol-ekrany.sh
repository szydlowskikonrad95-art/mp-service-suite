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

# ⛔ REJESTR PRODUKTOW MA WLASNA, WEZSZA LISTE — i to NIE jest wyjatek od naprawy 2.25,
#    tylko granica, ktora ta naprawa przekroczyla.
#
#    Do 5.08 stalo tu `grep "Roles::menu_cap_for_current_user()"` po pliku ekranu. Ta
#    kontrola pilnowala NAZWY FUNKCJI, a nie zachowania — i zadala rzeczy sprzecznej
#    z kontraktem: `menu_cap_for_current_user()` zwraca cap z listy CALEGO personelu,
#    wiec koordynatorowi zwracalo jego wlasny i pozycja „Rejestr MP" mu sie pokazywala.
#    Tyle ze ekran rejestru wpuszcza wylacznie `mp_agent`/`mp_system_admin` — tak stoi
#    w `dokumentacja-techniczna/SECURITY.md:51` („Ekran «Rejestr MP» (lista produktow) |
#    `mp_agent` lub `mp_system_admin`"), wpisane w PR #24, czyli PRZED obiema naprawami,
#    i tak samo mowi instrukcja klienta (`dla-klienta/instrukcje/ADMIN.md:4`: administrator
#    ma „wszystko, co koordynator, PLUS rejestr produktow"). Koordynator dostawal wiec
#    drzwi, ktore go odsylaly `wp_die` — soczewka S4, znalezisko 5, widziane na zywej
#    instancji. Kontrola po nazwie funkcji utrwalala te wade jako wymog.
#
#    Dlatego pytamy teraz o ZACHOWANIE i o obie strony naraz: cap, z ktorym pozycja
#    menu by sie zarejestrowala, ma zgadzac sie z bramka ekranu — dla KAZDEJ roli.
#    Reguła 2.25 („koordynator nie ma mniej ekranow niz podwladny") obowiazuje dalej
#    tam, gdzie ekran koordynatora WPUSZCZA — pilnuje tego pkt 3b nizej.
#    ⛔ Pytamy EKRAN, nie pomocnika. Pierwsza wersja tej kontroli wolala
#    `Roles::registry_menu_cap()` wprost — i przechodzilaby na zielono nawet wtedy, gdyby
#    `ProductsScreen::add_menu()` wpisal do menu zupelnie inny cap. Mierzymy wiec to, co
#    ekran faktycznie rejestruje: `add_menu_page()` wklada pozycje do `$menu` ZAWSZE, a
#    o tym, czy czlowiek ja zobaczy, decyduje cap zapisany w tej pozycji.
rej_menu()  { wp eval "wp_set_current_user( get_user_by( 'login', 'test-$1' )->ID );
	global \$menu; \$menu = array();
	MP\\Registry\\Admin\\ProductsScreen::add_menu();
	\$cap = '';
	foreach ( (array) \$menu as \$poz ) { if ( ( \$poz[2] ?? '' ) === MP\\Registry\\Admin\\ProductsScreen::PAGE_SLUG ) { \$cap = \$poz[1] ?? ''; } }
	echo ( '' !== \$cap && current_user_can( \$cap ) ) ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]'; }
rej_ekran() { wp eval "wp_set_current_user( get_user_by( 'login', 'test-$1' )->ID ); echo MP\\Registry\\Common\\Roles::can_current_user_see_registry() ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]'; }

for R in mp_agent mp_coordinator; do
	M=$(rej_menu "$R"); E=$(rej_ekran "$R")
	[ -n "$M" ] && [ "$M" = "$E" ] \
		&& ok "rejestr produktow, $R: menu i ekran mowia TO SAMO ($M) — zero drzwi, ktore odsylaja" \
		|| bad "rejestr produktow, $R: menu mowi '$M', ekran '$E' — rozjazd wrocil"
done
# Proba kontrolna kierunku: gdyby menu chowalo sie WSZYSTKIM, powyzsze przeszloby
# (dwa razy „nie" = zgodnosc), a produkt stracilby ekran. Pracownik ma widziec.
[ "$(rej_menu mp_agent)" = "tak" ] && ok "[kontrolna] pracownik DALEJ widzi rejestr (naprawa nie poszla za daleko)" || bad "[kontrolna] pracownik stracil rejestr — zgodnosc wyzej nic nie znaczy"

echo "== 3b. POMIAR ZACHOWANIA: MENU REJESTRUJE SIE DLA KOORDYNATORA =="
MENU=$(wp eval "wp_set_current_user( get_user_by( 'login', 'test-mp_coordinator' )->ID ); global \$menu; \$menu = array(); MP\\Intake\\Admin\\UnverifiedScreen::add_menu(); MP\\Intake\\Admin\\CasesScreen::add_menu(); \$slugi = array(); foreach ( (array) \$menu as \$poz ) { \$slugi[] = \$poz[2] ?? ''; } echo implode( ',', \$slugi );" 2>/dev/null)
case "$MENU" in *mp-intake-unverified*) ok "koordynator DOSTAJE pozycje menu zgloszen niepotwierdzonych" ;; *) bad "menu koordynatora bez ekranu niepotwierdzonych ($MENU)" ;; esac
case "$MENU" in *mp-intake-cases*|*cases*) ok "koordynator ma tez ekran spraw (kontrola: pomiar w ogole widzi menu)" ;; *) bad "pomiar nie widzi zadnego menu — wynik wyzej nic nie znaczy" ;; esac

echo "== 4. GRANICA NAPRAWY — TO MA ZOSTAC ZAMKNIETE =="
grep -q "'mp_system_admin'" "$REPO"/mp-warranty-registry/includes/Admin/ImportScreen.php 2>/dev/null && ok "import zostaje za administratorem systemu (wymog zamowienia)" || bad "import stracil bramke administratora!"
grep -q "'mp_system_admin'" "$REPO"/mp-warranty-registry/includes/Admin/ExceptionsScreen.php 2>/dev/null && ok "wyjatki gwarancyjne zostaja za administratorem systemu" || bad "wyjatki straciły bramke administratora!"

# ⛔ SPRZATANIE OBOWIAZKOWE: te konta zmieniaja SKLAD PERSONELU, a kolejne testy
# w tym samym przebiegu licza adresatow powiadomien (SLA wysyla do koordynatora).
# Zostawione konto testowe = czerwony test cztery pozycje dalej, w miejscu,
# ktore z ta zmiana nie ma nic wspolnego.
for R in mp_coordinator mp_agent mp_client; do
	UID_T=$(wp user get "test-$R" --field=ID 2>/dev/null | tr -d '[:space:]')
	[ -n "$UID_T" ] && wp user delete "$UID_T" --yes >/dev/null 2>&1
done

ZOSTALO=$(wp user list --role=mp_coordinator --field=user_login 2>/dev/null | grep -c '^test-' || true)
[ "${ZOSTALO:-0}" = "0" ] && ok "konta testowe posprzatane (kolejne testy dostaja czyste srodowisko)" || bad "konta testowe zostaly — nastepne testy dostana falszywy wynik"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
# ⛔ STRAZNIK KOMPLETU (lekcja z 4.08: „bramka, ktora cicho nie startuje, swieci zielono").
# Kontrole ida przez `wp eval` — gdy klasa sie nie zaladuje albo `wp` padnie, wynik jest
# pusty i caly blok potrafi przemknac bez ani jednego OK ani FAIL. Liczba ZMIERZONA na
# przebiegu z tej zmiany: 1 (pkt 0) + 3 (pkt 1) + 3 (pkt 2) + 5 (pkt 3) + 2 (pkt 3b)
# + 2 (pkt 4) + 1 (sprzatanie) = 17.
if [ "$(( PASS + FAIL ))" -lt 17 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane min. 17."
	exit 2
fi
[ "$FAIL" -eq 0 ] || exit 1
