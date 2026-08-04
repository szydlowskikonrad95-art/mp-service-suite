#!/usr/bin/env bash
# ZYWY DOWOD 2.49: zmiana danych kontaktowych przez klienta zostawia slad w historii.
#
# BUG (audyt 2.49, waga drobna): panel klienta pozwala zmienic wlasna nazwe i telefon,
# i NIE zapisywal zadnego zdarzenia — w wykazie trzynastu typow nie bylo nic o kontakcie.
# Skutek praktyczny: serwis dzwonil pod numer, ktory klient w miedzyczasie zmienil,
# i nie mial jak ustalic, ze zmiana zaszla ani kiedy.
#
# ⚠️ CO PRODUKT ROBI DOBRZE (wieksza czesc tej pozycji): trzy najwazniejsze zdarzenia —
# status, przydzial, priorytet — nios juz wartosc STARA i NOWA. Tu rozciagamy sam
# FAKT zapisu, bez wartosci, bo tresc jest dana osobowa.
#
# ⛔ NO-PII: wpis niesie NAZWY POL, ktore sie zmienily, NIGDY numeru telefonu.
# Kontrola nr 4 pilnuje tego wprost — historia sprawy jest dziennikiem bez danych
# osobowych i naprawa jednej pozycji nie moze zlamac tej zasady.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

TELEFON_STARY='500100200'
TELEFON_NOWY='600300400'

# ⛔⛔ DLACZEGO TEN TEST PADAL — i dlaczego pierwsza diagnoza byla BLEDNA.
#
# Podejrzenie bylo takie, ze winne sa pozostalosci po poprzednich przebiegach
# (konto WordPressa z tym samym adresem). NIEPRAWDA. Przyczyna siedziala w tym
# pliku: zmienna nazywala sie `UID`, a `UID` jest w bashu TYLKO DO ODCZYTU.
# Przypisanie `UID=$(...)` nie przechodzi, powloka leci dalej, i w zmiennej
# zostaje identyfikator UZYTKOWNIKA POWLOKI (82 = www-data), a nie konto klienta.
# Test wolal wiec `wp eval --user=82` — obcego uzytkownika — panel nie mial czego
# zapisac i wynik wygladal na wade produktu.
#
# ⚠️ NAJGORSZE: kontrola gotowosci nizej swiecila wtedy na ZIELONO i meldowala
# „user=82", bo 82 jest liczba wieksza od zera. Numer wygladal wiarygodnie.
# Dlatego kontrola sprawdza teraz, czy konto ISTNIEJE w WordPressie i czy nalezy
# do naszej kartoteki — sam fakt, ze zmienna jest niepusta, nie dowodzi niczego.
#
# Unikalny adres i numer seryjny na przebieg ZOSTAJA — nie byly przyczyna, ale
# uniezalezniaja wynik od tego, co zostawil poprzedni (albo przerwany) przebieg.
STEMPEL="$$-$(date +%s)"
MAIL="kontakt-2-49-${STEMPEL}@example.com"
SERIAL="KONTAKT-${STEMPEL}"

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ⛔ WOLAMY PRAWDZIWY HANDLER PANELU KLIENTA, nie wlasna kopie jego logiki.
# Powtorzenie logiki w tescie mierzy sciagawke, a nie produkt: przeszloby nawet
# wtedy, gdyby panel nie zapisywal nic. Idziemy ta sama droga co klient — nonce,
# pola formularza, ten sam handler.
zmien_kontakt() {
	wp eval --user="$1" "
		\$_POST['_mp_nonce'] = wp_create_nonce( 'mp_intake_update_contact' );
		\$_POST['name']      = '$2';
		\$_POST['phone']     = '$3';
		\$_REQUEST           = \$_POST;
		MP\\Intake\\Front\\AccountPage::handle_update_contact();" >/dev/null 2>&1
}

CID=$(mkcase "$MAIL" "$SERIAL")

# Konto klienta zaklada produkt swoja metoda — wolamy JA, a nie tworzymy uzytkownika
# recznie: recznie zalozony nie bylby podpiety w kartotece i panel by go nie poznal.
KID=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CID")
wp eval "MP\\Intake\\Accounts::ensure_for_customer( $KID, '$MAIL' );" >/dev/null 2>&1

