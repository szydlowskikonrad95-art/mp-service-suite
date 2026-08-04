#!/usr/bin/env bash
# ZYWY DOWOD: notatka wewnetrzna personelu WCHODZI do paczki RODO.
#
# Skad ta pozycja: naprawa 2.15 dolozyla notatki wewnetrzne i — slusznie — ustawila
# odczyt DOMYSLNY tak, zeby ich NIE zwracal (`Messages::for_case()` bez drugiego
# argumentu). Panel klienta jest przez to bezpieczny. Ale `Privacy::export()`, czyli
# wydanie danych na zadanie RODO, czytal wiadomosci wlasnie tym domyslnym odczytem —
# wiec po tamtej zmianie notatki o kliencie PRZESTALY wchodzic do wydawanej paczki.
#
# ⛔ Decyzja (czat glowny, 4.08): MAJA WCHODZIC. Artykul 15 RODO obejmuje takze OPINIE
# o osobie, wiec notatka personelu o kliencie jest jego dana. Pominiecie byloby awaria
# NIEWIDOCZNA dla administratora — paczka wygladalaby na kompletna.
#
# Ten test pilnuje OBU stron naraz, bo latwo naprawic jedna kosztem drugiej:
#   1. notatka wewnetrzna JEST w paczce RODO (sedno naprawy),
#   2. paczka mowi, ze to notatka personelu, a nie wiadomosc wyslana do klienta,
#   3. zwykla wiadomosc dalej jest w paczce (bez regresji),
#   4. panel klienta NADAL notatki NIE pokazuje — gwarancja z 2.15 nietknieta,
#   5. po usunieciu danych notatka znika z paczki tak samo jak reszta.
#
# Wymaga zywego `wp`. Exit 0 = OK. Test sprzata po sobie (wspolna baza w CI).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
ev()  { wp eval "$1" 2>/dev/null; }

EMAIL="rodo-notatka-$$@przyklad.test"
NOTATKA="NOTATKA-WEWNETRZNA-Klient-podejrzany-o-ingerencje-$$"
WIADOMOSC="ZWYKLA-WIADOMOSC-Prosze-o-status-$$"

ZALOZONE_KONTA=''
KONTO_ID=''

# Odporne zakladanie konta (w CI role MP bywaja chwilowo skasowane przez test
# odinstalowania — patrz naprawa dowodu 2.38).
konto() {
	LOGIN="$1"; UPRAWNIENIE="$2"; KONTO_ID=''
	ID=$(wp user get "$LOGIN" --field=ID 2>/dev/null | tr -d '[:space:]')

	if [ -z "$ID" ]; then
		WYNIK=$(wp user create "$LOGIN" "$LOGIN@c-rodo-notatki.test" --porcelain 2>&1)
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
		echo "  --   rola '$UPRAWNIENIE' nie istnieje w tej bazie — nadaje samo uprawnienie"
		wp user add-cap "$ID" "$UPRAWNIENIE" >/dev/null 2>&1
	fi

	KONTO_ID="$ID"
}

paczka_rodo() {
	ev "\$w = MP\\Intake\\Privacy::export( '$EMAIL' );
		\$t = '';
		foreach ( (array) \$w['data'] as \$grupa ) {
			foreach ( (array) \$grupa['data'] as \$pole ) { \$t .= \$pole['name'] . '=' . \$pole['value'] . \"\n\"; }
		}
		echo \$t;"
}

konto rodo_agent mp_agent
AGENT="$KONTO_ID"

OUT=$(wp mp case-create --kind=reklamacja --email="$EMAIL" --name='Klient Notatka' \
	--serial="SN-RODO-$$" --document="FV/RODO/$$" --date='2026-05-05' --desc='Sprzet nie wlacza sie' 2>/dev/null)
TOK=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$TOK" >/dev/null 2>&1
CASE_ID=$(ev "global \$wpdb; echo (int) \$wpdb->get_var( \$wpdb->prepare( \"SELECT c.id FROM {\$wpdb->prefix}mp_service_cases c INNER JOIN {\$wpdb->prefix}mp_customers k ON k.id = c.customer_id WHERE k.email = %s ORDER BY c.id DESC LIMIT 1\", '$EMAIL' ) );" | tr -d '[:space:]')

sprzataj() {
	if [ -n "${CASE_ID:-}" ] && [ "$CASE_ID" != "0" ]; then
		wp db query "DELETE FROM wp_mp_messages WHERE case_id=$CASE_ID;" >/dev/null 2>&1
		wp db query "DELETE FROM wp_mp_case_events WHERE case_id=$CASE_ID;" >/dev/null 2>&1
		wp db query "DELETE FROM wp_mp_service_cases WHERE id=$CASE_ID;" >/dev/null 2>&1
	fi
	wp db query "DELETE FROM wp_mp_customers WHERE email='$EMAIL';" >/dev/null 2>&1
	for U in $ZALOZONE_KONTA; do wp user delete "$U" --yes >/dev/null 2>&1; done
}

if [ -z "$CASE_ID" ] || [ "$CASE_ID" = "0" ] || [ -z "$AGENT" ] || [ "$FAIL" -gt 0 ]; then
	bad "nie udalo sie przygotowac stanowiska (CASE_ID=$CASE_ID AGENT=$AGENT) — powod wyzej"
	sprzataj
	echo "WYNIK: $PASS ok, $FAIL fail"
	exit 1
fi
ok "seed: sprawa potwierdzona (id=$CASE_ID), konto pracownika gotowe"

ev "MP\\Intake\\Messages::add( $CASE_ID, 'client', null, '$WIADOMOSC' );" >/dev/null 2>&1
ev "MP\\Intake\\Messages::add_internal_note( $CASE_ID, $AGENT, '$NOTATKA' );" >/dev/null 2>&1
ILE=$(wp db query "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CASE_ID;" --skip-column-names 2>/dev/null | tr -d '[:space:]')
[ "$ILE" -ge 2 ] 2>/dev/null && ok "seed: w sprawie sa wiadomosc klienta i notatka personelu ($ILE wpisow)" || bad "seed: wpisow w sprawie: $ILE"

echo "== 1. SEDNO: NOTATKA WEWNETRZNA JEST W PACZCE RODO =="
PACZKA=$(paczka_rodo)
case "$PACZKA" in
	*"$NOTATKA"*) ok "notatka personelu wydana klientowi na zadanie RODO" ;;
	*)            bad "notatki NIE MA w paczce RODO — awaria niewidoczna dla administratora" ;;
