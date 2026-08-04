#!/usr/bin/env bash
# ZYWY DOWOD (audytor spojnosci paczki, 27.07): odinstalowanie zostawialo CRONA.
#
# Kazda wtyczka planuje wlasne zadanie cykliczne (Intake — retencja zalacznikow
# i porzuconych zgloszen; Registry — sprzatanie importow; Automator — sweep SLA
# i dokanczanie przeliczen). Deaktywacja czyscila je poprawnie (petla po
# CRON_HOOKS), ale uninstall mial OSOBNA, recznie wpisana liste — i w dwoch
# wtyczkach byla PUSTA. Efekt: po odinstalowaniu wtyczki zaplanowane zadanie
# zostawalo w bazie WordPressa na zawsze, mimo ze OWNERSHIP.md obiecuje
# "warstwa (i) ZAWSZE: opcje techniczne, transienty, CRONY".
# Dotychczasowy test uninstalla sprawdzal tabele i opcje — cronow NIE dotykal,
# dlatego nikt tego nie zlapal.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

HAKI="mp_intake_retention_sweep mp_registry_imports_sweep mp_automator_sla_sweep"

# ── 0. Po aktywacji zadania SA zaplanowane (inaczej test nic nie dowodzi) ────
for hak in $HAKI; do
	ILE=$(wp cron event list --fields=hook --format=count --hook="$hak" 2>/dev/null || echo 0)
	[ "${ILE:-0}" -ge 1 ] 2>/dev/null \
		&& ok "stan wyjsciowy: $hak zaplanowany" \
		|| bad "stan wyjsciowy: BRAK $hak (aktywacja go nie zaplanowala?)"
done

# ── 0b. Stan wyjsciowy: katalogi robocze ISTNIEJA i maja pliki ──────────────
# Bez tego kontrola nizej nic nie dowodzi — pusty katalog "znika" tez wtedy, gdy
# uninstall go nie rusza. Zakladamy pliki TA SAMA droga co produkt (Importer/Attachments
# tworza katalog z guardami .htaccess + index.php).
# Audyt 29.07: Registry NIE kasowal `mp-imports` przy odinstalowaniu, choc OWNERSHIP.md
# obiecuje "warstwa (i) ZAWSZE: ... pliki techniczne". Intake swoj katalog kasowal.
#
# ⛔ ZMIANA KONTRAKTU (audyt 2.2, 4.08) — te dwa katalogi NIE sa juz tym samym:
#   · `mp-imports`     = pliki wsadowe i raporty importu. Artefakty TECHNICZNE,
#                        nie wskazuje na nie zadna przezywajaca sprawa => kasowane ZAWSZE.
#   · `mp-attachments` = zdjecia uszkodzen i skany dokumentow zakupu, czyli DOWODY
#                        w sprawach. Ida za TYM SAMYM przelacznikiem co reszta danych
#                        sprawy => przy WYLACZONYM przelaczniku ZOSTAJA.
# Wczesniej ten test wymagal, zeby zniknely oba. To wymaganie kodowalo dokladnie
# te wade, ktora audyt 2.2 zglosil: pliki gina nieodwracalnie, a wiersze w bazie
# (odwracalne) zostaja — czyli sprawy przezywaja BEZ dowodow.
KATALOGI="mp-attachments mp-imports"
KATALOGI_TECHNICZNE="mp-imports"
KATALOGI_DOWODOWE="mp-attachments"

wp eval '
$base = wp_upload_dir()["basedir"];
foreach (array("mp-attachments","mp-imports") as $k) {
	$d = rtrim($base,"/")."/".$k;
	wp_mkdir_p($d);
	file_put_contents($d."/probka-testowa.dat", "x");
	file_put_contents($d."/index.php", "<?php\n// Silence is golden.\n");
	file_put_contents($d."/.htaccess", "Require all denied\n");
}' >/dev/null 2>&1

for kat in $KATALOGI; do
	IST=$(wp eval "echo is_dir(rtrim(wp_upload_dir()['basedir'],'/').'/$kat') ? 1 : 0;" 2>/dev/null)
	[ "${IST:-0}" = "1" ] \
		&& ok "stan wyjsciowy: katalog $kat istnieje i ma pliki" \
		|| bad "stan wyjsciowy: nie udalo sie zalozyc $kat (test nic nie dowiedzie)"
done

