#!/usr/bin/env bash
# ZYWY DOWOD #15 (formularz dynamiczny wg rodzaju) — warstwa SERWEROWA.
# Sprawdza to, czego e2e wczesniej NIE lapalo (skladalo POST z gotowym kind):
#  - render UNII pol: KAZDE pole (w tym return_reason ze zwrotu) jest w DOM od
#    razu (data-mp-field) — koniec dwuetapowego "wyslij->blad->pole sie pojawia";
#  - config dla JS (mpIntakeForm: kinds + allFields) + skrypt enqueue z ?ver;
#  - submit KAZDEGO rodzaju tylko jego polami tworzy sprawe: zapytanie=opis,
#    zwrot=serial+dokument+data+powod (return_reason), naprawa=serial+opis;
#  - regresja: pusta reklamacja nadal ODRZUCONA (serwer = zrodlo prawdy).
# Warstwa KLIENCKA (pokazywanie/ukrywanie pol w przegladarce) = dowod browser.
# Wymaga MP_BASE. Chodzi na poligonie i w CI (e2e-import).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

reset_all() {
	wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_consents;" >/dev/null 2>&1
	wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_rl%' OR option_name LIKE '_transient_timeout_mp_rl%'" >/dev/null 2>&1
}

PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
HTML=$(curl -s "$MP_BASE$PAGE_PATH")
NONCE=$(echo "$HTML" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "formularz pobrany + nonce" || bad "brak nonce/formularza"

# ── 1. Render UNII: KAZDE pole obecne w DOM (w tym return_reason ze zwrotu) ──
for K in serial purchase_document purchase_date issue_description return_reason; do
	if echo "$HTML" | grep -q "data-mp-field=\"$K\""; then
		ok "pole '$K' w DOM (data-mp-field)"
	else
		bad "pole '$K' BRAK w DOM (unia pol niepelna)"
	fi
done

# ── 2. Config dla JS + skrypt enqueue z wersja ──────────────────────────────
echo "$HTML" | grep -q 'mpIntakeForm' && ok "config mpIntakeForm w stronie (localize)" || bad "brak configu mpIntakeForm"
echo "$HTML" | grep -q 'return_reason' && ok "config niesie return_reason (zwrot)" || bad "config bez return_reason"
echo "$HTML" | grep -qE 'assets/js/intake-form\.js\?ver=' && ok "skrypt intake-form.js enqueue z ?ver" || bad "skrypt intake-form.js niezaenqueue'owany/bez ?ver"

# submit <kind> <extra-pola...> — wspolne: email, zgoda, czas OK.
submit() {
	local email="$1" kind="$2"; shift 2
	local args=( --data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE"
		--data-urlencode "mp_ts=$(( $(date +%s) - 60 ))" --data-urlencode "kind=$kind"
		--data-urlencode "email=$email" --data-urlencode "mp_consent=1" )
	local kv
	for kv in "$@"; do args+=( --data-urlencode "$kv" ); done
	curl -s -o /dev/null "${args[@]}" "$MP_BASE/wp-admin/admin-post.php"
}

# ── 3. ZAPYTANIE tylko z opisem => sprawa POWSTAJE (rdzen flagi #15) ─────────
reset_all
submit 'zapytanie@example.com' 'zapytanie' 'issue_description=Pytanie ogolne bez numeru seryjnego'
CZ=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CZ" = "1" ] && ok "ZAPYTANIE z samym opisem -> sprawa utworzona (bez serialu)" || bad "zapytanie nie utworzylo sprawy ($CZ)"

# ── 4. ZWROT z jego polami (w tym return_reason) => sprawa POWSTAJE 1. razem ─
reset_all
submit 'zwrot@example.com' 'zwrot' 'serial=ZWROTSER1' 'purchase_document=FV/2026/7' 'purchase_date=2026-03-10' 'return_reason=Nie pasuje rozmiar'
CW=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CW" = "1" ] && ok "ZWROT z powodem (return_reason) -> sprawa utworzona za 1. razem" || bad "zwrot nie utworzyl sprawy ($CW)"

# ── 5. NAPRAWA (serial+opis) => sprawa POWSTAJE ─────────────────────────────
reset_all
submit 'naprawa@example.com' 'naprawa' 'serial=NAPRSER1' 'issue_description=Nie wlacza sie'
CN=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CN" = "1" ] && ok "NAPRAWA (serial+opis) -> sprawa utworzona" || bad "naprawa nie utworzyla sprawy ($CN)"

# ── 6. REGRESJA: pusta reklamacja (bez wymaganych) nadal ODRZUCONA ──────────
reset_all
submit 'pusta@example.com' 'reklamacja' 'serial=' 'purchase_document=' 'purchase_date=' 'issue_description='
CP=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CP" = "0" ] && ok "regresja: pusta reklamacja ODRZUCONA (serwer = zrodlo prawdy)" || bad "pusta reklamacja przeszla mimo braku pol ($CP)"

# ── 7. REGRESJA: pelna reklamacja nadal dziala ──────────────────────────────
reset_all
submit 'reklama@example.com' 'reklamacja' 'serial=REKSER1' 'purchase_document=FV/2026/1' 'purchase_date=2026-03-01' 'issue_description=Usterka ekranu'
CR=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CR" = "1" ] && ok "regresja: pelna reklamacja -> sprawa utworzona" || bad "pelna reklamacja nie przeszla ($CR)"

echo
echo "WYNIK C-form-dynamic: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
