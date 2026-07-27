#!/usr/bin/env bash
# C28 — RODO art. 15: eksport MUSI oddac to, co o kliencie trzymamy.
#
# Znalezisko audytu 28.07: przy USUWANIU danych redagujemy pola formularza jako
# dane wrazliwe (opis usterki, numer dokumentu zakupu, numer seryjny), ale przy
# ZADANIU DOSTEPU ich nie eksportowalismy. Czyli sami uznajemy je za dane osobowe,
# a nie dajemy ich klientowi na zadanie — to niespojnosc, ktora widac dopiero, gdy
# porowna sie eraser z exporterem.
#
# Test pilnuje zasady: co redagujemy przy usuwaniu, to musi byc w eksporcie.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
ev()  { wp eval "$1" 2>/dev/null; }

EMAIL="eksport-c28-$$@example.com"
OPIS="Glosnik nie laczy sie przez Bluetooth po aktualizacji"
DOKUMENT="FV/C28/7788"
SERIAL="SN-C28-4321"

OUT=$(wp mp case-create --kind=reklamacja --email="$EMAIL" --name='Klient Eksport' \
      --serial="$SERIAL" --document="$DOKUMENT" --date='2026-05-05' --desc="$OPIS" 2>/dev/null)
TOK=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$TOK" >/dev/null 2>&1
[ -n "$TOK" ] && ok "seed: sprawa zalozona i potwierdzona" || bad "seed: nie udalo sie zalozyc sprawy"

EKSPORT=$(ev "\$w = MP\\Intake\\Privacy::export('$EMAIL');
	\$t = '';
	foreach ( (array) \$w['data'] as \$grupa ) {
		foreach ( (array) \$grupa['data'] as \$pole ) { \$t .= \$pole['name'] . '=' . \$pole['value'] . \"\n\"; }
	}
	echo \$t;")

# to, co juz dzialalo — straznik regresji
case "$EKSPORT" in *"$EMAIL"*) ok "eksport zawiera e-mail" ;; *) bad "eksport BEZ e-maila" ;; esac
case "$EKSPORT" in *"Klient Eksport"*) ok "eksport zawiera imie i nazwisko" ;; *) bad "eksport BEZ imienia" ;; esac
case "$EKSPORT" in *SRV/*) ok "eksport zawiera numer sprawy" ;; *) bad "eksport BEZ numeru sprawy" ;; esac

# rdzen tego testu: tresci z formularza
case "$EKSPORT" in *"$OPIS"*) ok "eksport zawiera OPIS USTERKI (tresc od klienta)" ;;
	*) bad "eksport BEZ opisu usterki — a przy usuwaniu go redagujemy" ;; esac
case "$EKSPORT" in *"$DOKUMENT"*) ok "eksport zawiera dokument zakupu" ;;
	*) bad "eksport BEZ dokumentu zakupu" ;; esac
case "$EKSPORT" in *"$SERIAL"*) ok "eksport zawiera numer seryjny" ;;
	*) bad "eksport BEZ numeru seryjnego" ;; esac

# Spojnosc eraser <-> exporter. UWAGA: przy AKTYWNEJ sprawie usuniecie jest
# ODRACZANE (obiecujemy to klientowi wprost), wiec najpierw zamykamy sprawe —
# inaczej test sprawdzalby odroczenie, a nie usuwanie.
CID=$(ev 'global $wpdb; echo (int) $wpdb->get_var("SELECT id FROM {$wpdb->prefix}mp_service_cases ORDER BY id DESC LIMIT 1");')
# Zamkniecie wprost przez repozytorium spraw — ten test sprawdza EKSPORT,
# nie panel admina (sciezke panelu pilnuja c26/c-case-actions).
ev "MP\\Intake\\CaseRepo::change_status($CID, 'zamknięte', 'nowe', 1, null);" >/dev/null
STATUS=$(ev "global \$wpdb; echo (string) \$wpdb->get_var(\"SELECT status FROM {\$wpdb->prefix}mp_service_cases WHERE id=$CID\");")
[ "$STATUS" = "zamknięte" ] && ok "sprawa zamknieta (warunek usuniecia danych)" || bad "nie zamknalem sprawy (status: $STATUS)"

WYNIK_ERASE=$(ev "\$w = MP\\Intake\\Privacy::erase('$EMAIL'); echo \$w['items_removed'] ? 'usuniete' : 'zatrzymane';")
[ "$WYNIK_ERASE" = "usuniete" ] && ok "eraser faktycznie usunal dane (sprawa zamknieta)" || bad "eraser nadal odracza ($WYNIK_ERASE)"
PO=$(ev "\$w = MP\\Intake\\Privacy::export('$EMAIL');
	\$t = '';
	foreach ( (array) \$w['data'] as \$grupa ) {
		foreach ( (array) \$grupa['data'] as \$pole ) { \$t .= \$pole['value'] . \"\n\"; }
	}
	echo \$t;")
case "$PO" in *"$OPIS"*) bad "po usunieciu danych opis usterki NADAL w eksporcie" ;;
	*) ok "po usunieciu danych tresci zniknely takze z eksportu" ;; esac

echo
echo "WYNIK C28: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
