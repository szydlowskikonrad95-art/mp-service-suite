#!/usr/bin/env bash
# ZYWY DOWOD S4 #1: zaladunek wiekszy niz post_max_size NIE konczy sie biala
# pusta strona, tylko komunikatem o limicie na stronie formularza.
# Sprzed naprawy: admin-post.php bez akcji (PHP wyrzucil $_POST) => pusty hook
# => 0 bajtow tresci. Po naprawie: strażnik wraca na formularz z „przyjmuje pliki do N".
# Kalibracja WBUDOWANA: assert komunikatu pada na kodzie sprzed naprawy (brak kontekstu).
# Wymaga MP_BASE.
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

FORM_URL=$(wp eval 'echo get_permalink((int)get_option("mp_intake_form_page_id"));' 2>/dev/null)
PMAX=$(wp eval 'echo (int) wp_convert_hr_to_bytes((string) ini_get("post_max_size"));' 2>/dev/null)
[ -n "$FORM_URL" ] && ok "adres formularza: $FORM_URL" || bad "brak adresu formularza"

# Zabezpieczenie kosztu: przy absurdalnie duzym post_max_size nie generujemy gigabajtow.
if [ -z "$PMAX" ] || [ "$PMAX" -le 0 ] || [ "$PMAX" -gt 67108864 ]; then
	bad "post_max_size=$PMAX B poza zakresem testu (≤64 MB) — ustaw mniejszy na stanowisku"
	echo "── S4 #1: PASS=$PASS FAIL=$FAIL ──"; [ "$FAIL" -eq 0 ]; exit
fi

BIG=$(mktemp); head -c $(( PMAX + 1048576 )) /dev/zero | tr '\0' 'x' > "$BIG"   # o 1 MB ponad limit
SESS_OK="1a1a1a1a2b2b2b2b3c3c3c3c4d4d4d4d"
SESS_BAD="9z9z-nieistotny-obcy-referer-klucz"   # nie 32hex — i tak testujemy przez wynik

# ── Nasz formularz jako Referer: strażnik ma wrocic z komunikatem ──────────
CODE=$(curl -s -o /tmp/s4-1-body.txt -w "%{http_code}" -e "$FORM_URL" -b "mp_intake_sess=$SESS_OK" \
	-H "Content-Type: application/x-www-form-urlencoded" --data-binary "@$BIG" \
	"$MP_BASE/wp-admin/admin-post.php")
BODYLEN=$(wc -c < /tmp/s4-1-body.txt | tr -d ' ')
NOTICE=$(wp eval "\$c=get_transient('mp_intake_ctx_$SESS_OK'); echo is_array(\$c)?(\$c['notice']??''):''; delete_transient('mp_intake_ctx_$SESS_OK');" 2>/dev/null)

case "$NOTICE" in
	*"przyjmuje pliki do"*) ok "komunikat o limicie zamiast bialej strony (http=$CODE)" ;;
	*) bad "brak komunikatu o limicie (http=$CODE, body=${BODYLEN}B, notice='$NOTICE')" ;;
esac

# ── Obcy Referer: strażnik NIE przechwytuje (zostaje domyslna pustka) ──────
curl -s -o /dev/null -e "$MP_BASE/?nieistniejaca-obca-strona" -b "mp_intake_sess=1a1a1a1a2b2b2b2b3c3c3c3c4d4d4d4d" \
	-H "Content-Type: application/x-www-form-urlencoded" --data-binary "@$BIG" \
	"$MP_BASE/wp-admin/admin-post.php" >/dev/null
NOTICE2=$(wp eval "\$c=get_transient('mp_intake_ctx_1a1a1a1a2b2b2b2b3c3c3c3c4d4d4d4d'); echo is_array(\$c)?(\$c['notice']??''):'NIC'; delete_transient('mp_intake_ctx_1a1a1a1a2b2b2b2b3c3c3c3c4d4d4d4d');" 2>/dev/null)
[ "$NOTICE2" = "NIC" ] && ok "obcy Referer nie przechwycony (brak kontekstu)" || bad "strażnik przechwycil cudzy POST: '$NOTICE2'"

rm -f "$BIG"
echo "── S4 #1: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
