#!/usr/bin/env bash
# ZYWY DOWOD (2.47): ekran importu OGLASZA postep, zakonczenie i blad.
#
# Do 1.3.12 stan importu istnial WYLACZNIE wizualnie: skrypt podmienial tekst
# w `#mp-import-message`, a w calym `ImportScreen.php` bylo 10 atrybutow `class=`
# i ZERO atrybutow `aria-`. Osoba z czytnikiem ekranu uruchamiala import i nie
# dowiadywala sie ani ze trwa, ani ze sie skonczyl, ani ze padl — tekst zmienial
# sie w ciszy. Ta sama technika (role=status / role=alert / aria-live) stoi
# w OSMIU miejscach na powierzchni KLIENTA i ani razu na powierzchni PERSONELU.
#
# 🔴 Ta wada przeszla przez skaner: `axe` dal na tym ekranie zero naruszen, bo bada
# stan STATYCZNY, a w chwili badania komunikatu jeszcze nie ma. Dlatego ten test
# mierzy RENDER ekranu i wartosci funkcji, a nie wynik skanera.
#
# Ten test pilnuje, ze:
#   1. sa DWA obszary ogloszen: spokojny (postep) i przerywajacy (blad),
#   2. zaden z nich nie jest ukryty — ukryty obszar aria-live bywa pomijany,
#   3. pasek postepu ma nazwe (bez niej czytnik mowi samo „pasek postepu"),
#   4. proba kontrolna liczbowa: przed naprawa atrybutow `aria-` bylo ZERO,
#   5. przy TRWAJACYM imporcie obszar niesie procent juz z serwera,
#   6. przelicznik procentow nie dzieli przez zero i nie wychodzi poza 0..100,
#   7. reszta ekranu importu dziala jak dzialala (regresja),
#   8. skrypt pisze do OBU obszarow i dlawi postep (kontrola statyczna — patrz nizej).
#
# Wymaga zywego `wp`. Exit 0 = OK. Test sprzata po sobie (wspolna baza w CI).
set -u

# Katalog repozytorium ZE SCIEZKI SKRYPTU — w CI test chodzi z /tmp/wp.
REPO="${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

ekran() {
	wp eval "wp_set_current_user( $ADM ); ob_start(); MP\\Registry\\Admin\\ImportScreen::render(); echo ob_get_clean();" 2>/dev/null
}

sprzataj() {
	wp db query "DELETE FROM wp_mp_import_jobs WHERE file_path='/tmp/mp-test-247.csv';" >/dev/null 2>&1
}

sprzataj

ADM=$(wp user create imp_adm imp_adm@example.com --role=mp_system_admin --porcelain 2>/dev/null)
[ -z "$ADM" ] && ADM=$(wp user get imp_adm --field=ID 2>/dev/null | tr -d '[:space:]')

if [ -z "$ADM" ]; then
	bad "nie udalo sie zalozyc konta administratora"
	echo "WYNIK: $PASS ok, $FAIL fail"
	exit 1
fi

HTML=$(ekran)

echo "== 1. DWA OBSZARY OGLOSZEN: SPOKOJNY I PRZERYWAJACY =="
echo "$HTML" | grep -q 'role="status"' && ok "jest obszar role=status (postep, zakonczenie)" || bad "brak role=status — postep nadal zmienia sie w ciszy"
echo "$HTML" | grep -q 'aria-live="polite"' && ok "postep ogłaszany spokojnie (polite)" || bad "brak aria-live=polite"
echo "$HTML" | grep -q 'role="alert"' && ok "jest obszar role=alert (blad)" || bad "brak role=alert — awaria importu nadal cicha"
echo "$HTML" | grep -q 'aria-live="assertive"' && ok "blad przerywa czytnikowi (assertive)" || bad "brak aria-live=assertive"

echo "== 2. OBSZARY NIE SA UKRYTE =="
# Ukryty (display:none) obszar aria-live bywa pomijany, gdy odslania sie go
# i zapelnia w tej samej chwili — a dokladnie tak dziala funkcja show() w skrypcie.
ZNACZNIK=$(echo "$HTML" | grep -o '<p id="mp-import-live"[^>]*' | head -1)
case "$ZNACZNIK" in
	*hidden*|*'display:none'*|*'display: none'*) bad "obszar postepu jest ukryty ($ZNACZNIK)" ;;
	'')                                          bad "nie ma obszaru #mp-import-live w ogole" ;;
	*)                                           ok  "obszar postepu na stale w dokumencie i nieukryty" ;;
esac
ZNACZNIK_A=$(echo "$HTML" | grep -o '<p id="mp-import-alert"[^>]*' | head -1)
case "$ZNACZNIK_A" in
	*hidden*|*'display:none'*|*'display: none'*) bad "obszar bledu jest ukryty ($ZNACZNIK_A)" ;;
	'')                                          bad "nie ma obszaru #mp-import-alert w ogole" ;;
	*)                                           ok  "obszar bledu na stale w dokumencie i nieukryty" ;;
esac

echo "== 3. PASEK POSTEPU MA NAZWE =="
echo "$HTML" | grep -o '<progress[^>]*' | grep -q 'aria-label' && ok "pasek postepu ma nazwe dla czytnika" || bad "pasek postepu bez nazwy"

