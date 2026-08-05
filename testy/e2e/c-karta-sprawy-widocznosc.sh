#!/usr/bin/env bash
# ZYWY DOWOD (audyt 2.24, DRUGA POLOWA): karta sprawy bramkuje tak samo jak lista.
#
# CO BYLO ZLE: naprawa 2.24 objela ZAPYTANIE LISTY (`query_for_staff`), a karty NIE.
# `CaseCard::render()` szla wprost do `mp_case_get_context` z samym numerem sprawy,
# wiec pracownik wpisywal numer w adresie i ogladal PELNA karte klienta, ktorego
# nie obsluguje — z imieniem, nazwiskiem, adresem e-mail i telefonem. Ostrzezenie
# przed tym stalo w komentarzu OBOK, w tym samym pliku: „ekran i tak bramkuje".
#
# ⛔ TEN TEST MIERZY OBIE STRONY i to jest jego sedno. Naprawa, ktora zamyka karte
#    WSZYSTKIM, przechodzi polowe kontroli i odbiera produktowi funkcje. Dlatego
#    tyle samo kontroli pilnuje, ze pracownik DALEJ otwiera swoja sprawe, a
#    koordynator i administrator DALEJ otwieraja kazda.
#
# ⛔ Mierzymy WYJSCIE RENDERA, nie sama funkcje sprawdzajaca. Zielona funkcja przy
#    niebramkujacym ekranie to dokladnie ten stan, ktory te wade wyprodukowal.
set -u

REPO="${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# ── stanowisko: dwa konta pracownikow + koordynator + administrator ──────────
for R in mp_coordinator mp_agent mp_system_admin; do
	wp user get "kart-$R" >/dev/null 2>&1 || \
		wp user create "kart-$R" "kart-$R@przyklad.pl" --role="$R" \
			--user_pass="$(head -c 18 /dev/urandom | base64 | tr -d '/+=')" >/dev/null 2>&1
done
wp user get kart-mp_agent2 >/dev/null 2>&1 || \
	wp user create kart-mp_agent2 kart-agent2@przyklad.pl --role=mp_agent \
		--user_pass="$(head -c 18 /dev/urandom | base64 | tr -d '/+=')" >/dev/null 2>&1

ID_A=$(wp user get kart-mp_agent --field=ID)
ID_B=$(wp user get kart-mp_agent2 --field=ID)
ID_K=$(wp user get kart-mp_coordinator --field=ID)
ID_S=$(wp user get kart-mp_system_admin --field=ID)

# ⛔ SPRZATANIE NA STARCIE, nie tylko na koncu: przerwany przebieg zostawia sprawy,
#    a `case_number` jest unikalny — drugi przebieg dostawal wtedy „Duplicate entry"
#    i mierzyl smieci. Zlapane przy pierwszym uruchomieniu tego testu.
wp eval '
	global $wpdb; $t = MP\Intake\Tables::full( MP\Intake\Tables::CASES );
	$wpdb->query( "DELETE FROM {$t} WHERE case_number LIKE \"SRV-KART-%\"" );
	$k = MP\Intake\Tables::full( MP\Intake\Tables::CUSTOMERS );
	$wpdb->query( "DELETE FROM {$k} WHERE email = \"kart-klient@przyklad.pl\"" );' >/dev/null 2>&1

