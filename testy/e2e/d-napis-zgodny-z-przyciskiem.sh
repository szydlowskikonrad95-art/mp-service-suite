#!/usr/bin/env bash
# ZYWY DOWOD: komunikat na ekranie ustawien odsyla do przycisku, ktory NAPRAWDE
# tak sie nazywa.
#
# NASZA WLASNA WPADKA (spoza listy klienta, znaleziona przy weryfikacji sweepu):
# ekran ustawien dwa razy kazal kliknac przycisk „Przelicz SLA", a przycisk, ktory
# czlowiek widzi w panelu, nazywa sie „Przelicz terminy obslugi". Produkt kazal
# wiec szukac czegos, czego na ekranie nie ma.
# ⛔ To ta sama klasa bledu co pozycje 2.35 i 2.40 — tylko ze nasza, dolozona
# przy naprawianiu cudzych. Dlatego dostaje bramke, a nie samo poprawienie napisu.
#
# ⭐ POROWNUJEMY WYRENDEROWANE EKRANY, nie dwa napisy w plikach: etykieta jest
# brana z tego, co panel naprawde wypisuje, a nie z drugiej kopii tego samego
# tekstu. Kopia rozjezdza sie tak samo cicho jak oryginal.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Etykieta przycisku WPROST z wyrenderowanego panelu (value="...").
ETYKIETA=$(wp eval --user=1 '
	ob_start();
	MP\Automator\Admin\PanelScreen::render();
	$html = (string) ob_get_clean();
	if ( 1 === preg_match( "/name=\"mp_recalc_submit\"[^>]*value=\"([^\"]+)\"/", $html, $m ) ) {
		echo $m[1];
		return;
	}
	if ( 1 === preg_match( "/value=\"([^\"]*Przelicz[^\"]*)\"/", $html, $m ) ) {
		echo $m[1];
	}' 2>/dev/null | sed 's/^ *//; s/ *$//')

[ -n "$ETYKIETA" ] \
	&& ok "etykieta przycisku odczytana z panelu: [$ETYKIETA]" \
	|| bad "nie udalo sie odczytac etykiety przycisku z panelu — kontrola bez podstawy"

# Napisy ekranu ustawien: bierzemy je z WYRENDEROWANEGO ekranu.
USTAWIENIA=$(wp eval --user=1 '
	ob_start();
	MP\Automator\Admin\SettingsScreen::render();
	echo (string) ob_get_clean();' 2>/dev/null)

[ -n "$USTAWIENIA" ] \
	&& ok "ekran ustawien wyrenderowany" \
	|| bad "ekran ustawien nie wyrenderowal sie — kontrola bez podstawy"

# ── SEDNO: ekran nie odsyla do przycisku o innej nazwie ────────────────────
printf '%s' "$USTAWIENIA" | grep -q "Przelicz SLA" \
	&& bad "ekran ustawien odsyla do przycisku Przelicz SLA, ktorego na ekranie NIE MA" \
	|| ok "ekran ustawien nie odsyla do nieistniejacego przycisku"

# Odsylacz musi wskazywac DOKLADNIE te etykiete, ktora ma przycisk.
if [ -n "$ETYKIETA" ]; then
	printf '%s' "$USTAWIENIA" | grep -qF "$ETYKIETA" \
		&& ok "odsylacz uzywa DOKLADNIE etykiety przycisku ([$ETYKIETA])" \
		|| bad "ekran ustawien nie uzywa etykiety [$ETYKIETA] — napisy rozjechaly sie znowu"
fi

echo ""
echo "WYNIK NAPIS-ZGODNY: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
