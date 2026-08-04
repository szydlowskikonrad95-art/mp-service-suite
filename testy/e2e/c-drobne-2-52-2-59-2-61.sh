#!/usr/bin/env bash
# ZYWY DOWOD trzech napraw z grupy 2:
#   2.59 — naglowki bezpieczenstwa docieraja na strone z formularzem wstawionym BLOKIEM,
#   2.52 — wersja struktury bazy ginie RAZEM z tabelami, nie zawsze,
#   2.61 — wtyczki nie wykonuja zbednej pracy przy kazdym zadaniu.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
REPO="${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"

echo "== 2.59: ROZPOZNANIE STRONY WIDZI BLOK, NIE TYLKO SKROT =="
# Pomiar, nie lektura: sk�adamy tresc obu rodzajow i pytamy rdzen WordPressa.
BLOK=$(wp eval '$t = "<!-- wp:mp/intake-form /-->"; echo has_block( "mp/intake-form", $t ) ? "widzi" : "nie";' 2>/dev/null | tr -d '[:space:]')
SKROT=$(wp eval '$t = "[mp_intake_form]"; echo has_shortcode( $t, "mp_intake_form" ) ? "widzi" : "nie";' 2>/dev/null | tr -d '[:space:]')
[ "$BLOK" = "widzi" ] && ok "rdzen WordPressa rozpoznaje blok w tresci" || bad "has_block nie widzi bloku ($BLOK)"
[ "$SKROT" = "widzi" ] && ok "rdzen rozpoznaje skrot (proba kontrolna metody)" || bad "has_shortcode nie widzi skrotu"

# Dowod, ze STARE rozpoznanie bylo slepe na blok — stad brala sie cala pozycja.
STARE=$(wp eval '$t = "<!-- wp:mp/intake-form /-->"; echo has_shortcode( $t, "mp_intake_form" ) ? "widzi" : "nie";' 2>/dev/null | tr -d '[:space:]')
[ "$STARE" = "nie" ] && ok "samo sprawdzanie skrotu NIE widzi bloku (zrodlo wady potwierdzone)" || bad "zalozenie pozycji nieaktualne"

grep -q "has_block" "$REPO"/mp-service-intake/includes/Front/PageDetect.php && ok "rozpoznanie strony pyta tez o blok" || bad "rozpoznanie nadal tylko po skrocie"

if [ -n "${MP_BASE:-}" ]; then
	echo "== 2.59 NA ZYWO: STRONA Z BLOKIEM DOSTAJE NAGLOWKI =="
	PID_B=$(wp post create --post_type=page --post_title="Blok naglowki test" --post_status=publish --post_content='<!-- wp:mp/intake-form /-->' --porcelain 2>/dev/null | tr -d '[:space:]')
	PID_O=$(wp post create --post_type=page --post_title="Obca strona test" --post_status=publish --post_content='zwykla tresc bez formularza' --porcelain 2>/dev/null | tr -d '[:space:]')

	MA=$(curl -sI "$MP_BASE/?page_id=$PID_B" | grep -ciE "x-frame-options|content-security-policy|x-content-type-options")
	NIE=$(curl -sI "$MP_BASE/?page_id=$PID_O" | grep -ciE "x-frame-options|content-security-policy")

	[ "${MA:-0}" -ge 3 ] && ok "strona z formularzem wstawionym BLOKIEM ma naglowki bezpieczenstwa ($MA)" || bad "strona z blokiem bez naglowkow ($MA) — formularz da sie osadzic w ramce"
	[ "${NIE:-0}" = "0" ] && ok "obca strona bez naglowkow (zero ingerencji poza wlasnymi stronami)" || bad "naglowki trafily na obca strone ($NIE)"

	wp post delete "$PID_B" --force >/dev/null 2>&1
	wp post delete "$PID_O" --force >/dev/null 2>&1
fi

echo "== 2.61: ZERO ZBEDNEJ PRACY PRZY KAZDYM ZADANIU =="
ILE=$(grep -rl "load_plugin_textdomain" "$REPO"/mp-service-intake/includes "$REPO"/mp-warranty-registry/includes "$REPO"/mp-workflow-automator/includes 2>/dev/null | wc -l | tr -d '[:space:]')
[ "$ILE" = "0" ] && ok "zadna wtyczka nie laduje tlumaczen recznie (WordPress robi to sam)" || bad "$ILE wtyczek nadal laduje tlumaczenia recznie"
# Proba kontrolna metody szukania: wzorzec, ktory MUSI trafic.
KONTROLA=$(grep -rl "add_action" "$REPO"/mp-service-intake/includes 2>/dev/null | wc -l | tr -d '[:space:]')
[ "${KONTROLA:-0}" -gt 0 ] && ok "proba kontrolna: wyszukiwanie w ogole trafia ($KONTROLA plikow)" || bad "wyszukiwanie nie dziala — wynik wyzej nic nie znaczy"

# Tlumaczenia nadal DZIALAJA (nie o to chodzilo, zeby je wylaczyc).
TLUM=$(wp eval 'echo MP\Intake\FormConfig::kind_label( "reklamacja" );' 2>/dev/null | tr -d '[:space:]')
[ "$TLUM" = "Reklamacja" ] && ok "napisy nadal dzialaja po skasowaniu recznego ladowania" || bad "napisy sie zepsuly ($TLUM)"

echo "== 2.52: WERSJA STRUKTURY GINIE RAZEM Z TABELAMI =="
# Wersje schematu kasujemy WYLACZNIE w galezi „usun dane" — sprawdzamy, ze nie
# ma jej juz na liscie warstwy technicznej (kasowanej zawsze).
for MOD in mp-service-intake mp-workflow-automator; do
	if grep -E "Uninstall::run" -A 3 "$REPO/$MOD/uninstall.php" | grep -q "schema_version'"; then
		bad "$MOD: wersja schematu nadal kasowana ZAWSZE"
	else
		ok "$MOD: wersja schematu poza warstwa techniczna"
	fi
done
# Wzorzec, z ktorego to wzielismy — modul rejestru — ma zostac bez zmian.
grep -q "VERSION_OPTION" "$REPO"/mp-warranty-registry/uninstall.php && ok "modul rejestru (wzorzec) nietkniety" || bad "ruszono wzorcowy modul rejestru"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