echo "== 4. PROBA KONTROLNA LICZBOWA (przed naprawa: ZERO atrybutow aria-) =="
ILE_ARIA=$(echo "$HTML" | grep -o 'aria-[a-z]*=' | wc -l | tr -d '[:space:]')
[ "$ILE_ARIA" -ge 4 ] && ok "ekran ma $ILE_ARIA atrybutow aria- (przed naprawa: 0)" || bad "atrybutow aria- na ekranie: $ILE_ARIA"

echo "== 5. PRZY TRWAJACYM IMPORCIE OBSZAR NIESIE PROCENT JUZ Z SERWERA =="
# Bez tego osoba, ktora odswiezy strone w trakcie importu, uslyszy pusty obszar.
# ⚠️ `ImportJobs::find_live()` szuka po `lock_key = 'product-import'` (UNIKAT), a nie
# po statusie — samo `status='processing'` NIE robi zadania zywym. Zlapane kalibracja:
# bez lock_key ekran renderowal sie jakby importu nie bylo.
ZAJETE=$(q "SELECT COUNT(*) FROM wp_mp_import_jobs WHERE lock_key='product-import';")
if [ "$ZAJETE" != "0" ]; then
	# Cudzy zywy import — nie wypychamy go, bo UNIKAT na lock_key trzyma jeden na raz.
	echo "  --   pomijam: na stanowisku trwa juz inny import (lock_key zajety)"
else
	wp db query "INSERT INTO wp_mp_import_jobs
		(file_path, status, total_rows, processed_rows, success_rows, error_rows, lock_key, created_at, updated_at)
		VALUES ('/tmp/mp-test-247.csv', 'processing', 200, 50, 50, 0, 'product-import', UTC_TIMESTAMP(), UTC_TIMESTAMP());" >/dev/null 2>&1
	JOB=$(q "SELECT id FROM wp_mp_import_jobs WHERE file_path='/tmp/mp-test-247.csv';")
fi
if [ "$ZAJETE" = "0" ] && [ -z "${JOB:-}" ]; then
	bad "nie udalo sie zalozyc zadania importu do proby"
elif [ "$ZAJETE" = "0" ]; then
	HTML_LIVE=$(ekran)
	SEKCJA=$(echo "$HTML_LIVE" | tr -d '\n' | grep -o '<p id="mp-import-live".*</p>' | head -c 400)
	case "$SEKCJA" in
		*"25 procent"*) ok "obszar ogloszen niesie procent (25) prosto z serwera" ;;
		*)              bad "obszar ogloszen bez procentu (widziane: $SEKCJA)" ;;
	esac
	echo "$HTML_LIVE" | grep -q 'Przetworzono' && ok "widoczny komunikat wierszowy nietkniety (bez regresji)" || bad "zniknal widoczny komunikat o wierszach"
fi

echo "== 6. PRZELICZNIK PROCENTOW =="
proc() { wp eval "echo MP\\Registry\\Admin\\ImportScreen::percent( $1, $2 );" 2>/dev/null | tr -d '[:space:]'; }
[ "$(proc 50 200)" = "25" ]  && ok "50 z 200 = 25%"                                 || bad "50 z 200 = $(proc 50 200)"
[ "$(proc 0 0)" = "0" ]      && ok "pusty plik: 0 z 0 = 0% (zero dzielenia przez zero)" || bad "0 z 0 = $(proc 0 0)"
[ "$(proc 200 200)" = "100" ] && ok "200 z 200 = 100%"                              || bad "200 z 200 = $(proc 200 200)"
[ "$(proc 300 200)" = "100" ] && ok "wiecej niz calosc nadal 100% (obciete)"        || bad "300 z 200 = $(proc 300 200)"

echo "== 7. RESZTA EKRANU IMPORTU BEZ ZMIAN (regresja) =="
echo "$HTML" | grep -q 'Import produktów z CSV' && ok "naglowek ekranu na miejscu" || bad "zniknal naglowek ekranu"
echo "$HTML" | grep -q 'type="file"' && ok "pole wyboru pliku na miejscu" || bad "zniknelo pole wyboru pliku"
echo "$HTML" | grep -q 'id="mp-import-message"' && ok "widoczny komunikat postepu na miejscu" || bad "zniknal widoczny komunikat postepu"
echo "$HTML" | grep -q 'id="mp-import-resume"' && ok "przycisk wznowienia na miejscu" || bad "zniknal przycisk wznowienia"

echo "== 8. SKRYPT PISZE DO OBU OBSZAROW I DLAWI POSTEP =="
# ⚠️ To JEDYNA kontrola statyczna w tym tescie i mowimy o tym wprost: na stanowisku
# nie ma przegladarki, wiec zachowania skryptu nie da sie tu zmierzyc. Reszta testu
# mierzy render. Gdyby doszla przegladarka, ten blok zastepuje sie przebiegiem.
JS="$REPO/mp-warranty-registry/assets/js/admin-import.js"
grep -q "mp-import-live" "$JS"  && ok "skrypt pisze do obszaru postepu"  || bad "skrypt nie zna obszaru postepu"
grep -q "mp-import-alert" "$JS" && ok "skrypt pisze do obszaru bledu"    || bad "skrypt nie zna obszaru bledu"
grep -q "lastAnnounced" "$JS"   && ok "postep dlawiony (czytnik nie czyta kazdej paczki)" || bad "brak dlawienia postepu"

sprzataj
wp user delete "$ADM" --yes >/dev/null 2>&1

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
