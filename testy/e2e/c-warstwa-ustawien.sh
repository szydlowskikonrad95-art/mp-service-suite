#!/usr/bin/env bash
# ZYWY DOWOD (naprawa 2.16 + 2.35 + czesc 2.11 + czesc 1 pkt 4): WARSTWA USTAWIEN.
#
# Produkt mial cztery dzialajace zapisy konfiguracji z panelu (szablony odpowiedzi,
# szablony maili, checklisty, pula pracownikow) i DOKLADNIE tam, gdzie zamowienie
# uzylo slowa „konfigurowalne", drogi dla czlowieka nie bylo:
#   - `StatusDefs::upsert()` istnial i NIKT go nie wolal (2.16),
#   - `SlaConfig` czytal opcje godzin, ktorej NIC nigdy nie zapisywalo (2.35),
#   - `Rules::insert()` wolal wylacznie test, panel dawal podglad (2.11 czesc a),
#   - przelacznik kasowania danych czytany 3x w uninstall.php, ustawialny znikad.
#
# ⛔ Ten test mierzy ZACHOWANIE, nie obecnosc stalych: wola funkcje zapisu, sprawdza
# co naprawde wyladowalo w bazie, renderuje ekran i patrzy, na jaka akcje POST-uje
# formularz. Sama nazwa klasy niczego by nie dowodzila.
#
# ⭐ KALIBRACJA: na kodzie sprzed naprawy test PADA (brak ekranu, brak SlaConfig::save_core,
# brak Rules::update/delete, brak handlerow admin-post). Sprawdzone przed scaleniem.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Wspolny naglowek dla wywolan `wp eval`: admin systemu + funkcje panelu admina.
BOOT='require_once ABSPATH . "wp-admin/includes/plugin.php"; require_once ABSPATH . "wp-admin/includes/template.php"; $u = get_users( array( "role" => "administrator", "number" => 1 ) ); wp_set_current_user( $u ? $u[0]->ID : 1 );'

echo "== 1. EKRAN USTAWIEN ISTNIEJE I SIEDZI POD WLASCIWYM MENU =="

MENU=$(wp eval "$BOOT \$GLOBALS['submenu'] = array(); MP\\Automator\\Admin\\SettingsScreen::add_menu(); \$out = ''; foreach ( (array) \$GLOBALS['submenu'] as \$parent => \$pozycje ) { foreach ( \$pozycje as \$p ) { if ( 'mp-automator-settings' === \$p[2] ) { \$out = \$parent . '|' . \$p[1]; } } } echo \$out;" 2>/dev/null)
[ "$MENU" = "mp-automator|mp_system_admin" ] \
	&& ok "ekran ustawien wisi pod menu automatyzacji, cap mp_system_admin ($MENU)" \
	|| bad "ekranu nie ma w menu albo ma zla bramke (dostalam: '$MENU')"

for MODUL in "Intake|mp-intake-settings|mp-cases" "Registry|mp-registry-settings|mp-registry"; do
	NS="${MODUL%%|*}"; RESZTA="${MODUL#*|}"; SLUG="${RESZTA%%|*}"; RODZIC="${RESZTA##*|}"
	M=$(wp eval "$BOOT \$GLOBALS['submenu'] = array(); MP\\${NS}\\Admin\\SettingsScreen::add_menu(); \$out=''; foreach ( (array) \$GLOBALS['submenu'] as \$parent => \$pozycje ) { foreach ( \$pozycje as \$p ) { if ( '$SLUG' === \$p[2] ) { \$out = \$parent; } } } echo \$out;" 2>/dev/null)
	[ "$M" = "$RODZIC" ] && ok "ekran ustawien modulu $NS wisi pod $RODZIC" || bad "ekran $NS nie trafil pod $RODZIC (dostalam: '$M')"
done

echo "== 2. FORMULARZ NAPRAWDE POST-UJE NA ISTNIEJACY HANDLER =="
# Renderujemy ekran do bufora i sprawdzamy, na jakie akcje ida formularze — a potem,
# czy te akcje maja podpiety handler. Formularz kierujacy w prozne admin-post.php
# wyglada identycznie jak dzialajacy: strona sie wyswietla, zapis nie robi nic.
HTML=$(wp eval "$BOOT ob_start(); MP\\Automator\\Admin\\SettingsScreen::render(); echo str_replace( array(\"\n\",\"\r\"), ' ', ob_get_clean() );" 2>/dev/null)