KLIENT_UID=$(q "SELECT wp_user_id FROM wp_mp_customers WHERE id = (SELECT customer_id FROM wp_mp_service_cases WHERE id=$CID)")
# ⛔ Kontrola gotowosci pyta WORDPRESSA, czy takie konto istnieje — nie poprzestaje
# na tym, ze zmienna jest niepusta i dodatnia. Wlasnie ta slabsza wersja przepuscila
# identyfikator powloki i kazala nam szukac wady w produkcie zamiast w tescie.
KONTO_ISTNIEJE=$(wp eval "echo get_userdata( $KLIENT_UID ) ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]')

{ [ -n "$CID" ] && [ "${KLIENT_UID:-0}" -gt 0 ] && [ "$KONTO_ISTNIEJE" = "tak" ]; } 2>/dev/null \
	&& ok "sprawa i konto klienta gotowe (case=$CID, user=$KLIENT_UID, istnieje w WP)" \
	|| bad "brak sprawy albo konta klienta (case=$CID user=$KLIENT_UID istnieje=$KONTO_ISTNIEJE)"

# ── 1. SEDNO: zmiana telefonu zostawia slad ────────────────────────────────
zmien_kontakt "$KLIENT_UID" "Klient Testowy" "$TELEFON_STARY"
wp db query "DELETE FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CONTACT_UPDATED'" >/dev/null 2>&1
zmien_kontakt "$KLIENT_UID" "Klient Testowy" "$TELEFON_NOWY"

SLAD=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CONTACT_UPDATED'")
[ "${SLAD:-0}" -ge 1 ] 2>/dev/null \
	&& ok "zmiana telefonu zostawila slad w historii sprawy" \
	|| bad "zmiana danych kontaktowych bez sladu (to jest wada 2.49)"

# ── 2. Slad mowi, CO sie zmienilo ─────────────────────────────────────────
PAYLOAD=$(q "SELECT payload FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CONTACT_UPDATED' ORDER BY id DESC LIMIT 1")
printf '%s' "$PAYLOAD" | grep -q "phone" \
	&& ok "slad mowi, ktore pole sie zmienilo (phone)" \
	|| bad "slad nie mowi, co sie zmienilo ($PAYLOAD)"

# ── 3. Zapis BEZ ZMIANY nie zasmieca historii ─────────────────────────────
PRZED=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CONTACT_UPDATED'")
zmien_kontakt "$KLIENT_UID" "Klient Testowy" "$TELEFON_NOWY"
PO=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CONTACT_UPDATED'")
[ "$PO" = "$PRZED" ] \
	&& ok "zapis formularza BEZ zmiany nie dokłada wpisu (historia nie puchnie od klikania)" \
	|| bad "kazde zapisanie formularza dokłada wpis ($PRZED -> $PO)"

# ── 4. NO-PII: w historii NIE MA numeru telefonu ──────────────────────────
# ⚠️ Najpierw upewniamy sie, ze wpis W OGOLE JEST. Sama kontrola „nie ma tu numeru"
# przechodzi tez wtedy, gdy nie ma ZADNEGO wpisu — czyli meldowalaby zachowana
# zasade NO-PII dokladnie w sytuacji, w ktorej produkt nie zapisuje nic.
if [ -z "$PAYLOAD" ]; then
	bad "brak wpisu do sprawdzenia — kontrola NO-PII nie ma czego badac"
else
	printf '%s' "$PAYLOAD" | grep -q "$TELEFON_NOWY" \
		&& bad "NUMER TELEFONU trafil do historii sprawy — zlamana zasada NO-PII w dzienniku" \
		|| ok "historia niesie nazwy pol, NIE wartosci (zasada NO-PII zachowana)"
fi

# ── 5. Pracownik widzi wpis PO POLSKU, nie surowy kod ────────────────────
# Nowy typ zdarzenia w CaseEvents to POLOWA roboty: karta sprawy ma osobna mape
# etykiet (Admin/CaseCard.php) i brak wpisu w NIEJ znaczy, ze na osi czasu swieci
# goly `CONTACT_UPDATED`. Dokladnie tak wygladala dziura C26 z `CASE_CREATED`.
# ⚠️ Kontrola idzie przez PRAWDZIWY RENDER karty, nie przez zajrzenie do mapy —
# sprawdzenie obecnosci klucza w tablicy przeszloby nawet wtedy, gdyby karta
# w ogole tej mapy nie uzywala.
KARTA=$(wp eval "wp_set_current_user(1); ob_start(); MP\\Intake\\Admin\\CaseCard::render($CID, 'mp-cases'); echo ob_get_clean();" 2>/dev/null)

printf '%s' "$KARTA" | grep -q 'CONTACT_UPDATED' \
	&& bad "os czasu pokazuje surowy kod CONTACT_UPDATED zamiast polskiej etykiety" \
	|| ok "os czasu nie pokazuje surowego kodu zdarzenia"

printf '%s' "$KARTA" | grep -q 'Zmiana danych kontaktowych' \
	&& ok "pracownik widzi wpis „Zmiana danych kontaktowych” na karcie sprawy" \
	|| bad "brak polskiej etykiety nowego zdarzenia na karcie sprawy"

# ── 6. SPRZATANIE ZE SPRAWDZENIEM ────────────────────────────────────────
wp db query "DELETE FROM wp_mp_case_events WHERE case_id=$CID; DELETE FROM wp_mp_service_cases WHERE id=$CID; DELETE FROM wp_mp_case_sla WHERE case_id=$CID;" >/dev/null 2>&1
[ -n "$KLIENT_UID" ] && wp user delete "$KLIENT_UID" --yes >/dev/null 2>&1
ZOSTALO=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id=$CID")
[ "${ZOSTALO:-1}" = "0" ] \
	&& ok "sprawa testowa i konto posprzatane" \
	|| bad "zostawiamy sprawe testowa"

echo ""
echo "WYNIK 2.49: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
