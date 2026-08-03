#!/usr/bin/env bash
# ZYWY DOWOD (naprawa 2.54 + 2.55): konto WordPressa klienta NIE NOSI danych osobowych.
#
# Co pilnuje ten test:
#   1. nowe konto klienta ma neutralna nazwe wyswietlana i neutralny czlon adresu
#      strony autora (WordPress publikuje OBIE te rzeczy na jawnej stronie),
#   2. jednorazowa naprawa kont ZALOZONYCH WCZESNIEJ dziala — bez niej ludzie juz
#      ujawnieni pozostaliby ujawnieni (nazwa wyswietlana zapisuje sie raz),
#   3. dwie osoby pod WSPOLNA skrzynka dostaja OSOBNE rekordy klienta (ochrona
#      `same_person` ma czym zadzialac, bo formularz pyta juz o nazwisko).
#
# Kazda kontrola ma PROBE KONTROLNA: najpierw pokazujemy, ze detektor wykrywa
# wyciek, gdy wyciek JEST. Inaczej „zero wyciekow" i „zepsuty test" wygladaja
# identycznie.
# CLI (bez HTTP). Chodzi na poligonie i w CI.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
cid() { echo "$1" | grep '^case_id=' | cut -d= -f2; }
tok() { echo "$1" | grep '^token=' | cut -d= -f2; }

# Czy tekst zdradza tozsamosc: adres e-mail albo nazwisko z formularza.
zdradza() { case "$1" in *@*|*owalsk*|*ovak*|*testowy*) return 0 ;; *) return 1 ;; esac; }

sprzataj() {
	wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
	wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
	for U in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$U" --yes >/dev/null 2>&1; done
}

sprzataj

echo "== 0. PROBA KONTROLNA DETEKTORA =="
zdradza 'jan.kowalski@przyklad.pl' && ok "detektor widzi adres e-mail" || bad "detektor NIE widzi adresu (test bylby slepy)"
zdradza 'Jan Kowalski'             && ok "detektor widzi nazwisko"     || bad "detektor NIE widzi nazwiska (test bylby slepy)"
zdradza 'Klient serwisu #7'        && bad "detektor krzyczy na neutralna nazwe (falszywy alarm)" || ok "neutralna nazwa przechodzi"

echo "== 1. NOWE KONTO KLIENTA =="
O1=$(wp mp case-create --kind=reklamacja --email='jan.kowalski@przyklad.pl' --name='Jan Kowalski' --serial='SN-TOZ-1' --document='FV/T1' --date='2026-03-15' --desc='opis' 2>/dev/null)
T1=$(tok "$O1")
[ -n "$T1" ] && ok "sprawa niepotwierdzona utworzona" || bad "nie udalo sie utworzyc sprawy"
wp mp case-verify "$T1" >/dev/null 2>&1

UID1=$(q "SELECT wp_user_id FROM wp_mp_customers WHERE email='jan.kowalski@przyklad.pl'")
[ -n "$UID1" ] && [ "$UID1" != "NULL" ] && ok "konto WP zalozone przy weryfikacji (id=$UID1)" || bad "konto WP nie powstalo ($UID1)"

DN=$(q "SELECT display_name FROM wp_users WHERE ID=$UID1")
NN=$(q "SELECT user_nicename FROM wp_users WHERE ID=$UID1")
LOGIN=$(q "SELECT user_login FROM wp_users WHERE ID=$UID1")

zdradza "$DN"    && bad "nazwa wyswietlana zdradza tozsamosc: $DN"          || ok "nazwa wyswietlana neutralna ($DN)"
zdradza "$NN"    && bad "adres strony autora zdradza tozsamosc: $NN"        || ok "czlon adresu strony autora neutralny ($NN)"
zdradza "$LOGIN" && bad "login zbudowany z danych osobowych: $LOGIN"        || ok "login neutralny ($LOGIN)"

# Imie NIE ginie — ma zyc tam, gdzie obsluguje je eraser RODO.
NAZWA=$(q "SELECT name FROM wp_mp_customers WHERE email='jan.kowalski@przyklad.pl'")
[ "$NAZWA" = "JanKowalski" ] && ok "imie i nazwisko zapisane w tabeli klientow" || bad "imie zgubione w tabeli klientow ($NAZWA)"

echo "== 2. NAPRAWA KONTA ZALOZONEGO WCZESNIEJ =="
# Odtwarzamy stan sprzed poprawki: nazwa wyswietlana = adres, czlon adresu z adresu.
wp db query "UPDATE wp_users SET display_name='jan.kowalski@przyklad.pl', user_nicename='jan-kowalskiprzyklad-pl' WHERE ID=$UID1" >/dev/null 2>&1
DN_PRZED=$(q "SELECT display_name FROM wp_users WHERE ID=$UID1")
zdradza "$DN_PRZED" && ok "stan sprzed poprawki odtworzony (wyciek istnieje: $DN_PRZED)" || bad "nie udalo sie odtworzyc wycieku — dalszy wynik nic nie dowodzi"

