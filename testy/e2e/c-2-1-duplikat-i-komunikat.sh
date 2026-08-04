#!/usr/bin/env bash
# ZYWY DOWOD 2.1: ochrona przed duplikatem rozpoznaje TEN SAM sprzet, a odrzucone
# zgloszenie nie brzmi jak przyjete.
#
# BUG (audyt 2.1, waga srednia) — dwie odrebne wady w jednej pozycji:
#  (a) klucz duplikatu liczony byl z SUROWEGO numeru seryjnego (sam `trim()`),
#      wiec „SN-DUP-1001" i „sn dup1001" dawaly dwa rozne klucze i ochrone
#      obchodzilo sie jednym myslnikiem. Produkt MA gotowa normalizacje z
#      kontraktem autora (`Common\Str::normalize_serial`) — rejestr produktow
#      i walidator licza numer wlasnie nia, a instrukcja klienta obiecuje te
#      regule jako wlasciwosc systemu. Nie zostala uzyta tam, gdzie decyduje.
#  (b) po odrzuceniu klient slyszal „To zgloszenie wlasnie przyjelismy — sprawdz
#      skrzynke". Przy podwojnym kliknieciu nieszkodliwe. Bolalo, gdy w tym samym
#      oknie zglaszal INNA usterke tego samego sprzetu: sprawa nie powstawala,
#      a on byl pewien, ze powstala.
#
# FIX: normalizacja w JEDNYM gardle (klucz dedup + licznik dobowy per numer),
# komunikat mowi wprost, ze zgloszenia NIE przyjeto, i podaje, ile odczekac.
#
# ⛔ Kontrole 4 i 5 pilnuja, zeby naprawa nie blokowala za szeroko: inny rodzaj
# sprawy i inny sprzet maja przejsc. Bez nich „naprawa" mogla by po prostu
# odrzucac wszystko i test bylby zielony.
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
	# Pulapka nr 6 z briefingu: rezerwacja dedup zyje 15 minut i przy powtorce
	# testu daje falszywe „sprawa nie powstala".
	wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_rl%' OR option_name LIKE '_transient_timeout_mp_rl%'; DELETE FROM wp_mp_rate_counters" >/dev/null 2>&1
	wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
}

reset_all

PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null | tr -d '[:space:]')
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | tr -d '[:space:]' | sed 's#^https\?://[^/]*##')
NONCE=$(curl -s "$MP_BASE$PAGE_PATH" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "nonce formularza pobrany" || bad "brak nonce formularza"

# submit <rodzaj> <email> <serial> -> zdanie, KTORE KLIENT WIDZI na stronie.
# Sloik ciastek: komunikat wraca kontekstem zapietym na ciastko sesji, nie w adresie.
# Wysylamy pola WSZYSTKICH rodzajow naraz (opis usterki I powod zwrotu) — kazdy
# rodzaj ma inny zestaw wymaganych pol, a formularz bierze tylko swoje. Bez tego
# kontrola „inny rodzaj przechodzi" padala na WALIDACJI i wygladala jak duplikat.
submit() {
	local kind="$1" email="$2" serial="$3"
	local jar
	jar=$(mktemp)
	curl -s -L -c "$jar" -b "$jar" -H "Referer: $MP_BASE$PAGE_PATH" \
		--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
		--data-urlencode "mp_ts=$(( $(date +%s) - 60 ))" \
		--data-urlencode "kind=$kind" --data-urlencode "email=$email" --data-urlencode "customer_name=Klient Testowy" \
		--data-urlencode "mp_consent=1" \
		--data-urlencode "serial=$serial" --data-urlencode "purchase_document=FV/1" \
		--data-urlencode "purchase_date=2026-03-15" --data-urlencode "issue_description=usterka" \
		--data-urlencode "return_reason=nie odpowiada opisowi" \
		"$MP_BASE/wp-admin/admin-post.php" \
		| grep -o 'class="mp-intake-notice"[^>]*>[^<]*' | sed 's/.*>//' | tr -d '\r\n'
	rm -f "$jar"
}

# ── 1. Pierwsze zgloszenie przechodzi (przypadek kontrolny) ──────────────────
NOTICE_1=$(submit reklamacja 'dup-2-1@example.com' 'SN-DUP-1001')
C1=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$C1" = "1" ] && ok "pierwsze zgloszenie przyjete (sprawa powstala)" || bad "pierwsze zgloszenie nie przeszlo (spraw: $C1)"

# ── 2. TEN SAM sprzet, inny ZAPIS numeru => duplikat ─────────────────────────
# To jest sedno (a): przed naprawa powstawala DRUGA sprawa.
NOTICE_2=$(submit reklamacja 'dup-2-1@example.com' 'sn dup1001')
C2=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$C2" = "1" ] \
	&& ok "inny zapis tego samego numeru rozpoznany jako duplikat (spraw nadal 1)" \
	|| bad "ochrone obeszlo spacja/myslnik — powstalo $C2 spraw (to jest wada 2.1a)"

# ── 3. Komunikat odrzucenia NIE brzmi jak przyjecie ──────────────────────────
[ -n "$NOTICE_2" ] && [ "$NOTICE_2" != "$NOTICE_1" ] \
	&& ok "odrzucenie brzmi INACZEJ niz przyjecie" \
	|| bad "odrzucenie brzmi tak samo jak przyjecie (to jest wada 2.1b)"

printf '%s' "$NOTICE_2" | grep -q "NIE przy" \
	&& ok "komunikat mowi wprost, ze zgloszenia NIE przyjeto" \
	|| bad "komunikat nie mowi, ze zgloszenie odpadlo ($NOTICE_2)"

# Liczba minut z KODU (nie wpisana w test) — inaczej zmiana okna dedup rozjedzie
# komunikat z rzeczywistoscia, a test tego nie zauwazy.
MIN=$(wp eval 'echo MP\Intake\RateLimit::dedup_minutes();' 2>/dev/null | tr -d '[:space:]')
printf '%s' "$NOTICE_2" | grep -q "$MIN" \
	&& ok "komunikat podaje, ile odczekac ($MIN min — liczba z kodu, nie z testu)" \
	|| bad "komunikat nie podaje okna dedup ($MIN)"

# ── 4. KONTROLA: ten sam sprzet, INNY rodzaj sprawy => ma przejsc ────────────
# Klucz to e-mail + numer + RODZAJ. Gdyby naprawa blokowala po samym numerze,
# klient nie zglosilby zwrotu tego samego sprzetu.
submit zwrot 'dup-2-1@example.com' 'SN-DUP-1001' >/dev/null
C3=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$C3" = "2" ] \
	&& ok "inny rodzaj sprawy na tym samym sprzecie przechodzi (brak nadgorliwej blokady)" \
	|| bad "naprawa blokuje za szeroko — inny rodzaj odrzucony (spraw: $C3)"

# ── 5. KONTROLA: INNY sprzet => ma przejsc ──────────────────────────────────
submit reklamacja 'dup-2-1-inny@example.com' 'SN-INNY-2002' >/dev/null
C4=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$C4" = "3" ] \
	&& ok "inny numer seryjny przechodzi (normalizacja nie sklaja roznych sprzetow)" \
	|| bad "inny sprzet odrzucony jako duplikat (spraw: $C4)"

# ── 6. Licznik dobowy per numer liczony po ZNORMALIZOWANYM numerze ──────────
# Ta sama luka, druga furtka: limit „5 zgloszen na numer na dobe" tez obchodzilo
# sie myslnikiem. Sprawdzamy stan w bazie, a klucz liczymy tak jak produkt.
KLUCZ=$(wp eval 'echo "mp_rl_sn_" . md5( MP\Intake\Common\Str::normalize_serial( "SN-DUP-1001" ) );' 2>/dev/null | tr -d '[:space:]')
HITS=$(q "SELECT hits FROM wp_mp_rate_counters WHERE rl_key='$KLUCZ'")
[ -n "$HITS" ] \
	&& ok "licznik dobowy zapisany pod znormalizowanym numerem (hits=$HITS)" \
	|| bad "brak licznika pod znormalizowanym numerem — limit dobowy da sie obejsc zapisem"

KLUCZ_SUROWY=$(wp eval 'echo "mp_rl_sn_" . md5( "SN-DUP-1001" );' 2>/dev/null | tr -d '[:space:]')
SUROWY=$(q "SELECT COUNT(*) FROM wp_mp_rate_counters WHERE rl_key='$KLUCZ_SUROWY'")
{ [ "$KLUCZ" = "$KLUCZ_SUROWY" ] || [ "$SUROWY" = "0" ]; } \
	&& ok "licznik NIE zostaje pod surowym zapisem numeru" \
	|| bad "licznik nadal siedzi pod surowym numerem (naprawa polowiczna)"

reset_all

echo ""
echo "WYNIK 2.1: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
