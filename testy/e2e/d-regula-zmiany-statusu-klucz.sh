#!/usr/bin/env bash
# ZYWY DOWOD: regula zmiany statusu skonfigurowana DOKLADNIE TAK, JAK UCZY NASZ EKRAN,
# naprawde zmienia status sprawy.
#
# CO BYLO ZLE: silnik czytal wylacznie klucz `new_status` (`RuleEngine::do_change_status`),
# a ekran ustawien podpowiadal adminowi `{"status":"w analizie"}` („Szczegoly akcji").
# Mapowania miedzy tymi kluczami nie bylo NIGDZIE. Regula zapisana wg naszej wlasnej
# podpowiedzi nie miala wiec celu: konczyla sie cicho jako `failed_no_target` w ukrytym
# rejestrze zdarzen — bez slowa na ekranie, bez maila, bez sladu dla czlowieka.
#
# ⛔ DLACZEGO NIKT TEGO NIE ZLAPAL: zalazki regul nie zawieraja ANI JEDNEJ reguly
# `change_status`, wiec ta sciezka nigdy nie zostala przejechana od konca do konca.
# Ten test jest pierwszym przejazdem.
#
# NAPRAWA: silnik przyjmuje OBA klucze (`new_status` kanoniczny, `status` jako zapis,
# ktorego uczyl interfejs do 1.3.12 — regul juz zapisanych nie wolno zepsuc), a podpowiedz
# na ekranie mowi kanoniczny.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Reguly wlasne czyscimy po sobie na koncu; systemowych (source='system') NIE ruszamy.
wp db query "DELETE FROM wp_mp_workflow_rules WHERE source <> 'system' AND action_type='change_status'" >/dev/null 2>&1

regula() { # $1 = tresc action_config_json
	wp db query "INSERT INTO wp_mp_workflow_rules
		(trigger_type, condition_key, condition_operator, condition_value, action_type, action_config_json, priority, enabled, source)
		VALUES ('status_changed','','','','change_status','$1',5,1,'test')" >/dev/null 2>&1
}
sprzataj_regule() { wp db query "DELETE FROM wp_mp_workflow_rules WHERE source='test'" >/dev/null 2>&1; }

sprawa() { # tworzy potwierdzona sprawe w statusie 'nowe'; echo = case_id
	local OUT CID TOKEN
	OUT=$(wp mp case-create --kind=reklamacja --email="klucz$RANDOM@example.com" --name='Jan Kowalski' \
		--serial="SEK-KL$RANDOM" --document='FV/2026/5' --date='2026-05-01' --desc='regula statusu' 2>/dev/null)
	CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
	TOKEN=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
	wp eval "MP\\Intake\\CaseRepo::verify('$TOKEN');" >/dev/null 2>&1
	echo "$CID"
}

# Zmiana statusu na „zaakceptowane" odpala wyzwalacz `status_changed`, czyli nasza regule.
odpal() { wp eval "apply_filters('mp_case_change_status', null, $1, 'zaakceptowane', 'nowe', 1, null);" >/dev/null 2>&1; }

# ── 1. SEDNO: zapis Z NASZEJ PODPOWIEDZI dziala od konca do konca ──────────
sprzataj_regule
regula '{"status":"w analizie"}'
CID=$(sprawa)
[ -n "$CID" ] && ok "sprawa $CID zalozona i potwierdzona (status startowy: $(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID"))" || bad "nie udalo sie zalozyc sprawy"

odpal "$CID"
STATUS=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
[ "$STATUS" = "wanalizie" ] || [ "$STATUS" = "w analizie" ] \
	&& ok "SEDNO: regula zapisana jak w podpowiedzi ({\"status\":…}) ZMIENILA status na „$STATUS”" \
	|| bad "regula z naszej podpowiedzi nie zadzialala — status to „$STATUS”, nie „w analizie”"

CICHA=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID AND payload LIKE '%failed_no_target%'")
[ "${CICHA:-1}" = "0" ] \
	&& ok "w rejestrze NIE MA cichego failed_no_target (regula znalazla cel)" \
	|| bad "regula wyladowala w rejestrze jako failed_no_target ($CICHA wpisow)"

# ── 2. Kanoniczny klucz dziala tak samo (nie zepsulismy tego, co bylo) ─────
sprzataj_regule
regula '{"new_status":"w analizie"}'
CID2=$(sprawa)
odpal "$CID2"
STATUS2=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID2")
[ "$STATUS2" = "wanalizie" ] || [ "$STATUS2" = "w analizie" ] \
	&& ok "kanoniczny zapis ({\"new_status\":…}) dziala bez zmian" \
	|| bad "kanoniczny klucz przestal dzialac — status „$STATUS2”"

# ── 3. Gdy oba, wygrywa kanoniczny (jednoznaczne rozstrzygniecie) ─────────
sprzataj_regule
regula '{"new_status":"w naprawie","status":"w analizie"}'
CID3=$(sprawa)
odpal "$CID3"
STATUS3=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID3")
[ "$STATUS3" = "wnaprawie" ] || [ "$STATUS3" = "w naprawie" ] \
	&& ok "przy obu kluczach wygrywa kanoniczny (dostalismy „$STATUS3”)" \
	|| bad "rozstrzygniecie przy obu kluczach inne niz umowione („$STATUS3”)"

# ── 4. Pusty cel nadal jest odmowa, a nie zgadywaniem ─────────────────────
sprzataj_regule
regula '{"status":"   "}'
CID4=$(sprawa)
odpal "$CID4"
STATUS4=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID4")
PUSTY=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID4 AND payload LIKE '%failed_no_target%'")
[ "$STATUS4" = "zaakceptowane" ] && [ "${PUSTY:-0}" -ge 1 ] 2>/dev/null \
	&& ok "pusty cel = odmowa z zapisem failed_no_target (nie zgadujemy za admina)" \
	|| bad "pusty cel obsluzony inaczej (status „$STATUS4”, wpisow failed_no_target: $PUSTY)"

# ── 5. Ekran uczy KANONICZNEGO klucza ─────────────────────────────────────
# Czytamy tekst z kodu ekranu przez refleksje pliku wtyczki zainstalowanej na stanowisku —
# test chodzi z katalogu WordPressa, wiec zrodel repo tu nie ma.
PLIK=$(wp eval 'echo dirname( MP_AUTOMATOR_FILE ) . "/includes/Admin/SettingsScreen.php";' 2>/dev/null | tr -d '[:space:]')
grep -q 'new_status&quot;:&quot;w analizie\|"new_status":"w analizie' "$PLIK" 2>/dev/null \
	&& ok "podpowiedz na ekranie ustawien uczy kanonicznego klucza (new_status)" \
	|| bad "podpowiedz na ekranie nadal uczy klucza, ktorego silnik nie czyta"

sprzataj_regule

echo ""
echo "WYNIK KLUCZ-STATUSU: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
