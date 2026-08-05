#!/usr/bin/env bash
# ZYWY DOWOD: licznik terminu STOI, gdy sprawa czeka na klienta — i rusza z powrotem,
# gdy wraca do pracy serwisu.
#
# CO BYLO ZLE: status „do uzupelnienia" (jeden z siedmiu ze specyfikacji klienta — czekamy, az
# klient cos dosle) mial WLASNE okno 72 h, liczone od zmiany statusu. Zegar bieglo przez
# caly czas oczekiwania, wiec po trzech dobach sprawa byla „po terminie" i ESKALOWALA DO
# KOORDYNATORA za to, ze klient nie odpisal. Falszywe przekroczenia to nie drobiazg: po nich
# ludzie przestaja czytac alarmy, takze prawdziwe. Zafalszowywaly tez sredni czas obslugi.
#
# ⛔ TEN DOWOD MUSI POKAZAC TRZY RZECZY NARAZ, bo kazda osobno moglaby klamac:
#   1. sprawa w „do uzupelnienia" NIE dostaje terminu i NIE eskaluje,
#   2. sprawa po powrocie do „w analizie" dostaje SWIEZY termin — czyli naprawa nie odebrala
#      terminow wszystkim (samo „brak terminu" wygladalo by tak samo przy zepsutym SLA),
#   3. prog wykrywania spraw krazacych przeliczyl sie SAM: 576 -> 432 godziny, bo liczy sie
#      z sumy godzin statusow. Sprawa zaparkowana tu na zawsze nadal zostanie zlapana.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ── 0. Konfiguracja: status oczekiwania ma ZERO godzin ────────────────────
KONF=$(wp eval '
	$s = MP\Automator\SlaConfig::for_status( "do uzupełnienia" );
	echo "godzin=" . (int) $s["sla_hours"] . ";terminal=" . ( $s["terminal"] ? "tak" : "nie" );
' 2>/dev/null | tr -d '[:space:]')
echo "$KONF" | grep -q 'godzin=0;' \
	&& ok "status oczekiwania ma ZERO godzin terminu ($KONF)" \
	|| bad "status oczekiwania nadal ma wlasne okno terminu ($KONF)"

echo "$KONF" | grep -q 'terminal=nie' \
	&& ok "status NIE stal sie terminalny (sprawa dalej zyje, tylko bez zegara)" \
	|| bad "status zrobil sie terminalny — to nie o to chodzilo ($KONF)"

# ── 1. Sprawa czekajaca na klienta ────────────────────────────────────────
OUT=$(wp mp case-create --kind=reklamacja --email="pauza$RANDOM@example.com" --name='Jan Kowalski' \
	--serial="SEK-PZ$RANDOM" --document='FV/2026/9' --date='2026-05-01' --desc='pauza licznika' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
TOKEN=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp eval "MP\\Intake\\CaseRepo::verify('$TOKEN');" >/dev/null 2>&1
[ -n "$CID" ] && ok "sprawa $CID potwierdzona (status: $(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID"))" || bad "brak sprawy"

# Termin przed przestawieniem — zeby bylo widac, ze sprawa go MIALA.
PRZED=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID AND deadline_at IS NOT NULL")
[ "${PRZED:-0}" = "1" ] \
	&& ok "w statusie roboczym sprawa MA termin (jest co zatrzymywac)" \
	|| bad "sprawa nie ma terminu juz na starcie — dowod bylby bez wartosci ($PRZED)"

wp eval "apply_filters('mp_case_change_status', null, $CID, 'do uzupełnienia', 'nowe', 1, null);" >/dev/null 2>&1
STATUS=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
[ "$STATUS" = "douzupełnienia" ] || [ "$STATUS" = "do uzupełnienia" ] \
	&& ok "sprawa przestawiona na „$STATUS” (czekamy na klienta)" \
	|| bad "nie udalo sie przestawic statusu ($STATUS)"

# ── 2. SEDNO: brak terminu i brak eskalacji ───────────────────────────────
TERMIN=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID AND deadline_at IS NOT NULL")
[ "${TERMIN:-1}" = "0" ] \
	&& ok "SEDNO: sprawa czekajaca na klienta NIE MA terminu (licznik stoi)" \
	|| bad "sprawa czekajaca na klienta nadal ma termin — licznik biegnie"

