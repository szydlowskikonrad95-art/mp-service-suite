#!/usr/bin/env bash
# ZYWY DOWOD 2.31: okno ogranicznika NIE przesuwa sie przy kazdym udanym zgloszeniu.
#
# BUG (audyt 2.31, waga drobna): `RateLimit::hit()` zerowal licznik dopiero po
# wygasnieciu okna, ale koniec okna (`window_expires_at`) ustawial BEZWARUNKOWO,
# przy kazdym trafieniu. Domyslnie: 3 zgloszenia na dobe na adres e-mail.
#
# Co to znaczylo dla czlowieka: klient skladajacy PO JEDNYM zgloszeniu dziennie
# nigdy nie przekraczal „trzech na dobe", a czwartego dnia dostawal odmowe — bo
# kazde udane zgloszenie odsuwalo koniec doby i licznik nigdy sie nie zerowal.
# „Na dobe" dzialalo jak „trzy pod rzad".
# 🔴 Instrukcja kazala obsludze sprawdzic, ile klient wyslal DZIS — pracownik
# widzial zero zgloszen z dzisiaj i nie znajdowal przyczyny blokady.
#
# ⚠️ CZEGO PRODUKT NIE ROBIL ZLE (to zmienia wage na drobna): licznik rosnie
# WYLACZNIE po utworzeniu sprawy (`record_submission`), nie na kazda probe —
# odrzucone proby okna NIE przedluzaly, wiec zablokowany klient nie zapetlal
# wlasnej blokady. Kontrola nr 4 pilnuje, ze to nadal prawda.
#
# ⛔ ASYMETRIA JEST ZAMIERZONA: ochrona przeciwzalewowa po adresie IP dalej ma
# okno PRZESUWANE (kto puka bez przerwy, zostaje zablokowany, dopoki nie
# przestanie). Kontrola nr 5 pilnuje, zeby nikt tego przy okazji nie „uproscil".
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Unikalne na przebieg — inaczej licznik z poprzedniego uruchomienia decyduje
# o wyniku i test mierzy smieci, a nie produkt.
STEMPEL="$$-$(date +%s)"
MAIL="okno-2-31-${STEMPEL}@example.com"
SERIAL="OKNO-${STEMPEL}"
IP="203.0.113.$(( ( $$ % 250 ) + 1 ))"

# Klucze licznikow liczymy TA SAMA droga co produkt (hash adresu), zeby test nie
# zgadywal, gdzie produkt zapisuje.
KLUCZ_MAIL=$(wp eval "echo 'mp_rl_em_' . md5( MP\\Intake\\RateLimit::normalize_email_for_key( '$MAIL' ) );" 2>/dev/null | tr -d '[:space:]')
KLUCZ_IP=$(wp eval "echo 'mp_rl_ip_' . md5( '$IP' );" 2>/dev/null | tr -d '[:space:]')

koniec_okna() { q "SELECT window_expires_at FROM wp_mp_rate_counters WHERE rl_key='$1'"; }
licznik()     { q "SELECT hits FROM wp_mp_rate_counters WHERE rl_key='$1'"; }

wp db query "DELETE FROM wp_mp_rate_counters WHERE rl_key IN ('$KLUCZ_MAIL','$KLUCZ_IP')" >/dev/null 2>&1

zgloszenie() { wp eval "MP\\Intake\\RateLimit::record_submission( '$MAIL', '$SERIAL', 'reklamacja' );" >/dev/null 2>&1; }

# ── 1. SEDNO: drugie zgloszenie NIE odsuwa konca okna ──────────────────────
zgloszenie
KONIEC_1=$(koniec_okna "$KLUCZ_MAIL")
[ -n "$KONIEC_1" ] \
	&& ok "pierwsze zgloszenie zalozylo licznik (okno do $KONIEC_1)" \
	|| bad "pierwsze zgloszenie nie zalozylo licznika — test nic nie dowiedzie"

# Odstep MUSI byc widoczny w zapisie daty (rozdzielczosc kolumny to 1 sekunda).
# Bez niego „okno sie nie przesunelo" i „przesunelo sie o zero sekund" wygladaja
# tak samo i kontrola przechodzilaby takze na wadliwym kodzie.
sleep 2

zgloszenie
KONIEC_2=$(koniec_okna "$KLUCZ_MAIL")
LICZNIK_2=$(licznik "$KLUCZ_MAIL")

[ "$KONIEC_2" = "$KONIEC_1" ] \
	&& ok "SEDNO: drugie zgloszenie NIE przesunelo konca okna ($KONIEC_1)" \
	|| bad "koniec okna przesuniety z $KONIEC_1 na $KONIEC_2 — „na dobe” dziala jak „pod rzad” (wada 2.31)"

[ "${LICZNIK_2:-0}" = "2" ] \
	&& ok "licznik policzyl oba zgloszenia (hits=2)" \
	|| bad "licznik pokazuje [$LICZNIK_2] zamiast 2 — ograniczenie przestaloby chronic"