# ⛔ KLIENT JEST KONIECZNY: `mp_case_get_context` laczy sprawe z klientem i bez
#    niego zwraca „not_found" — czyli karta pokazuje „Sprawa niedostepna" KAZDEMU.
#    Test bez klienta mierzylby brak danych zamiast bramki i swiecil na zielono
#    z zupelnie innego powodu (zmierzona wpadka, 5.08).
KLIENT=$(wp eval '
	global $wpdb; $k = MP\Intake\Tables::full( MP\Intake\Tables::CUSTOMERS );
	$wpdb->insert( $k, array( "email" => "kart-klient@przyklad.pl", "name" => "Klient Kartowy",
		"phone" => "600100200", "created_at" => current_time( "mysql", 1 ),
		"updated_at" => current_time( "mysql", 1 ) ) );
	echo (int) $wpdb->insert_id;' 2>/dev/null | tr -d '\r')

# ── dwie sprawy: jedna przydzielona A, jedna NIEPRZYDZIELONA nikomu ──────────
SPRAWA_A=$(wp eval '
	global $wpdb; $t = MP\Intake\Tables::full( MP\Intake\Tables::CASES );
	$wpdb->insert( $t, array( "case_number" => "SRV-KART-A", "kind" => "naprawa",
		"status" => "new", "identity_status" => "verified", "verified_at" => current_time( "mysql", 1 ),
		"customer_id" => '"$KLIENT"', "assigned_to" => '"$ID_A"', "created_at" => current_time( "mysql", 1 ) ) );
	echo (int) $wpdb->insert_id;' 2>/dev/null | tr -d '\r')
SPRAWA_X=$(wp eval '
	global $wpdb; $t = MP\Intake\Tables::full( MP\Intake\Tables::CASES );
	$wpdb->insert( $t, array( "case_number" => "SRV-KART-X", "kind" => "naprawa",
		"status" => "new", "identity_status" => "verified", "verified_at" => current_time( "mysql", 1 ),
		"customer_id" => '"$KLIENT"', "assigned_to" => 0, "created_at" => current_time( "mysql", 1 ) ) );
	echo (int) $wpdb->insert_id;' 2>/dev/null | tr -d '\r')

[ -n "$SPRAWA_A" ] && [ -n "$SPRAWA_X" ] || { echo "BLAD PRZEBIEGU: nie zalozylem spraw"; exit 2; }
echo "== stanowisko: sprawa A=$SPRAWA_A (agent $ID_A), sprawa X=$SPRAWA_X (nieprzydzielona) =="

# Render karty jako WSKAZANY uzytkownik — zwraca wyjscie HTML.
karta() {
	# ⚠️ Ta wersja WP-CLI NIE przyjmuje argumentow pozycyjnych do `wp eval`
	#    („Too many positional arguments"), wiec liczby wstawiamy wprost. Sa to
	#    identyfikatory zalozone przez ten skrypt, nie dane z zewnatrz.
	wp eval "
		wp_set_current_user( $1 );
		ob_start();
		MP\Intake\Admin\CaseCard::render( $2, 'mp-cases' );
		echo ob_get_clean();" 2>/dev/null
}
niedostepna() { printf '%s' "$1" | grep -q "Sprawa niedostępna"; }
# ⛔ Strone „WOLNO" dowodzimy POZYTYWNIE: w wyjsciu ma stac NUMER sprawy. Sprawdzanie
#    samego BRAKU komunikatu o niedostepnosci przepuscilo by pusta strone i kazdy inny
#    blad renderu jako „widzi".
widzi() { printf '%s' "$1" | grep -q "SRV-KART"; }

echo "== A. NIE WOLNO — pracownik przy cudzej i nieprzydzielonej =="

WY=$(karta "$ID_B" "$SPRAWA_A")
niedostepna "$WY" && ok "pracownik B nie otwiera sprawy przydzielonej pracownikowi A" \
	|| bad "pracownik B OTWORZYL cudzą sprawę — wada NIE jest naprawiona"

WY=$(karta "$ID_A" "$SPRAWA_X")
niedostepna "$WY" && ok "pracownik A nie otwiera sprawy NIEPRZYDZIELONEJ nikomu" \
	|| bad "pracownik A otworzył sprawę bez przydziału"

# ⛔ PROBA KONTROLNA WYCIEKU: komunikat ma byc TAKI SAM dla sprawy nieistniejacej,
#    inaczej sama roznica odpowiedzi zdradza, ze sprawa o tym numerze istnieje.
WY_NIC=$(karta "$ID_B" 999999)
niedostepna "$WY_NIC" && ok "[kontrolna] sprawa nieistniejąca daje TEN SAM komunikat — brak wycieku przez różnicę" \
	|| bad "[kontrolna] sprawa nieistniejąca odpowiada inaczej niż niedostępna"

echo "== B. WOLNO — bez tego naprawa odbiera funkcję wszystkim =="

WY=$(karta "$ID_A" "$SPRAWA_A")
widzi "$WY" && ok "pracownik A dalej otwiera swoją sprawę (widzi numer)" \
	|| bad "pracownik A NIE otwiera WŁASNEJ sprawy — naprawa poszła za daleko"

for PARA in "$ID_K:koordynator" "$ID_S:administrator"; do
	KTO=${PARA%%:*}; NAZWA=${PARA##*:}
	WY=$(karta "$KTO" "$SPRAWA_A")
	widzi "$WY" && ok "$NAZWA dalej otwiera sprawę pracownika (widzi numer)" \
		|| bad "$NAZWA nie otwiera sprawy pracownika — naprawa poszła za daleko"
	WY=$(karta "$KTO" "$SPRAWA_X")
	widzi "$WY" && ok "$NAZWA dalej otwiera sprawę nieprzydzieloną (widzi numer)" \
		|| bad "$NAZWA nie otwiera sprawy nieprzydzielonej"
done

echo "== C. AKCJE NA SPRAWIE — nie tylko podgląd =="
# ⛔ Zapis jest grozniejszy od podgladu: karte pracownik tylko OGLADAL, a zadaniem
#    POST mogl zmienic status cudzej sprawy albo NAPISAC DO KLIENTA, ktorego nie
#    obsluguje. Mierzymy warunek, na ktorym stoja handlery.
akcja_wolna() {
	wp eval "wp_set_current_user( $1 ); echo MP\\Intake\\CaseRepo::can_current_user_see( $2 ) ? 'TAK' : 'NIE';" 2>/dev/null
}
[ "$(akcja_wolna "$ID_B" "$SPRAWA_A")" = "NIE" ] \
	&& ok "pracownik B nie ma prawa do akcji na cudzej sprawie (status/odpowiedź/notatka)" \
	|| bad "pracownik B MOŻE działać na cudzej sprawie — zapis dalej otwarty"
[ "$(akcja_wolna "$ID_A" "$SPRAWA_A")" = "TAK" ] \
	&& ok "pracownik A dalej działa na swojej sprawie" \
	|| bad "pracownik A stracił prawo do WŁASNEJ sprawy — naprawa poszła za daleko"
[ "$(akcja_wolna "$ID_K" "$SPRAWA_A")" = "TAK" ] \
	&& ok "koordynator dalej działa na sprawie pracownika" \
	|| bad "koordynator stracił prawo do sprawy pracownika"
TRZY=$(grep -c "self::deny_if_not_visible( \$case_id );" "$REPO/mp-service-intake/includes/Admin/CaseActions.php")
[ "$TRZY" -eq 3 ] && ok "wszystkie trzy akcje pytają o prawo do sprawy (status, odpowiedź, notatka)" \
	|| bad "bramkę ma tylko $TRZY z 3 akcji"
PRZYDZ=$(grep -c "self::can_assign()" "$REPO/mp-service-intake/includes/Admin/CaseActions.php")
[ "$PRZYDZ" -ge 1 ] && ok "przydział ma WŁASNY, węższy warunek (koordynator/administrator)" \
	|| bad "przydział nie ma osobnego warunku"

echo "== D. KONTRAKT JEST JEDEN — karta i lista pytają tego samego =="
WSPOLNY=$(grep -c "CaseRepo::can_current_user_see" "$REPO/mp-service-intake/includes/Admin/CaseCard.php")
[ "$WSPOLNY" -ge 1 ] && ok "karta pyta CaseRepo::can_current_user_see (a nie własnego warunku)" \
	|| bad "karta sprawdza widoczność po swojemu — rozjedzie się z listą"
SCOPE=$(grep -c "scope_for_current_user" "$REPO/mp-service-intake/includes/CaseRepo.php")
[ "$SCOPE" -ge 2 ] && ok "lista i karta stoją na tym samym scope_for_current_user ($SCOPE odwołania)" \
	|| bad "scope_for_current_user użyty tylko $SCOPE raz — kontrakt nie jest wspólny"

# ── sprzatanie: konta testowe zmieniaja sklad personelu i psuja testy SLA ────
wp eval '
	global $wpdb; $t = MP\Intake\Tables::full( MP\Intake\Tables::CASES );
	$wpdb->query( "DELETE FROM {$t} WHERE case_number LIKE \"SRV-KART-%\"" );
	$k = MP\Intake\Tables::full( MP\Intake\Tables::CUSTOMERS );
	$wpdb->query( "DELETE FROM {$k} WHERE email = \"kart-klient@przyklad.pl\"" );' >/dev/null 2>&1

echo
echo "PASS=$PASS FAIL=$FAIL"
# Prog kompletu: mniej wykonanych kontroli = ktoras cicho nie wystartowala.
if [ "$(( PASS + FAIL ))" -lt 15 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane min. 15."
	exit 2
fi
[ "$FAIL" -eq 0 ] || exit 1
