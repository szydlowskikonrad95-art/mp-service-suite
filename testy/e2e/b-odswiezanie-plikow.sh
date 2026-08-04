#!/usr/bin/env bash
# ZYWY DOWOD (2.41): poprawka samego stylu albo skryptu DOCIERA do przegladarek.
#
# Rejestr podpinal swoje pliki przegladarkowe SAMA wersja wtyczki, a automator obok
# robi to poprawnie: `wersja . '.' . filemtime` (PanelScreen::asset_ver). Skutek starego
# ukladu: poprawka dotykajaca WYLACZNIE stylu albo skryptu, wydana bez podniesienia
# numeru wersji, nie dociera do przegladarki z plikiem w pamieci podrecznej —
# uzytkownik widzi stara wersje i nikt sie o tym nie dowiaduje.
#
# Ten test pilnuje, ze:
#   1. znacznik wersji pliku NIE jest golym numerem wersji wtyczki,
#   2. zmiana samego pliku ZMIENIA znacznik (to jest cala istota naprawy),
#   3. dotyczy to WSZYSTKICH plikow przegladarkowych rejestru, nie jednego,
#   4. brak pliku nie wywraca ekranu — zostaje sama wersja wtyczki.
#
# Numeru wersji NIE wpisujemy — bierzemy ze stalej MP_REGISTRY_VERSION.
# Wymaga zywego `wp`. Exit 0 = OK. Test przywraca czasy plikow, ktore rusza.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

WERSJA=$(wp eval 'echo MP_REGISTRY_VERSION;' 2>/dev/null | tr -d '[:space:]')
KATALOG=$(wp eval 'echo plugin_dir_path( MP_REGISTRY_FILE );' 2>/dev/null | tr -d '[:space:]')

if [ -z "$WERSJA" ] || [ -z "$KATALOG" ]; then
	bad "nie udalo sie odczytac wersji/katalogu wtyczki (WERSJA='$WERSJA' KATALOG='$KATALOG')"
	echo "WYNIK: $PASS ok, $FAIL fail"
	exit 1
fi

# Znacznik `ver`, ktory NAPRAWDE trafia na podpiety plik — mierzymy rejestr WordPressa
# po wywolaniu enqueue, a nie tresc pliku PHP. Hook ekranu bierzemy z samej klasy.
znacznik() {
	wp eval "
		wp_set_current_user( 1 );
		\$r = new ReflectionClass( '$1' );
		\$p = \$r->getProperty( 'hook_suffix' );
		\$p->setAccessible( true );
		$1::add_menu();
		\$hook = (string) \$p->getValue();
		$1::enqueue( \$hook );
		\$kolekcja = '$3' === 'js' ? wp_scripts() : wp_styles();
		echo isset( \$kolekcja->registered['$2'] ) ? (string) \$kolekcja->registered['$2']->ver : 'BRAK-UCHWYTU';
	" 2>/dev/null | tr -d '[:space:]'
}

echo "== 1. ZNACZNIK NIE JEST GOLYM NUMEREM WERSJI WTYCZKI =="
Z_CSS=$(znacznik 'MP\Registry\Admin\ProductsScreen' 'mp-registry-admin' 'css')
[ "$Z_CSS" != "BRAK-UCHWYTU" ] && [ -n "$Z_CSS" ] \
	&& ok "styl rejestru podpiety, znacznik: $Z_CSS" \
	|| bad "nie udalo sie odczytac znacznika stylu rejestru ($Z_CSS)"
[ "$Z_CSS" != "$WERSJA" ] \
	&& ok "znacznik stylu rejestru to NIE goly numer wersji ($Z_CSS != $WERSJA)" \
	|| bad "znacznik = goly numer wersji ($Z_CSS) — poprawka samego stylu nie dotrze do przegladarki"

echo "== 2. ZMIANA SAMEGO PLIKU ZMIENIA ZNACZNIK =="
# Sedno pozycji: bez podnoszenia wersji wtyczki, sama zmiana pliku ma wymusic
# swieze pobranie. Czas pliku przywracamy na koniec (wspolne stanowisko).
PLIK="$KATALOG/assets/css/admin-registry.css"
if [ ! -f "$PLIK" ]; then
	bad "nie ma pliku stylu do proby ($PLIK)"
