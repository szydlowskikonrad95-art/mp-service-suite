#!/usr/bin/env bash
# ZYWY DOWOD (2.41, czwarte i ostatnie miejsce): poprawka samego stylu albo skryptu
# w module ZGLOSZEN dociera do przegladarek.
#
# Co bylo zle: formularz zgloszenia podpinal swoj arkusz i skrypt SAMA wersja
# wtyczki. Poprawka dotykajaca wylacznie pliku CSS/JS, wydana bez podniesienia
# numeru wersji, nie zmieniala parametru `ver` — przegladarka z plikiem w pamieci
# podrecznej dalej pokazywala stary wyglad, a nikt sie o tym nie dowiadywal.
# Trzy miejsca (rejestr, panel automatu, ekran importu) byly juz naprawione klasa
# `Assets::ver`; to jest czwarte.
#
# Exit 0 = OK. Test nic nie zapisuje.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# ── 1. SEDNO: znacznik wersji pliku ODBIJA plik, nie tylko wersje wtyczki ───
ZNACZNIK=$(wp eval '
	$css   = "assets/css/intake.css";
	$plik  = plugin_dir_path( MP_INTAKE_FILE ) . $css;
	$ver   = MP\Intake\Assets::ver( $css );
	$mtime = file_exists( $plik ) ? (int) filemtime( $plik ) : 0;
	echo wp_json_encode( array(
		"ver"          => $ver,
		"wersja_sama"  => MP_INTAKE_VERSION,
		"niesie_plik"  => $mtime > 0 && $ver === MP_INTAKE_VERSION . "." . $mtime,
		"rozny"        => $ver !== MP_INTAKE_VERSION,
	) );
' 2>/dev/null)
echo "$ZNACZNIK" | grep -q '"niesie_plik":true' \
	&& ok "SEDNO: znacznik wersji = wersja wtyczki + znacznik czasu PLIKU" \
	|| bad "znacznik wersji nie odbija pliku ($ZNACZNIK)"
echo "$ZNACZNIK" | grep -q '"rozny":true' \
	&& ok "znacznik rozni sie od samej wersji wtyczki (poprawka pliku zmienia adres)" \
	|| bad "znacznik dalej jest sama wersja wtyczki ($ZNACZNIK)"

# ── 2. SEDNO: formularz zgloszenia podpina pliki TYM znacznikiem ────────────
# Uruchamiamy prawdziwe podpinanie i pytamy WordPressa, z jakim `ver` zarejestrowal
# arkusz i skrypt — mierzymy zachowanie, nie obecnosc tekstu w pliku.
PODPIETE=$(wp eval '
	$r = new ReflectionMethod( "MP\Intake\Front\FormRenderer", "enqueue_assets" );
	$r->setAccessible( true );
	$r->invoke( null );

	$style  = wp_styles()->registered["mp-intake"] ?? null;
	$script = wp_scripts()->registered["mp-intake-form"] ?? null;
	echo wp_json_encode( array(
		"styl_ver"     => $style ? (string) $style->ver : "",
		"skrypt_ver"   => $script ? (string) $script->ver : "",
		"styl_ok"      => $style && (string) $style->ver === MP\Intake\Assets::ver( "assets/css/intake.css" ),
		"skrypt_ok"    => $script && (string) $script->ver === MP\Intake\Assets::ver( "assets/js/intake-form.js" ),
		"styl_niesamo" => $style && (string) $style->ver !== MP_INTAKE_VERSION,
	) );
' 2>/dev/null)
echo "$PODPIETE" | grep -q '"styl_ok":true' \
	&& ok "SEDNO: arkusz formularza podpiety ze znacznikiem odbijajacym plik" \
	|| bad "arkusz formularza dalej idzie sama wersja wtyczki ($PODPIETE)"
echo "$PODPIETE" | grep -q '"skrypt_ok":true' \
	&& ok "SEDNO: skrypt formularza podpiety ze znacznikiem odbijajacym plik" \
	|| bad "skrypt formularza dalej idzie sama wersja wtyczki ($PODPIETE)"

# ── 3. Poprawka SAMEGO pliku zmienia adres (sedno pozycji, mierzone wprost) ─
ZMIANA=$(wp eval '
	$css  = "assets/css/intake.css";
	$plik = plugin_dir_path( MP_INTAKE_FILE ) . $css;
	$przed = MP\Intake\Assets::ver( $css );
	$stary_mtime = (int) filemtime( $plik );
	touch( $plik, $stary_mtime + 120 );
	clearstatcache( true, $plik );
	$po = MP\Intake\Assets::ver( $css );
	touch( $plik, $stary_mtime );          // stan pliku wraca dokladnie taki, jaki byl
	clearstatcache( true, $plik );
	echo wp_json_encode( array( "zmienil_sie" => $przed !== $po, "wrocil" => MP\Intake\Assets::ver( $css ) === $przed ) );
' 2>/dev/null)
echo "$ZMIANA" | grep -q '"zmienil_sie":true' \
	&& ok "SEDNO: zmiana samego pliku (bez podbicia wersji wtyczki) ZMIENIA adres — przegladarka pobierze nowy" \
	|| bad "zmiana pliku nie zmienia adresu — poprawka nie dotrze do przegladarek ($ZMIANA)"
echo "$ZMIANA" | grep -q '"wrocil":true' \
	&& ok "test przywrocil znacznik czasu pliku (nic po sobie nie zostawia)" \
	|| bad "znacznik czasu pliku zostal zmieniony ($ZMIANA)"

# ── 4. PRZYPADEK BEZ WADY: brak pliku nie wywraca ekranu ───────────────────
BRAK=$(wp eval 'echo MP\Intake\Assets::ver( "assets/css/nie-ma-takiego-pliku.css" ) === MP_INTAKE_VERSION ? "WERSJA" : "INNE";' 2>/dev/null | tr -d '[:space:]')
[ "$BRAK" = "WERSJA" ] \
	&& ok "brak pliku => sama wersja wtyczki (znacznik poprawia odswiezanie, nie wywraca ekranu)" \
	|| bad "brak pliku daje dziwny znacznik ($BRAK)"

echo ""
echo "WYNIK 2.41-intake: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
