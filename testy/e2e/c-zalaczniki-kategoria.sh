#!/usr/bin/env bash
# ZYWY DOWOD P1.2, druga polowa: ZALACZNIKI zalezne od KATEGORII produktu.
# Kartka (Plugin 1): „wymagane pola i zalaczniki zalezne od wybranej kategorii
# produktu". Pola dzialaly od poczatku, zalaczniki NIE — we wszystkich
# kategoriach identyczne i zawsze opcjonalne.
#
# Sprawdzane WYKONANIEM przez HTTP (jak klient), nie z kodu:
#   1. agd BEZ pliku          -> zgloszenie ODBITE, zero nowych spraw
#   2. odbity formularz       -> kategoria NADAL wybrana (inaczej klient traci ksztalt formularza)
#   3. agd + poprawny JPG     -> sprawa POWSTAJE, zalacznik zapisany
#   4. agd + plik-smiec       -> ODBITE (liczy sie plik PRZECHODZACY walidacje, nie sam wybor pliku)
#   5. audio BEZ pliku        -> sprawa powstaje (zero regresji)
#   6. bez kategorii, bez pliku -> sprawa powstaje (miekki fallback, kategoria jest opcjonalna)
#   7. HTML formularza        -> dla agd pole ma `required` i etykiete o tabliczce
# Wymaga zywego `wp`. Exit 0 = OK.
set -u

BASE="${MP_BASE:-http://localhost:8090}"
JAR="$(mktemp)"
TMPDIR_T="$(mktemp -d)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Naglowek Host = kanoniczny host WP (gdy curlujemy inny hostname niz home URL).
SITE_HOST=$(wp option get home 2>/dev/null | sed 's#^https\?://##;s#/.*##')
HOSTHDR=(); [ -n "$SITE_HOST" ] && HOSTHDR=(-H "Host: $SITE_HOST")
cget() { curl -s "${HOSTHDR[@]}" "$@"; }

# Liczniki antyspamowe: kazda proba (tez nieudana) zjada limit IP 10/10min,
# a ten test wysyla szesc razy. Bez czyszczenia test mierzylby rate-limit,
# nie regule zalacznikow.
reset_rl() {
	wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_rl%' OR option_name LIKE '_transient_timeout_mp_rl%'; DELETE FROM wp_mp_rate_counters" >/dev/null 2>&1
}

# Adres auto-strony formularza.
PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
PAGE_URL="$BASE$PAGE_PATH"

# Pliki testowe: prawdziwy JPG (finfo rozpoznaje po TRESCI) i smiec z rozszerzeniem .jpg.
JPG="$TMPDIR_T/tabliczka.jpg"
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00' > "$JPG"
head -c 3000 /dev/zero | tr '\0' 'x' >> "$JPG"
printf '\xff\xd9' >> "$JPG"
SMIEC="$TMPDIR_T/udaje-zdjecie.jpg"
printf 'to nie jest zdjecie, to zwykly tekst\n' > "$SMIEC"

