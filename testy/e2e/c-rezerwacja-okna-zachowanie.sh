#!/usr/bin/env bash
# ZYWY DOWOD: rezerwacja okna (`RateLimit::claim_window`) zachowuje sie DOKLADNIE
# tak, jak obiecuje kontrakt — niezaleznie od tego, jak jest w srodku napisana.
#
# Ta metoda jest wspolnym mechanizmem DWOCH rzeczy: odsiewania podwojnych zgloszen
# (modul zgloszen) i tlumienia podwojnych maili (modul automatyzacji). Warunki,
# ktore mial spelniac dotad i ma spelniac dalej:
#  1. pierwsza rezerwacja przechodzi, druga w tym samym oknie NIE;
#  2. okno liczy sie od PIERWSZEJ rezerwacji, a cudza proba go NIE PRZEDLUZA;
#  3. okno <= 0 wylacza rezerwacje (zawsze wolno);
#  4. inny klucz w tym samym oknie przechodzi (rezerwacja nie lapie za szeroko).
#
# Test jest krotki i nic nie zapisuje trwale — sprzata swoje klucze na wejsciu
# i na wyjsciu. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

sprzataj() { wp db query "DELETE FROM wp_mp_rate_counters WHERE rl_key LIKE 'proba_okna_%'" >/dev/null 2>&1; }
sprzataj

KLUCZ="proba_okna_$(date +%s)"

# ── 1. Pierwsza przechodzi, druga w oknie odbija ────────────────────────────
PARA=$(wp eval "
	\$a = MP\\Intake\\RateLimit::claim_window( '${KLUCZ}_a', 60 ) ? '1' : '0';
	\$b = MP\\Intake\\RateLimit::claim_window( '${KLUCZ}_a', 60 ) ? '1' : '0';
	echo \$a . \$b;
" 2>/dev/null | tr -d '[:space:]')
[ "$PARA" = "10" ] \
	&& ok "pierwsza rezerwacja przyznana, druga w tym samym oknie odrzucona" \
	|| bad "zle zachowanie pary rezerwacji ($PARA, oczekiwane 10)"

# ── 2. Inny klucz w tym samym oknie przechodzi ──────────────────────────────
INNY=$(wp eval "echo MP\\Intake\\RateLimit::claim_window( '${KLUCZ}_b', 60 ) ? '1' : '0';" 2>/dev/null | tr -d '[:space:]')
[ "$INNY" = "1" ] \
	&& ok "inny klucz w tym samym oknie przechodzi (rezerwacja nie lapie za szeroko)" \
	|| bad "inny klucz zablokowany ($INNY)"

# ── 3. Okno <= 0 wylacza rezerwacje ─────────────────────────────────────────
ZERO=$(wp eval "
	\$a = MP\\Intake\\RateLimit::claim_window( '${KLUCZ}_c', 0 ) ? '1' : '0';
	\$b = MP\\Intake\\RateLimit::claim_window( '${KLUCZ}_c', 0 ) ? '1' : '0';
	echo \$a . \$b;
" 2>/dev/null | tr -d '[:space:]')
[ "$ZERO" = "11" ] \
	&& ok "okno <= 0 wylacza rezerwacje (kazda proba przechodzi — jak dotad)" \
	|| bad "okno zero zachowuje sie inaczej niz dotad ($ZERO, oczekiwane 11)"

# ── 4. SEDNO: okno liczy sie od PIERWSZEJ rezerwacji, cudza proba go NIE PRZEDLUZA ──
# Rezerwujemy na 6 sekund. Proby w 1. i 3. sekundzie musza sie odbic (to sa wlasnie
# „cudze proby"). Po uplywie okna klucz ma byc znowu wolny — gdyby ktorakolwiek
# z prob przedluzala okno, ostatnia probowka bylaby odmowna.
OKNO=$(wp eval "
	\$k = '${KLUCZ}_d';
	\$pierwsza = MP\\Intake\\RateLimit::claim_window( \$k, 6 ) ? '1' : '0';
	sleep( 1 );
	\$w1 = MP\\Intake\\RateLimit::claim_window( \$k, 6 ) ? '1' : '0';
	sleep( 2 );
	\$w3 = MP\\Intake\\RateLimit::claim_window( \$k, 6 ) ? '1' : '0';
	sleep( 5 );
	\$po = MP\\Intake\\RateLimit::claim_window( \$k, 6 ) ? '1' : '0';
	echo \$pierwsza . \$w1 . \$w3 . \$po;
" 2>/dev/null | tr -d '[:space:]')

[ "$OKNO" = "1001" ] \
	&& ok "okno liczy sie od PIERWSZEJ rezerwacji: proby w trakcie odbite, po uplywie klucz znowu wolny (cudza proba NIE przedluza okna)" \
	|| bad "zachowanie okna inne niz dotad ($OKNO, oczekiwane 1001 = przyznana / odbita / odbita / znowu wolna)"

# ── 5. Zwolnienie rezerwacji dziala jak dotad (retry po odrzuconej walidacji) ──
ZWOLNIENIE=$(wp eval "
	\$k = '${KLUCZ}_e';
	\$a = MP\\Intake\\RateLimit::claim_window( \$k, 60 ) ? '1' : '0';
	\$GLOBALS['wpdb']->query( \$GLOBALS['wpdb']->prepare( 'DELETE FROM ' . MP\\Intake\\Tables::full( MP\\Intake\\Tables::RATE_COUNTERS ) . ' WHERE rl_key = %s', \$k ) );
	\$b = MP\\Intake\\RateLimit::claim_window( \$k, 60 ) ? '1' : '0';
	echo \$a . \$b;
" 2>/dev/null | tr -d '[:space:]')
[ "$ZWOLNIENIE" = "11" ] \
	&& ok "po zwolnieniu klucza rezerwacja jest znowu dostepna (sciezka retry po bledzie walidacji)" \
	|| bad "zwolniony klucz nie wraca do obiegu ($ZWOLNIENIE)"

sprzataj
ZOSTALO=$(wp db query "SELECT COUNT(*) FROM wp_mp_rate_counters WHERE rl_key LIKE 'proba_okna_%'" --skip-column-names 2>/dev/null | tr -d '[:space:]')
[ "${ZOSTALO:-9}" = "0" ] \
	&& ok "test posprzatal swoje klucze" \
	|| bad "zostaly klucze testowe ($ZOSTALO)"

echo ""
echo "WYNIK REZERWACJA-OKNA: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