# ── 0c. Przelacznik kasowania danych MUSI byc wylaczony ────────────────────
# Bez tego kontrola zalacznikow nizej jest dwuznaczna: gdyby ktorys wczesniejszy
# test zostawil przelacznik WLACZONY, dowody znikneloby zgodnie z umowa, a my
# zameldowalibysmy wade. Odtwarzamy wprost sytuacje PRZYPADKOWEGO odinstalowania.
wp eval "delete_option('mp_intake_delete_data');" >/dev/null 2>&1
PRZELACZNIK=$(wp eval "echo (string) get_option('mp_intake_delete_data', '0');" 2>/dev/null | tr -d '[:space:]')
[ "$PRZELACZNIK" = "0" ] \
	&& ok "stan wyjsciowy: przelacznik kasowania danych WYLACZONY (przypadkowe odinstalowanie)" \
	|| bad "przelacznik kasowania danych = [$PRZELACZNIK] — kontrola dowodow bylaby dwuznaczna"

# ── 1. Odinstalowanie WSZYSTKICH trzech wtyczek ─────────────────────────────
wp plugin deactivate mp-service-intake mp-warranty-registry mp-workflow-automator >/dev/null 2>&1
wp plugin uninstall mp-service-intake mp-warranty-registry mp-workflow-automator >/dev/null 2>&1

# ── 2. SEDNO: zero zaplanowanych zadan po odinstalowaniu ────────────────────
for hak in $HAKI; do
	ILE=$(wp cron event list --fields=hook --format=count --hook="$hak" 2>/dev/null || echo 0)
	[ "${ILE:-0}" = "0" ] \
		&& ok "$hak sprzatniety przy odinstalowaniu" \
		|| bad "$hak ZOSTAL w bazie po odinstalowaniu ($ILE) — zadanie-widmo"
done

# ── 3. Kontrola: w tabeli opcji nie ma sladu naszych hakow ──────────────────
SLAD=$(wp db query "SELECT COUNT(*) FROM wp_options WHERE option_name='cron' AND option_value LIKE '%mp_intake_%'" --skip-column-names 2>/dev/null | tr -d '[:space:]')
[ "${SLAD:-0}" = "0" ] \
	&& ok "wpis 'cron' w opcjach nie zawiera juz naszych hakow" \
	|| bad "haki MP dalej siedza w opcji 'cron' ($SLAD)"

# ── 4. SEDNO 2: katalogi TECHNICZNE znikaja, DOWODOWE zostaja ───────────────
# Pliki wsadowe importu zawieraja numery seryjne, faktury i daty zakupu, ale nie
# jest do nich przypieta zadna sprawa — to artefakty techniczne warstwy (i).
ile_plikow() {
	wp eval "
		\$d = rtrim(wp_upload_dir()['basedir'],'/').'/$1';
		if ( ! is_dir(\$d) ) { echo '0'; }
		else { \$f = glob(\$d.'/*'); echo count(false === \$f ? array() : \$f) + (is_file(\$d.'/.htaccess') ? 1 : 0); }
	" 2>/dev/null
}

for kat in $KATALOGI_TECHNICZNE; do
	ZOSTAL=$(ile_plikow "$kat")
	[ "${ZOSTAL:-1}" = "0" ] \
		&& ok "katalog techniczny $kat sprzatniety przy odinstalowaniu (zero plikow na dysku)" \
		|| bad "katalog $kat ZOSTAL po odinstalowaniu ($ZOSTAL plikow) — artefakty techniczne na serwerze"
done

# ⛔ Tu kontrola jest ODWROTNA i to jest zamierzone (audyt 2.2). Przy WYLACZONYM
# przelaczniku wiersze spraw zostaja w bazie — gdyby pliki zniknely, zostalyby
# sprawy wskazujace na dowody, ktorych juz nie ma. Kasowanie pliku jest
# NIEODWRACALNE, zostawienie tabeli odwracalne; produkt nie moze usuwac tego,
# czego nie da sie odtworzyc, i zachowywac tego, co odtworzyc mozna.
# Pelny dowod obu stron przelacznika: testy/e2e/c-2-2-zalaczniki-przy-odinstalowaniu.sh
for kat in $KATALOGI_DOWODOWE; do
	ZOSTAL=$(ile_plikow "$kat")
	[ "${ZOSTAL:-0}" -ge 1 ] 2>/dev/null \
		&& ok "katalog dowodowy $kat ZOSTAL przy odinstalowaniu bez zgody ($ZOSTAL plikow) — sprawy nie traca dowodow" \
		|| bad "katalog $kat skasowany mimo wylaczonego przelacznika — sprawy zostaja bez dowodow (wada 2.2)"
done

echo ""
echo "WYNIK UNINSTALL-CRONY: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
