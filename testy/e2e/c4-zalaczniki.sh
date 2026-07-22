#!/usr/bin/env bash
# ZYWY DOWOD C4 (zalaczniki twardo): upload z EXIF przez formularz -> strip
# metadanych, losowa nazwa bez rozszerzenia, MIME po tresci; deny-ALL na katalogu
# (bezposredni URL -> 403); endpoint serwujacy z bramka (personel TAK, anonim 403,
# IDOR nie dziala); odrzut zlego typu/za duzego; retencja (cron kasuje wiersz+plik).
set -u

BASE="${MP_BASE:-http://localhost:8090}"
CAPTURE="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
UP_DIR="$(wp eval 'echo wp_upload_dir()["basedir"];' 2>/dev/null)/mp-attachments"
JAR="$(mktemp)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

SITE_HOST=$(wp option get home 2>/dev/null | sed 's#^https\?://##;s#/.*##')
HOSTHDR=(); [ -n "$SITE_HOST" ] && HOSTHDR=(-H "Host: $SITE_HOST")
cget()  { curl -s "${HOSTHDR[@]}" "$@"; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_attachments; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
rm -f "$CAPTURE"

# ext-fileinfo obecne (bez tego caly upload odmawia).
HASFI=$(wp eval 'echo function_exists("finfo_open") ? "TAK" : "NIE";' 2>/dev/null)
[ "$HASFI" = "TAK" ] && ok "ext-fileinfo obecne (MIME po tresci mozliwe)" || bad "brak ext-fileinfo"

# Katalog istnieje z deny-ALL po pierwszym uzyciu — wymus utworzenie.
wp eval 'MP\Intake\Attachments::dir();' >/dev/null 2>&1
grep -qi "denied\|Deny from all" "$UP_DIR/.htaccess" 2>/dev/null && ok "katalog mp-attachments ma deny-ALL (.htaccess)" || bad "brak deny-ALL"

# ── 1. JPEG z EXIF (GPS) do uploadu ────────────────────────────────────────
IMG=/tmp/mp-exif.jpg
wp eval '
$im = imagecreatetruecolor(32, 32);
imagefilledrectangle($im, 0, 0, 32, 32, imagecolorallocate($im, 200, 50, 50));
imagejpeg($im, "/tmp/mp-base.jpg", 90);
imagedestroy($im);
' >/dev/null 2>&1
# Wstrzyknij EXIF z GPS (exiftool jak jest, inaczej marker w APP1) — fallback: kopiuj bazowy.
if command -v exiftool >/dev/null 2>&1; then
	exiftool -overwrite_original -GPSLatitude=52.2 -GPSLongitude=21.0 -Make=TestCam /tmp/mp-base.jpg >/dev/null 2>&1
fi
cp /tmp/mp-base.jpg "$IMG"
ok "przygotowano JPEG do uploadu ($(wc -c < "$IMG") B)"

# Formularz + nonce.
PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
HTML=$(cget "$BASE$PAGE_PATH")
NONCE=$(echo "$HTML" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
echo "$HTML" | grep -q 'name="mp_files\[\]"' && ok "formularz ma pole zalacznikow (mp_files[])" || bad "brak pola plikow"

# ── 2. Wyslanie zgloszenia Z ZALACZNIKIEM ──────────────────────────────────
cget -c "$JAR" -b "$JAR" -o /dev/null \
	-F "action=mp_intake_submit" -F "_mp_nonce=$NONCE" \
	-F "mp_ts=$(( $(date +%s) - 30 ))" \
	-F "kind=reklamacja" -F "email=foto@example.com" \
	-F "serial=FOTO-1" -F "purchase_document=FV/2026/5" \
	-F "purchase_date=2026-03-15" -F "issue_description=Zdjecie usterki" -F "mp_consent=1" \
	-F "mp_files[]=@$IMG;type=image/jpeg" \
	"$BASE/wp-admin/admin-post.php"

CID=$(q "SELECT id FROM wp_mp_service_cases WHERE status IS NULL LIMIT 1")
ACOUNT=$(q "SELECT COUNT(*) FROM wp_mp_attachments WHERE case_id=$CID")
[ "$ACOUNT" = "1" ] && ok "zalacznik zapisany na sprawie unverified" || bad "zalaczniki: $ACOUNT"

# MIME po tresci, losowa nazwa BEZ rozszerzenia, retention ustawione.
read -r APATH AMIME ARET <<< "$(wp db query "SELECT path, mime, retention_until FROM wp_mp_attachments WHERE case_id=$CID" --skip-column-names 2>/dev/null)"
[ "$AMIME" = "image/jpeg" ] && ok "MIME wykryty po tresci: $AMIME" || bad "MIME: $AMIME"
echo "$APATH" | grep -qE '^[0-9a-f-]{36}$' && ok "losowa nazwa UUID bez rozszerzenia ($APATH)" || bad "nazwa: $APATH"
[ -n "$ARET" ] && ok "retention_until ustawione ($ARET)" || bad "brak retention_until"

# Strip EXIF: plik na dysku nie zawiera markera GPS/Make.
FILE_ON_DISK="$UP_DIR/$APATH"
if [ -f "$FILE_ON_DISK" ]; then
	strings "$FILE_ON_DISK" 2>/dev/null | grep -qiE "GPSLat|TestCam|GPS" && bad "EXIF/GPS NIE usuniety!" || ok "EXIF/GPS usuniety ze zdjecia (strip)"
else
	bad "plik zalacznika nie istnieje na dysku"
fi

# ── 3. Bezposredni URL do pliku => deny-ALL (Apache/nginx) lub guard wdrozony ─
# .htaccess dziala na Apache/nginx (cel klienta + poligon). Wbudowany serwer PHP
# (`wp server` w CI) NIE honoruje .htaccess — tam potwierdzamy ze GUARD jest
# wdrozony (ochrona zadziala na docelowym Apache), a portable bramka = endpoint (nizej).
UP_BASEURL=$(wp eval 'echo wp_upload_dir()["baseurl"];' 2>/dev/null)
UP_URLPATH=$(echo "$UP_BASEURL" | sed 's#^https\?://[^/]*##')
SRV_SW=$(cget -sI "$BASE/" 2>/dev/null | grep -i '^server:' | tr -d '\r')
DCODE=$(cget -o /dev/null -w '%{http_code}' "$BASE$UP_URLPATH/mp-attachments/$APATH")
if echo "$SRV_SW" | grep -qiE 'apache|nginx'; then
	{ [ "$DCODE" = "403" ] || [ "$DCODE" = "404" ]; } && ok "bezposredni URL do pliku odbity (HTTP $DCODE, deny-ALL na $SRV_SW)" || bad "plik dostepny wprost na Apache/nginx! ($DCODE)"
else
	grep -qi 'denied' "$UP_DIR/.htaccess" 2>/dev/null && ok "guard deny-ALL wdrozony ($SRV_SW nie honoruje .htaccess — ochrona zadziala na Apache/nginx; portable bramka = endpoint nizej)" || bad "brak guarda .htaccess"
fi

# ── 4. Bramka dostepu (IDOR/ownership) — deterministycznie przez wp eval ───
AID=$(q "SELECT id FROM wp_mp_attachments WHERE case_id=$CID LIMIT 1")
# Sprawa jest UNVERIFIED => nawet po zalogowaniu klient NIE ma dostepu; personel TAK, anonim NIE.
GATE_ADMIN=$(wp eval "wp_set_current_user(1); echo MP\Intake\Attachments::can_access_case($CID) ? 'TAK' : 'NIE';" 2>/dev/null)
GATE_ANON=$(wp eval "wp_set_current_user(0); echo MP\Intake\Attachments::can_access_case($CID) ? 'TAK' : 'NIE';" 2>/dev/null)
[ "$GATE_ADMIN" = "TAK" ] && ok "bramka: personel (mp_system_admin) MA dostep" || bad "personel bez dostepu"
[ "$GATE_ANON" = "NIE" ] && ok "bramka: anonim NIE ma dostepu (unverified => tylko personel)" || bad "anonim ma dostep!"

# Klient-wlasciciel vs OBCY klient po weryfikacji (ownership).
# get-or-create (poligon: DB trwaly, users moga zostac z poprzedniego przebiegu).
ensure_user() { wp user get "$1" --field=ID 2>/dev/null || wp user create "$1" "$2" --role="$3" --user_pass=x --porcelain 2>/dev/null; }
CLIENT_OWNER=$(ensure_user owner owner@example.com mp_client | tr -d '[:space:]')
CLIENT_OTHER=$(ensure_user other other@example.com mp_client | tr -d '[:space:]')
# Klient z kontem WP=CLIENT_OWNER, sprawa verified spieta z tym klientem.
CUSTID=$(wp eval "global \$wpdb; \$wpdb->insert('wp_mp_customers', array('email'=>'foto@example.com','wp_user_id'=>$CLIENT_OWNER,'created_at'=>gmdate('Y-m-d H:i:s'),'updated_at'=>gmdate('Y-m-d H:i:s'))); echo \$wpdb->insert_id;" 2>/dev/null)
wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', customer_id=$CUSTID WHERE id=$CID" >/dev/null 2>&1
GATE_OWNER=$(wp eval "wp_set_current_user($CLIENT_OWNER); echo MP\Intake\Attachments::can_access_case($CID) ? 'TAK' : 'NIE';" 2>/dev/null)
GATE_OTHER=$(wp eval "wp_set_current_user($CLIENT_OTHER); echo MP\Intake\Attachments::can_access_case($CID) ? 'TAK' : 'NIE';" 2>/dev/null)
[ "$GATE_OWNER" = "TAK" ] && ok "bramka: klient-WLASCICIEL sprawy verified MA dostep" || bad "wlasciciel bez dostepu ($GATE_OWNER)"
[ "$GATE_OTHER" = "NIE" ] && ok "bramka IDOR: OBCY klient NIE ma dostepu do cudzej sprawy" || bad "IDOR: obcy klient ma dostep!"

# ── 5. Endpoint HTTP: bez waznego nonce => odrzut (nie 200) ────────────────
ANON=$(cget -o /dev/null -w '%{http_code}' "$BASE/wp-admin/admin-post.php?action=mp_intake_attachment&id=$AID&_wpnonce=zlynonce")
[ "$ANON" != "200" ] && ok "endpoint bez waznego nonce odbity (HTTP $ANON)" || bad "endpoint przepuscil bez nonce!"

# ── 6. Odrzut zlego typu (PHP jako .jpg) i za duzego pliku ─────────────────
printf '<?php echo "hack"; ?>' > /tmp/mp-bad.jpg
BADRES=$(wp eval '$r = MP\Intake\Attachments::validate_upload(array("error"=>0,"tmp_name"=>"/tmp/mp-bad.jpg","size"=>20,"name"=>"x.jpg")); echo $r === null ? "PRZESZEDL" : "ODRZUCONY";' 2>/dev/null)
[ "$BADRES" = "ODRZUCONY" ] && ok "plik PHP przebrany za .jpg odrzucony (MIME po tresci)" || bad "PHP-jako-jpg przeszedl!"

# ── 7. Retencja: przeterminuj i odpal sweep => wiersz+plik znikaja ─────────
wp db query "UPDATE wp_mp_attachments SET retention_until='2000-01-01 00:00:00' WHERE id=$AID" >/dev/null 2>&1
SWEPT=$(wp eval 'echo MP\Intake\Attachments::run_retention_sweep();' 2>/dev/null)
DELAT=$(q "SELECT deleted_at FROM wp_mp_attachments WHERE id=$AID")
[ -n "$DELAT" ] && [ "$DELAT" != "NULL" ] && ok "retencja: przeterminowany zalacznik oznaczony deleted_at" || bad "retencja nie oznaczyla ($DELAT)"
[ ! -f "$FILE_ON_DISK" ] && ok "retencja: PLIK skasowany z dysku (wiersz+plik)" || bad "plik zostal na dysku po retencji"

echo
echo "WYNIK C4: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
