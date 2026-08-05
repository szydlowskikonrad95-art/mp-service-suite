#!/usr/bin/env bash
# ZYWY DOWOD (bloker wydania 1.3.13, defekt wniesiony naprawa Z1b w #283):
# link „pobierz CSV" DOROBIONY PRZEZ JS po zakonczeniu importu prowadzil do
# „Wybrany odnosnik jest nieaktualny", dopoki operator nie odswiezyl strony —
# a baner w tym samym momencie kazal kliknac wlasnie tam.
#
# PRZYCZYNA: `wp_nonce_url()` zwraca adres PO `esc_html()`, wiec z `&amp;`
# zamiast `&`. `WP_Scripts::localize()` odkreca encje TYLKO dla skalarow
# najwyzszego poziomu, a nasz adres siedzi w zagniezdzonej tablicy
# (`job.reportUrl`); zwrotka AJAX-owa idzie przez JSON, ktory encji nie tyka
# w ogole. W efekcie JS wstawia do `href` adres, w ktorym separatorem jest
# `&amp;` — przegladarka czyta parametry jako `amp;job` i `amp;_wpnonce`,
# wiec `job` i `_wpnonce` NIE DOCIERAJA i weryfikacja nonce pada.
#
# Kalibracja WBUDOWANA: A1/A2/A3 i B1/B2 PADAJA na kodzie sprzed naprawy.
# Sekcja C to kontrola kierunku: adres renderowany w HTML dziala tak samo jak
# przedtem (tam `esc_url()` na wyjsciu i tak wszystko prostowal).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

wp db query "DELETE FROM wp_mp_import_jobs" >/dev/null 2>&1

# Job z bledami — tylko taki dostaje link do raportu.
JOB=$(wp eval '
	global $wpdb; $t = $wpdb->prefix . "mp_import_jobs";
	$wpdb->insert( $t, array(
		"file_path" => "/tmp/z1b.csv", "status" => "processing", "total_rows" => 8,
		"processed_rows" => 4, "success_rows" => 2, "error_rows" => 2,
		"job_token" => "z1btok", "created_at" => current_time( "mysql", true ),
		// lock_key = ten sam znacznik, po ktorym ImportJobs::find_live() poznaje
		// job ZYWY; bez niego js_config() nie zwrocilby wcale sekcji "job"
		// i sekcja A mierzylaby pustke zamiast adresu.
		"lock_key" => MP\Registry\ImportJobs::LOCK_LIVE,
	) );
	echo (int) $wpdb->insert_id;' 2>/dev/null)
[ -n "$JOB" ] && [ "$JOB" -gt 0 ] 2>/dev/null && ok "0: zalozony import z bledami (id=$JOB)" || { bad "0: setup padl"; echo "── Z1b: PASS=$PASS FAIL=$FAIL ──"; exit 1; }

# ── A. ADRES TAK, JAK DOSTAJE GO JS z konfiguracji ekranu (job.reportUrl) ────
# Bierzemy DOKLADNIE te droge co produkt: js_config() -> wp_localize_script.
# `localize()` odkreca encje tylko dla skalarow najwyzszego poziomu, wiec
# odtwarzamy to wiernie, zeby test mierzyl to, co naprawde widzi przegladarka.
ADRES_JS=$(wp eval '
	wp_set_current_user( 1 );
	$m = new ReflectionMethod( "MP\\Registry\\Admin\\ImportScreen", "js_config" );
	$m->setAccessible( true );
	$cfg = $m->invoke( null );
	$w = $cfg["job"]["reportUrl"] ?? "";
	// Wierne odtworzenie WP_Scripts::localize(): dekodowanie TYLKO dla skalarow
	// najwyzszego poziomu — nasz adres siedzi w tablicy "job", wiec go pomija.
	foreach ( $cfg as $k => $v ) { if ( is_scalar( $v ) ) { $cfg[$k] = html_entity_decode( (string) $v, ENT_QUOTES, "UTF-8" ); } }
	echo $cfg["job"]["reportUrl"] ?? "BRAK";' 2>/dev/null)

echo "     adres z konfiguracji: $ADRES_JS"
case "$ADRES_JS" in
	*"amp;"*) bad "A1: adres dla JS niesie encje &amp; — przegladarka zgubi job i _wpnonce" ;;
	BRAK|"") bad "A1: brak adresu raportu w konfiguracji ekranu" ;;
	*)        ok  "A1: adres dla JS bez encji &amp;" ;;
esac

