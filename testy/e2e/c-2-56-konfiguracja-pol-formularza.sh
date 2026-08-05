#!/usr/bin/env bash
# ZYWY DOWOD 2.56: nadpisanie konfiguracji pol formularza jest ZYWA furtka
# wdrozeniowca, a nie martwa galezia — i znika przy odinstalowaniu za zgoda.
#
# BUG (audyt 2.56, waga drobna): `FormConfig` zapowiadal w naglowku, ze „admin
# edytuje wymagalnosc bez zmiany kodu". Opcja `mp_intake_form_config` byla tylko
# CZYTANA (`fields_for`), a zapisu nie bylo NIGDZIE — ani ekranu, ani polecenia.
# Skutek: informatyk klienta szukal w panelu ekranu, ktorego nikt nie zbudowal.
# Dodatkowo `uninstall.php` tej opcji nie kasowal, choc naglowek zaliczal ja do
# warstwy TRESCI, a OWNERSHIP.md mowi, ze warstwa tresci ginie za zgoda admina.
#
# ⛔ UCZCIWIE: to NIE jest brak wobec zamowienia. Specyfikacja wymaga „wymaganych pol
# i zalacznikow zaleznych od kategorii produktu" — i to JEST zrobione
# (`category_fields`, `attachments_for`). Edytowania pol z panelu zamawiajacy nie
# zamawial, wiec ekranu NIE dokladamy. Zglaszamy rozbieznosc kodu z jego wlasnym
# opisem, wiec naprawa jest dwuczesciowa: prawdziwy opis + sprzatanie opcji.
#
# ⚠️ Test mierzy ZACHOWANIE, nie brzmienie komentarza. Sprawdzanie, czy w pliku
# stoi wlasciwe zdanie, mierzy nasza wlasna sciagawke — przeszloby nawet wtedy,
# gdyby produkt dzialal inaczej, niz komentarz mowi.
#
# ⚠️ Test NAPRAWDE odinstalowuje modul (wzorzec z c-2-2: --skip-delete + ponowna
# aktywacja) i na koncu sprawdza, ze srodowisko wrocilo.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

opcja_istnieje() {
	wp eval "echo ( false === get_option( MP\\Intake\\FormConfig::OPTION, false ) ) ? 'nie' : 'tak';" 2>/dev/null | tr -d '[:space:]'
}

# Nadpisanie ustawiamy TA SAMA droga co wdrozeniowiec — zapisem opcji. Produkt
# swojego zapisu nie ma i celowo go nie dokladamy (patrz naglowek).
ustaw_nadpisanie() {
	wp eval '
		$cfg = array(
			"reklamacja" => array(
				array( "key" => "issue_description", "label" => "Opis usterki", "type" => "textarea", "required" => false, "pii_sensitive" => false ),
			),
		);
		update_option( MP\Intake\FormConfig::OPTION, $cfg, false );' >/dev/null 2>&1
}

odinstaluj_i_wroc() {
	wp plugin uninstall mp-service-intake --deactivate --skip-delete >/dev/null 2>&1
	wp plugin activate mp-service-intake >/dev/null 2>&1
}

