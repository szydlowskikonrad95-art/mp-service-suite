#!/usr/bin/env bash
# STRAZNIK: API-KONTRAKT.md i SECURITY.md musza opisywac TEN kod, ktory jest.
#
# Trzy pozycje audytu 1.3.12, wszystkie tej samej klasy „dokument mowi co innego
# niz kod" — ale w strone ODWROTNA niz zwykle: tu kod jest LEPSZY niz dokument.
#
#  2.32  SECURITY.md:87 opisywal rate-limit „na transientach" i wymienial wlasna
#        tabele jako „poza zakresem". Tabela JEST od migracji v2 (RATE_COUNTERS
#        w szesciu miejscach RateLimit.php). Dokument ZANIZAL wlasny wyrob:
#        wdrozeniowiec kalibrowal progi wedlug mechanizmu, ktorego nie ma,
#        i bral pod uwage zastrzezenie o object-cache, ktore nie obowiazuje.
#
#  2.33  Kontrakt opisywal WYLACZNIE `mp_case_deadline` (pojedynczy), a lista
#        spraw stoi na hurtowym `mp_case_deadlines`. Skutek juz zaszedl:
#        zewnetrzny recenzent czytajacy sam kontrakt zdiagnozowal „zapytanie na
#        kazdy wiersz" jako zagrozenie najwyzszej wagi — wade, ktorej w kodzie
#        NIE MA. Dokument wyprodukowal falszywy alarm przeciwko wlasnemu produktowi.
#
#  2.48  `mp_intake_captcha_html` = zaczep-widmo: ZERO wywolan w kodzie. Stal
#        szesnascie linii pod nasza wlasna nota o naprawieniu pierwszego widma
#        (`mp_case_card_sections`, audyt #15). Klase bledu znalezliono, nazwano,
#        opisano skutek — i naprawiono EGZEMPLARZ, nie przeczesujac dokumentu.
#
# ⭐ DLATEGO SEKCJA 3 NIE SPRAWDZA JEDNEJ NAZWY, TYLKO ROBI KONTROLE W OBIE STRONY
#    dla KAZDEGO punktu kontraktu. Test na sama captche zamknalby egzemplarz
#    i przepuscil trzecie widmo — czyli powtorzylby dokladnie ten blad, ktory
#    ta pozycja opisuje.
#
# ⭐ PRZYPADKI KONTROLNE (bez nich „naprawa" byloby przepisaniem dokumentu):
#    kazde twierdzenie dokumentu jest tu sprawdzane RAZEM z kodem, ktorego dotyczy.
#    Gdyby kod wrocil na transienty albo lista przestala wolac wariant hurtowy,
#    ten test ma zaczerwienic sie tak samo, jak gdy sklamie dokument.
#
# ⛔ STRAZNIK KOMPLETU (lekcja z 04.08: „kontrola, ktora cicho nie startuje,
#    swieci zielono"): ekstraktor nazw musi znalezc co najmniej MIN_PUNKTOW
#    punktow kontraktu. Zepsuty regex = blad przebiegu, nie zielone zero.
#
# Uruchomienie z katalogu repo:  bash testy/dokumenty/kontrakt-i-bezpieczenstwo-zgodne-z-kodem.sh
# Zero WordPressa i zero bazy — czyta pliki repo. Exit 0 = zero FAIL.
set -u

# Katalog repo liczony z $0, nie wzglednie (w CI test chodzi z /tmp/wp).
REPO="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
cd "$REPO" || { echo "BLAD PRZEBIEGU: nie wchodze do $REPO"; exit 2; }

KONTRAKT="dokumentacja-techniczna/API-KONTRAKT.md"
SECURITY="dokumentacja-techniczna/SECURITY.md"
MIN_PUNKTOW=20

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

for f in "$KONTRAKT" "$SECURITY"; do
	[ -f "$f" ] || { echo "BLAD PRZEBIEGU: brak $f"; exit 2; }
done

