#!/usr/bin/env bash
# ZYWY DOWOD (cz. 1 pkt 5): status „odrzucone" da sie NIE TYLKO WYBRAC, ale i ZAPISAC.
#
# Co bylo zle: karta sprawy pokazuje pole powodu odrzucenia wylacznie wtedy, gdy
# lista powodow nie jest pusta, a lista pochodzi z zaczepu `mp_rejection_reasons`,
# ktorego NIKT W PRODUKCIE NIE REJESTROWAL — byly tylko dwa odczyty (karta sprawy
# i eksport CSV). Bez powodu `CaseRepo::change_status` odbija zapis bledem
# REJECTION_REASON_REQUIRED. Pracownik wybieral wiec status z listy siedmiu
# wymaganych przez specyfikacje klienta, klikal „Zmien status" i dostawal odmowe,
# ktorej nie mial jak spelnic. Slepy zaulek.
#
# Test sprawdza obie strony: (a) ze slepy zaulek zniknal, (b) ze naprawa NIE
# odebrala nikomu dzialajacej funkcji — zapis bez powodu ma dalej byc odrzucany,
# a wlasna lista powodow ma wygrywac z domyslna.
#
# Wymaga zywego `wp`. Exit 0 = OK. Test sprzata po sobie (opcja + sprawy).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

sprzataj() {
	wp eval 'delete_option( "mp_intake_rejection_reasons" );' >/dev/null 2>&1
	wp db query "DELETE FROM wp_mp_service_cases WHERE case_number LIKE 'SRV%' AND id IN (SELECT case_id FROM wp_mp_consents WHERE email='cz15-odrzut@example.com')" >/dev/null 2>&1
	wp db query "DELETE FROM wp_mp_consents WHERE email='cz15-odrzut@example.com'" >/dev/null 2>&1
	wp db query "DELETE FROM wp_mp_customers WHERE email='cz15-odrzut@example.com'" >/dev/null 2>&1
}
sprzataj

# ── 1. SEDNO: kontrakt `mp_rejection_reasons` MA dostawce ───────────────────
ILE=$(wp eval '$r = apply_filters( "mp_rejection_reasons", array() ); echo is_array( $r ) ? count( $r ) : -1;' 2>/dev/null | tr -d '[:space:]')
[ "${ILE:-0}" -ge 1 ] \
	&& ok "SEDNO: slownik powodow odrzucenia ma dostawce (powodow: $ILE)" \
	|| bad "zaczep mp_rejection_reasons dalej nie ma dostawcy (zwrocil: $ILE) — status „odrzucone\" zostaje niezapisywalny"

# ── 2. SEDNO: karta sprawy POKAZUJE pole wyboru powodu ──────────────────────
# Zakladamy sprawe, potwierdzamy ja i renderujemy karte tak, jak widzi ja pracownik.
OUT=$(wp mp case-create --kind=reklamacja --email=cz15-odrzut@example.com --name='Klient Testowy' \
	--serial=CZ15-1 --document='FV/CZ15/1' --date='2026-03-01' --desc='sprawa do odrzucenia' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2 | tr -d '[:space:]')
TOK=$(echo "$OUT" | grep '^token=' | cut -d= -f2 | tr -d '[:space:]')
wp eval "MP\\Intake\\CaseRepo::verify( '$TOK' );" >/dev/null 2>&1

if [ "${CID:-0}" -gt 0 ]; then
	ok "sprawa testowa zalozona (#$CID) i potwierdzona"
else
	bad "nie udalo sie zalozyc sprawy testowej (CID=$CID) — dalsze kontrole nie maja sensu"
fi