# SYMULUJEMY UPLYW 72 GODZIN: cofamy sam TERMIN, ale WYLACZNIE gdy istnieje
# (`AND deadline_at IS NOT NULL`) — dzieki temu nie fabrykujemy terminu tam, gdzie go nie ma.
# Na kodzie sprzed naprawy sprawa ma termin, wiec cofniecie go daje dokladnie te falszywa
# eskalacje, o ktora chodzi. Po naprawie termin jest NULL, wiec to zapytanie nie robi NIC.
wp db query "UPDATE wp_mp_case_sla
	SET deadline_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL 1 DAY),
	    warning_at  = DATE_SUB(UTC_TIMESTAMP(), INTERVAL 2 DAY)
	WHERE case_id=$CID AND deadline_at IS NOT NULL" >/dev/null 2>&1
wp eval "add_filter('pre_wp_mail','__return_true'); MP\\Automator\\Sweep::run();" >/dev/null 2>&1
ESK=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID AND escalated_at IS NOT NULL")
PRZYP=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID AND reminder_sent_at IS NOT NULL")
[ "${ESK:-1}" = "0" ] && [ "${PRZYP:-1}" = "0" ] \
	&& ok "SEDNO: po przebiegu zamiatarki ZERO eskalacji i ZERO przypomnien (koordynator nie dostaje alarmu za milczenie klienta)" \
	|| bad "sprawa mimo wszystko eskalowala/przypominala (eskalacje=$ESK, przypomnienia=$PRZYP)"

# ── 3. Powrot do pracy serwisu = SWIEZY termin ────────────────────────────
# Bez tej kontroli „brak terminu" wygladaloby identycznie jak zepsute SLA.
wp eval "apply_filters('mp_case_change_status', null, $CID, 'w analizie', 'do uzupełnienia', 1, null);" >/dev/null 2>&1
PO=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID AND deadline_at > UTC_TIMESTAMP()")
[ "${PO:-0}" = "1" ] \
	&& ok "po powrocie do „w analizie” sprawa dostaje SWIEZY termin w przyszlosci (naprawa nie odebrala terminow wszystkim)" \
	|| bad "sprawa nie odzyskala terminu po powrocie do pracy serwisu ($PO)"

INNE=$(wp eval '
	$n = MP\Automator\SlaConfig::for_status( "nowe" );
	$a = MP\Automator\SlaConfig::for_status( "w analizie" );
	echo "nowe=" . (int) $n["sla_hours"] . ";analiza=" . (int) $a["sla_hours"];
' 2>/dev/null | tr -d '[:space:]')
echo "$INNE" | grep -q 'nowe=24;analiza=48' \
	&& ok "pozostale statusy maja swoje godziny bez zmian ($INNE)" \
	|| bad "naprawa ruszyla godziny innych statusow ($INNE)"

# ── 4. Prog wykrywania spraw krazacych przeliczyl sie SAM ─────────────────
PROG=$(wp eval 'echo (int) MP\Automator\Sla::stale_threshold_hours();' 2>/dev/null | tr -d '[:space:]')
RACHUNEK=$(wp eval '
	$suma = 0;
	foreach ( MP\Automator\SlaConfig::core_effective() as $k ) { $suma += (int) $k["sla_hours"]; }
	echo (int) ceil( $suma * MP\Automator\SlaConfig::slowest_priority_modifier() );
' 2>/dev/null | tr -d '[:space:]')
[ "$PROG" = "432" ] \
	&& ok "SEDNO: prog krazenia przeliczyl sie SAM na 432 godz. (bylo 576 — wypadly 72 h oczekiwania)" \
	|| bad "prog krazenia wynosi $PROG zamiast 432"
[ "$PROG" = "$RACHUNEK" ] \
	&& ok "prog nadal jest RACHUNKIEM z konfiguracji, nie liczba wpisana recznie" \
	|| bad "prog rozjechal sie z rachunkiem (prog=$PROG, rachunek=$RACHUNEK)"

echo ""
echo "WYNIK PAUZA-LICZNIKA: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