# Wysylka formularza jak z przegladarki (multipart). $1=email $2=serial
# $3=kategoria $4=plik (pusty = bez zalacznika). Echo: cialo odpowiedzi
# po przekierowaniu (formularz z komunikatem albo strona z potwierdzeniem).
wyslij() {
	local email="$1" serial="$2" kat="$3" plik="${4:-}"
	local nonce html
	html=$(cget -c "$JAR" -b "$JAR" "$PAGE_URL")
	nonce=$(echo "$html" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')

	# `-e` = naglowek Referer. Powrot z bledem idzie przez wp_get_referer():
	# BEZ Referera WP odsyla na strone glowna i komunikat bledu nigdy sie nie
	# pokazuje — przegladarka wysyla ten naglowek zawsze, curl nie.
	local args=(-c "$JAR" -b "$JAR" -L -e "$PAGE_URL"
		-F "action=mp_intake_submit" -F "_mp_nonce=$nonce"
		-F "mp_ts=$(( $(date +%s) - 60 ))" -F "mp_hp="
		-F "kind=reklamacja" -F "category=$kat" -F "email=$email"
		-F "serial=$serial" -F "purchase_document=FV/2026/9" -F "purchase_date=2026-03-15"
		-F "issue_description=nie wlacza sie po podlaczeniu" -F "mp_consent=1")

	[ -n "$plik" ] && args+=(-F "mp_files[]=@$plik")

	cget "${args[@]}" "$BASE/wp-admin/admin-post.php"
}

echo "== P1.2 zalaczniki wg kategorii =="

# ── 1. AGD bez pliku => odbite, zero nowych spraw ──────────────────────────
reset_rl
BEFORE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
ODP=$(wyslij "zal-agd-brak@example.com" "ZALAGD1" "agd" "")
AFTER=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$BEFORE" = "$AFTER" ] && ok "AGD bez zalacznika: sprawa NIE powstala ($BEFORE -> $AFTER)" \
	|| bad "AGD bez zalacznika: sprawa powstala mimo wymogu ($BEFORE -> $AFTER)"
echo "$ODP" | grep -q "trzeba dołączyć załącznik" \
	&& ok "AGD bez zalacznika: klient widzi POWOD odrzucenia" || bad "brak komunikatu o wymaganym zalaczniku"

# ── 2. Odbity formularz pamieta kategorie (inaczej znikaja pola kategorii) ──
echo "$ODP" | grep -q '<option value="agd" selected' \
	&& ok "po odbiciu kategoria AGD nadal wybrana" || bad "po odbiciu kategoria wrocila do pustej"

# ── 3. AGD z poprawnym JPG => sprawa powstaje, zalacznik zapisany ──────────
reset_rl
BEFORE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
wyslij "zal-agd-ok@example.com" "ZALAGD2" "agd" "$JPG" >/dev/null
AFTER=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$AFTER" -gt "$BEFORE" ] && ok "AGD z zalacznikiem: sprawa powstala ($BEFORE -> $AFTER)" \
	|| bad "AGD z poprawnym zalacznikiem: sprawa NIE powstala (bramka za ostra)"
CID=$(q "SELECT id FROM wp_mp_service_cases WHERE id=(SELECT MAX(id) FROM wp_mp_service_cases)")
ILE=$(q "SELECT COUNT(*) FROM wp_mp_attachments WHERE case_id=$CID")
[ "${ILE:-0}" -ge 1 ] && ok "zalacznik zapisany przy sprawie $CID (szt: $ILE)" || bad "sprawa bez zalacznika mimo wgrania pliku"

# ── 4. AGD + plik-smiec (.jpg, ale tresc tekstowa) => odbite ───────────────
reset_rl
BEFORE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
ODP=$(wyslij "zal-agd-smiec@example.com" "ZALAGD3" "agd" "$SMIEC")
AFTER=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$BEFORE" = "$AFTER" ] && ok "AGD + plik-smiec: sprawa NIE powstala (liczy sie plik PRZECHODZACY walidacje)" \
	|| bad "AGD + plik-smiec: sprawa powstala bez uzytecznego zalacznika"

# ── 5. AUDIO bez pliku => sprawa powstaje (zero regresji) ──────────────────
reset_rl
BEFORE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
wyslij "zal-audio@example.com" "ZALAUDIO1" "audio" "" >/dev/null
AFTER=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$AFTER" -gt "$BEFORE" ] && ok "AUDIO bez zalacznika: sprawa powstala (zero regresji)" \
	|| bad "AUDIO bez zalacznika: sprawa NIE powstala — regresja na kategorii bez wymogu"

# ── 6. Bez kategorii, bez pliku => sprawa powstaje (miekki fallback) ───────
reset_rl
BEFORE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
wyslij "zal-bezkat@example.com" "ZALBEZKAT1" "" "" >/dev/null
AFTER=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "$AFTER" -gt "$BEFORE" ] && ok "bez kategorii bez zalacznika: sprawa powstala (fallback miekki)" \
	|| bad "bez kategorii: zgloszenie zablokowane — fallback jest ZA TWARDY"

# ── 7. HTML formularza: dla AGD pole wymagane i etykieta mowi CO wgrac ─────
HTML=$(cget "$PAGE_URL?category=agd")
HTML_AGD=$(cget -c "$JAR" -b "$JAR" "$PAGE_URL")
echo "$HTML_AGD" | grep -q 'name="mp_files\[\]"' && ok "pole zalacznikow obecne w formularzu" || bad "brak pola zalacznikow"
# Etykieta i `required` dla kategorii wybranej po stronie serwera (render z wartosciami).
wp eval '
 $html = MP\Intake\Front\FormRenderer::render( array( "values" => array( "kind" => "reklamacja", "category" => "agd" ) ) );
 echo ( false !== strpos( $html, "tabliczki znamionowej" ) ? "LABEL_OK " : "LABEL_BRAK " );
 echo ( preg_match( "/name=\"mp_files\[\]\"[^>]*required/", $html ) ? "REQ_OK" : "REQ_BRAK" );' 2>/dev/null | tee "$TMPDIR_T/render.txt" >/dev/null
grep -q "LABEL_OK" "$TMPDIR_T/render.txt" && ok "etykieta dla AGD mowi o tabliczce znamionowej" || bad "etykieta AGD bez informacji CO wgrac"
grep -q "REQ_OK" "$TMPDIR_T/render.txt" && ok "pole zalacznikow ma required dla AGD" || bad "pole zalacznikow bez required dla AGD"

# Kontrast: audio renderuje sie BEZ required (zero regresji w HTML).
wp eval '
 $html = MP\Intake\Front\FormRenderer::render( array( "values" => array( "kind" => "reklamacja", "category" => "audio" ) ) );
 echo ( preg_match( "/name=\"mp_files\[\]\"[^>]*required/", $html ) ? "REQ_JEST" : "REQ_BRAK" );' 2>/dev/null | grep -q "REQ_BRAK" \
	&& ok "AUDIO renderuje pole zalacznikow BEZ required" || bad "AUDIO dostalo required — regresja"

rm -rf "$TMPDIR_T" "$JAR"
echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
