#!/usr/bin/env bash
# LUKA Z AUDYTU BEZPIECZENSTWA (spoza listy): limit „3 zgloszenia na dobe" — dany
# klientowi NA PISMIE — dalo sie obejsc plus-adresowaniem.
#
# Klucz licznika powstawal z adresu po samym `strtolower`+`trim`, wiec
# „jan+1@gmail.com", „jan+2@gmail.com" i „jan+3@gmail.com" to byly TRZY osobne
# liczniki, kazdy z wlasnym limitem — a poczta i tak trafia do JEDNEJ skrzynki,
# bo Gmail i wiekszosc dostawcow czlon po plusie ignoruje. Numer seryjny tego nie
# ratowal (walidator sprawdza KSZTALT numeru, nie jego istnienie w rejestrze),
# a limit po adresie sieciowym to okno PRZESUWANE przeciw zalewowi, nie sufit dobowy.
#
# TEN TEST DOWODZI TRZECH RZECZY — i trzecia jest tu po to, zeby naprawa nie
# okazala sie gorsza od wady:
#   1. warianty z plusem tego samego adresu licza sie do JEDNEGO licznika,
#   2. dwa ROZNE adresy maja nadal OSOBNE liczniki (przypadek bez wady — bez niego
#      „naprawa" mogla by skleic obcych ludzi i odebrac limit wszystkim),
#   3. adres ZAPISANY w bazie i UZYTY do wysylki jest DOKLADNIE taki, jaki podal
#      czlowiek — normalizacja dotyczy WYLACZNIE klucza licznika.
#
# KALIBRACJA (opis w naglowku, zeby nikt nie musial jej wymyslac od nowa):
#   git stash / checkout wersji sprzed naprawy `RateLimit.php` i uruchomic ten test
#   — sekcja 1 MUSI paść (trzy osobne liczniki po 1 zamiast jednego z 3, czwarte
#   zgloszenie NIE zablokowane). Sekcje 2 i 3 maja przejsc TAK SAMO przed i po:
#   one pilnuja, ze naprawa niczego nie zepsula.
#
# Chodzi na poligonie (MP_BASE z env) i w CI. Exit 0 = zero FAIL.
set -u

BASE="${MP_BASE:-http://localhost:8090}"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); echo "  OK   $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
skip() { SKIP=$((SKIP+1)); echo "  SKIP $1"; }
# ⛔ Pytamy baze przez `wp eval` i `$wpdb`, NIE przez `wp db query`. Na instalacji
# postawionej z paczki na MySQL 8 klient wiersza polecen wywala sie na TLS
# („self-signed certificate in certificate chain") i KAZDE zapytanie wraca PUSTE —
# a puste wyglada dokladnie jak „zero wierszy", czyli jak wynik. Zlapane wlasnym
# przebiegiem: test meldowal trzy wady produktu, ktorych nie bylo.
q()    { wp eval "global \$wpdb; \$v = \$wpdb->get_var( \"$1\" ); echo null === \$v ? '' : \$v;" 2>/dev/null | tr -d '[:space:]'; }
wykonaj() { wp eval "global \$wpdb; \$wpdb->query( \"$1\" );" >/dev/null 2>&1; }

# Unikalne na przebieg — inaczej o wyniku decyduje licznik z poprzedniego
# uruchomienia i test mierzy smieci, a nie produkt.
STEMPEL="$$-$(date +%s)"
BAZOWY="plus-${STEMPEL}@example.com"
WAR1="plus-${STEMPEL}+jeden@example.com"
WAR2="plus-${STEMPEL}+dwa@example.com"
WAR3="plus-${STEMPEL}+trzy@example.com"
OBCY="inny-${STEMPEL}@example.com"
SERIAL="PLUS-${STEMPEL}"

# ⭐ KLUCZ LICZYMY TYLKO DLA ADRESOW BEZ PLUSA — i to jest celowe.
# Dla adresu bez plusa stara droga (`strtolower`+`trim`) i nowa (normalizacja)
# daja IDENTYCZNY wynik, wiec ta sama linijka liczy poprawny klucz na kodzie
# SPRZED naprawy i PO niej. Dzieki temu test da sie uruchomic na obu wersjach —
# a kalibracja, ktora nie przechodzi przez ten sam przyrzad, nic nie dowodzi.
# ⛔ Nie wolamy tu `normalize_email_for_key()`: na starym kodzie tej metody NIE MA,
# wiec kalibracja padlaby na braku funkcji, a nie na luce, ktora ma pokazac.
klucz() { wp eval "echo 'mp_rl_em_' . md5( strtolower( trim( '$1' ) ) );" 2>/dev/null | tr -d '[:space:]'; }
klucz_stary() { klucz "$1"; }
licznik() { q "SELECT hits FROM wp_mp_rate_counters WHERE rl_key='$1'"; }