else
	CZAS_STARY=$(date -r "$PLIK" +%s 2>/dev/null)
	touch -d '@1900000000' "$PLIK" 2>/dev/null || touch -t 210201010101 "$PLIK" 2>/dev/null
	Z_PO=$(znacznik 'MP\Registry\Admin\ProductsScreen' 'mp-registry-admin' 'css')
	[ -n "$CZAS_STARY" ] && touch -d "@$CZAS_STARY" "$PLIK" 2>/dev/null
	[ "$Z_PO" != "$Z_CSS" ] \
		&& ok "po zmianie pliku znacznik jest inny ($Z_CSS -> $Z_PO)" \
		|| bad "znacznik nie zareagowal na zmiane pliku (dalej $Z_PO)"
	Z_WROC=$(znacznik 'MP\Registry\Admin\ProductsScreen' 'mp-registry-admin' 'css')
	[ "$Z_WROC" = "$Z_CSS" ] && ok "czas pliku przywrocony (stanowisko bez sladu)" || bad "nie udalo sie przywrocic czasu pliku ($Z_WROC)"
fi

echo "== 3. TO SAMO NA WSZYSTKICH PLIKACH REJESTRU, NIE NA JEDNYM =="
# Naprawa wzorca, nie egzemplarza: ekran importu ma OSOBNY styl i OSOBNY skrypt.
Z_IMP_CSS=$(znacznik 'MP\Registry\Admin\ImportScreen' 'mp-import-admin' 'css')
Z_IMP_JS=$(znacznik 'MP\Registry\Admin\ImportScreen' 'mp-import-admin' 'js')
[ "$Z_IMP_CSS" != "$WERSJA" ] && [ "$Z_IMP_CSS" != "BRAK-UCHWYTU" ] \
	&& ok "styl importu ze znacznikiem pliku ($Z_IMP_CSS)" || bad "styl importu z golym numerem wersji ($Z_IMP_CSS)"
[ "$Z_IMP_JS" != "$WERSJA" ] && [ "$Z_IMP_JS" != "BRAK-UCHWYTU" ] \
	&& ok "skrypt importu ze znacznikiem pliku ($Z_IMP_JS)" || bad "skrypt importu z golym numerem wersji ($Z_IMP_JS)"
# ⚠️ NIE porownujemy znacznikow stylu i skryptu miedzy soba: swiezy `git clone` nadaje
# wszystkim plikom niemal ten sam czas, wiec taka proba bylaby chwiejna w CI. Mierzymy
# wlasciwosc, o ktora naprawde chodzi: ruszenie JEDNEGO pliku rusza WYLACZNIE jego znacznik.
PLIK_JS="$KATALOG/assets/js/admin-import.js"
if [ ! -f "$PLIK_JS" ]; then
	bad "nie ma pliku skryptu do proby ($PLIK_JS)"
else
	CZAS_JS=$(date -r "$PLIK_JS" +%s 2>/dev/null)
	touch -d '@1900000001' "$PLIK_JS" 2>/dev/null || touch -t 210201010102 "$PLIK_JS" 2>/dev/null
	Z_JS2=$(znacznik 'MP\Registry\Admin\ImportScreen' 'mp-import-admin' 'js')
	Z_CSS2=$(znacznik 'MP\Registry\Admin\ImportScreen' 'mp-import-admin' 'css')
	[ -n "$CZAS_JS" ] && touch -d "@$CZAS_JS" "$PLIK_JS" 2>/dev/null
	[ "$Z_JS2" != "$Z_IMP_JS" ] && [ "$Z_CSS2" = "$Z_IMP_CSS" ] \
		&& ok "ruszenie skryptu zmienilo znacznik SKRYPTU i nie ruszylo stylu" \
		|| bad "znaczniki nie sa niezalezne (js: $Z_IMP_JS -> $Z_JS2, css: $Z_IMP_CSS -> $Z_CSS2)"
	Z_JS3=$(znacznik 'MP\Registry\Admin\ImportScreen' 'mp-import-admin' 'js')
	[ "$Z_JS3" = "$Z_IMP_JS" ] && ok "czas skryptu przywrocony" || bad "nie udalo sie przywrocic czasu skryptu ($Z_JS3)"
fi

echo "== 4. BRAK PLIKU NIE WYWRACA EKRANU =="
BRAK=$(wp eval "echo MP\\Registry\\Assets::ver( 'assets/css/nie-ma-takiego-pliku.css' );" 2>/dev/null | tr -d '[:space:]')
[ "$BRAK" = "$WERSJA" ] && ok "brak pliku => sama wersja wtyczki ($BRAK)" || bad "brak pliku dal '$BRAK' zamiast '$WERSJA'"

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
