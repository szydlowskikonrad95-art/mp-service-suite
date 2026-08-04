#!/usr/bin/env bash
# ZYWY DOWOD 2.1b: gdy poczta pada, NIKT nie slyszy tego samego co przy sukcesie.
#
# BUG (audyt 2.1b, waga duza): wynik `wp_mail()` byl ignorowany na KAZDEJ drodze
# wysylki w Intake. Skutek trojaki:
#   (a) klient po wyslaniu formularza dostawal zdanie brzmiace jak potwierdzenie
#       („wyslalismy link") takze wtedy, gdy mail nie wyszedl — czekal na link,
#       ktory nie mial prawa przyjsc, a zgloszenie umieralo niepotwierdzone;
#   (b) po klikanieciu linku klient slyszal, ze numer sprawy poszedl mailem —
#       a numer poznaje WYLACZNIE z tego maila (krok 6 specyfikacji);
#   (c) personel na ekranie „Niepotwierdzone" widzial takie zgloszenie
#       NIEODROZNIALNIE od udanego, a po kliknieciu „Wyslij ponownie" dostawal
#       „wyslany ponownie" nawet gdy poczta znowu odmowila.
# Awaria byla zapisywana na osi sprawy i podnosila alarm GLOBALNY („poczta nie
# dziala"), ale nikt nie potrafil wskazac, KTOREJ sprawy dotyczy.
#
# FIX: wynik wysylki dociera do czlowieka na wszystkich trzech drogach, a ekran
# „Niepotwierdzone" ma kolumne „Poczta" z oznaczeniem spraw, ktorym link nie doszedl.
# Oznaczenie liczy sie od wydania AKTUALNEGO tokenu, wiec udana ponowna wysylka
# gasi je sama (kontrola nr 8).
#
# ⛔ SWIADOMIE NIE ZMIENIONE: komunikat przy logowaniu do panelu (Front\Login).
# Tam maila wysylamy tylko dla ISTNIEJACEGO konta, wiec osobny komunikat o awarii
# byl oracle'em enumeracji kont. Kontrola nr 9 pilnuje, ze zostalo jak bylo.
#
# Wymaga MP_BASE. Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

reset_all() {
	wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_case_events;" >/dev/null 2>&1
	# Pulapka nr 6 z briefingu: 15-minutowa rezerwacja dedup daje falszywe
	# „sprawa nie powstala" przy powtorce testu.
	wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_rl%' OR option_name LIKE '_transient_timeout_mp_rl%' OR option_name LIKE '_transient_mp_resend_throttle%' OR option_name LIKE '_transient_timeout_mp_resend_throttle%'; DELETE FROM wp_mp_rate_counters" >/dev/null 2>&1
	wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
	wp option delete mp_intake_mail_alert >/dev/null 2>&1
}

# ── 0. Przelacznik poczty na drodze HTTP ─────────────────────────────────────
# W kontenerze CI nie ma serwera poczty, wiec „naturalna" wysylka padalaby ZAWSZE
# i przypadek kontrolny (poczta dziala) sprawdzalby to samo, co przypadek awarii.
# Dlatego oba stany wymuszamy naglowkiem — jeden mu-plugin, dwie wartosci.
MU="wp-content/mu-plugins/mp-test-mail-switch.php"
mkdir -p "wp-content/mu-plugins"
cat > "$MU" <<'PHP'
<?php
// TEST-ONLY: naglowek X-MP-Test-Mail steruje wynikiem wysylki.
// fail => wp_mail() zwraca falsz (serwer poczty odmawia), ok => sukces.
add_filter( 'pre_wp_mail', static function ( $short ) {
	if ( ! isset( $_SERVER['HTTP_X_MP_TEST_MAIL'] ) ) {
		return $short;
	}

	return 'fail' === $_SERVER['HTTP_X_MP_TEST_MAIL'] ? false : true;
}, 99 );
PHP
[ -f "$MU" ] && ok "przelacznik poczty wgrany (mu-plugin)" || bad "nie udalo sie wgrac przelacznika poczty"