for AKCJA in mp_automator_status_config mp_automator_sla_config mp_automator_rules_config mp_automator_uninstall_switch; do
	case "$HTML" in
		*"value=\"$AKCJA\""*) ok "ekran ma formularz kierujacy na akcje $AKCJA" ;;
		*) bad "na ekranie NIE MA formularza akcji $AKCJA" ;;
	esac

	PODPIETY=$(wp eval "echo has_action( 'admin_post_$AKCJA' ) ? 'tak' : 'nie';" 2>/dev/null)
	[ "$PODPIETY" = "tak" ] && ok "akcja $AKCJA ma podpiety handler (POST ma gdzie trafic)" || bad "akcja $AKCJA BEZ handlera — zapis nie zrobilby nic"
done

case "$HTML" in *'wp_nonce'*|*'_wpnonce'*) ok "formularze niosa jednorazowy klucz" ;; *) bad "brak jednorazowego klucza w formularzach" ;; esac

echo "== 3. GODZINY TERMINOW: ZAPIS DZIALA I PODBIJA WERSJE POLITYKI =="
# Przed naprawa `SlaConfig` NIE MIAL zadnej funkcji zapisu, a wersja polityki byla
# stemplowana w wierszach i NIGDY nie zmieniana (zawsze 1) — kolumna niosla pozor.
PRZED=$(wp eval 'echo MP\Automator\SlaConfig::policy_version();' 2>/dev/null)
GODZ_PRZED=$(wp eval 'echo MP\Automator\SlaConfig::for_status("nowe")["sla_hours"];' 2>/dev/null)

wp eval 'MP\Automator\SlaConfig::save_core( array( "nowe" => array( "sla_hours" => 48, "warning_hours" => 7 ) ) );' >/dev/null 2>&1

GODZ_PO=$(wp eval 'echo MP\Automator\SlaConfig::for_status("nowe")["sla_hours"];' 2>/dev/null)
WARN_PO=$(wp eval 'echo MP\Automator\SlaConfig::for_status("nowe")["warning_hours"];' 2>/dev/null)
PO=$(wp eval 'echo MP\Automator\SlaConfig::policy_version();' 2>/dev/null)

[ "$GODZ_PRZED" = "24" ] && ok "wartosc fabryczna statusu nowe to 24 h (jest od czego mierzyc)" || bad "nieoczekiwana wartosc wyjsciowa: $GODZ_PRZED"
[ "$GODZ_PO" = "48" ] && ok "zapisana godzina terminu WIDOCZNA w wyliczeniu (24 -> 48)" || bad "zapis godzin nie dotarl do wyliczenia (jest $GODZ_PO)"
[ "$WARN_PO" = "7" ] && ok "zapisane okno ostrzegawcze widoczne (7 h — liczba nie do trafienia domyslna 25%)" || bad "okno ostrzegawcze nie zapisane (jest $WARN_PO)"
[ -n "$PRZED" ] && [ "$PO" = "$((PRZED+1))" ] && ok "wersja polityki podbita ($PRZED -> $PO) — widac, ze terminy sprzed zmiany sa stare" || bad "wersja polityki NIE podbita ($PRZED -> $PO)"

# Termin liczy sie NOWA wartoscia (nie tylko odczyt opcji — realne wyliczenie).
DEADLINE=$(wp eval 'echo (string) MP\Automator\SlaConfig::deadline_for( "nowe", "2026-01-01 00:00:00", "normal" );' 2>/dev/null)
[ "$DEADLINE" = "2026-01-03 00:00:00" ] && ok "wyliczony termin uzywa nowej godziny (48 h od bazy)" || bad "termin nie uzywa nowej godziny (dostalam: $DEADLINE)"

wp eval 'MP\Automator\SlaConfig::save_core( array() );' >/dev/null 2>&1
POWROT=$(wp eval 'echo MP\Automator\SlaConfig::for_status("nowe")["sla_hours"];' 2>/dev/null)
[ "$POWROT" = "24" ] && ok "wyczyszczenie nadpisan wraca do wartosci fabrycznej" || bad "po wyczyszczeniu zostalo $POWROT"

echo "== 4. STATUSY WLASNE: ZAPIS Z EKRANU SIEGA WALIDATORA DRUGIEGO MODULU =="
wp eval 'MP\Automator\StatusDefs::delete( "test-ustawienia" );' >/dev/null 2>&1
SLUG=$(wp eval 'echo MP\Automator\StatusDefs::upsert( "test-ustawienia", array( "label" => "Test ustawien", "active" => true, "terminal" => false, "sla_hours" => 12, "warning_hours" => 3 ) );' 2>/dev/null)
[ "$SLUG" = "test-ustawienia" ] && ok "status wlasny zapisany" || bad "zapis statusu odrzucony ($SLUG)"

