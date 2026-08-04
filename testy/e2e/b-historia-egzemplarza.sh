#!/usr/bin/env bash
# ZYWY DOWOD (2.38, czesc rejestru): historia egzemplarza jest HISTORIA, nie licznikiem.
#
# Kartka, plugin 2: „historia zmian danych produktu i decyzji gwarancyjnych".
# Do 1.3.12 dziennik `wp_mp_product_events` byl ZAPISYWANY I NIGDY NIECZYTANY —
# w calym produkcie nie bylo ani jednego SELECT-a z tej tabeli. Ekran poprawiania
# danych obiecywal wprost „zmiana zapisuje sie w historii produktu: kto, kiedy
# i co poprawil", a tej historii nie dalo sie nigdzie zobaczyc.
#
# Ten test pilnuje, ze:
#   1. czytnik historii oddaje WIERSZE (typ, payload, kto, kiedy), nie liczbe,
#   2. ekran historii pokazuje wartosc PRZED i PO oraz nazwe konta, nie samo ID,
#   3. numer faktury NIE trafia na ekran (PII — dziennik trzyma sam fakt zmiany),
#   4. decyzja gwarancyjna jest w historii, a jej uzasadnienie NIE,
#   5. archiwizacja nazywa sie archiwizacja, a nie „poprawiono dane produktu",
#   6. historie widzi PRACOWNIK, nie tylko administrator (prowadzi sprawe),
#   7. z listy rejestru jest wejscie do historii (inaczej dziennik nie ma drzwi),
#   8. egzemplarz bez zdarzen mowi to wprost, zamiast pokazywac pusta tabele.
#
# ⛔ ZAKRES: to zamyka historie egzemplarza po stronie REJESTRU. Druga polowa 2.38
# (duplikat ze wskazaniem sprawy + lista spraw produktu zamiast licznika) siedzi
# w module zgloszen i jest osobna pozycja — patrz opis PR.
#
# Wymaga zywego `wp`. Exit 0 = OK. Test sprzata po sobie (wspolna baza w CI).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

SERIAL='HIST-TEST-1'
NORM='HISTTEST1'
SERIAL2='HIST-TEST-2'
NORM2='HISTTEST2'

# Render ekranu tak, jak zobaczy go czlowiek: wywolujemy widok i lapiemy wyjscie.
# Mierzymy ZACHOWANIE EKRANU, nie obecnosc napisu w pliku zrodlowym.
ekran_historii() {
	wp eval "wp_set_current_user( $1 ); \$_GET = array( 'page' => 'mp-registry', 'historia' => $2 ); ob_start(); MP\\Registry\\Admin\\ProductsScreen::render(); echo ob_get_clean();" 2>/dev/null
}

sprzataj() {
	for N in "$NORM" "$NORM2"; do
		P=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$N';")
		if [ -n "$P" ]; then
			wp db query "DELETE FROM wp_mp_product_events WHERE product_registry_id=$P;" >/dev/null 2>&1
			wp db query "DELETE FROM wp_mp_warranty_exceptions WHERE product_registry_id=$P;" >/dev/null 2>&1
			wp db query "DELETE FROM wp_mp_product_registry WHERE id=$P;" >/dev/null 2>&1
		fi
	done
}

# Czysty stan na wejsciu — test idempotentny (moze isc kilka razy pod rzad).
sprzataj

ADM=$(wp user create hist_adm hist_adm@example.com --role=mp_system_admin --porcelain 2>/dev/null)
[ -z "$ADM" ] && ADM=$(wp user get hist_adm --field=ID 2>/dev/null | tr -d '[:space:]')
AGT=$(wp user create hist_agent hist_agent@example.com --role=mp_agent --porcelain 2>/dev/null)
[ -z "$AGT" ] && AGT=$(wp user get hist_agent --field=ID 2>/dev/null | tr -d '[:space:]')

wp db query "INSERT INTO wp_mp_product_registry
	(serial_display, serial_normalized, model, batch, category, purchase_document, purchase_date, warranty_until, source, archived, created_at, updated_at)
	VALUES ('$SERIAL','$NORM','Model-STARY','P-38','agd','FV/2026/380','2026-01-10','2027-01-10','csv_import',0,UTC_TIMESTAMP(),UTC_TIMESTAMP());" >/dev/null 2>&1
wp db query "INSERT INTO wp_mp_product_registry
	(serial_display, serial_normalized, model, batch, category, purchase_document, purchase_date, warranty_until, source, archived, created_at, updated_at)
	VALUES ('$SERIAL2','$NORM2','Model-BEZ-HISTORII','P-38','agd','FV/2026/381','2026-01-10','2027-01-10','csv_import',0,UTC_TIMESTAMP(),UTC_TIMESTAMP());" >/dev/null 2>&1

