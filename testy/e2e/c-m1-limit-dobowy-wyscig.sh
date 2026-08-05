#!/usr/bin/env bash
# ZYWY DOWOD M1 (recenzja zewnetrzna 1.3.12 — dobowy limit zgloszen obchodliwy wyscigiem):
# `RateLimit::check()` TYLKO CZYTAL licznik e-mail/serial, a inkrement szedl dopiero
# po utworzeniu sprawy (`record_submission`). Miedzy odczytem a zapisem miescil sie
# drugi POST: dwa rownolegle zgloszenia widzialy „2 z 3 wykorzystane" i OBA przechodzily.
# Limit dany klientowi na pismie („3 zgloszenia na dobe") konczyl sie czterema sprawami.
# Po naprawie: ATOMOWA rezerwacja (`reserve_submission`) — inkrement i sprawdzenie w JEDNYM
# zapisie, przed utworzeniem sprawy; kto przekroczyl, oddaje trafienie i dostaje odmowe.
# Semantyka D5 zachowana: odrzucona walidacja ODDAJE miejsce (limit niezjedzony).
#
# KALIBRACJA (kod sprzed naprawy): scenariusz B tworzy 2-6 spraw zamiast 1.
# Wymaga MP_BASE. Chodzi na poligonie i w CI.
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

STEMPEL=$(date +%s)
MAIL="wyscig-limit-$STEMPEL@example.com"

# Klucz licznika dobowego adresu — liczony TA SAMA funkcja co produkcja (plus-adresowanie).
klucz_maila() { wp eval "echo 'mp_rl_em_' . md5( MP\\Intake\\RateLimit::normalize_email_for_key( '$1' ) );" 2>/dev/null | tr -d '[:space:]'; }

# Zajmuje N miejsc w limicie CZYSTYM SQL-em, bez API wtyczki. Dzieki temu przygotowanie
# sceny dziala TAK SAMO na kodzie sprzed naprawy (kalibracja) i po niej, i nie ustawia
# przy okazji markera dedupu (ten sklejalby rownolegle POST-y i zamaskowal dziure).
zajmij_miejsca() {
	wp db query "INSERT INTO wp_mp_rate_counters (rl_key, hits, window_expires_at)
		VALUES ('$(klucz_maila "$1")', $2, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 1 DAY))
		ON DUPLICATE KEY UPDATE hits = $2, window_expires_at = DATE_ADD(UTC_TIMESTAMP(), INTERVAL 1 DAY);" >/dev/null 2>&1
}

wp db query "DELETE FROM wp_mp_rate_counters;" >/dev/null 2>&1

# ── Scenariusz A: rezerwacja jest ATOMOWA (API) ──────────────────────────────
# Limit e-mail = 3/dobe. Trzy rezerwacje przechodza, czwarta odbija.
for i in 1 2 3; do
	R=$(wp eval "var_export( null === MP\\Intake\\RateLimit::reserve_submission( '$MAIL', '' ) );" 2>/dev/null)
	[ "$R" = "true" ] || bad "rezerwacja $i z 3 odrzucona ($R)"
done
[ "$FAIL" -eq 0 ] && ok "trzy rezerwacje w dobie przyznane (limit 3/doba)"

R4=$(wp eval "echo (string) MP\\Intake\\RateLimit::reserve_submission( '$MAIL', '' );" 2>/dev/null | tr -d '[:space:]')
[ "$R4" = "email" ] && ok "czwarta rezerwacja ODRZUCONA i wskazuje zakres 'email'" || bad "czwarta rezerwacja przeszla albo zly zakres ($R4)"

# Odrzucona proba NIE moze podbic licznika (inaczej odmowa zjadalaby limit).
HITS=$(q "SELECT hits FROM wp_mp_rate_counters WHERE rl_key = '$(wp eval "echo 'mp_rl_em_' . md5( MP\\Intake\\RateLimit::normalize_email_for_key( '$MAIL' ) );" 2>/dev/null | tr -d '[:space:]')'")
[ "$HITS" = "3" ] && ok "licznik po odrzuconej probie nadal 3 (proba oddana)" || bad "licznik po odmowie = $HITS (oczekiwane 3)"

# D5: zwolnienie miejsca po odrzuconym zgloszeniu wraca do puli.
wp eval "MP\\Intake\\RateLimit::release_submission( '$MAIL', '' );" >/dev/null 2>&1
R5=$(wp eval "var_export( null === MP\\Intake\\RateLimit::reserve_submission( '$MAIL', '' ) );" 2>/dev/null)
[ "$R5" = "true" ] && ok "po oddaniu miejsca (blad walidacji) rezerwacja znow dostepna — D5" || bad "oddane miejsce nie wrocilo do puli ($R5)"

# ── Scenariusz B: PRAWDZIWY wyscig — 6 rownoleglych POST-ow na JEDEN wolny slot ──
MAIL_B="wyscig-http-$STEMPEL@example.com"
wp db query "DELETE FROM wp_mp_service_cases WHERE pending_email LIKE 'wyscig-http-%'; DELETE FROM wp_mp_rate_counters;" >/dev/null 2>&1

# Zuzywamy 2 z 3 miejsc, zeby zostalo DOKLADNIE JEDNO.
zajmij_miejsca "$MAIL_B" 2

PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
SITE_HOST=$(wp option get home 2>/dev/null | sed 's#^https\?://##;s#/.*##')
HOSTHDR=(); [ -n "$SITE_HOST" ] && HOSTHDR=(-H "Host: $SITE_HOST")
HTML=$(curl -s "${HOSTHDR[@]}" "$MP_BASE$PAGE_PATH")
NONCE=$(echo "$HTML" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "nonce formularza pobrany" || bad "brak nonce formularza"

TS=$(( $(date +%s) - 60 ))
# ⛔ KAZDY POST MA WLASNY NUMER SERYJNY. Klucz dedupu to (serial|adres|rodzaj), wiec
# przy wspolnym numerze atomowa rezerwacja dedupu przepuscilaby jeden POST i test
# swiecilby na zielono TAKZE na kodzie z dziura (sprawdzone — tak wlasnie bylo).
# Rozne numery => dedup nie ma nic do gadania i o wyniku decyduje WYLACZNIE limit
# dobowy adresu. Rodzaj „reklamacja", bo tylko on zbiera numer seryjny.
for i in 1 2 3 4 5 6; do
	curl -s "${HOSTHDR[@]}" -o /dev/null \
		--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
		--data-urlencode "mp_ts=$TS" \
		--data-urlencode "kind=reklamacja" --data-urlencode "email=$MAIL_B" \
		--data-urlencode "customer_name=Klient Testowy" \
		--data-urlencode "serial=WYSCIG-$STEMPEL-$i" \
		--data-urlencode "purchase_document=FV/$STEMPEL/$i" \
		--data-urlencode "purchase_date=2026-03-15" \
		--data-urlencode "issue_description=rownolegle zgloszenie numer $i" \
		--data-urlencode "mp_consent=1" \
		"$MP_BASE/wp-admin/admin-post.php" &
done
wait

ILE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE pending_email = '$MAIL_B'")
[ "$ILE" = "1" ] && ok "6 rownoleglych POST-ow na 1 wolne miejsce => DOKLADNIE 1 sprawa" \
	|| bad "rownolegle POST-y stworzyly $ILE spraw (oczekiwana 1) — limit dobowy przekroczony"

# Licznik po burzy = dokladnie limit (odrzucone proby oddaly swoje trafienia).
HITS_B=$(q "SELECT hits FROM wp_mp_rate_counters WHERE rl_key = '$(wp eval "echo 'mp_rl_em_' . md5( MP\\Intake\\RateLimit::normalize_email_for_key( '$MAIL_B' ) );" 2>/dev/null | tr -d '[:space:]')'")
[ "$HITS_B" = "3" ] && ok "licznik po burzy = 3 (nie rozjechal sie ponad limit)" || bad "licznik po burzy = $HITS_B (oczekiwane 3)"

# ── Scenariusz C: odmowa mowi TYM SAMYM zdaniem co przed naprawa ─────────────
# Komunikaty sa czescia umowy z klientem (S4 #3 / Z8): odmowa ma powiedziec, KTORY
# zakres blokuje i KIEDY znow mozna, i NIE MOZE wyczyscic formularza. Naprawa M1
# zmienia moment ksiegowania limitu, nie to, co widzi czlowiek — wiec sprawdzamy
# wyrenderowana strone, a nie tylko kod odpowiedzi.
# Kontekst PRG idzie transientem pod ciasteczkiem sesji i KASUJE SIE PRZY ODCZYCIE,
# wiec nonce pobieramy PRZED odmowa, a strone czytamy DOKLADNIE RAZ po niej.
MAIL_C="wyscig-msg-$STEMPEL@example.com"
JAR=$(mktemp)
NONCE_C=$(curl -s -c "$JAR" "${HOSTHDR[@]}" "$MP_BASE$PAGE_PATH" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
zajmij_miejsca "$MAIL_C" 3

curl -s -c "$JAR" -b "$JAR" "${HOSTHDR[@]}" -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE_C" \
	--data-urlencode "mp_ts=$TS" \
	--data-urlencode "kind=zapytanie" --data-urlencode "email=$MAIL_C" \
	--data-urlencode "customer_name=Klient Testowy" \
	--data-urlencode "issue_description=opis po wyczerpaniu limitu" \
	--data-urlencode "mp_consent=1" \
	"$MP_BASE/wp-admin/admin-post.php"

STRONA=$(curl -s -b "$JAR" "${HOSTHDR[@]}" "$MP_BASE$PAGE_PATH")
rm -f "$JAR"

echo "$STRONA" | grep -q "Z tego adresu e-mail wysłano zbyt wiele zgłoszeń" \
	&& ok "odmowa obwinia WLASCIWY zakres (adres e-mail) — Z8" || bad "brak/zly komunikat odmowy na stronie"
echo "$STRONA" | grep -q "Kolejne zgłoszenie z tego adresu wyślesz po" \
	&& ok "odmowa mowi, KIEDY znow mozna — S4 #3" || bad "komunikat nie podaje momentu powrotu"
echo "$STRONA" | grep -q "opis po wyczerpaniu limitu" \
	&& ok "odmowa NIE czysci formularza (opis wraca do pola)" || bad "odmowa zgubila wpisane dane"

ILE_C=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE pending_email = '$MAIL_C'")
[ "$ILE_C" = "0" ] && ok "zgloszenie po wyczerpaniu limitu NIE utworzylo sprawy" || bad "sprawa powstala mimo limitu ($ILE_C)"

# ── Sprzatanie: sprawy i liczniki tego testu ────────────────────────────────
wp db query "DELETE FROM wp_mp_consents WHERE email LIKE 'wyscig-%@example.com';
	DELETE FROM wp_mp_service_cases WHERE pending_email LIKE 'wyscig-%@example.com';
	DELETE FROM wp_mp_rate_counters;" >/dev/null 2>&1

echo
echo "WYNIK M1: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
