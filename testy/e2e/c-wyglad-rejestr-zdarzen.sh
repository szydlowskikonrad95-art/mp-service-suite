#!/usr/bin/env bash
# ZYWY DOWOD: trzy wady z kontroli wygladu na dzialajacej instalacji (W3, W4, W5)
# plus kontrola prawa do CUDZEJ sprawy przy odznaczaniu kroku checklisty.
#
# ⛔ Kazda kontrola mierzy ZACHOWANIE (wolamy prawdziwy kod produktu), a nie obecnosc
#    tekstu w pliku. Metody sa prywatne, wiec siegamy po nie refleksja — to jedyny
#    sposob, zeby sprawdzic DOKLADNIE to, co zobaczy czlowiek na ekranie.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

wywolaj() { # <klasa> <metoda> <arg>
	wp eval "\$m = new ReflectionMethod('$1', '$2'); \$m->setAccessible(true); echo \$m->invoke(null, $3);" 2>/dev/null
}

echo "== W3: rejestr zdarzen nie pokazuje wewnetrznego numeru wiersza =="
# Sprawa, ktorej na pewno nie ma — numer daleko poza zakresem.
WYNIK=$(wywolaj 'MP\Automator\Admin\PanelScreen' 'numer_sprawy' '999999999')
case "$WYNIK" in
	*usuni*) ok "sprawa nieistniejaca: „$WYNIK” — czytelna informacja zamiast samego ID" ;;
	*) bad "sprawa nieistniejaca daje „$WYNIK”" ;;
esac
# ⛔ PROBA KONTROLNA KIERUNKU: gdyby naprawa pisala „usunieta” ZAWSZE, powyzsze tez
#    by przeszlo, a produkt klamalby przy kazdej sprawie niepotwierdzonej. Zakladamy
#    wiec sprawe ISTNIEJACA i niezweryfikowana i sprawdzamy, ze mowi o niej inaczej.
ID_NIEPOTW=$(wp eval '
	global $wpdb; $t = $wpdb->prefix . "mp_service_cases";
	$wpdb->insert( $t, array(
		"case_number" => "SRV/2026/T9001", "kind" => "serwis", "status" => "nowe",
		"identity_status" => "pending", "created_at" => current_time( "mysql", true ),
	) );
	echo (int) $wpdb->insert_id;' 2>/dev/null)
if [ -n "${ID_NIEPOTW:-}" ] && [ "${ID_NIEPOTW:-0}" -gt 0 ] 2>/dev/null; then
	WYNIK2=$(wywolaj 'MP\Automator\Admin\PanelScreen' 'numer_sprawy' "$ID_NIEPOTW")
	case "$WYNIK2" in
		*usuni*) bad "[kontrolna] sprawa ISTNIEJACA opisana jako usunieta — „$WYNIK2”" ;;
		*niepotwierdzona*) ok "[kontrolna] sprawa istniejaca, niepotwierdzona: „$WYNIK2” — bez klamstwa o usunieciu" ;;
		*) bad "[kontrolna] nieoczekiwany opis sprawy istniejacej: „$WYNIK2”" ;;
	esac
	wp eval "global \$wpdb; \$wpdb->delete( \$wpdb->prefix . 'mp_service_cases', array( 'id' => $ID_NIEPOTW ) );" >/dev/null 2>&1
else
	bad "[kontrolna] nie udalo sie zalozyc sprawy kontrolnej — wynik W3 niepelny"
fi

echo "== W4: kolumna Szczegoly mowi po polsku albo nic =="
SUROWY=$(wywolaj 'MP\Automator\Admin\PanelScreen' 'payload_summary' "'result=succes wiadomosc techniczna'")
[ "$SUROWY" = "—" ] && ok "surowy tekst deweloperski nie trafia na ekran (jest „—”)" \
	|| bad "surowy tekst dalej widoczny: „$SUROWY”"
ZNANY=$(wywolaj 'MP\Automator\Admin\PanelScreen' 'payload_summary' "'{\"rule_id\":7,\"error_code\":\"smtp_failed\"}'")
case "$ZNANY" in
	*reguła*|*regu*) ok "znane klucze po polsku: „$ZNANY”" ;;
	*) bad "znane klucze nadal technicznie: „$ZNANY”" ;;
esac
case "$ZNANY" in
	*rule_id*|*error_code*) bad "w opisie zostal techniczny klucz: „$ZNANY”" ;;
	*) ok "[kontrolna] techniczne nazwy kluczy zniknely z opisu" ;;