PID=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$NORM';")
PID2=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$NORM2';")

if [ -z "$PID" ] || [ -z "$PID2" ] || [ -z "$ADM" ] || [ -z "$AGT" ]; then
	bad "nie udalo sie przygotowac stanowiska (PID=$PID PID2=$PID2 ADM=$ADM AGT=$AGT)"
	sprzataj
	echo "WYNIK: $PASS ok, $FAIL fail"
	exit 1
fi

echo "== 0. ZALOZENIE: dziennik JEST zapisywany (bez tego test nie ma o czym mowic) =="
wp eval "MP\\Registry\\Repo::update( $PID, array('model'=>'Model-NOWY'), $ADM );" >/dev/null 2>&1
ZAPIS=$(q "SELECT COUNT(*) FROM wp_mp_product_events WHERE product_registry_id=$PID AND event_type='PRODUCT_UPDATED';")
[ "$ZAPIS" = "1" ] && ok "poprawka danych zostawila wpis w dzienniku" || bad "dziennik nie dostal wpisu ($ZAPIS) — zalozenie testu nieaktualne"

echo "== 1. CZYTNIK ODDAJE WIERSZE, NIE LICZBE =="
ILE=$(wp eval "echo count( MP\\Registry\\ProductEvents::history( $PID ) );" 2>/dev/null | tr -d '[:space:]')
[ "$ILE" = "1" ] && ok "history() zwrocilo 1 wiersz historii" || bad "history() zwrocilo '$ILE' (przed naprawa tej metody NIE BYLO — dziennik byl tylko zapisywany)"

TYP=$(wp eval "\$h = MP\\Registry\\ProductEvents::history( $PID ); echo \$h[0]['event_type'];" 2>/dev/null | tr -d '[:space:]')
[ "$TYP" = "PRODUCT_UPDATED" ] && ok "wiersz niesie typ zdarzenia ($TYP)" || bad "typ zdarzenia z historii: '$TYP'"

PRZED=$(wp eval "\$h = MP\\Registry\\ProductEvents::history( $PID ); echo \$h[0]['payload']['model']['before'];" 2>/dev/null | tr -d '[:space:]')
PO=$(wp eval "\$h = MP\\Registry\\ProductEvents::history( $PID ); echo \$h[0]['payload']['model']['after'];" 2>/dev/null | tr -d '[:space:]')
[ "$PRZED" = "Model-STARY" ] && [ "$PO" = "Model-NOWY" ] && ok "payload zdekodowany: '$PRZED' -> '$PO'" || bad "payload z historii: '$PRZED' -> '$PO'"

KTO=$(wp eval "\$h = MP\\Registry\\ProductEvents::history( $PID ); echo \$h[0]['actor_id'];" 2>/dev/null | tr -d '[:space:]')
[ "$KTO" = "$ADM" ] && ok "wiersz niesie autora zmiany (id=$KTO)" || bad "autor z historii: '$KTO' (oczekiwano $ADM)"

PUSTA=$(wp eval "echo count( MP\\Registry\\ProductEvents::history( 999999 ) );" 2>/dev/null | tr -d '[:space:]')
[ "$PUSTA" = "0" ] && ok "proba kontrolna: nieistniejacy produkt = 0 wierszy (pomiar nie zwraca czegokolwiek)" || bad "nieistniejacy produkt zwrocil '$PUSTA' wierszy"

echo "== 2. EKRAN POKAZUJE PRZED/PO I NAZWE KONTA =="
HTML=$(ekran_historii "$ADM" "$PID")
echo "$HTML" | grep -q 'Historia egzemplarza' && ok "ekran historii sie otwiera" || bad "ekran historii nie wyrenderowal sie (przed naprawa adres ?historia= pokazywal zwykla liste)"
echo "$HTML" | grep -q 'Model-STARY' && echo "$HTML" | grep -q 'Model-NOWY' \
	&& ok "ekran pokazuje wartosc PRZED i PO" || bad "ekran bez wartosci przed/po"
echo "$HTML" | grep -q 'hist_adm' && ok "ekran pokazuje KTO (nazwa konta, nie samo ID)" || bad "ekran nie pokazuje autora zmiany"
# ⚠️ Samo „Model" nie jest dowodem — lista rejestru tez ma kolumne Model i test
# przechodzil na kodzie SPRZED naprawy. Szukamy ksztaltu zdania z historii.
echo "$HTML" | grep -q 'Model: ' && ok "nazwa pola po polsku, nie klucz kolumny" || bad "brak czytelnej nazwy pola"

