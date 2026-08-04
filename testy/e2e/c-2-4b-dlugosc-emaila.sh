#!/usr/bin/env bash
# ZYWY DOWOD (2.4 czesc b): adres e-mail ma regule DLUGOSCI — na kazdej sciezce.
#
# Co bylo zle: kolumny `customers.email` i `service_cases.contact_email` to
# VARCHAR(190), a reguly dlugosci dla adresu nie bylo NIGDZIE — mimo ze komentarz
# w kodzie twierdzil, ze e-mail ma „wlasna, ciasniejsza regule". Adres poprawny
# ksztaltem, ale dluzszy niz 190 znakow, przechodzil walidacje i rozbijal sie
# dopiero o baze: czlowiek dostawal „blad zapisu do bazy" zamiast zdania o tym,
# co ma poprawic. Czesc (a) tej pozycji (import) zostala naprawiona wczesniej —
# to jest jej druga polowka.
#
# Exit 0 = OK. Test nic nie zapisuje trwale (sprzata zalozone konto i sprawe).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Adres POPRAWNY KSZTALTEM, ale dluzszy niz kolumna: 60-znakowa czesc lokalna
# (limit RFC to 64) + lancuch poddomen. Chodzi o to, zeby ksztalt NIE byl powodem
# odrzucenia — inaczej test badalby nie te regule, co trzeba.
DLUGI=$(wp eval 'echo str_repeat( "a", 60 ) . "@" . str_repeat( "bardzo-dluga-poddomena.", 6 ) . "example.com";' 2>/dev/null | tr -d '[:space:]')
DL=${#DLUGI}
[ "$DL" -gt 190 ] \
	&& ok "adres testowy ma $DL znakow (wiecej niz kolumna 190)" \
	|| bad "adres testowy jest za krotki ($DL) — test nie cwiczy limitu"

KSZTALT=$(wp eval "echo MP\\Intake\\Validator::is_email( '$DLUGI' ) ? 'POPRAWNY' : 'ZLY';" 2>/dev/null | tr -d '[:space:]')
[ "$KSZTALT" = "POPRAWNY" ] \
	&& ok "proba kontrolna: ksztalt adresu jest POPRAWNY (odrzuci go wylacznie regula dlugosci)" \
	|| bad "adres testowy jest zly ksztaltem ($KSZTALT) — test badalby inna regule"

# ── 1. SEDNO: regula dlugosci istnieje i lapie adres ────────────────────────
WALIDATOR=$(wp eval "echo (string) ( MP\\Intake\\Validator::validate_email( '$DLUGI' ) ?? 'BRAK-BLEDU' );" 2>/dev/null | tr -d '[:space:]')
[ "$WALIDATOR" = "TOO_LONG" ] \
	&& ok "SEDNO: walidator odrzuca za dlugi adres kodem TOO_LONG" \
	|| bad "walidator nie ma reguly dlugosci dla e-maila (zwrocil: $WALIDATOR)"

# ── 2. SEDNO: sciezka zgloszenia z formularza ───────────────────────────────
ZGLOSZENIE=$(wp eval "
	\$bledy = MP\\Intake\\CaseRepo::collect_validation_errors( 'zapytanie', '$DLUGI', array( 'issue_description' => 'opis' ), gmdate( 'Y-m-d' ) );
	\$kody = array();
	foreach ( \$bledy as \$b ) { if ( 'email' === ( \$b['field'] ?? '' ) ) { \$kody[] = (string) \$b['reason_code']; } }
	echo wp_json_encode( \$kody );
" 2>/dev/null)
echo "$ZGLOSZENIE" | grep -q 'TOO_LONG' \
	&& ok "SEDNO: zgloszenie z formularza odrzuca za dlugi adres PRZED baza" \
	|| bad "sciezka zgloszenia przepuszcza za dlugi adres do bazy ($ZGLOSZENIE)"

# ── 3. SEDNO: sciezka zakladania konta klienta ──────────────────────────────
KONTO=$(wp eval "echo (int) MP\\Intake\\Accounts::ensure_for_customer( 999999, '$DLUGI' );" 2>/dev/null | tr -d '[:space:]')
[ "$KONTO" = "0" ] \
	&& ok "SEDNO: zakladanie konta odrzuca za dlugi adres (zero prob zapisu do bazy)" \
	|| bad "zakladanie konta probowalo zalozyc konto na adresie $DL znakow (zwrocilo: $KONTO)"

# ── 4. PRZYPADEK BEZ WADY: normalny adres dalej przechodzi wszedzie ─────────
NORMALNY='jan.kowalski@example.com'
DOBRY=$(wp eval "echo (string) ( MP\\Intake\\Validator::validate_email( '$NORMALNY' ) ?? 'OK' );" 2>/dev/null | tr -d '[:space:]')
[ "$DOBRY" = "OK" ] \
	&& ok "normalny adres dalej przechodzi (naprawa nikomu nic nie odebrala)" \
	|| bad "normalny adres zostal odrzucony ($DOBRY)"

ZLY=$(wp eval "echo (string) ( MP\\Intake\\Validator::validate_email( 'to-nie-jest-adres' ) ?? 'BRAK' );" 2>/dev/null | tr -d '[:space:]')
[ "$ZLY" = "INVALID_EMAIL" ] \
	&& ok "adres bez ksztaltu dalej dostaje INVALID_EMAIL (nie TOO_LONG)" \
	|| bad "zly ksztalt dostal inny kod niz dotad ($ZLY)"

# Adres TUZ POD limitem: czesc lokalna 60 znakow (limit RFC to 64), reszta w domenie
# — inaczej odrzucilby go sam ksztalt, a nie regula dlugosci.
GRANICA=$(wp eval '
	$adres = str_repeat( "a", 60 ) . "@" . str_repeat( "b", 60 ) . "." . str_repeat( "c", 60 ) . ".pl";
	echo strlen( $adres ) . ":" . ( MP\Intake\Validator::validate_email( $adres ) ?? "OK" );
' 2>/dev/null | tr -d '[:space:]')
DLUG_G=${GRANICA%%:*}
WYNIK_G=${GRANICA##*:}
{ [ "${DLUG_G:-0}" -le 190 ] && [ "${DLUG_G:-0}" -ge 150 ] && [ "$WYNIK_G" = "OK" ]; } \
	&& ok "adres tuz pod limitem ($DLUG_G znakow) przechodzi — limit nie jest zbyt ciasny" \
	|| bad "adres miesczacy sie w kolumnie zostal odrzucony ($GRANICA)"

echo ""
echo "WYNIK 2.4b: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
