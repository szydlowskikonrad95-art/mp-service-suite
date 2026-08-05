#!/usr/bin/env bash
# ZYWY DOWOD Z8 (polowanie 2026-08-05, druga fala S2): jeden wspolny komunikat
# odmowy „Z TEGO ADRESU wysłano zbyt wiele zgłoszeń" — takze gdy odbicie poszlo
# z limitu NUMERU SERYJNEGO albo LACZA (IP). Klient z niewinnym, swiezym adresem
# czytal, ze wina lezy w adresie: zmienial adres (nic nie dawalo) albo uznawal
# system za zepsuty. FIX: SubmissionHandler pyta RateLimit o ZAKRES blokady
# i mowi wlasciwym zdaniem (adres e-mail / numer seryjny / lacze).
#
# Kalibracja WBUDOWANA: asserty B1/B2 i C1/C2 PADAJA na kodzie sprzed naprawy
# (komunikat zawsze mowil „Z tego adresu"); sekcja A to kontrola kierunku —
# przy limicie ADRESU zdanie o adresie ma ZOSTAC.
# Wymaga MP_BASE. Chodzi na poligonie i w CI (jak c-s4-3-limit-zachowuje-formularz.sh).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

reset() {
	wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_attachments; DELETE FROM wp_mp_rate_counters" >/dev/null 2>&1
	wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_intake_ctx_%' OR option_name LIKE '_transient_timeout_mp_intake_ctx_%'" >/dev/null 2>&1
}

PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
NONCE=$(curl -s "$MP_BASE$PAGE_PATH" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "nonce formularza pobrany" || bad "brak nonce formularza"

# submit <email> <serial> [cookie]
submit() {
	local email="$1" serial="$2" cookie="${3:-}"
	local args=()
	[ -n "$cookie" ] && args+=( -b "mp_intake_sess=$cookie" )
	curl -s -o /dev/null "${args[@]}" \
		--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
		--data-urlencode "mp_ts=$(( $(date +%s) - 60 ))" \
		--data-urlencode "kind=reklamacja" --data-urlencode "email=$email" --data-urlencode "customer_name=Klient Testowy" \
		--data-urlencode "mp_consent=1" \
		--data-urlencode "serial=$serial" --data-urlencode "purchase_document=FV/1" \
		--data-urlencode "purchase_date=2026-03-15" \
		--data-urlencode "issue_description=opis usterki $email $serial" \
		"$MP_BASE/wp-admin/admin-post.php"
}

# notice <klucz-sesji> — komunikat z kontekstu PRG spod naszego ciasteczka.
notice() {
	wp eval "\$c = get_transient('mp_intake_ctx_$1'); echo is_array(\$c) ? (string) (\$c['notice'] ?? '') : 'NOCTX';" 2>/dev/null
}

# ── A. KONTROLA KIERUNKU: limit ADRESU (3/doba) — zdanie o adresie ma zostac ──
reset
submit 'z8-a@example.com' 'Z8-A-1'; submit 'z8-a@example.com' 'Z8-A-2'; submit 'z8-a@example.com' 'Z8-A-3'
CNT=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CNT" = "3" ] && ok "A0: 3 zgloszenia przyjete (limit adresu wyczerpany)" || bad "A0: spodziewane 3 sprawy, jest $CNT"
SESS_A="aaaa1111aaaa1111aaaa1111aaaa1111"
submit 'z8-a@example.com' 'Z8-A-4' "$SESS_A"
NA=$(notice "$SESS_A")
case "$NA" in
	*"tego adresu"*) ok "A1: przy limicie ADRESU komunikat mowi o adresie" ;;
	*) bad "A1: przy limicie adresu zniknelo zdanie o adresie: '$NA'" ;;
esac

# ── B. KALIBRACJA Z8: limit NUMERU SERYJNEGO (5/doba), 6. proba ze SWIEZEGO adresu ──
reset
for i in 1 2 3 4 5; do submit "z8-b$i@example.com" 'Z8-SN-LIMIT'; done
CNT=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CNT" = "5" ] && ok "B0: 5 zgloszen na jeden serial przyjete" || bad "B0: spodziewane 5 spraw, jest $CNT"
SESS_B="bbbb2222bbbb2222bbbb2222bbbb2222"
submit 'z8-b6-swiezy@example.com' 'Z8-SN-LIMIT' "$SESS_B"
CNT=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CNT" = "5" ] && ok "B0b: 6. proba odbita limitem seriala" || bad "B0b: limit seriala przepuscil 6. probe ($CNT)"
NB=$(notice "$SESS_B")
case "$NB" in
	*"tego adresu"*|*"Tego adresu"*) bad "B1: swiezy adres obwiniony za limit SERIALA: '$NB'" ;;
	*) ok "B1: komunikat nie zwala winy na niewinny adres" ;;
esac
case "$NB" in
	*"numer"*) ok "B2: komunikat wskazuje numer seryjny jako zakres blokady" ;;
	*) bad "B2: komunikat nie mowi, ze chodzi o numer seryjny: '$NB'" ;;
esac

# ── C. KALIBRACJA Z8: limit LACZA (IP, 10/10 min), 11. proba ─────────────────
reset
for i in 1 2 3 4 5 6 7 8 9 10; do submit "z8-c$i@example.com" "Z8-C-$i"; done
CNT=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CNT" = "10" ] && ok "C0: 10 zgloszen z jednego lacza przyjete" || bad "C0: spodziewane 10 spraw, jest $CNT"
SESS_C="cccc3333cccc3333cccc3333cccc3333"
submit 'z8-c11@example.com' 'Z8-C-11' "$SESS_C"
CNT=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$CNT" = "10" ] && ok "C0b: 11. proba odbita limitem lacza" || bad "C0b: limit lacza przepuscil 11. probe ($CNT)"
NC=$(notice "$SESS_C")
case "$NC" in
	*"tego adresu"*|*"Tego adresu"*) bad "C1: swiezy adres obwiniony za limit LACZA: '$NC'" ;;
	*) ok "C1: komunikat nie zwala winy na niewinny adres" ;;
esac
case "$NC" in
	*"łącza"*) ok "C2: komunikat wskazuje lacze jako zakres blokady" ;;
	*) bad "C2: komunikat nie mowi, ze chodzi o lacze: '$NC'" ;;
esac

# ── Wspolna czesc komunikatu ma przezyc rozroznienie zakresow ────────────────
case "$NB" in
	*"napisz wiadomość"*) ok "D1: wskazowka „napisz wiadomość przy sprawie” zostala (S4 #3 trzyma)" ;;
	*) bad "D1: rozroznienie zakresow zgubilo wskazowke co robic: '$NB'" ;;
esac

reset
echo "── Z8: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