echo "== 3. PII NIE WYCHODZI NA EKRAN =="
wp eval "MP\\Registry\\Repo::update( $PID, array('purchase_document'=>'FV/TAJNA/380'), $ADM );" >/dev/null 2>&1
HTML=$(ekran_historii "$ADM" "$PID")
echo "$HTML" | grep -q 'TAJNA' && bad "PII WYCIEKLO na ekran historii" || ok "numer faktury nieobecny na ekranie"
echo "$HTML" | grep -q 'Dokument zakupu' && ok "sam FAKT zmiany dokumentu jest widoczny" || bad "zmiana dokumentu w ogole nie pokazana"

echo "== 4. DECYZJA GWARANCYJNA W HISTORII, UZASADNIENIE POZA NIA =="
WYJ=$(wp eval "wp_set_current_user( $ADM ); \$r = MP\\Registry\\WarrantyExceptions::create( $PID, null, 'Uzasadnienie-testowe-238', null ); echo isset( \$r['error'] ) ? 'ERR:'.\$r['error'] : 'OK';" 2>/dev/null)
case "$WYJ" in
	OK*) ok "wyjatek gwarancyjny nadany" ;;
	*)   bad "nie udalo sie nadac wyjatku ($WYJ)" ;;
esac
HTML=$(ekran_historii "$ADM" "$PID")
echo "$HTML" | grep -qi 'wyjątek gwarancyjny' && ok "decyzja gwarancyjna widoczna w historii" || bad "decyzja gwarancyjna nie trafila na ekran"
echo "$HTML" | grep -q 'Uzasadnienie-testowe-238' && bad "uzasadnienie wyjatku WYCIEKLO do historii" || ok "uzasadnienie poza dziennikiem (NO-PII-IN-LOG)"

echo "== 5. ARCHIWIZACJA NAZWANA PO LUDZKU =="
ARCH=$(wp eval "wp_set_current_user( $ADM ); \$r = MP\\Registry\\Archive::archive( $PID ); echo is_array( \$r ) ? 'ERR:'.\$r['error'] : 'OK';" 2>/dev/null)
case "$ARCH" in
	OK*) ok "produkt zarchiwizowany" ;;
	*)   bad "archiwizacja odmowiona ($ARCH)" ;;
esac
HTML=$(ekran_historii "$ADM" "$PID")
echo "$HTML" | grep -q 'Przeniesiono do archiwum' \
	&& ok "archiwizacja opisana jako archiwizacja, nie jako 'poprawiono dane'" \
	|| bad "archiwizacja pokazana jako zwykla poprawka danych"
wp eval "wp_set_current_user( $ADM ); MP\\Registry\\Archive::restore( $PID );" >/dev/null 2>&1

echo "== 6. HISTORIE WIDZI PRACOWNIK, NIE TYLKO ADMINISTRATOR =="
HTML_AGT=$(ekran_historii "$AGT" "$PID")
# ⚠️ „Model-NOWY" wystarczyloby ZA MALO: to wartosc BIEZACA, wiec widnieje takze
# na zwyklej liscie rejestru — sprawdzenie przechodzilo przed naprawa. Dowodem
# jest naglowek historii + wartosc PRZED zmiana, ktorej lista nie zna.
echo "$HTML_AGT" | grep -q 'Historia egzemplarza' && echo "$HTML_AGT" | grep -q 'Model-STARY' \
	&& ok "pracownik prowadzacy sprawe widzi historie egzemplarza" || bad "pracownik nie dostal historii"
echo "$HTML_AGT" | grep -q 'Popraw dane produktu' && bad "pracownik dostal link do edycji (to zostaje u administratora)" || ok "pracownik bez linku do edycji (uprawnienia nienaruszone)"

echo "== 7. Z LISTY REJESTRU JEST WEJSCIE DO HISTORII =="
LISTA=$(wp eval "wp_set_current_user( $AGT ); \$_GET = array( 'page' => 'mp-registry', 'f_serial' => '$SERIAL' ); ob_start(); MP\\Registry\\Admin\\ProductsScreen::render(); echo ob_get_clean();" 2>/dev/null)
echo "$LISTA" | grep -q "historia=$PID" && ok "lista rejestru prowadzi do historii egzemplarza" || bad "z listy nie ma drogi do historii (dziennik bez drzwi)"

echo "== 8. EGZEMPLARZ BEZ ZDARZEN MOWI TO WPROST =="
HTML2=$(ekran_historii "$ADM" "$PID2")
echo "$HTML2" | grep -q 'nie ma jeszcze żadnego wpisu' && ok "pusta historia opisana zdaniem, nie pusta tabela" || bad "brak komunikatu o pustej historii"

# Sprzatanie po sobie — wspolna baza w CI, smiec wywala cudzy test kilka pozycji dalej.
sprzataj
wp user delete "$ADM" --yes >/dev/null 2>&1
wp user delete "$AGT" --yes >/dev/null 2>&1

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