KARTA=$(wp eval "
	wp_set_current_user( 1 );
	\$u = wp_get_current_user();
	\$u->add_cap( 'mp_coordinator' );
	\$u->add_cap( 'mp_system_admin' );
	ob_start();
	MP\\Intake\\Admin\\CaseCard::render( $CID, 'mp-intake-cases' );
	\$html = (string) ob_get_clean();
	\$u->remove_cap( 'mp_coordinator' );
	\$u->remove_cap( 'mp_system_admin' );
	echo wp_json_encode( array(
		'ma_pole'   => false !== strpos( \$html, 'name=\"rejection_reason_code\"' ),
		'ma_opcje'  => false !== strpos( \$html, 'brak_dowodu' ),
		'ma_status' => false !== strpos( \$html, 'odrzucone' ),
	) );
" 2>/dev/null)

echo "$KARTA" | grep -q '"ma_status":true' \
	&& ok "karta sprawy oferuje status „odrzucone\" na liscie" \
	|| bad "statusu „odrzucone\" nie ma nawet na liscie ($KARTA)"
echo "$KARTA" | grep -q '"ma_pole":true' \
	&& ok "SEDNO: karta sprawy POKAZUJE pole wyboru powodu odrzucenia" \
	|| bad "karta sprawy dalej nie pokazuje pola powodu — pracownik nie ma jak spelnic wymogu ($KARTA)"
echo "$KARTA" | grep -q '"ma_opcje":true' \
	&& ok "pole ma z czego wybierac (widoczny powod ze slownika)" \
	|| bad "pole powodu jest puste ($KARTA)"

# ── 3. PELNA SCIEZKA: odrzucenie z powodem PRZECHODZI i zapisuje kod ────────
ZAPIS=$(wp eval "
	wp_set_current_user( 1 );
	\$u = wp_get_current_user();
	\$u->add_cap( 'mp_coordinator' );
	\$powody = apply_filters( 'mp_rejection_reasons', array() );
	\$kod    = is_array( \$powody ) && array() !== \$powody ? (string) array_key_first( \$powody ) : '';
	\$biezacy = (string) \$GLOBALS['wpdb']->get_var( 'SELECT status FROM wp_mp_service_cases WHERE id = $CID' );
	\$r = MP\\Intake\\CaseRepo::change_status( $CID, 'odrzucone', \$biezacy, 1, \$kod );
	\$u->remove_cap( 'mp_coordinator' );
	echo wp_json_encode( array( 'kod' => \$kod, 'ok' => ! empty( \$r['success'] ), 'blad' => \$r['error_code'] ?? '' ) );
" 2>/dev/null)

echo "$ZAPIS" | grep -q '"ok":true' \
	&& ok "SEDNO: odrzucenie z powodem ze slownika PRZECHODZI (koniec slepego zaulka)" \
	|| bad "odrzucenie z powodem dalej nie przechodzi ($ZAPIS)"
STATUS_DB=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
KOD_DB=$(q "SELECT rejection_reason_code FROM wp_mp_service_cases WHERE id=$CID")
{ [ "$STATUS_DB" = "odrzucone" ] && [ -n "$KOD_DB" ]; } \
	&& ok "w bazie: status=odrzucone, powod zapisany ($KOD_DB)" \
	|| bad "baza nie potwierdza odrzucenia (status=$STATUS_DB powod=$KOD_DB)"

# ── 4. PRZYPADEK BEZ WADY: naprawa nie odbiera niczego, co dzialalo ─────────
# (a) zapis BEZ powodu ma dalej byc odrzucany — to jest wymog, nie usterka.
BEZ=$(wp eval "
	wp_set_current_user( 1 );
	\$u = wp_get_current_user(); \$u->add_cap( 'mp_coordinator' );
	\$r = MP\\Intake\\CaseRepo::change_status( $CID, 'odrzucone', 'odrzucone', 1, '' );
	\$u->remove_cap( 'mp_coordinator' );
	echo (string) ( \$r['error_code'] ?? 'BRAK' );
" 2>/dev/null | tr -d '[:space:]')
[ "$BEZ" = "REJECTION_REASON_REQUIRED" ] \
	&& ok "zapis BEZ powodu dalej odbija sie o wymog (naprawa niczego nie rozluznila)" \
	|| bad "zapis bez powodu przeszedl albo padl inaczej ($BEZ)"

# (b) WLASNA lista administratora wygrywa z domyslna.
WLASNE=$(wp eval '
	$slownik = MP\Intake\RejectionReasons::parse( "wlasny_powod|Powód z ustawień\nSam Tekst Bez Kodu" );
	update_option( "mp_intake_rejection_reasons", $slownik, false );
	$z_filtra = apply_filters( "mp_rejection_reasons", array() );
	echo wp_json_encode( array(
		"ma_wlasny"   => isset( $z_filtra["wlasny_powod"] ),
		"etykieta"    => $z_filtra["wlasny_powod"] ?? "",
		"kod_z_tekstu"=> isset( $z_filtra["sam_tekst_bez_kodu"] ),
		"bez_domyslnych" => ! isset( $z_filtra["brak_dowodu"] ),
	) );
' 2>/dev/null)
echo "$WLASNE" | grep -q '"ma_wlasny":true' \
	&& ok "wlasna lista z ekranu ustawien wygrywa z domyslna" \
	|| bad "zapisana lista nie dotarla do karty sprawy ($WLASNE)"
echo "$WLASNE" | grep -q '"kod_z_tekstu":true' \
	&& ok "linia bez kodu dostaje kod z tekstu (administrator nie wymysla kluczy)" \
	|| bad "linia bez kodu przepadla ($WLASNE)"
echo "$WLASNE" | grep -q '"bez_domyslnych":true' \
	&& ok "po zapisie wlasnej listy domyslne powody znikaja (lista jest JEDNA)" \
	|| bad "domyslne powody mieszaja sie z wlasnymi ($WLASNE)"

# (c) pusta lista NIE jest zapisywalna — inaczej slepy zaulek wracalby jednym klikiem.
PUSTA=$(wp eval '
	$slownik = MP\Intake\RejectionReasons::parse( "   \n\n  " );
	echo wp_json_encode( array( "puste_z_parse" => array() === $slownik, "po_awaryjnym_zapisie" => count( MP\Intake\RejectionReasons::all() ) ) );
' 2>/dev/null)
echo "$PUSTA" | grep -q '"puste_z_parse":true' \
	&& ok "same biale znaki nie tworza slownika (handler odmowi zapisu)" \
	|| bad "puste wejscie dalo niepusty slownik ($PUSTA)"

# (d) zepsuty wpis w bazie => karta sprawy dalej ma z czego wybrac (fail-safe).
AWARIA=$(wp eval '
	update_option( "mp_intake_rejection_reasons", "to nie jest tablica", false );
	echo count( apply_filters( "mp_rejection_reasons", array() ) );
' 2>/dev/null | tr -d '[:space:]')
[ "${AWARIA:-0}" -ge 1 ] \
	&& ok "zepsuta konfiguracja spada na slownik domyslny (slepy zaulek nie wraca)" \
	|| bad "zepsuta konfiguracja zostawia pusta liste ($AWARIA)"

# ── 5. Sprzatanie ───────────────────────────────────────────────────────────
sprzataj
ZOSTALO=$(wp eval 'echo null === get_option( "mp_intake_rejection_reasons", null ) ? "0" : "1";' 2>/dev/null | tr -d '[:space:]')
[ "$ZOSTALO" = "0" ] \
	&& ok "test posprzatal konfiguracje i sprawy testowe" \
	|| bad "opcja z powodami zostala w bazie"

echo ""
echo "WYNIK CZ1-5: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