esac
NIEZNANY=$(wywolaj 'MP\Automator\Admin\PanelScreen' 'payload_summary' "'{\"jakis_wewnetrzny_klucz\":\"abc\"}'")
[ "$NIEZNANY" = "—" ] && ok "klucz spoza slownika: „—” zamiast surowego zapisu" \
	|| bad "klucz spoza slownika dalej wyciek: „$NIEZNANY”"

echo "== W5: historia importow pokazuje ZAIMPORTOWANE, nie „przetworzone” =="
# Import, w ktorym wszystkie wiersze padly: przetworzone 8, udane 0, bledy 8.
ID_JOB=$(wp eval '
	global $wpdb; $t = $wpdb->prefix . "mp_import_jobs";
	$wpdb->insert( $t, array(
		"file_path" => "/tmp/t9001.csv", "status" => "done", "total_rows" => 8,
		"processed_rows" => 8, "success_rows" => 0, "error_rows" => 8,
		"job_token" => "t9001", "created_at" => current_time( "mysql", true ),
	) );
	echo (int) $wpdb->insert_id;' 2>/dev/null)
if [ -n "${ID_JOB:-}" ] && [ "${ID_JOB:-0}" -gt 0 ] 2>/dev/null; then
	HTML=$(wp eval "
		\$m = new ReflectionMethod('MP\\Registry\\Admin\\ImportScreen', 'render_history');
		\$m->setAccessible(true); ob_start(); \$m->invoke(null); echo ob_get_clean();" 2>/dev/null)
	echo "$HTML" | grep -q "0 / 8" \
		&& ok "wiersz importu pokazuje „0 / 8” — zgodne z „8 bledow”" \
		|| bad "wiersz importu NIE pokazuje „0 / 8” (sprzecznosc „8/8 wierszy” + „8 bledow” wraca)"
	echo "$HTML" | grep -q "8 / 8" \
		&& bad "ekran dalej pokazuje „8 / 8” obok „8 bledow” — to sie wyklucza" \
		|| ok "[kontrolna] „8 / 8” zniknelo z tego wiersza"
	wp eval "global \$wpdb; \$wpdb->delete( \$wpdb->prefix . 'mp_import_jobs', array( 'id' => $ID_JOB ) );" >/dev/null 2>&1
else
	bad "nie udalo sie zalozyc importu kontrolnego — wynik W5 niepelny"
fi

echo "== PRAWO DO CUDZEJ SPRAWY: odznaczenie kroku checklisty =="
# Dwoje pracownikow, sprawa przypisana do PIERWSZEGO; drugi probuje odznaczyc krok.
WYNIK_OBCY=$(wp eval '
	global $wpdb;
	foreach ( array( "t9001-agent-a", "t9001-agent-b" ) as $login ) {
		if ( ! get_user_by( "login", $login ) ) {
			wp_insert_user( array( "user_login" => $login, "user_pass" => wp_generate_password(), "role" => "mp_agent" ) );
		}
	}
	$a = get_user_by( "login", "t9001-agent-a" )->ID;
	$b = get_user_by( "login", "t9001-agent-b" )->ID;
	$t = $wpdb->prefix . "mp_service_cases";
	$wpdb->insert( $t, array(
		"case_number" => "SRV/2026/T9002", "kind" => "serwis", "status" => "w analizie",
		"identity_status" => "verified", "assigned_to" => $a,
		"created_at" => current_time( "mysql", true ), "verified_at" => current_time( "mysql", true ),
	) );
	$case = (int) $wpdb->insert_id;
	$auth = MP\Intake\CaseRepo::checklist_authorize( $case, "zebranie_danych", true, $b );
	$wpdb->delete( $t, array( "id" => $case ) );
	echo ( ! empty( $auth["success"] ) ? "PRZESZLO" : "ODMOWA:" . ( $auth["error_code"] ?? "?" ) );' 2>/dev/null)
case "$WYNIK_OBCY" in
	ODMOWA:NOT_CASE_OWNER) ok "pracownik NIE odznaczy kroku na cudzej sprawie ($WYNIK_OBCY)" ;;
	PRZESZLO) bad "🔴 DZIURA: pracownik odznaczyl krok na CUDZEJ sprawie" ;;
	*) bad "nieoczekiwany wynik autoryzacji: „$WYNIK_OBCY”" ;;
esac

echo
echo "PASS=$PASS FAIL=$FAIL"
# ⛔ Straznik kompletu: wszystko idzie przez `wp eval`, wiec cichy brak startu
#    swiecilby zielono. Liczba ZMIERZONA na przebiegu z ta zmiana.
if [ "$(( PASS + FAIL ))" -lt 9 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane min. 9."
	exit 2
fi
[ "$FAIL" -eq 0 ] || exit 1