# Wszystkie wywolania zaczepow W KODZIE (zrodlo prawdy dla obu kierunkow).
KOD_HOOKI=$(grep -rhoE "(apply_filters|do_action)\( *'mp_[a-z0-9_]+'" \
	--include=*.php mp-service-intake mp-warranty-registry mp-workflow-automator \
	| grep -oE "mp_[a-z0-9_]+" | sort -u)

LICZBA_KOD=$(printf '%s\n' "$KOD_HOOKI" | grep -c . || true)
if [ "$LICZBA_KOD" -lt "$MIN_PUNKTOW" ]; then
	echo "BLAD PRZEBIEGU: w kodzie widze tylko $LICZBA_KOD zaczepow (< $MIN_PUNKTOW)."
	echo "To wada przyrzadu, nie produktu — nie melduj zielonego."
	exit 2
fi

echo "== 2.32 · SECURITY.md o ograniczniku zgłoszeń =="

# Sedno: dokument nie opisuje mechanizmu, ktorego nie ma.
if grep -qiE "rate-limit zgłoszeń na transientach" "$SECURITY"; then
	bad "2.32a SECURITY.md nadal opisuje rate-limit „na transientach\""
else
	ok "2.32a SECURITY.md nie opisuje już ogranicznika na transientach"
fi

# Sedno: dokument nie zaniza wlasnego wyrobu.
if grep -qiE "twardsza gwarancja = własna tabela \(poza zakresem" "$SECURITY"; then
	bad "2.32b SECURITY.md nadal nazywa własną tabelę „poza zakresem\" (produkt ją MA)"
else
	ok "2.32b SECURITY.md nie nazywa już własnej tabeli „poza zakresem\""
fi

# Sedno: dokument nazywa mechanizm, ktory jest.
if grep -qE "wp_mp_rate_counters|RATE_COUNTERS" "$SECURITY"; then
	ok "2.32c SECURITY.md wskazuje tabelę liczników po nazwie"
else
	bad "2.32c SECURITY.md nie wskazuje tabeli liczników — wdrożeniowiec nie wie, co kalibrować"
fi

# PRZYPADEK KONTROLNY: kod NAPRAWDE liczy w tabeli.
UZYC_TABELI=$(grep -cE "Tables::RATE_COUNTERS" mp-service-intake/includes/RateLimit.php || true)
if [ "$UZYC_TABELI" -ge 6 ]; then
	ok "2.32d [kontrolny] kod liczy w tabeli — $UZYC_TABELI odwołań do Tables::RATE_COUNTERS"
else
	bad "2.32d [kontrolny] tylko $UZYC_TABELI odwołań do RATE_COUNTERS — dokument obiecuje więcej niż kod"
fi

# PRZYPADEK KONTROLNY: liczniki NIE wrocily na transienty.
if grep -qE "(set|get)_transient\( *(self::)?(rate|dedup|limit)" mp-service-intake/includes/RateLimit.php; then
	bad "2.32e [kontrolny] licznik znowu chodzi na transiencie — teraz kłamie NOWY zapis w dokumencie"
else
	ok "2.32e [kontrolny] liczniki nie chodzą na transientach"
fi

echo "== 2.33 · hurtowy wariant terminów SLA =="

# PRZYPADEK KONTROLNY: to kod ustala kontrakt, nie odwrotnie.
if grep -qE "apply_filters\( *'mp_case_deadlines'" mp-service-intake/includes/Admin/CasesListTable.php; then
	ok "2.33a [kontrolny] lista spraw naprawdę woła wariant hurtowy"
else
	bad "2.33a [kontrolny] lista nie woła 'mp_case_deadlines' — kontrakt opisywałby nieistniejącą drogę"
fi

if grep -qE "add_filter\( *'mp_case_deadlines'" mp-workflow-automator/includes/CaseCardApi.php; then
	ok "2.33b [kontrolny] automator rejestruje wariant hurtowy"
else
	bad "2.33b [kontrolny] automator nie rejestruje 'mp_case_deadlines'"
fi

# Sedno: kontrakt zna punkt, na ktorym stoi glowny ekran.
if grep -qE '`mp_case_deadlines' "$KONTRAKT"; then
	ok "2.33c kontrakt opisuje hurtowe 'mp_case_deadlines'"
