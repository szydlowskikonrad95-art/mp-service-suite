#!/usr/bin/env bash
# Sciezka klienta na CZYSTYM WP (PHP 8.1 / MySQL 8), instalacja wylacznie z paczki.
# Wszystko przez HTTP jak u kolegi; DB tylko do ODCZYTU wyniku (wp eval, nie wp db query
# — klient mysql w tym obrazie nie dogaduje sie po TLS z MySQL 8, to sprawa harnessu).
set -u
BASE="http://localhost:8097"
MAILPIT="http://localhost:8098"
COMPOSE="$(cd "$(dirname "$0")" && pwd)/compose.yml"
JAR="$(mktemp)"; ADMJAR="$(mktemp)"
HASLO="${MP_TEST_HASLO:-$(cat "$(dirname "$0")/paczka/.haslo" 2>/dev/null)}"
[ -n "$HASLO" ] || { echo "BRAK hasla — ustaw MP_TEST_HASLO albo odpal uruchom.sh"; exit 2; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
W()   { docker compose -p mpzero -f "$COMPOSE" exec -T cli wp --path=/var/www/html "$@" 2>/dev/null; }
ev()  { W eval "$1" | tr -d '\r'; }

EMAIL="jan.kowalski+$(date +%s)@przyklad.pl"

echo "== 1. Formularz na stronie utworzonej przy aktywacji =="
PAGE_ID="$(W option get mp_intake_form_page_id | tr -d '\r')"
PAGE_URL="$(W post url "$PAGE_ID" | tr -d '\r')"
HTML="$(curl -s -c "$JAR" "$PAGE_URL")"
echo "$HTML" | grep -q 'name="action" value="mp_intake_submit"' && ok "formularz renderuje sie ($PAGE_URL)" || bad "brak formularza pod $PAGE_URL"
NONCE=$(echo "$HTML" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "nonce formularza obecny" || bad "brak nonce"

echo "== 2. Klient wysyla reklamacje =="
# Kategoria AGD wymaga zalacznika (kartka P1.2: „wymagane pola i zalaczniki
# zalezne od wybranej kategorii produktu"), wiec zgloszenie idzie jak
# z przegladarki: multipart ze zdjeciem tabliczki znamionowej.
ZDJECIE="$(mktemp /tmp/tabliczka-XXXXXX.jpg)"
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00' > "$ZDJECIE"
head -c 3000 /dev/zero | tr '\0' 'x' >> "$ZDJECIE"
printf '\xff\xd9' >> "$ZDJECIE"

wyslij_zgloszenie() { # $1=plik zalacznika (pusty = bez zalacznika)
  local plik="${1:-}" args
  args=(-F "action=mp_intake_submit" -F "_mp_nonce=$NONCE"
        -F "mp_ts=$(( $(date +%s) - 60 ))" -F "mp_hp="
        -F "kind=reklamacja" -F "email=$EMAIL"
        -F "category=agd" -F "cat_agd_model=Robot MX-200"
        -F "serial=SN-TEST-0001" -F "purchase_document=FV/2026/07/11"
        -F "purchase_date=2026-03-15"
        -F "issue_description=Urzadzenie nie wlacza sie po tygodniu uzytkowania."
        -F "mp_consent=1")
  [ -n "$plik" ] && args+=(-F "mp_files[]=@$plik")
  curl -s -b "$JAR" -c "$JAR" -e "$PAGE_URL" -o /dev/null "${args[@]}" "$BASE/wp-admin/admin-post.php"
}

# Kontrola reguly: TA SAMA tresc bez zalacznika NIE moze zalozyc sprawy.
wyslij_zgloszenie ""
CNT0=$(ev 'global $wpdb; echo (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->prefix}mp_service_cases");')
[ "${CNT0:-0}" -eq 0 ] && ok "AGD bez zalacznika odrzucone (wymog z kartki dziala)" \
  || bad "AGD bez zalacznika zalozylo sprawe — wymog zalacznika NIE dziala"

wyslij_zgloszenie "$ZDJECIE"
rm -f "$ZDJECIE"
CNT=$(ev 'global $wpdb; echo (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->prefix}mp_service_cases");')
[ "${CNT:-0}" -ge 1 ] && ok "zgloszenie z zalacznikiem zapisane w bazie (spraw: $CNT)" || bad "zgloszenie NIE zapisane"

echo "== 3. Mail z linkiem potwierdzajacym (skrzynka klienta) =="
sleep 2
MSG=$(curl -s "$MAILPIT/api/v1/messages" | python3 -c "import sys,json;d=json.load(sys.stdin);print(json.dumps(d.get('messages',[])[0]) if d.get('messages') else '')" 2>/dev/null)
[ -n "$MSG" ] && ok "mail wyszedl: $(echo "$MSG" | python3 -c 'import sys,json;print(json.load(sys.stdin)["Subject"])')" || bad "zaden mail nie doszedl"
MID=$(echo "$MSG" | python3 -c 'import sys,json;print(json.load(sys.stdin)["ID"])' 2>/dev/null)
TRESC=$(curl -s "$MAILPIT/api/v1/message/$MID" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("Text") or d.get("HTML") or "")' 2>/dev/null)
LINK=$(echo "$TRESC" | grep -oE 'https?://[^ "<]*mp_intake_verify[^ "<]*' | head -1 | sed 's/&amp;/&/g' | tr -d '\r')
[ -n "$LINK" ] && ok "link potwierdzajacy w mailu" || bad "brak linku potwierdzajacego w tresci maila"

echo "== 4. Klient klika link, potem przycisk Potwierdzam =="
# GET z maila NIE potwierdza (poprawnie — GET nie zmienia stanu); pokazuje strone z przyciskiem.
POTW=$(curl -s -b "$JAR" -c "$JAR" -w '\nHTTP:%{http_code}' "$LINK")
echo "$POTW" | grep -q 'HTTP:200' && ok "strona potwierdzenia odpowiada 200" || bad "potwierdzenie: $(echo "$POTW" | tail -1)"
echo "$POTW" | grep -q 'name="action" value="mp_intake_verify_confirm"' && ok "GET z maila nie zmienia stanu — jest przycisk do klikniecia" || bad "brak formularza potwierdzenia"
VNONCE=$(echo "$POTW" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
VTOKEN=$(echo "$POTW" | grep -o 'name="token" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
KLIK=$(curl -s -b "$JAR" -c "$JAR" -L -w '\nHTTP:%{http_code}' \
  --data-urlencode "action=mp_intake_verify_confirm" --data-urlencode "token=$VTOKEN" \
  --data-urlencode "_mp_nonce=$VNONCE" "$BASE/wp-admin/admin-post.php")
echo "$KLIK" | grep -q 'HTTP:200' && ok "klikniecie Potwierdzam odpowiada 200" || bad "Potwierdzam: $(echo "$KLIK" | tail -1)"
UZYTY=$(ev 'global $wpdb; echo (string) $wpdb->get_var("SELECT verify_token_used_at FROM {$wpdb->prefix}mp_service_cases ORDER BY id DESC LIMIT 1");')
[ -n "$UZYTY" ] && ok "zgloszenie potwierdzone (token zuzyty $UZYTY)" || bad "po klikniecu Potwierdzam sprawa NADAL niepotwierdzona"
STATUS=$(ev 'global $wpdb; $r=$wpdb->get_row("SELECT status, identity_status FROM {$wpdb->prefix}mp_service_cases ORDER BY id DESC LIMIT 1"); echo $r->status."/".$r->identity_status;')
SRV=$(ev 'global $wpdb; echo (string) $wpdb->get_var("SELECT case_number FROM {$wpdb->prefix}mp_service_cases ORDER BY id DESC LIMIT 1");')
[ -n "$SRV" ] && ok "numer sprawy nadany: $SRV (status: $STATUS)" || bad "brak numeru sprawy po potwierdzeniu"
echo "$SRV" | grep -qE '^SRV/[0-9]{4}/[0-9]{4}$' && ok "format numeru zgodny z kartka klienta: SRV/RRRR/NNNN" || bad "format numeru NIEZGODNY z kartka: $SRV"

echo "== 4b. Drugi mail: numer sprawy =="
sleep 3
MAILE=$(curl -s "$MAILPIT/api/v1/messages" | python3 -c 'import sys,json;print("|".join(m["Subject"] for m in json.load(sys.stdin)["messages"]))')
[ "$(echo "$MAILE" | tr '|' '\n' | wc -l)" -ge 2 ] && ok "drugi mail wyszedl (skrzynka: $MAILE)" || bad "brak drugiego maila po potwierdzeniu (skrzynka: $MAILE)"

echo "== 5. Panel administratora (logowanie jak kolega) =="
curl -s -c "$ADMJAR" -o /dev/null --data-urlencode "log=szef" --data-urlencode "pwd=$HASLO" \
  --data-urlencode "wp-submit=Zaloguj" --data-urlencode "redirect_to=$BASE/wp-admin/" --data-urlencode "testcookie=1" \
  "$BASE/wp-login.php"
grep -q 'wordpress_logged_in' "$ADMJAR" && ok "zalogowany do panelu" || bad "logowanie do panelu nieudane"
sprawdz_ekran() { # $1=url  $2=nazwa  $3=czego szukam
  local out code
  out=$(curl -s -b "$ADMJAR" -w '\nHTTP:%{http_code}' "$BASE/wp-admin/$1")
  code=$(echo "$out" | tail -1 | cut -d: -f2)
  if [ "$code" != "200" ]; then bad "$2 — HTTP $code"; return; fi
  if echo "$out" | grep -qiE 'Fatal error|There has been a critical error'; then bad "$2 — blad krytyczny na ekranie"; return; fi
  if [ -n "$3" ] && ! echo "$out" | grep -q "$3"; then bad "$2 — brak spodziewanej tresci ($3)"; return; fi
  ok "$2 — otwiera sie i pokazuje dane"
}
[ -n "$SRV" ] && sprawdz_ekran "admin.php?page=mp-cases" "MP: Sprawy" "$SRV" || bad "MP: Sprawy — brak numeru sprawy do sprawdzenia"
sprawdz_ekran "admin.php?page=mp-automator" "Automatyzacje MP" ""
sprawdz_ekran "admin.php?page=mp-registry" "Rejestr gwarancji" ""
sprawdz_ekran "site-health.php" "Narzedzia -> Stan witryny" ""

echo "== 6. Wlasne testy w Stanie witryny (obietnica z PRZECZYTAJ-MNIE) =="
TESTY=$(ev 'echo implode(",", array_keys( apply_filters("site_status_tests", array("direct"=>array(),"async"=>array()))["direct"] ));')
LICZ=$(echo "$TESTY" | tr ',' '\n' | grep -c '^mp_')
[ "${LICZ:-0}" -ge 1 ] && ok "wtyczki dopisuja $LICZ wlasnych testow do Stanu witryny" || bad "ZERO wlasnych testow w Stanie witryny (PRZECZYTAJ-MNIE obiecuje inaczej)"

echo "== 7. Cisza w logach (WP_DEBUG wlaczony) =="
LOG=$(ev 'echo file_exists(WP_CONTENT_DIR."/debug.log") ? file_get_contents(WP_CONTENT_DIR."/debug.log") : "";')
NASZE=$(echo "$LOG" | grep -iE 'PHP (Notice|Warning|Deprecated|Fatal|Parse error)' | grep -E 'mp-service-intake|mp-warranty-registry|mp-workflow-automator')
[ -z "$NASZE" ] && ok "zero PHP notice/warning z naszego kodu" || { bad "notice z naszego kodu:"; echo "$NASZE" | head -5 | sed 's/^/       /'; }
OBCE=$(echo "$LOG" | grep -icE 'PHP (Notice|Warning|Deprecated|Fatal|Parse error)' || true)
echo "       (wpisow w debug.log lacznie: ${OBCE:-0})"

echo
echo "WYNIK sciezki klienta: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