# Sprawdzenie, ze przyrzad w ogole dziala: bez tego pusty wynik ponizej wygladalby
# jak „zero licznikow", czyli jak zdany test.
K_BAZOWY=$(klucz "$BAZOWY")
if [ -z "$K_BAZOWY" ] || [ ${#K_BAZOWY} -lt 20 ]; then
	echo "  FAIL pomiar niewazny: nie udalo sie policzyc klucza przez produkt (wp eval nie odpowiada?)"
	echo "WYNIK: 0 ok, 1 fail"
	exit 1
fi

sprzataj() {
	for a in "$BAZOWY" "$WAR1" "$WAR2" "$WAR3" "$OBCY"; do
		wykonaj "DELETE FROM wp_mp_rate_counters WHERE rl_key='$(klucz "$a")'"
	done
	wykonaj "DELETE FROM wp_mp_rate_counters WHERE rl_key LIKE 'mp_rl_dd_%'"
}
sprzataj

echo "== 1. Trzy warianty z plusem = JEDEN licznik =="

# Rodzaje rozne, zeby o wyniku nie zadecydowal dedup (ten sam serial+adres+rodzaj
# w 15 minut to duplikat) — mierzymy LIMIT DOBOWY, nie ochrone przed duplikatem.
for para in "$WAR1 reklamacja" "$WAR2 naprawa" "$WAR3 zapytanie"; do
	set -- $para
	wp eval "MP\\Intake\\RateLimit::record_submission( '$1', '$SERIAL', '$2' );" >/dev/null 2>&1
done

HITS=$(licznik "$K_BAZOWY")
[ "${HITS:-0}" = "3" ] && ok "trzy warianty z plusem zliczone do JEDNEGO licznika (hits=3)" \
	|| bad "warianty NIE trafily do jednego licznika (hits='${HITS:-brak}', oczekiwane 3) — limit dobowy da sie obejsc plusem"

OSOBNE=0
for a in "$WAR1" "$WAR2" "$WAR3"; do
	KS=$(klucz_stary "$a")
	[ "$KS" = "$K_BAZOWY" ] && continue
	[ -n "$(licznik "$KS")" ] && OSOBNE=$((OSOBNE+1))
done
[ "$OSOBNE" = "0" ] && ok "zaden wariant nie zalozyl WLASNEGO licznika (osobnych: 0)" \
	|| bad "powstalo $OSOBNE osobnych licznikow dla wariantow tego samego adresu"

# Sedno obietnicy ze specyfikacji: czwarte zgloszenie z KOLEJNEGO wariantu ma sie odbic.
POWOD=$(wp eval "echo (string) MP\\Intake\\RateLimit::check( '198.51.100.7', '${BAZOWY%@*}+cztery@example.com', 'INNY-$STEMPEL', 'reklamacja' );" 2>/dev/null | tr -d '[:space:]')
[ "$POWOD" = "rate" ] && ok "czwarte zgloszenie (kolejny wariant z plusem) ZABLOKOWANE — limit dobowy trzyma" \
	|| bad "czwarte zgloszenie przeszlo (powod='${POWOD:-brak}') — obietnica '3 na dobe' nadal do obejscia"

echo
echo "== 2. Dwa ROZNE adresy = OSOBNE liczniki (przypadek bez wady) =="

wp eval "MP\\Intake\\RateLimit::record_submission( '$OBCY', 'OBCY-$STEMPEL', 'reklamacja' );" >/dev/null 2>&1
K_OBCY=$(klucz "$OBCY")

[ "$K_OBCY" != "$K_BAZOWY" ] && ok "obcy adres ma INNY klucz licznika niz adres z plusami" \
	|| bad "obcy adres dostal TEN SAM klucz co inny czlowiek — naprawa skleja obcych ludzi"
[ "$(licznik "$K_OBCY")" = "1" ] && ok "licznik obcego adresu ma wlasne 1 trafienie (nie 4)" \
	|| bad "licznik obcego adresu ma '$(licznik "$K_OBCY")' — cudze zgloszenia weszly na jego limit"

POWOD_OBCY=$(wp eval "echo (string) MP\\Intake\\RateLimit::check( '198.51.100.8', '$OBCY', 'OBCY2-$STEMPEL', 'naprawa' );" 2>/dev/null | tr -d '[:space:]')
[ -z "$POWOD_OBCY" ] && ok "obcy adres NIE jest zablokowany cudzym limitem" \
	|| bad "obcy adres zablokowany (powod='$POWOD_OBCY') — naprawa odbiera limit ludziom bez winy"

echo
echo "== 3. Adres w bazie i w wysylce NIETKNIETY =="

PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
SITE_HOST=$(wp option get home 2>/dev/null | sed 's#^https\?://##;s#/.*##')
HOSTHDR=(); [ -n "$SITE_HOST" ] && HOSTHDR=(-H "Host: $SITE_HOST")
# Adresata sprawdzamy W TYM SAMYM PROCESIE, w ktorym produkt wysyla — filtr `wp_mail`
# zalozony tuz przed wywolaniem jego wlasnej metody wysylkowej. ⛔ Nie zakladamy do tego
# zadnego pliku w `mu-plugins`: na instalacji z paczki ten katalog bywa podmontowany
# tylko do odczytu, a test, ktory nie umie zalozyc swojego przyrzadu, konczy sie
# pominieciem — czyli brakiem dowodu tam, gdzie dowod byl wymagany.

ZGLOSZENIOWY="baza-${STEMPEL}+tag@example.com"
wykonaj "DELETE FROM wp_mp_rate_counters WHERE rl_key='$(klucz "baza-${STEMPEL}@example.com")'"

if [ -z "$PAGE_PATH" ]; then
	skip "droga HTTP pominieta — nie ma strony formularza (to NIE jest zaliczenie sekcji 3)"
else
	NONCE=$(curl -s "${HOSTHDR[@]}" "$BASE$PAGE_PATH" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
	curl -s "${HOSTHDR[@]}" -o /dev/null \
		--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
		--data-urlencode "mp_ts=$(( $(date +%s) - 30 ))" \
		--data-urlencode "kind=zapytanie" --data-urlencode "email=$ZGLOSZENIOWY" \
		--data-urlencode "customer_name=Klient Testowy" --data-urlencode "name=Jan Kowalski" \
		--data-urlencode "issue_description=sprawdzenie adresu z plusem" \
		--data-urlencode "mp_consent=1" "$BASE/wp-admin/admin-post.php"

	W_BAZIE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE pending_email='$ZGLOSZENIOWY'")
	[ "${W_BAZIE:-0}" -ge 1 ] && ok "w bazie stoi adres DOKLADNIE taki, jaki podal czlowiek (z plusem)" \
		|| bad "adresu z plusem nie ma w bazie w oryginalnej postaci — normalizacja wyciekla poza klucz licznika"

	OBCIETY=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE pending_email='baza-${STEMPEL}@example.com'")
	[ "${OBCIETY:-0}" = "0" ] && ok "w bazie NIE ma wersji obcietej — zapis nie uzywa klucza licznika" \
		|| bad "w bazie wyladowal adres BEZ czlonu po plusie — poczta poszlaby nie tam, gdzie klient chcial"

	ADRESAT=$(wp eval "
		add_filter( 'wp_mail', static function ( \$a ) { echo '[ADRESAT]' . ( is_array( \$a['to'] ) ? implode( ',', \$a['to'] ) : \$a['to'] ); return \$a; }, 1 );
		add_filter( 'pre_wp_mail', '__return_true', 99 );
		MP\\Intake\\Front\\Mailer::send_magic_link( '$ZGLOSZENIOWY', 'token-testowy-$STEMPEL' );
	" 2>/dev/null | sed -n 's/.*\[ADRESAT\]//p' | tr -d '[:space:]')

	if [ -z "$ADRESAT" ]; then
		bad "nie udalo sie przechwycic adresata — sciezka wysylki nie zostala zmierzona"
	else
		[ "$ADRESAT" = "$ZGLOSZENIOWY" ] \
			&& ok "wysylka idzie na adres DOKLADNIE taki, jaki podal czlowiek (z plusem)" \
			|| bad "wysylka idzie na '$ADRESAT' zamiast na '$ZGLOSZENIOWY' — normalizacja wyciekla do poczty"
	fi
fi

sprzataj
wykonaj "DELETE FROM wp_mp_rate_counters WHERE rl_key='$(klucz "baza-${STEMPEL}@example.com")'"

echo
echo "WYNIK: $PASS ok, $FAIL fail, $SKIP pominietych"
[ "$SKIP" -gt 0 ] && echo "  (pominiete NIE sa zaliczone — sekcja bez dowodu jest sekcja bez dowodu)"
[ "$FAIL" -eq 0 ]