WIDZI=$(wp eval '$s = apply_filters( "mp_registered_statuses", array() ); echo isset( $s["test-ustawienia"] ) ? "tak" : "nie";' 2>/dev/null)
[ "$WIDZI" = "tak" ] && ok "status opublikowany do walidatora przez zaczep (nie zostal w opcji)" || bad "status nie dotarl do walidatora"

SLA_ST=$(wp eval 'echo MP\Automator\SlaConfig::for_status("test-ustawienia")["sla_hours"];' 2>/dev/null)
[ "$SLA_ST" = "12" ] && ok "termin statusu wlasnego brany z definicji (12 h)" || bad "termin statusu wlasnego nie dziala ($SLA_ST)"

ZA_DLUGI=$(wp eval 'echo MP\Automator\StatusDefs::upsert( "status-o-nazwie-duzo-za-dlugiej-na-kolumne", array( "label" => "X" ) );' 2>/dev/null)
[ -z "$ZA_DLUGI" ] && ok "proba kontrolna: klucz dluzszy niz kolumna statusu ODRZUCONY" || bad "wpuszczono klucz dluzszy niz kolumna ($ZA_DLUGI)"

wp eval 'MP\Automator\StatusDefs::delete( "test-ustawienia" );' >/dev/null 2>&1
PO_KASACJI=$(wp eval 'echo isset( MP\Automator\StatusDefs::all()["test-ustawienia"] ) ? "jest" : "nie ma";' 2>/dev/null)
[ "$PO_KASACJI" = "nie ma" ] && ok "usuniecie statusu z ekranu dziala" || bad "status zostal po usunieciu"

echo "== 5. REGULY PRZYDZIALU: ADMINISTRATOR MOZE JE ZMIENIC, SYSTEMOWEJ NIE SKASUJE =="
ID=$(wp eval 'echo MP\Automator\Rules::insert( array( "trigger_type" => "case_created", "condition_key" => "kategoria", "condition_operator" => "equals", "condition_value" => "agd", "action_type" => "assign", "action_config" => array( "pool" => array( 1 ) ), "priority" => 20, "enabled" => true, "source" => "user" ) );' 2>/dev/null)
[ -n "$ID" ] && [ "$ID" -gt 0 ] 2>/dev/null && ok "regula wlasna zalozona (id=$ID)" || bad "nie udalo sie zalozyc reguly ($ID)"

wp eval "MP\\Automator\\Rules::update( $ID, array( 'condition_key' => 'rodzaj', 'condition_operator' => 'equals', 'condition_value' => 'naprawa', 'priority' => 5, 'enabled' => false ) );" >/dev/null 2>&1
SPRAWDZ=$(wp eval "\$r = MP\\Automator\\Rules::by_id( $ID ); echo \$r['condition_key'] . '|' . \$r['condition_value'] . '|' . \$r['priority'] . '|' . \$r['enabled'];" 2>/dev/null)
[ "$SPRAWDZ" = "rodzaj|naprawa|5|0" ] && ok "zmiana warunku, kolejnosci i wylaczenie reguly zapisane ($SPRAWDZ)" || bad "zmiana reguly nie zapisala sie ($SPRAWDZ)"

ZLY=$(wp eval "MP\\Automator\\Rules::update( $ID, array( 'condition_key' => 'wymyslony-klucz' ) ); \$r = MP\\Automator\\Rules::by_id( $ID ); echo \$r['condition_key'];" 2>/dev/null)
[ "$ZLY" = "" ] && ok "proba kontrolna: klucz warunku spoza kontekstu sprawy NIE zostaje zapisany" || bad "wpuszczono klucz spoza kontekstu ($ZLY)"

