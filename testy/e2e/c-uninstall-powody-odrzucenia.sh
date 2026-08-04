#!/usr/bin/env bash
# ZYWY DOWOD: powody odrzucenia sprawy sa TRESCIA KLIENTA — gina za jawna zgoda
# admina, a BEZ zgody ZOSTAJA.
#
# BUG (znalezione 4.08 przy sweepie dokumentacji technicznej, spoza listy audytu):
# opcja `mp_intake_rejection_reasons` doszla razem z ekranem ustawien powodow
# odrzucenia, ale `uninstall.php` nie kasowal jej w ZADNEJ warstwie. Po
# odinstalowaniu ZA ZGODA zostawal w bazie wiersz, ktory po ponownej instalacji
# po cichu podmienial domyslny slownik (`RejectionReasons::defaults()`, 6 pozycji)
# na poprzednia liste — czyli „czysta instalacja" nie byla czysta.
#
# ⛔ TO JEST TA SAMA KLASA CO 2.56 I W TYM SAMYM PLIKU, naprawiona kilka godzin
# wczesniej tego samego dnia. Dlatego dowod idzie tym samym wzorcem co
# `c-2-56-konfiguracja-pol-formularza.sh`, a nie nowym pomyslem.
#
# ⭐ WAZNIEJSZY JEST TU PRZYPADEK KONTROLNY, NIE SEDNO. Naprawe da sie zrobic
# ZLE na jeden oczywisty sposob: wstawic kasowanie do warstwy (i), ktora chodzi
# ZAWSZE — takze przy odinstalowaniu przez pomylke. Wtedy serwis traci wlasna
# liste powodow („naprawa nieoplacalna", „sprzet po terminie akcji serwisowej")
# BEZ PYTANIA, a to wada CIEZSZA niz ta, ktora naprawiamy. Sekcja 2 pilnuje
# wlasnie tego i musi przechodzic TAK SAMO przed i po naprawie.
#
# ⚠️ Sprawdzamy ZACHOWANIE, nie brzmienie komentarza w uninstall.php — kontrola
# obecnosci zdania w pliku mierzylaby nasza wlasna sciagawke.
#
# ⚠️ Test NAPRAWDE odinstalowuje modul (wzorzec z c-2-2 i 2.56: --skip-delete
# + ponowna aktywacja) i na koncu sprawdza, ze srodowisko wrocilo. Dlatego jest
# wpisany do `testy/e2e/NA-KONIEC.txt`.
#
# ⚠️ Baze pytamy przez `wp eval` + $wpdb, nie przez `wp db query` — na instalacji
# z paczki (MySQL 8) `wp db query` wywala sie na TLS i kazde zapytanie wraca
# PUSTE, co wyglada dokladnie jak „zero wierszy" (wada przyrzadu z 4.08).
#
# KALIBRACJA: na kodzie sprzed naprawy pada WYLACZNIE sedno (sekcja 3),
# a sekcje 1, 2 i 4 przechodza identycznie.
#
# Chodzi na poligonie i w CI. Exit 0 = OK.
set -u

PASS=0; FAIL=0
KONTROLE_OCZEKIWANE=9
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

opcja_istnieje() {
	wp eval "echo ( false === get_option( MP\\Intake\\RejectionReasons::OPTION, false ) ) ? 'nie' : 'tak';" 2>/dev/null | tr -d '[:space:]'
}

# Ile powodow widzi ODBIORCA — pytamy przez KONTRAKT (`mp_rejection_reasons`),
# czyli tak, jak pyta karta sprawy i eksport CSV automatu. Pytanie o sama opcje
# sprawdzaloby nasza implementacje, a nie to, co dostaje odbiorca.
ile_powodow() {
	wp eval 'echo count( (array) apply_filters( "mp_rejection_reasons", array() ) );' 2>/dev/null | tr -d '[:space:]'
}

czy_ma_wlasny() {
	wp eval '
		$slownik = (array) apply_filters( "mp_rejection_reasons", array() );
		echo isset( $slownik["naprawa_nieoplacalna"] ) ? "tak" : "nie";' 2>/dev/null | tr -d '[:space:]'
}

# Lista klienta ustawiana TA SAMA droga co z ekranu ustawien — zapisem opcji
# po sanityzacji produktu (handler admin-post robi dokladnie to samo).
ustaw_wlasne_powody() {
	wp eval '
		$wlasne = MP\Intake\RejectionReasons::sanitize( array(
			"naprawa_nieoplacalna" => "Naprawa nieoplacalna",
			"po_terminie_akcji"    => "Sprzet po terminie akcji serwisowej",
		) );
		update_option( MP\Intake\RejectionReasons::OPTION, $wlasne, false );' >/dev/null 2>&1
}

odinstaluj_i_wroc() {
	wp plugin uninstall mp-service-intake --deactivate --skip-delete >/dev/null 2>&1
	wp plugin activate mp-service-intake >/dev/null 2>&1
}

# ── 1. Stan wyjsciowy: slownik domyslny JEST NIEPUSTY, wlasny go nadpisuje ──
# Gdyby domyslny byl pusty, cala reszta testu nie mialaby sensu: „brak opcji"
# i „brak powodow" znaczylyby to samo, a odrzucenie sprawy byloby niemozliwe
# na czystej instalacji.
wp eval "delete_option( MP\\Intake\\RejectionReasons::OPTION );" >/dev/null 2>&1
DOMYSLNYCH=$(ile_powodow)