esac

echo "== 2. PACZKA MOWI, ZE TO NOTATKA PERSONELU =="
case "$PACZKA" in
	*"notatka wewnętrzna personelu"*) ok "wpis opisany jako notatka wewnetrzna" ;;
	*)                                bad "paczka nie odroznia notatki od wiadomosci do klienta" ;;
esac

echo "== 3. ZWYKLA WIADOMOSC DALEJ W PACZCE (bez regresji) =="
case "$PACZKA" in
	*"$WIADOMOSC"*) ok "wiadomosc klienta dalej w paczce" ;;
	*)              bad "z paczki zniknela zwykla wiadomosc" ;;
esac

echo "== 4. PANEL KLIENTA NADAL NIE POKAZUJE NOTATKI (gwarancja z 2.15) =="
# ⛔ Tu najlatwiej naprawic jedno kosztem drugiego: dolozyc notatki do eksportu
# i przy okazji rozszczelnic odczyt domyslny, ktorym karmi sie panel klienta.
DOMYSLNY=$(ev "\$m = MP\\Intake\\Messages::for_case( $CASE_ID ); \$t=''; foreach ( \$m as \$w ) { \$t .= \$w['body'] . \"\n\"; } echo \$t;")
case "$DOMYSLNY" in
	*"$NOTATKA"*) bad "odczyt DOMYSLNY zwraca notatke — panel klienta by ja pokazal" ;;
	*)            ok "odczyt domyslny dalej bez notatek wewnetrznych" ;;
esac
case "$DOMYSLNY" in
	*"$WIADOMOSC"*) ok "odczyt domyslny dalej zwraca zwykle wiadomosci (proba kontrolna)" ;;
	*)              bad "odczyt domyslny nie zwraca nic — pomiar wyzej nic nie znaczy" ;;
esac

echo "== 5. REDAKCJA RODO OBEJMUJE TAKZE NOTATKE =="
# ⛔ Skoro notatke WYDAJEMY na zadanie dostepu (art. 15), to przy zadaniu usuniecia
# (art. 17) musi zniknac tak samo jak reszta — inaczej sami zrobilismy sobie dziure.
# ⚠️ Nie wolamy tu `Privacy::erase()`: przy AKTYWNEJ sprawie odmawia ono usuniecia
# (retencja do zakonczenia sprawy) i test mierzylby wtedy retencje, a nie redakcje.
# Zlapane kalibracja — pierwsza wersja tej sekcji padala z tego wlasnie powodu.
ev "MP\\Intake\\Messages::redact_for_cases( array( $CASE_ID ) );" >/dev/null 2>&1
PO=$(paczka_rodo)
case "$PO" in
	*"$NOTATKA"*) bad "redakcja RODO pominela notatke wewnetrzna — zostaje w paczce po usunieciu danych" ;;
	*)            ok "notatka zredagowana razem z wiadomosciami" ;;
esac
case "$PO" in
	*"$WIADOMOSC"*) bad "redakcja pominela zwykla wiadomosc — pomiar wyzej nic nie znaczy" ;;
	*)              ok "zwykla wiadomosc tez zredagowana (proba kontrolna)" ;;
esac

sprzataj

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