# ── 2. Limit NADAL dziala: trzecie przechodzi, czwarte odrzucone ───────────
# Naprawa okna nie moze rozbroic ochrony. Domyslnie 3 zgloszenia na adres.
zgloszenie
BLOKADA=$(wp eval "echo (string) MP\\Intake\\RateLimit::check( '', '$MAIL', '', 'reklamacja' );" 2>/dev/null | tr -d '[:space:]')
[ "$BLOKADA" = "rate" ] \
	&& ok "po trzech zgloszeniach czwarte jest odrzucone (limit dziala dalej)" \
	|| bad "po trzech zgloszeniach kolejne przechodzi (odpowiedz: [$BLOKADA]) — ochrona rozbrojona"

# ── 3. Po WYGASNIECIU okna klient jest odblokowany ────────────────────────
# Przesuwamy koniec okna w przeszlosc — tak wyglada nastepna doba. To jedyne
# miejsce, gdzie test rusza baze: podrozy w czasie nie da sie zrobic inaczej.
wp db query "UPDATE wp_mp_rate_counters SET window_expires_at = '2020-01-01 00:00:00' WHERE rl_key='$KLUCZ_MAIL'" >/dev/null 2>&1
PO_DOBIE=$(wp eval "echo (string) MP\\Intake\\RateLimit::check( '', '$MAIL', '', 'reklamacja' );" 2>/dev/null | tr -d '[:space:]')
[ -z "$PO_DOBIE" ] \
	&& ok "po wygasnieciu okna klient moze zglaszac ponownie" \
	|| bad "po wygasnieciu okna klient dalej zablokowany ([$PO_DOBIE])"

zgloszenie
LICZNIK_PO=$(licznik "$KLUCZ_MAIL")
[ "${LICZNIK_PO:-0}" = "1" ] \
	&& ok "nowe okno startuje od jednego zgloszenia (hits=1)" \
	|| bad "po wygasnieciu okna licznik = [$LICZNIK_PO] zamiast 1"

# ── 4. Odrzucone proby NIE przedluzaja okna ───────────────────────────────
# Gdyby przedluzaly, zablokowany klient zapetlalby wlasna blokade kazda proba.
wp db query "UPDATE wp_mp_rate_counters SET hits=3 WHERE rl_key='$KLUCZ_MAIL'" >/dev/null 2>&1
KONIEC_PRZED_PROBA=$(koniec_okna "$KLUCZ_MAIL")
sleep 2
wp eval "MP\\Intake\\RateLimit::check( '', '$MAIL', '', 'reklamacja' );" >/dev/null 2>&1
KONIEC_PO_PROBIE=$(koniec_okna "$KLUCZ_MAIL")
[ "$KONIEC_PO_PROBIE" = "$KONIEC_PRZED_PROBA" ] \
	&& ok "odrzucona proba nie przedluzyla okna (klient nie zapetla blokady)" \
	|| bad "odrzucona proba przesunela okno z $KONIEC_PRZED_PROBA na $KONIEC_PO_PROBIE"

# ── 5. Ochrona przeciwzalewowa po IP DALEJ ma okno przesuwane ─────────────
# ⛔ To NIE jest ta sama sprawa co limit zgloszen i celowo zostaje inne: przy
# zalewie chcemy, zeby blokada trwala, dopoki puka. Kontrola stoi tu po to, zeby
# ktos „porzadkujacy" nie zrownal obu przypadkow i nie oslabil ochrony.
wp db query "DELETE FROM wp_mp_rate_counters WHERE rl_key='$KLUCZ_IP'" >/dev/null 2>&1
wp eval "MP\\Intake\\RateLimit::check( '$IP', 'inny-$STEMPEL@example.com', '', 'reklamacja' );" >/dev/null 2>&1
IP_KONIEC_1=$(koniec_okna "$KLUCZ_IP")
sleep 2
wp eval "MP\\Intake\\RateLimit::check( '$IP', 'inny2-$STEMPEL@example.com', '', 'reklamacja' );" >/dev/null 2>&1
IP_KONIEC_2=$(koniec_okna "$KLUCZ_IP")

if [ -z "$IP_KONIEC_1" ] || [ -z "$IP_KONIEC_2" ]; then
	bad "licznik IP nie powstal — kontrola asymetrii nic nie dowodzi"
elif [ "$IP_KONIEC_2" != "$IP_KONIEC_1" ]; then
	ok "ochrona po IP zachowala okno PRZESUWANE ($IP_KONIEC_1 -> $IP_KONIEC_2)"
else
	bad "okno IP przestalo sie przesuwac — oslabiona ochrona przed zalewem"
fi

# ── 6. SPRZATANIE ────────────────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_rate_counters WHERE rl_key IN ('$KLUCZ_MAIL','$KLUCZ_IP')" >/dev/null 2>&1
ZOSTALO=$(q "SELECT COUNT(*) FROM wp_mp_rate_counters WHERE rl_key IN ('$KLUCZ_MAIL','$KLUCZ_IP')")
[ "${ZOSTALO:-1}" = "0" ] \
	&& ok "liczniki testowe posprzatane" \
	|| bad "zostawiamy liczniki testowe ($ZOSTALO)"

echo ""
echo "WYNIK 2.31: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