# ── 1. Galaz nadpisania ZYJE (inaczej nalezaloby ja usunac, a nie opisywac) ──
# Domyslnie opis usterki w reklamacji jest polem WYMAGANYM. Nadpisanie zdejmuje
# ten wymog. Gdyby galaz byla martwa, wynik nie zmienilby sie po zapisie opcji.
wp eval "delete_option( MP\\Intake\\FormConfig::OPTION );" >/dev/null 2>&1
WYMAGANE_DOMYSLNIE=$(wp eval '
	foreach ( MP\Intake\FormConfig::fields_for( "reklamacja" ) as $f ) {
		if ( "issue_description" === $f["key"] ) { echo $f["required"] ? "tak" : "nie"; }
	}' 2>/dev/null | tr -d '[:space:]')

[ "$WYMAGANE_DOMYSLNIE" = "tak" ] \
	&& ok "stan wyjsciowy: bez nadpisania opis usterki jest wymagany" \
	|| bad "stan wyjsciowy inny niz zakladamy (wymagane=[$WYMAGANE_DOMYSLNIE]) — test nic nie dowiedzie"

ustaw_nadpisanie
WYMAGANE_PO=$(wp eval '
	foreach ( MP\Intake\FormConfig::fields_for( "reklamacja" ) as $f ) {
		if ( "issue_description" === $f["key"] ) { echo $f["required"] ? "tak" : "nie"; }
	}' 2>/dev/null | tr -d '[:space:]')

[ "$WYMAGANE_PO" = "nie" ] \
	&& ok "nadpisanie DZIALA: zapis opcji zdjal wymog z pola (furtka wdrozeniowca zywa)" \
	|| bad "nadpisanie bez skutku (wymagane=[$WYMAGANE_PO]) — galaz w fields_for jest martwa"

# ── 2. Odinstalowanie BEZ zgody NIE rusza konfiguracji ─────────────────────
# OWNERSHIP.md: warstwa TRESCI ginie wylacznie za jawna zgoda admina.
wp eval "delete_option('mp_intake_delete_data');" >/dev/null 2>&1
ustaw_nadpisanie
odinstaluj_i_wroc

[ "$(opcja_istnieje)" = "tak" ] \
	&& ok "po odinstalowaniu BEZ zgody konfiguracja pol zostaje (warstwa tresci)" \
	|| bad "konfiguracja pol skasowana mimo wylaczonego przelacznika"

# ── 3. SEDNO: odinstalowanie ZA ZGODA sprzata konfiguracje ────────────────
# Bez tego po ponownej instalacji zostawal w bazie wiersz, ktory po cichu
# nadpisywalby domyslne pola formularza — i nikt by nie wiedzial dlaczego.
ustaw_nadpisanie
wp eval "update_option('mp_intake_delete_data', '1');" >/dev/null 2>&1
odinstaluj_i_wroc

[ "$(opcja_istnieje)" = "nie" ] \
	&& ok "SEDNO: po odinstalowaniu ZA ZGODA konfiguracja pol skasowana" \
	|| bad "konfiguracja pol przezyla odinstalowanie za zgoda (to jest wada 2.56)"

# ── 4. SRODOWISKO WROCILO ────────────────────────────────────────────────
wp eval "delete_option('mp_intake_delete_data');" >/dev/null 2>&1
wp eval "delete_option( MP\\Intake\\FormConfig::OPTION );" >/dev/null 2>&1

AKTYWNA=$(wp plugin list --name=mp-service-intake --field=status 2>/dev/null | tr -d '[:space:]')
[ "$AKTYWNA" = "active" ] \
	&& ok "modul zgloszen znowu aktywny" \
	|| bad "modul zostal wylaczony ([$AKTYWNA]) — nastepne testy padna bez zwiazku ze zmiana"

TABELE=$(wp db query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name LIKE 'wp_mp_%'" --skip-column-names 2>/dev/null | tr -d '[:space:]')
[ "${TABELE:-0}" -ge 5 ] 2>/dev/null \
	&& ok "tabele modulu odtworzone po ponownej aktywacji ($TABELE)" \
	|| bad "po ponownej aktywacji brakuje tabel ($TABELE)"

WYMAGANE_KONIEC=$(wp eval '
	foreach ( MP\Intake\FormConfig::fields_for( "reklamacja" ) as $f ) {
		if ( "issue_description" === $f["key"] ) { echo $f["required"] ? "tak" : "nie"; }
	}' 2>/dev/null | tr -d '[:space:]')
[ "$WYMAGANE_KONIEC" = "tak" ] \
	&& ok "formularz wrocil do domyslnej mapy pol" \
	|| bad "formularz zostal z nadpisaniem (wymagane=[$WYMAGANE_KONIEC])"

echo ""
echo "WYNIK 2.56: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