reset_all

PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
NONCE=$(curl -s "$MP_BASE$PAGE_PATH" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "nonce formularza pobrany" || bad "brak nonce formularza"

# submit <ok|fail> <email> <serial> -> zdanie, KTORE KLIENT WIDZI na stronie.
# Idziemy cala droga PRG: POST -> przekierowanie na strone formularza -> render
# komunikatu z kontekstu. Mierzymy to, co widzi czlowiek, nie tresc w kodzie.
submit() {
	local mail="$1" email="$2" serial="$3"
	# Sloik ciastek jest KONIECZNY: komunikat wraca w kontekscie zapietym na
	# ciastko sesji (`mp_intake_sess`), a nie w adresie. Bez ciastka kazde
	# zadanie dostaje swoj klucz i strona po przekierowaniu nie ma czego pokazac.
	local jar
	jar=$(mktemp)
	curl -s -L -c "$jar" -b "$jar" -H "X-MP-Test-Mail: $mail" -H "Referer: $MP_BASE$PAGE_PATH" \
		--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
		--data-urlencode "mp_ts=$(( $(date +%s) - 60 ))" \
		--data-urlencode "kind=reklamacja" --data-urlencode "email=$email" --data-urlencode "customer_name=Klient Testowy" \
		--data-urlencode "mp_consent=1" \
		--data-urlencode "serial=$serial" --data-urlencode "purchase_document=FV/1" \
		--data-urlencode "purchase_date=2026-03-15" --data-urlencode "issue_description=usterka" \
		"$MP_BASE/wp-admin/admin-post.php" \
		| grep -o 'class="mp-intake-notice"[^>]*>[^<]*' | sed 's/.*>//' | tr -d '\r\n'
	rm -f "$jar"
}

# ── 1. Poczta DZIALA => komunikat neutralny (przypadek kontrolny) ────────────
NOTICE_OK=$(submit ok 'poczta-dziala@example.com' 'MAILOK-1')
[ -n "$NOTICE_OK" ] && ok "poczta dziala: klient dostal komunikat" || bad "brak komunikatu przy dzialajacej poczcie"

# ── 2. Poczta PADA => komunikat MUSI byc inny niz przy sukcesie ──────────────
NOTICE_FAIL=$(submit fail 'poczta-padla@example.com' 'MAILFAIL-1')
[ -n "$NOTICE_FAIL" ] && [ "$NOTICE_FAIL" != "$NOTICE_OK" ] \
	&& ok "awaria poczty: klient slyszy CO INNEGO niz przy sukcesie" \
	|| bad "klient slyszy TO SAMO co przy sukcesie (to jest wada 2.1b)"

printf '%s' "$NOTICE_FAIL" | grep -qi "awaria naszej poczty" \
	&& ok "komunikat nazywa rzecz po imieniu (awaria poczty, nie wina klienta)" \
	|| bad "komunikat awarii nie mowi, ze poczta padla ($NOTICE_FAIL)"

# Anty-enumeracja: komunikat awarii nie zdradza, czy dane pasuja do bazy.
printf '%s' "$NOTICE_FAIL" | grep -qiE "konto|klient istnieje|znaleziono" \
	&& bad "komunikat awarii zdradza istnienie danych (enumeracja)" \
	|| ok "komunikat awarii nie zdradza istnienia danych w bazie"

# Obie sprawy MUSZA powstac — naprawa dotyczy komunikatu, nie przyjmowania zgloszen.
LICZBA=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$LICZBA" = "2" ] && ok "oba zgloszenia przyjete (regresja zero)" || bad "przyjeto $LICZBA zgloszen zamiast 2"

CID_OK=$(q "SELECT id FROM wp_mp_service_cases ORDER BY id ASC LIMIT 1")
CID_FAIL=$(q "SELECT id FROM wp_mp_service_cases ORDER BY id DESC LIMIT 1")
NR_OK=$(q "SELECT case_number FROM wp_mp_service_cases ORDER BY id ASC LIMIT 1")
NR_FAIL=$(q "SELECT case_number FROM wp_mp_service_cases ORDER BY id DESC LIMIT 1")

EV_FAIL=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID_FAIL AND event_type='MAIL_FAILED'")
[ "${EV_FAIL:-0}" -ge 1 ] 2>/dev/null && ok "awaria zapisana na osi sprawy $NR_FAIL" || bad "brak sladu MAIL_FAILED przy sprawie $NR_FAIL"

EV_OK=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID_OK AND event_type='MAIL_FAILED'")
[ "${EV_OK:-0}" = "0" ] && ok "sprawa z udana wysylka NIE dostala falszywego sladu" || bad "udana wysylka zapisala MAIL_FAILED ($EV_OK)"

# ── 3. EKRAN PERSONELU: sprawy MUSZA byc rozroznialne ────────────────────────
# Rdzen pozycji 2.1b: alarm globalny istnial, brakowalo odpowiedzi „ktora sprawa".
oznaczenie() {
	wp eval --user=1 '
		ob_start();
		MP\Intake\Admin\UnverifiedScreen::render_page();
		$h = ob_get_clean();
		$szukany = "'"$1"'";
		foreach ( explode( "<tr>", $h ) as $wiersz ) {
			if ( false !== strpos( $wiersz, $szukany ) ) {
				echo false !== strpos( $wiersz, "Link NIE doszed" ) ? "TAK" : "NIE";
				return;
			}
		}
		echo "BRAK-WIERSZA";' 2>/dev/null | tr -d '[:space:]'
}

[ "$(oznaczenie "$NR_FAIL")" = "TAK" ] \
	&& ok "ekran Niepotwierdzone OZNACZA sprawe, ktorej link nie doszedl ($NR_FAIL)" \
	|| bad "sprawa $NR_FAIL nieodrozninalna od udanej (to jest wada 2.1b)"

[ "$(oznaczenie "$NR_OK")" = "NIE" ] \
	&& ok "sprawa z udana wysylka NIE jest oznaczana (brak falszywego alarmu)" \
	|| bad "oznaczenie zapalone przy sprawie z udana wysylka ($NR_OK)"

# ── 4. PONOWNA WYSYLKA: personel nie moze uslyszec „wyslane", gdy nie wyszlo ─
resend() {
	local case_id="$1" mail="$2"
	wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient%mp_resend_throttle%'" >/dev/null 2>&1
	wp eval --user=1 '
		$_POST["case_id"]  = '"$case_id"';
		$_POST["email"]    = "";
		$_POST["_wpnonce"] = wp_create_nonce( "mp_intake_resend_'"$case_id"'" );
		$_REQUEST          = $_POST;
		add_filter( "pre_wp_mail", "__return_'"$mail"'", 99 );
		add_filter( "wp_redirect", static function ( $l ) {
			echo "KOMUNIKAT:" . rawurldecode( (string) wp_parse_url( $l, PHP_URL_QUERY ) );
			return $l;
		} );
		MP\Intake\Admin\UnverifiedScreen::handle_resend();' 2>/dev/null | sed 's/.*mp_notice=//'
}

R_FAIL=$(resend "$CID_FAIL" false)
R_OK=$(resend "$CID_FAIL" true)

[ -n "$R_FAIL" ] && [ "$R_FAIL" != "$R_OK" ] \
	&& ok "personel: nieudana ponowna wysylka brzmi INACZEJ niz udana" \
	|| bad "personel slyszy to samo przy nieudanej i udanej wysylce"

printf '%s' "$R_FAIL" | grep -q "Stan witryny" \
	&& ok "komunikat porazki mowi personelowi, GDZIE szukac przyczyny" \
	|| bad "komunikat porazki bez wskazowki dla personelu ($R_FAIL)"

printf '%s' "$R_FAIL" | grep -q "Link weryfikacyjny" \
	&& bad "komunikat porazki niesie zdanie sukcesu ($R_FAIL)" \
	|| ok "komunikat porazki nie udaje sukcesu"

# Udana ponowka GASI oznaczenie — dowod, ze liczy sie stan AKTUALNEGO linku,
# a nie sama obecnosc historycznego wpisu na osi (os jest append-only).
[ "$(oznaczenie "$NR_FAIL")" = "NIE" ] \
	&& ok "udana ponowna wysylka GASI oznaczenie (nie wisi wiecznie)" \
	|| bad "oznaczenie zostalo mimo udanej ponownej wysylki"

# ── 4b. REGRESJA Z CI: oba wpisy w TEJ SAMEJ SEKUNDZIE ──────────────────────
# Pierwsza wersja tej naprawy liczyla oznaczenie z CZASU (awaria nowsza niz
# wydanie tokenu) i przechodzila lokalnie, a na maszynie CI zapalala oznaczenie
# mimo udanej ponowki: znaczniki maja rozdzielczosc JEDNEJ SEKUNDY, a tam caly
# przebieg miesci sie w jednej. Tu WYMUSZAMY identyczny czas obu wpisow — jesli
# ktos wroci do porownywania czasu, ta kontrola padnie od razu, na kazdej maszynie.
wp eval "MP\\Intake\\CaseEvents::log( $CID_FAIL, 'MAIL_FAILED', array( 'kind' => 'magic_link', 'error_code' => 'test' ), null );
	MP\\Intake\\CaseEvents::log( $CID_FAIL, 'MAIL_SENT', array( 'kind' => 'magic_link' ), null );" >/dev/null 2>&1
wp db query "UPDATE wp_mp_case_events SET created_at='2026-01-01 00:00:00' WHERE case_id=$CID_FAIL AND event_type IN ('MAIL_FAILED','MAIL_SENT')" >/dev/null 2>&1

[ "$(oznaczenie "$NR_FAIL")" = "NIE" ] \
	&& ok "przy identycznym czasie obu wpisow rozstrzyga KOLEJNOSC (oznaczenie zgaszone)" \
	|| bad "oznaczenie liczone z czasu — w tej samej sekundzie nie odroznia awarii od ponowki"

wp eval "MP\\Intake\\CaseEvents::log( $CID_FAIL, 'MAIL_FAILED', array( 'kind' => 'magic_link', 'error_code' => 'test' ), null );" >/dev/null 2>&1
wp db query "UPDATE wp_mp_case_events SET created_at='2026-01-01 00:00:00' WHERE case_id=$CID_FAIL AND event_type IN ('MAIL_FAILED','MAIL_SENT')" >/dev/null 2>&1

[ "$(oznaczenie "$NR_FAIL")" = "TAK" ] \
	&& ok "nowa awaria po ponowce znowu zapala oznaczenie (proba kontrolna)" \
	|| bad "oznaczenie nie zapala sie po kolejnej awarii — kontrola odwrotna padla"

# ── 4b. POTWIERDZENIE przy padnietej poczcie: prawda BEZ numeru sprawy ──────
# Numer SRV wychodzi wylacznie mailem albo panelem (krok 6 specyfikacji, pilnuje C3).
# Pierwsza wersja tej poprawki pokazywala numer na ekranie „skoro mail nie
# wyszedl" — i C3 od razu ja zlapal. Zmiana tamtej reguly to decyzja wlasciciela
# produktu, nie skutek uboczny naprawy komunikatu. Ta kontrola pilnuje obu rzeczy
# naraz: komunikat ma byc PRAWDZIWY, ale numer ma NIE wyciec.
JAR=$(mktemp)
TOKEN=$(wp eval "echo (string) MP\\Intake\\CaseRepo::regenerate_token( $CID_OK );" 2>/dev/null | tr -d '[:space:]')
curl -s -c "$JAR" -o /tmp/mp-2-1b-verify.html "$MP_BASE/wp-admin/admin-post.php?action=mp_intake_verify&token=$TOKEN"
VNONCE=$(grep -o 'name="_mp_nonce" value="[^"]*"' /tmp/mp-2-1b-verify.html | head -1 | sed 's/.*value="//;s/"//')
curl -s -c "$JAR" -b "$JAR" -H "X-MP-Test-Mail: fail" -o /tmp/mp-2-1b-confirm.html \
	--data-urlencode "action=mp_intake_verify_confirm" --data-urlencode "_mp_nonce=$VNONCE" \
	--data-urlencode "token=$TOKEN" \
	"$MP_BASE/wp-admin/admin-post.php"
rm -f "$JAR"

grep -q "nie wysz" /tmp/mp-2-1b-confirm.html \
	&& ok "potwierdzenie przy awarii poczty: klient slyszy, ze wiadomosc nie wyszla" \
	|| bad "potwierdzenie udaje, ze mail poszedl (to jest wada 2.1b)"

grep -q "SRV/" /tmp/mp-2-1b-confirm.html \
	&& bad "strona potwierdzenia ZDRADZA numer SRV (regula: numer tylko mailem/panelem)" \
	|| ok "numer sprawy NIE wyciekl na strone mimo awarii poczty"

VER=$(q "SELECT identity_status FROM wp_mp_service_cases WHERE id=$CID_OK")
[ "$VER" = "verified" ] \
	&& ok "sprawa potwierdzona mimo padnietej poczty (regresja zero)" \
	|| bad "awaria poczty zablokowala potwierdzenie sprawy (=$VER)"

rm -f /tmp/mp-2-1b-verify.html /tmp/mp-2-1b-confirm.html

# ── 5. BRAMKA: logowanie do panelu ma JEDEN komunikat, zaleznie od wyniku poczty ─
# To jedyna kontrola nie-behawioralna w tym tescie i tak jest zamierzona: chodzi
# o to, ZEBY KTOS TEGO NIE „NAPRAWIL" tak samo jak reszty. Osobny komunikat przy
# awarii pojawialby sie tylko dla adresow, ktore SA w bazie (mail idzie wylacznie
# dla istniejacego konta) — czyli dawalby sposob na sprawdzanie, kto jest klientem.
# Sciezka liczona z $0, bo w CI test chodzi z /tmp/wp, a nie z katalogu repo.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOGIN_PHP="$REPO/mp-service-intake/includes/Front/Login.php"

if [ -f "$LOGIN_PHP" ]; then
	ROZGALEZIENIA=$(grep -c "send_login_link" "$LOGIN_PHP")
	KOMUNIKATY=$(grep -c "back_with_notice( __( 'Jeśli konto istnieje" "$LOGIN_PHP")
	{ [ "$ROZGALEZIENIA" = "1" ] && [ "$KOMUNIKATY" = "1" ]; } \
		&& ok "logowanie: JEDEN komunikat niezalezny od wyniku wysylki (brak enumeracji kont)" \
		|| bad "logowanie: komunikat rozgalezil sie po wyniku poczty ($KOMUNIKATY komunikatow) — to oracle enumeracji"
else
	bad "nie znaleziono Login.php ($LOGIN_PHP) — bramka anty-enumeracyjna nie zostala sprawdzona"
fi

# ── SPRZATANIE ZE SPRAWDZENIEM ──────────────────────────────────────────────
# Testy w zadaniu e2e-import chodza JEDEN PO DRUGIM na TEJ SAMEJ bazie: stan
# zostawiony tutaj wywala test kilka pozycji dalej, w miejscu bez zwiazku ze
# zmiana. Sprzatanie BEZ kontroli jest zyczeniem, nie faktem — wiec sprawdzamy.
rm -f "$MU"
reset_all

[ ! -f "$MU" ] \
	&& ok "przelacznik poczty (mu-plugin) usuniety ze srodowiska" \
	|| bad "mu-plugin ZOSTAL ($MU) — nastepne testy beda mialy podmieniona poczte"

ZOSTALO=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "${ZOSTALO:-1}" = "0" ] \
	&& ok "zgloszenia testowe posprzatane (nastepny test nie policzy ich jako swoich)" \
	|| bad "zostawiamy $ZOSTALO spraw w bazie"

echo ""
echo "WYNIK 2.1b: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