# ⛔ Regule systemowa zakladamy SAMI. Wersja szukajaca jej w bazie dawala falszywy
# FAIL na stanowisku, na ktorym nikt jeszcze nie zasiewal regul — test nie moze
# zalezec od tego, co ktos zostawil w bazie przed nami.
SYS_ID=$(wp eval 'echo MP\Automator\Rules::insert( array( "trigger_type" => "status_changed", "condition_key" => "", "action_type" => "notify", "action_config" => array( "template_key" => "test" ), "priority" => 99, "enabled" => true, "source" => "system", "system_key" => "test_ochrona_systemowej" ) );' 2>/dev/null)
if [ -n "$SYS_ID" ] && [ "$SYS_ID" -gt 0 ] 2>/dev/null; then
	SKAS=$(wp eval "echo MP\\Automator\\Rules::delete( $SYS_ID ) ? 'skasowana' : 'odmowa';" 2>/dev/null)
	[ "$SKAS" = "odmowa" ] && ok "reguly systemowej NIE da sie skasowac z ekranu (zostaje wylaczenie)" || bad "ekran pozwolil skasowac regule systemowa"

	ZYJE=$(wp eval "echo null === MP\\Automator\\Rules::by_id( $SYS_ID ) ? 'nie ma' : 'jest';" 2>/dev/null)
	[ "$ZYJE" = "jest" ] && ok "regula systemowa nadal w bazie po probie kasacji" || bad "regula systemowa zniknela"

	# Wylaczyc systemowa WOLNO — to jest droga zamiast kasowania.
	wp eval "MP\\Automator\\Rules::update( $SYS_ID, array( 'enabled' => false, 'priority' => 98 ) );" >/dev/null 2>&1
	STAN=$(wp eval "\$r = MP\\Automator\\Rules::by_id( $SYS_ID ); echo \$r['enabled'] . '|' . \$r['priority'] . '|' . \$r['action_type'];" 2>/dev/null)
	[ "$STAN" = "0|98|notify" ] && ok "regule systemowa mozna wylaczyc i przestawic kolejnosc, typ akcji zostaje ($STAN)" || bad "wylaczenie reguly systemowej nie zadzialalo ($STAN)"

	# Proba kontrolna: podmiana typu akcji reguly systemowej ma byc ODRZUCONA —
	# inaczej ekran po cichu rozbrajalby powiadomienia zasiane przy instalacji.
	wp eval "MP\\Automator\\Rules::update( $SYS_ID, array( 'action_type' => 'assign' ) );" >/dev/null 2>&1
	TYP=$(wp eval "\$r = MP\\Automator\\Rules::by_id( $SYS_ID ); echo \$r['action_type'];" 2>/dev/null)
	[ "$TYP" = "notify" ] && ok "proba kontrolna: typu akcji reguly systemowej ekran NIE zmienia" || bad "ekran podmienil typ akcji reguly systemowej ($TYP)"

	wp db query "DELETE FROM wp_mp_workflow_rules WHERE id=$SYS_ID" >/dev/null 2>&1
else
	bad "nie udalo sie zalozyc reguly systemowej do sprawdzenia ochrony ($SYS_ID)"
fi

USUN=$(wp eval "echo MP\\Automator\\Rules::delete( $ID ) ? 'usunieta' : 'odmowa';" 2>/dev/null)
[ "$USUN" = "usunieta" ] && ok "regule wlasna administrator moze usunac" || bad "nie udalo sie usunac reguly wlasnej"

echo "== 6. UCZCIWOSC EKRANU: POLA, KTORYCH PRODUKT NIE ZBIERA, SA OZNACZONE =="
# Kraj i jezyk maja kolumny, silnik je czyta — ale NIC ich nigdy nie wypelnia.
# Regula na nich nie zadziala; ekran, ktory by o tym milczal, zastawialby pulapke.
case "$HTML" in
	*'zawsze puste'*) ok "ekran ostrzega, ze warunek na tym polu nie zadziala" ;;
	*) bad "ekran NIE ostrzega o polach, ktorych produkt nie zbiera" ;;
esac

echo "== 7. PRZELACZNIK KASOWANIA DANYCH — TRZY WTYCZKI, TRZY OSOBNE USTAWIENIA =="
for PARA in "mp_automator_delete_data|Automator" "mp_intake_delete_data|Intake" "mp_registry_delete_data|Registry"; do
	OPCJA="${PARA%%|*}"; NS="${PARA##*|}"
	STALA=$(wp eval "echo MP\\${NS}\\Admin\\SettingsScreen::OPTION_DELETE_DATA;" 2>/dev/null)
	[ "$STALA" = "$OPCJA" ] && ok "ekran $NS ustawia dokladnie te opcje, ktora czyta jego uninstall.php ($OPCJA)" || bad "ekran $NS pisze do '$STALA', a uninstall.php czyta '$OPCJA'"
done

wp option update mp_automator_delete_data 1 >/dev/null 2>&1
CZYTA=$(wp eval 'echo MP\Automator\Common\UninstallSwitch::is_on( "mp_automator_delete_data" ) ? "wlaczony" : "wylaczony";' 2>/dev/null)
[ "$CZYTA" = "wlaczony" ] && ok "przelacznik odczytuje wlaczone ustawienie" || bad "przelacznik nie widzi wlaczonego ustawienia"
wp option update mp_automator_delete_data 0 >/dev/null 2>&1
CZYTA0=$(wp eval 'echo MP\Automator\Common\UninstallSwitch::is_on( "mp_automator_delete_data" ) ? "wlaczony" : "wylaczony";' 2>/dev/null)
[ "$CZYTA0" = "wylaczony" ] && ok "proba kontrolna: wylaczone ustawienie odczytane jako wylaczone" || bad "przelacznik zawsze melduje wlaczony"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