[ "${DOMYSLNYCH:-0}" -ge 1 ] 2>/dev/null \
	&& ok "stan wyjsciowy: bez opcji kontrakt oddaje slownik domyslny ($DOMYSLNYCH powodow)" \
	|| bad "bez opcji kontrakt oddaje PUSTO (=[$DOMYSLNYCH]) — test nic nie dowiedzie"

ustaw_wlasne_powody

[ "$(czy_ma_wlasny)" = "tak" ] \
	&& ok "lista klienta DZIALA: kontrakt oddaje wlasne powody serwisu" \
	|| bad "zapis wlasnych powodow bez skutku — kontrakt ich nie widzi"

# ── 2. PRZYPADEK KONTROLNY (wazniejszy od sedna): BEZ zgody opcja ZOSTAJE ──
# OWNERSHIP.md: warstwa TRESCI ginie WYLACZNIE za jawna zgoda admina. Ta sekcja
# lapie naprawe zrobiona w zlym miejscu (warstwa „zawsze") i musi przechodzic
# tak samo przed i po naprawie.
wp eval "delete_option('mp_intake_delete_data');" >/dev/null 2>&1
ustaw_wlasne_powody
odinstaluj_i_wroc

[ "$(opcja_istnieje)" = "tak" ] \
	&& ok "KONTROLNY: po odinstalowaniu BEZ zgody opcja powodow ZOSTAJE" \
	|| bad "opcja powodow skasowana mimo WYLACZONEGO przelacznika — naprawa siedzi w zlej warstwie"

[ "$(czy_ma_wlasny)" = "tak" ] \
	&& ok "KONTROLNY: wlasne powody serwisu przezyly odinstalowanie bez zgody" \
	|| bad "serwis stracil wlasne powody bez pytania — wada ciezsza niz naprawiana"

# ── 3. SEDNO: ZA ZGODA opcja znika, a slownik wraca do domyslnego ──────────
ustaw_wlasne_powody
wp eval "update_option('mp_intake_delete_data', '1');" >/dev/null 2>&1
odinstaluj_i_wroc

[ "$(opcja_istnieje)" = "nie" ] \
	&& ok "SEDNO: po odinstalowaniu ZA ZGODA opcja powodow skasowana" \
	|| bad "opcja powodow przezyla odinstalowanie za zgoda (to jest naprawiana wada)"

[ "$(czy_ma_wlasny)" = "nie" ] \
	&& ok "SEDNO: po ponownej instalacji nie ma juz starych powodow klienta" \
	|| bad "po ponownej instalacji wrocila stara lista — czysta instalacja nie jest czysta"

PO_REINSTALACJI=$(ile_powodow)
[ "${PO_REINSTALACJI:-0}" = "${DOMYSLNYCH:-0}" ] \
	&& ok "SEDNO: slownik wrocil do domyslnego ($PO_REINSTALACJI powodow, tyle co na starcie)" \
	|| bad "slownik po reinstalacji ma [$PO_REINSTALACJI] powodow zamiast [$DOMYSLNYCH]"

# ── 4. SRODOWISKO WROCILO ─────────────────────────────────────────────────
wp eval "delete_option('mp_intake_delete_data');" >/dev/null 2>&1
wp eval "delete_option( MP\\Intake\\RejectionReasons::OPTION );" >/dev/null 2>&1

AKTYWNA=$(wp plugin list --name=mp-service-intake --field=status 2>/dev/null | tr -d '[:space:]')
[ "$AKTYWNA" = "active" ] \
	&& ok "modul zgloszen znowu aktywny" \
	|| bad "modul zostal wylaczony ([$AKTYWNA]) — nastepne testy padna bez zwiazku ze zmiana"

TABELE=$(wp eval '
	global $wpdb;
	echo (int) $wpdb->get_var( "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name LIKE \"{$wpdb->prefix}mp\\_%\"" );' 2>/dev/null | tr -d '[:space:]')
[ "${TABELE:-0}" -ge 5 ] 2>/dev/null \
	&& ok "tabele modulu odtworzone po ponownej aktywacji ($TABELE)" \
	|| bad "po ponownej aktywacji brakuje tabel ([$TABELE])"

# ⛔ STRAZNIK KOMPLETU (lekcja z 4.08: „kontrola, ktora cicho nie startuje,
# swieci zielono"). Gdyby ktorykolwiek `wp eval` zwrocil smiec i kontrola nie
# wykonala sie ANI RAZ, suma bylaby mniejsza — a wynik wygladalby na zielony.
WYKONANE=$(( PASS + FAIL ))
if [ "$WYKONANE" -ne "$KONTROLE_OCZEKIWANE" ]; then
	echo ""
	echo "BLAD PRZEBIEGU: wykonano $WYKONANE kontroli zamiast $KONTROLE_OCZEKIWANE."
	echo "To wada przyrzadu, nie produktu — nie melduj zielonego."
	exit 2
fi

echo ""
echo "WYNIK powody-odrzucenia: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