wp eval 'echo MP\Intake\Accounts::redact_public_identities();' >/dev/null 2>&1

DN_PO=$(q "SELECT display_name FROM wp_users WHERE ID=$UID1")
NN_PO=$(q "SELECT user_nicename FROM wp_users WHERE ID=$UID1")
zdradza "$DN_PO" && bad "po naprawie nazwa nadal zdradza: $DN_PO"       || ok "konto zalozone wczesniej naprawione ($DN_PO)"
zdradza "$NN_PO" && bad "po naprawie adres nadal zdradza: $NN_PO"       || ok "adres strony autora naprawiony ($NN_PO)"

echo "== 3. WSPOLNA SKRZYNKA — DWIE OSOBY, DWA REKORDY =="
O2=$(wp mp case-create --kind=naprawa --email='recepcja@przyklad.pl' --name='Anna Nowak' --serial='SN-TOZ-2' --desc='pierwsza osoba' 2>/dev/null)
wp mp case-verify "$(tok "$O2")" >/dev/null 2>&1
O3=$(wp mp case-create --kind=naprawa --email='recepcja@przyklad.pl' --name='Piotr Zieliński' --serial='SN-TOZ-3' --desc='druga osoba' 2>/dev/null)
wp mp case-verify "$(tok "$O3")" >/dev/null 2>&1

ILE=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE email='recepcja@przyklad.pl'")
[ "$ILE" = "2" ] && ok "dwie osoby pod wspolna skrzynka = dwa rekordy klienta" || bad "oczekiwano 2 rekordow, jest $ILE (ochrona przed sklejeniem nie zadzialala)"

# Proba kontrolna do punktu 3: TA SAMA osoba dwa razy = JEDEN rekord.
O4=$(wp mp case-create --kind=naprawa --email='recepcja@przyklad.pl' --name='anna   nowak' --serial='SN-TOZ-4' --desc='ta sama osoba' 2>/dev/null)
wp mp case-verify "$(tok "$O4")" >/dev/null 2>&1
ILE2=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE email='recepcja@przyklad.pl'")
[ "$ILE2" = "2" ] && ok "ta sama osoba (inna pisownia) NIE tworzy trzeciego rekordu" || bad "oczekiwano 2 rekordow, jest $ILE2 (sklejanie za ostre)"

if [ -n "${MP_BASE:-}" ]; then
	echo "== 4. STRONA AUTORA WIDZIANA ANONIMOWO (HTTP) =="
	O5=$(wp mp case-create --kind=naprawa --email='ewa.testowa@przyklad.pl' --name='Ewa Testowa' --serial='SN-TOZ-5' --desc='publiczny' 2>/dev/null)
	wp mp case-verify "$(tok "$O5")" >/dev/null 2>&1
	UID5=$(q "SELECT wp_user_id FROM wp_mp_customers WHERE email='ewa.testowa@przyklad.pl'")

	HTML=$(curl -s "$MP_BASE/?author=$UID5")
	KOD=$(curl -s -o /dev/null -w '%{http_code}' "$MP_BASE/?author=$UID5")

	# Proba kontrolna: konto NIEISTNIEJACE musi zachowac sie inaczej, inaczej
	# „200" niczego nie dowodzi.
	KOD_BRAK=$(curl -s -o /dev/null -w '%{http_code}' "$MP_BASE/?author=99999")
	[ "$KOD_BRAK" = "404" ] && ok "proba kontrolna: nieistniejace konto daje 404" || bad "nieistniejace konto daje $KOD_BRAK — pomiar niewiarygodny"
	[ "$KOD" = "200" ] && ok "strona autora klienta istnieje (kod $KOD) — jest co sprawdzac" || bad "strona autora nieosiagalna ($KOD)"

	echo "$HTML" | grep -q 'ewa.testowa@przyklad.pl' && bad "adres e-mail widoczny publicznie na stronie autora" || ok "adres e-mail NIE wycieka na stronie autora"
	echo "$HTML" | grep -q 'Ewa Testowa'             && bad "nazwisko widoczne publicznie na stronie autora"    || ok "nazwisko NIE wycieka na stronie autora"

	# Pas zapasowy: ta strona nie ma trafiac do wyszukiwarek. Uwaga na pulapke
	# pomiaru — WordPress wypisuje ten znacznik w APOSTROFACH.
	echo "$HTML" | grep -qi "<meta name=.robots.[^>]*noindex" && ok "strona autora klienta ma noindex" || bad "brak noindex na stronie autora klienta"

	# I kontrola w druga strone: strona glowna NIE moze dostac noindex.
	curl -s "$MP_BASE/" | grep -qi "<meta name=.robots.[^>]*noindex" && bad "noindex trafil na strone glowna (za szeroki filtr)" || ok "strona glowna bez noindex (filtr nie jest za szeroki)"
fi

sprzataj

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
