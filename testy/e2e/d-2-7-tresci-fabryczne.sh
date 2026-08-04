#!/usr/bin/env bash
# ZYWY DOWOD (poz. 2.7): produkt NAZYWA treści fabryczne WordPressa widoczne bez
# logowania — i niczego przy tym nie kasuje.
#
# CO BYLO ZLE: na uruchomionej instancji wisial opublikowany wpis „Hello world!"
# i strona „Sample Page", obie dostepne bez logowania. Przy pierwszym kontakcie
# produkt wyglada przez to na niedokonczony.
#
# ⛔ DLACZEGO NAPRAWA NIE KASUJE: to tresci WITRYNY, nie wtyczki. Wtyczka, ktora
# kasuje albo chowa cudze wpisy przy aktywacji, robi rzecz nieodwracalna — usuwa je
# czlowiek, krokiem z instrukcji wdrozenia. Kod ma tylko pilnowac, zeby o tym kroku
# nie dalo sie zapomniec po cichu (sama instrukcja jest niesprawdzalna).
#
# ⭐ NAJWAZNIEJSZA KONTROLA TEGO PLIKU JEST TA OSTATNIA: po uruchomieniu diagnostyki
# oba wpisy MAJA nadal istniec i byc opublikowane. Kontrola, ktora „przy okazji"
# sprzata, byla by grozniejsza niz sama wada.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

zdrowie() {
	wp eval --user=1 '
		$w = MP\Automator\Admin\SiteHealthTests::test_tresci_fabryczne();
		echo ( $w["status"] ?? "" ) . "|" . wp_strip_all_tags( (string) ( $w["description"] ?? "" ) );
	' 2>/dev/null
}

# ── 0. Stan wyjsciowy: wpis 1 i strona 2 opublikowane i nieedytowane ──────
STAN=$(q "SELECT COUNT(*) FROM wp_posts WHERE ID IN (1,2) AND post_status='publish' AND post_modified_gmt = post_date_gmt")
[ "${STAN:-0}" = "2" ] \
	&& ok "stan wyjsciowy: wpis nr 1 i strona nr 2 sa opublikowane i nietkniete" \
	|| bad "stanowisko nie ma tresci fabrycznych — ten dowod nie ma czego sprawdzac ($STAN)"

# ── 1. SEDNO: diagnostyka to ZGLASZA i podaje, o co chodzi ────────────────
WYNIK=$(zdrowie)
echo "$WYNIK" | grep -q '^recommended|' \
	&& ok "SEDNO 2.7: Stan witryny ZGLASZA tresci fabryczne" \
	|| bad "Stan witryny milczy o tresciach fabrycznych ($WYNIK)"

echo "$WYNIK" | grep -q 'bez logowania' \
	&& ok "komunikat mowi, ze widzi to KAZDY bez logowania (a nie tylko admin)" \
	|| bad "komunikat nie tlumaczy, na czym polega problem ($WYNIK)"

echo "$WYNIK" | grep -qi 'http' \
	&& ok "komunikat podaje ADRESY — admin wie, ktore to strony" \
	|| bad "komunikat nie podaje adresow ($WYNIK)"

# ── 2. NIC NIE ZOSTALO SKASOWANE ANI UKRYTE ──────────────────────────────
PO=$(q "SELECT COUNT(*) FROM wp_posts WHERE ID IN (1,2) AND post_status='publish'")
[ "${PO:-0}" = "2" ] \
	&& ok "po diagnostyce oba wpisy NADAL istnieja i sa opublikowane (zero kasowania)" \
	|| bad "diagnostyka ruszyla cudze tresci — to jest gorsze niz sama wada ($PO)"

# ── 3. Gdy tresc ZNIKA z widoku publicznego, kontrola milknie ────────────
# Nie kasujemy nic na stanowisku — chowamy do szkicu i oddajemy stan zastany.
wp db query "UPDATE wp_posts SET post_status='draft' WHERE ID IN (1,2)" >/dev/null 2>&1
wp eval 'clean_post_cache(1); clean_post_cache(2);' >/dev/null 2>&1
WYNIK2=$(zdrowie)
echo "$WYNIK2" | grep -q '^good|' \
	&& ok "po ukryciu tresci kontrola przestaje alarmowac (brak falszywego alarmu)" \
	|| bad "kontrola alarmuje mimo ukrytych tresci ($WYNIK2)"

# ── 4. Wlasna tresc pod tym samym numerem NIE jest zglaszana ─────────────
# Ktos, kto przerobil przykladowa strone na swoja, ma miec spokoj: rozpoznajemy
# tresc NIEEDYTOWANA, a nie „strone o numerze 2".
wp db query "UPDATE wp_posts SET post_status='publish', post_modified_gmt = DATE_ADD(post_date_gmt, INTERVAL 1 DAY) WHERE ID IN (1,2)" >/dev/null 2>&1
wp eval 'clean_post_cache(1); clean_post_cache(2);' >/dev/null 2>&1
WYNIK3=$(zdrowie)
echo "$WYNIK3" | grep -q '^good|' \
	&& ok "tresc EDYTOWANA nie jest zglaszana (to juz wlasna strona, nie fabryka)" \
	|| bad "kontrola zglasza tresc, ktora ktos przerobil na wlasna ($WYNIK3)"

# ── Oddanie stanu zastanego ──────────────────────────────────────────────
wp db query "UPDATE wp_posts SET post_status='publish', post_modified_gmt = post_date_gmt, post_modified = post_date WHERE ID IN (1,2)" >/dev/null 2>&1
wp eval 'clean_post_cache(1); clean_post_cache(2);' >/dev/null 2>&1
ODDANE=$(q "SELECT COUNT(*) FROM wp_posts WHERE ID IN (1,2) AND post_status='publish' AND post_modified_gmt = post_date_gmt")
[ "${ODDANE:-0}" = "2" ] \
	&& ok "stanowisko oddane w stanie zastanym" \
	|| bad "nie udalo sie oddac stanu zastanego ($ODDANE)"

echo ""
echo "WYNIK 2.7-TRESCI-FABRYCZNE: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
