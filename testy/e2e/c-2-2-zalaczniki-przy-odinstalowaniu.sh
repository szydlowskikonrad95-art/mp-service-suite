#!/usr/bin/env bash
# ZYWY DOWOD 2.2: przypadkowe odinstalowanie nie zabiera DOWODOW ze spraw.
#
# BUG (audyt 2.2, waga duza): pliki zalacznikow byly kasowane z dysku BEZWARUNKOWO,
# a wiersze w bazie dopiero za jawna zgoda admina — ktora jest DOMYSLNIE WYLACZONA.
# Deklarowany cel tej asymetrii: „zeby przypadkowe odinstalowanie nie skasowalo
# danych biznesowych". W sprawie reklamacyjnej ZALACZNIK JEST DOWODEM (zdjecie
# uszkodzenia, skan dokumentu zakupu), wiec po odinstalowaniu zostawaly sprawy
# BEZ DOWODOW: wiersze wskazujace na pliki, ktorych juz nie ma.
# ⛔ Kasowanie plikow jest NIEODWRACALNE, zostawienie tabel — odwracalne. Produkt
# zachowywal to, co dalo sie odtworzyc, i usuwal to, czego odtworzyc sie nie da.
#
# FIX: zalaczniki ida za TEN SAM przelacznik co reszta danych sprawy.
#
# ⚠️ Test NAPRAWDE odinstalowuje modul (wzorzec z d-dod.sh: --skip-delete +
# ponowna aktywacja) i sprawdza na koncu, ze srodowisko wrocilo — inaczej zepsulby
# testy idace po nim na tej samej bazie.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ⚠️ Istnienie pliku sprawdzamy PRZEZ PHP, nie powloka: wtyczka pisze tam, gdzie
# widzi ja WordPress, a to nie musi byc ta sama sciezka, ktora widzi powloka
# uruchamiajaca test (na stanowisku w kontenerze rozjezdza sie to w calosci).
dowod_istnieje() {
	wp eval '
		$u = wp_upload_dir();
		echo is_file( rtrim( (string) $u["basedir"], "/" ) . "/mp-attachments/dowod-uszkodzenia.jpg" ) ? "tak" : "nie";' 2>/dev/null | tr -d '[:space:]'
}

# ⚠️ Plik zakladamy PRZEZ PHP, nie powloka. Zalozony z powloki nalezy do roota,
# a wtyczka chodzi jako uzytkownik serwera — nie mialaby prawa go skasowac i test
# meldowalby wade produktu tam, gdzie jest wada stanowiska. Tedy idzie tez produkt.
przygotuj_dowod() {
	wp eval '
		$u   = wp_upload_dir();
		$dir = rtrim( (string) $u["basedir"], "/" ) . "/mp-attachments";
		wp_mkdir_p( $dir );
		file_put_contents( $dir . "/dowod-uszkodzenia.jpg", "zdjecie uszkodzenia - dowod w sprawie" );' >/dev/null 2>&1
}

odinstaluj_i_wroc() {
	wp plugin uninstall mp-service-intake --deactivate --skip-delete >/dev/null 2>&1
	wp plugin activate mp-service-intake >/dev/null 2>&1
}

# ── 1. PRZELACZNIK WYLACZONY (stan domyslny) => DOWOD ZOSTAJE ───────────────
wp eval "delete_option('mp_intake_delete_data');" >/dev/null 2>&1
DOMYSLNY=$(wp eval "echo (string) get_option('mp_intake_delete_data', '0');" 2>/dev/null | tr -d '[:space:]')
[ "$DOMYSLNY" = "0" ] \
	&& ok "przelacznik kasowania danych jest domyslnie WYLACZONY (tak dziala przypadkowe odinstalowanie)" \
	|| bad "przelacznik domyslnie [$DOMYSLNY] — zalozenie testu nieaktualne"

przygotuj_dowod
[ "$(dowod_istnieje)" = "tak" ] && ok "zalacznik-dowod przygotowany na dysku" || bad "nie udalo sie przygotowac pliku"

odinstaluj_i_wroc

[ "$(dowod_istnieje)" = "tak" ] \
	&& ok "SEDNO: po odinstalowaniu BEZ zgody dowod ZOSTAJE na dysku" \
	|| bad "dowod skasowany mimo wylaczonego przelacznika — sprawy zostaja bez dowodow (to jest wada 2.2)"

# ── 2. Kontrola spojnosci: skoro dane zostaja, to i pliki — i odwrotnie ────
TABELA=$(q "SHOW TABLES LIKE 'wp_mp_service_cases'")
[ -n "$TABELA" ] \
	&& ok "tabele spraw tez zostaly (pliki i dane trzymaja sie razem)" \
	|| bad "tabele zniknely mimo wylaczonego przelacznika"

# ── 3. PRZELACZNIK WLACZONY => wszystko znika, tez pliki ──────────────────
przygotuj_dowod
wp eval "update_option('mp_intake_delete_data', '1');" >/dev/null 2>&1
odinstaluj_i_wroc

[ "$(dowod_istnieje)" = "nie" ] \
	&& ok "po odinstalowaniu ZA ZGODA dowod znika razem z danymi (spojnie, bez sierot)" \
	|| bad "przy jawnej zgodzie plik zostal — sprzatanie niepelne"

# ── 4. SRODOWISKO WROCILO (inaczej zepsulibysmy testy idace po nas) ───────
wp eval "delete_option('mp_intake_delete_data');" >/dev/null 2>&1
AKTYWNA=$(wp plugin list --name=mp-service-intake --field=status 2>/dev/null | tr -d '[:space:]')
[ "$AKTYWNA" = "active" ] \
	&& ok "modul zgloszen znowu aktywny" \
	|| bad "modul zostal wylaczony ([$AKTYWNA]) — nastepne testy padna bez zwiazku ze zmiana"

TABELE=$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name LIKE 'wp_mp_%'")
[ "${TABELE:-0}" -ge 5 ] 2>/dev/null \
	&& ok "tabele modulu odtworzone po ponownej aktywacji ($TABELE)" \
	|| bad "po ponownej aktywacji brakuje tabel ($TABELE)"

STRONA=$(wp option get mp_intake_form_page_id 2>/dev/null | tr -d '[:space:]')
[ -n "$STRONA" ] && [ "${STRONA:-0}" -gt 0 ] 2>/dev/null \
	&& ok "auto-strona formularza odtworzona (id=$STRONA)" \
	|| bad "brak auto-strony formularza po ponownej aktywacji"

echo ""
echo "WYNIK 2.2: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