else
	bad "2.33c kontrakt NIE opisuje 'mp_case_deadlines' — kto pisze 4. moduł, napisze zapytanie na wiersz"
fi

# Sedno: wariant pojedynczy zostaje jako zapas, nie znika.
if grep -qE '`mp_case_deadline\(' "$KONTRAKT"; then
	ok "2.33d kontrakt nadal opisuje wariant pojedynczy (zapas przy braku modułu D)"
else
	bad "2.33d zniknął wariant pojedynczy — a lista spada na niego, gdy hurtowego nikt nie obsługuje"
fi

echo "== 2.48 · zero zaczepów-widm (kontrola w OBIE strony) =="

# Punkty kontraktu = naglowki `### `mp_...``, wytluszczenia `**`mp_...``
# na poczatku linii oraz wiersze mapy skrotowej `| mp_... |`.
# Zwykla wzmianka w zdaniu albo w nocie NIE jest punktem kontraktu — inaczej
# nota o wycofanej captchy sama zglaszalaby siebie.
PUNKTY=$(grep -hoE "^(### \`|\*\*\`|\| *(\*\*)?\`?)mp_[a-z0-9_]+" "$KONTRAKT" \
	| grep -oE "mp_[a-z0-9_]+" | sort -u)

# Mapa skrotowa wymienia po kilka nazw w jednej komorce, rozdzielonych '·'.
PUNKTY_MAPA=$(grep -hoE "^\| [^|]*mp_[a-z0-9_]+[^|]*\|" "$KONTRAKT" \
	| grep -oE "mp_[a-z0-9_]+" | sort -u)

PUNKTY=$(printf '%s\n%s\n' "$PUNKTY" "$PUNKTY_MAPA" | grep -E "^mp_" | sort -u)
LICZBA_PUNKTOW=$(printf '%s\n' "$PUNKTY" | grep -c . || true)

# STRAZNIK KOMPLETU — zepsuty ekstraktor ma byc bledem, nie zielonym zerem.
if [ "$LICZBA_PUNKTOW" -lt "$MIN_PUNKTOW" ]; then
	echo "BLAD PRZEBIEGU: ekstraktor znalazl tylko $LICZBA_PUNKTOW punktow kontraktu (< $MIN_PUNKTOW)."
	echo "Kontrola widm NIE wykonala sie — to wada przyrzadu, nie zielone zero."
	exit 2
fi
echo "  (ekstraktor: $LICZBA_PUNKTOW punktów kontraktu, $LICZBA_KOD zaczepów w kodzie)"

WIDMA=""
for h in $PUNKTY; do
	printf '%s\n' "$KOD_HOOKI" | grep -qx "$h" || WIDMA="$WIDMA $h"
done

if [ -z "$WIDMA" ]; then
	ok "2.48a każdy punkt kontraktu ma wywołanie w kodzie (sprawdzone $LICZBA_PUNKTOW nazw)"
else
	bad "2.48a zaczep(y)-widmo w kontrakcie:$WIDMA — integrator podepnie się donikąd"
fi

# Sedno pozycji, nazwane wprost: captcha ma zniknac Z PUNKTOW kontraktu.
if printf '%s\n' "$PUNKTY" | grep -qx "mp_intake_captcha_html"; then
	bad "2.48b 'mp_intake_captcha_html' nadal stoi jako punkt kontraktu"
else
	ok "2.48b 'mp_intake_captcha_html' nie jest już punktem kontraktu"
fi

# PROBA KONTROLNA metody (ta sama, ktorej uzyl audyt): ekstraktor musi widziec
# zaczepy, ktore ISTNIEJA. Bez tego „zero widm" moglby znaczyc „zero odczytu".
for znany in mp_case_deadline mp_warranty_check mp_case_created; do
	if printf '%s\n' "$PUNKTY" | grep -qx "$znany"; then
		ok "2.48c [próba kontrolna] ekstraktor widzi istniejący punkt '$znany'"
	else
		bad "2.48c [próba kontrolna] ekstraktor NIE widzi '$znany' — metoda nie działa, wynik nic nie znaczy"
	fi
done

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
