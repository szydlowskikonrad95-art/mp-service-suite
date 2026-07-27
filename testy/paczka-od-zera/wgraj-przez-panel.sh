#!/usr/bin/env bash
# Klient NIE ma konsoli — wgrywa ZIP w panelu: Wtyczki -> Dodaj nowa -> Wyslij wtyczke na serwer.
set -u
BASE="http://localhost:8097"; J="$(mktemp)"
PLUG="mp-warranty-registry"
ZIP="$(ls paczka/mp-service-suite-*/$PLUG.zip | head -1)"
W(){ docker compose -p mpzero -f ./compose.yml exec -T cli wp --path=/var/www/html "$@" 2>/dev/null; }
HASLO="${MP_TEST_HASLO:-$(cat "$(dirname "$0")/paczka/.haslo" 2>/dev/null)}"
[ -n "$HASLO" ] || { echo "BRAK hasla — ustaw MP_TEST_HASLO albo odpal uruchom.sh"; exit 2; }
PASS=0; FAIL=0; ok(){ PASS=$((PASS+1)); echo "  OK   $1"; }; bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# stan wyjsciowy: witryna bez tej wtyczki
W plugin deactivate $PLUG >/dev/null; W plugin delete $PLUG >/dev/null
[ -z "$(W plugin list --name=$PLUG --field=name)" ] && ok "witryna bez wtyczki $PLUG (stan wyjsciowy)" || bad "wtyczka nadal obecna"

curl -s -c "$J" -o /dev/null --data-urlencode "log=szef" --data-urlencode "pwd=$HASLO" \
  --data-urlencode "wp-submit=Zaloguj" --data-urlencode "testcookie=1" "$BASE/wp-login.php"
STRONA=$(curl -s -b "$J" "$BASE/wp-admin/plugin-install.php?tab=upload")
NONCE=$(echo "$STRONA" | grep -o 'name="_wpnonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "ekran 'Wyslij wtyczke na serwer' otwarty" || bad "brak ekranu wysylki wtyczki"

WYNIK=$(curl -s -b "$J" -F "pluginzip=@$ZIP" -F "_wpnonce=$NONCE" \
        -F "_wp_http_referer=/wp-admin/plugin-install.php?tab=upload" -F "install-plugin-submit=Zainstaluj teraz" \
        "$BASE/wp-admin/update.php?action=upload-plugin")
echo "$WYNIK" | grep -qi 'Wtyczka została zainstalowana\|Plugin installed successfully' \
  && ok "panel: wtyczka zainstalowana z ZIP-a" || { bad "panel odmowil instalacji:"; echo "$WYNIK" | grep -oiE '<p>[^<]{10,200}</p>' | head -3 | sed 's/^/       /'; }

LINK=$(echo "$WYNIK" | grep -o 'href="[^"]*action=activate[^"]*"' | head -1 | sed -e 's/href="//' -e 's/"$//' -e 's/&#038;/\&/g' -e 's/&amp;/\&/g')
[ -n "$LINK" ] && ok "panel proponuje 'Wlacz wtyczke'" || bad "brak linku aktywacji"
case "$LINK" in http*) A="$LINK";; *) A="$BASE/wp-admin/$LINK";; esac; curl -s -b "$J" -o /dev/null "$A"
[ "$(W plugin list --name=$PLUG --field=status)" = "active" ] && ok "wtyczka wlaczona z panelu" || bad "wtyczka nie wlaczyla sie z panelu"
LOG=$(W eval 'echo file_exists(WP_CONTENT_DIR."/debug.log") ? file_get_contents(WP_CONTENT_DIR."/debug.log") : "";')
[ -z "$(echo "$LOG" | grep -E 'mp-warranty-registry' | grep -iE 'Fatal|Warning|Notice')" ] && ok "cisza w logach po instalacji z panelu" || bad "logi krzycza po instalacji z panelu"
echo; echo "WYNIK panelu: $PASS ok, $FAIL fail"; [ "$FAIL" -eq 0 ]