# Czy po rozbiorze zapytania (tak jak robi to serwer) sa WSZYSTKIE parametry?
WYNIK_A=$(wp eval "
	\$adres = '$ADRES_JS';
	\$q = (string) wp_parse_url( \$adres, PHP_URL_QUERY );
	parse_str( \$q, \$p );
	echo isset( \$p['job'] ) ? 'job=' . \$p['job'] : 'job=BRAK';
	echo '|';
	echo isset( \$p['_wpnonce'] ) ? 'nonce=' . \$p['_wpnonce'] : 'nonce=BRAK';" 2>/dev/null)
echo "     po rozbiorze: $WYNIK_A"
case "$WYNIK_A" in
	*"job=$JOB"*) ok "A2: parametr job dociera do serwera" ;;
	*)            bad "A2: parametr job NIE dociera ($WYNIK_A)" ;;
esac

NONCE=$(printf '%s' "$WYNIK_A" | sed 's/.*nonce=//')
if [ "$NONCE" = "BRAK" ] || [ -z "$NONCE" ]; then
	bad "A3: nonce NIE dociera do serwera — weryfikacja padnie"
else
	# ⚠️ wp_set_current_user PRZED weryfikacja: nonce jest wiazany z uzytkownikiem
	# i jego sesja, a kazde `wp eval` to OSOBNY proces startujacy jako niezalogowany.
	# Bez tego test odrzucalby PRAWIDLOWY nonce i wskazywal na wade, ktorej nie ma.
	WERYF=$(wp eval "wp_set_current_user( 1 ); echo wp_verify_nonce( '$NONCE', 'mp_import_report_$JOB' ) ? 'OK' : 'ODRZUCONY';" 2>/dev/null)
	[ "$WERYF" = "OK" ] \
		&& ok "A3: nonce z adresu PRZECHODZI weryfikacje (link zadziala od razu)" \
		|| bad "A3: nonce z adresu odrzucony przez wp_verify_nonce"
fi

# ── B. ADRES ZE ZWROTKI WZNOWIENIA IMPORTU (ta sama klasa — JSON, zero encji) ─
ADRES_AJAX=$(wp eval "
	wp_set_current_user( 1 );
	// Ta sama wartosc, ktora ajax_reclaim wklada do zwrotki JSON.
	echo MP\\Registry\\Admin\\ImportScreen::report_url( $JOB );" 2>/dev/null)
echo "     adres ze zwrotki wznowienia: $ADRES_AJAX"
case "$ADRES_AJAX" in
	*"amp;"*) bad "B1: adres w zwrotce wznowienia niesie encje &amp;" ;;
	*)        ok  "B1: adres w zwrotce wznowienia bez encji &amp;" ;;
esac
WYNIK_B=$(wp eval "
	wp_set_current_user( 1 );   // jak wyzej — nonce jest per uzytkownik
	parse_str( (string) wp_parse_url( '$ADRES_AJAX', PHP_URL_QUERY ), \$p );
	echo ( isset( \$p['job'], \$p['_wpnonce'] ) && wp_verify_nonce( \$p['_wpnonce'], 'mp_import_report_' . \$p['job'] ) ) ? 'PRZECHODZI' : 'PADA';" 2>/dev/null)
[ "$WYNIK_B" = "PRZECHODZI" ] \
	&& ok "B2: adres ze zwrotki przechodzi weryfikacje nonce" \
	|| bad "B2: adres ze zwrotki NIE przechodzi weryfikacji ($WYNIK_B)"

# ── C. KONTROLA KIERUNKU: link renderowany w HTML dziala jak dotad ───────────
# Tam na wyjsciu stoi esc_url() i przegladarka i tak odkreca encje — ta sciezka
# byla sprawna PRZED naprawa i musi zostac sprawna PO niej.
HTML=$(wp eval "
	wp_set_current_user( 1 );
	\$m = new ReflectionMethod( 'MP\\Registry\\Admin\\ImportScreen', 'render_history' );
	\$m->setAccessible( true ); ob_start(); \$m->invoke( null ); echo ob_get_clean();" 2>/dev/null)
echo "$HTML" | grep -q "mp_import_report" \
	&& ok "C1: tabela historii nadal renderuje link do raportu" \
	|| bad "C1: link do raportu zniknal z tabeli historii"
echo "$HTML" | grep -q "_wpnonce" \
	&& ok "C2: link w HTML nadal niesie nonce" \
	|| bad "C2: link w HTML stracil nonce"

wp db query "DELETE FROM wp_mp_import_jobs" >/dev/null 2>&1

echo "── Z1b-ADRES: PASS=$PASS FAIL=$FAIL ──"
if [ "$(( PASS + FAIL ))" -lt 8 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane 8."
	exit 2
fi
[ "$FAIL" -eq 0 ]
