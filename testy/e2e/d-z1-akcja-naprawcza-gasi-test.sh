#!/usr/bin/env bash
# ZYWY DOWOD Z1 (niezalezna kontrola wdrozenia 1.3.13, waga WYSOKA):
# test „Stanu witryny" o pustej puli pracownikow podawal akcje naprawcza, ktora
# NIE naprawia problemu — kazal nadac role „Pracownik serwisu MP". Kontroler
# wykonal to doslownie: ostrzezenie NIE zniknelo, a zgloszenia dalej szly do nikogo.
#
# PRZYCZYNA: test liczy pule ZAPISANA w regule (`pracownikow_w_puli` czyta
# `action_config_json` -> `pool`), a rola jest tylko dodatkowym filtrem uprawnien.
# Gasi go dopiero Automatyzacje MP -> „Kto dostaje zgloszenia" -> „Zapisz liste".
#
# Kalibracja WBUDOWANA: A2 i A3 PADAJA na kodzie sprzed naprawy (akcja odsylala
# do Uzytkownikow i nie wspominala o zapisie listy). Sekcje B i C to kontrole
# ZACHOWANIA — dowodza, ze warunek testu jest dobry: sama rola go NIE gasi,
# a zapis puli TAK. Te dwie przechodza w obu stanach kodu i pilnuja, zeby
# „naprawa tekstu" nie przykryla ewentualnej wady warunku.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Stan testu: jedna wlaczona regula przydzialu z PUSTA pula.
wp db query "DELETE FROM wp_mp_workflow_rules" >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
wp eval '
	global $wpdb; $t = $wpdb->prefix . "mp_workflow_rules";
	// Pula pusta = dokladnie stan po swiezej instalacji.
	$wpdb->query( "UPDATE {$t} SET action_config_json = \x27{\"pool\":[]}\x27 WHERE action_type = \x27assign\x27" );' >/dev/null 2>&1

# ⛔ Ekstrakcja pol przez PHP, NIE przez python3 — obraz wp-cli, na ktorym chodzi
# CI, nie ma pythona; test oparty na nim padlby wszedzie poza moja maszyna.
status_testu() { wp eval '$w = MP\Automator\Admin\SiteHealthTests::test_pula_przydzialu(); echo (string) ( $w["status"] ?? "" );' 2>/dev/null; }
tresc_testu()  { wp eval '$w = MP\Automator\Admin\SiteHealthTests::test_pula_przydzialu(); echo (string) ( $w["actions"] ?? "" ) . " " . (string) ( $w["description"] ?? "" );' 2>/dev/null; }

STATUS=$(status_testu)
[ "$STATUS" = "recommended" ] && ok "A1: przy pustej puli test ostrzega (status=$STATUS)" \
	|| bad "A1: spodziewany 'recommended', jest '$STATUS'"

AKCJA=$(tresc_testu)
case "$AKCJA" in
	*"Kto dostaje zgłoszenia"*) ok "A2: akcja kieruje do ekranu, ktory gasi problem" ;;
	*) bad "A2: akcja NIE wskazuje „Kto dostaje zgłoszenia\": $(printf '%.150s' "$AKCJA")" ;;
esac
case "$AKCJA" in
	*"Zapisz listę pracowników"*) ok "A3: akcja mowi o zapisaniu listy (to jest czynnosc gaszaca)" ;;
	*) bad "A3: akcja nie mowi o zapisaniu listy pracownikow" ;;
esac

# ── B. KONTROLA ZACHOWANIA: sama ROLA NIE gasi testu (to bylo sedno wady) ────
UID_A=$(wp user get z1agent --field=ID 2>/dev/null); [ -z "$UID_A" ] && UID_A=$(wp user create z1agent 'z1@example.com' --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
STATUS_B=$(status_testu)
[ "$STATUS_B" = "recommended" ] \
	&& ok "B1: po samym nadaniu roli test NADAL ostrzega (wada byla realna)" \
	|| bad "B1: sama rola zgasila test — warunek mierzy co innego niz sadzimy ($STATUS_B)"

# ── C. KONTROLA ZACHOWANIA: zapis puli GASI test ────────────────────────────
wp eval "
	\$id = (int) \$GLOBALS['wpdb']->get_var( \"SELECT id FROM {\$GLOBALS['wpdb']->prefix}mp_workflow_rules WHERE action_type='assign' LIMIT 1\" );
	MP\\Automator\\AssignmentPool::save_pool( \$id, array( $UID_A ) );" >/dev/null 2>&1
STATUS_C=$(status_testu)
[ "$STATUS_C" = "good" ] \
	&& ok "C1: po zapisaniu listy pracownikow test GASNIE (instrukcja z akcji dziala)" \
	|| bad "C1: po zapisaniu puli test dalej ostrzega ($STATUS_C) — warunek do naprawy"

wp db query "DELETE FROM wp_mp_workflow_rules" >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1

echo "── Z1: PASS=$PASS FAIL=$FAIL ──"
if [ "$(( PASS + FAIL ))" -lt 5 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane 5."
	exit 2
fi
[ "$FAIL" -eq 0 ]
