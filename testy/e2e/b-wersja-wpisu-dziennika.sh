#!/usr/bin/env bash
# ZYWY DOWOD (2.45): wpis w dzienniku rejestru niesie WERSJE swojego ksztaltu.
#
# `EVENT_MODEL.md` sekcja 2 opisuje wspolny ksztalt wpisu dla WSZYSTKICH trzech
# dziennikow i wymienia w nim `schema_version` — „wersja ksztaltu payloadu
# (w payloadzie)". Dziennik rejestru jako JEDYNY z trzech tego pola nie zapisywal
# (intake 2 wystapienia, automator 2, rejestr 0). Dziennik jest append-only, wiec
# przy pierwszej zmianie ksztaltu nie dalo by sie odroznic starych wpisow od nowych —
# a mowa o wpisach, ktore specyfikacja wymienia wprost jako historie zmian i decyzji.
#
# Ten test pilnuje, ze:
#   1. wpis o zmianie danych produktu niesie wersje ksztaltu,
#   2. wpis o decyzji gwarancyjnej tez ja niesie (nie tylko jedna sciezka),
#   3. czytnik historii podaje ja wprost, a nie kaze jej szukac w payloadzie,
#   4. wersja NIE udaje zmiany pola na ekranie historii (regresja 2.38),
#   5. archiwizacja dalej jest nazwana archiwizacja, a nie „poprawiono dane",
#   6. wpis SPRZED naprawy (bez wersji) dalej sie czyta — dziennika nie wolno poprawiac.
#
# ⛔ Numeru wersji NIE wpisujemy — bierzemy ze stalej ProductEvents::SCHEMA_VERSION.
# Wymaga zywego `wp`. Exit 0 = OK. Test sprzata po sobie (wspolna baza w CI).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

SERIAL='WER-TEST-1'
NORM='WERTEST1'

ZALOZONE_KONTA=''
KONTO_ID=''

# ⛔ Ten sam odporny wzorzec, co w pozostalych dowodach rejestru: w CI role MP moga
# byc chwilowo skasowane przez test odinstalowania, wiec czytamy kod wyjscia,
# pokazujemy blad i w razie braku roli nadajemy samo uprawnienie.
konto() {
	LOGIN="$1"; UPRAWNIENIE="$2"; KONTO_ID=''
	MAIL="$LOGIN@b-wersja-wpisu-dziennika.test"
	ID=$(wp user get "$LOGIN" --field=ID 2>/dev/null | tr -d '[:space:]')

	if [ -z "$ID" ]; then
		WYNIK=$(wp user create "$LOGIN" "$MAIL" --porcelain 2>&1)
		KOD=$?
		ID=$(printf '%s' "$WYNIK" | tr -d '[:space:]' | grep -Eo '^[0-9]+$')
		if [ -z "$ID" ]; then
			bad "nie udalo sie zalozyc konta '$LOGIN' (kod $KOD): $WYNIK"
			return 1
		fi
	else
		echo "  --   konto '$LOGIN' juz istnieje (id=$ID) — uzywam istniejacego"
	fi

	ZALOZONE_KONTA="$ZALOZONE_KONTA $ID"

	if wp role exists "$UPRAWNIENIE" >/dev/null 2>&1; then
		wp user set-role "$ID" "$UPRAWNIENIE" >/dev/null 2>&1
	else
		echo "  --   rola '$UPRAWNIENIE' nie istnieje w tej bazie — nadaje samo uprawnienie"
		wp user add-cap "$ID" "$UPRAWNIENIE" >/dev/null 2>&1
	fi

	KONTO_ID="$ID"
}

sprzataj() {
	P=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$NORM';")
	if [ -n "$P" ]; then
		wp db query "DELETE FROM wp_mp_product_events WHERE product_registry_id=$P;" >/dev/null 2>&1
		wp db query "DELETE FROM wp_mp_warranty_exceptions WHERE product_registry_id=$P;" >/dev/null 2>&1
		wp db query "DELETE FROM wp_mp_product_registry WHERE id=$P;" >/dev/null 2>&1
	fi
}

sprzataj
konto wer_adm mp_system_admin
ADM="$KONTO_ID"

wp db query "INSERT INTO wp_mp_product_registry
	(serial_display, serial_normalized, model, batch, category, purchase_document, purchase_date, warranty_until, source, archived, created_at, updated_at)
	VALUES ('$SERIAL','$NORM','Model-A','P-45','agd','FV/2026/45','2026-01-10','2027-01-10','csv_import',0,UTC_TIMESTAMP(),UTC_TIMESTAMP());" >/dev/null 2>&1
PID=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$NORM';")

WERSJA=$(wp eval 'echo MP\Registry\ProductEvents::SCHEMA_VERSION;' 2>/dev/null | tr -d '[:space:]')

# Brak stalej NIE przerywa testu — chcemy zobaczyc, ktore dokladnie sprawdzenia padaja
# na kodzie sprzed naprawy (test, ktory umiera na starcie, slabo kalibruje).
if [ -z "$WERSJA" ]; then
	bad "klasa dziennika nie ma stalej SCHEMA_VERSION (wspolny kontrakt EVENT_MODEL)"
	WERSJA='BRAK-STALEJ'
else
	ok "dziennik rejestru ma stala wersji ksztaltu ($WERSJA)"
fi

if [ -z "$PID" ] || [ -z "$ADM" ]; then
	bad "nie udalo sie przygotowac stanowiska (PID=$PID ADM=$ADM) — powod wyzej"
	sprzataj
	for U in $ZALOZONE_KONTA; do wp user delete "$U" --yes >/dev/null 2>&1; done
	echo "WYNIK: $PASS ok, $FAIL fail"
	exit 1
fi

echo "== 1. WPIS O ZMIANIE DANYCH NIESIE WERSJE KSZTALTU =="
wp eval "MP\\Registry\\Repo::update( $PID, array('model'=>'Model-B'), $ADM );" >/dev/null 2>&1
PAY=$(wp db query "SELECT payload FROM wp_mp_product_events WHERE product_registry_id=$PID ORDER BY id DESC LIMIT 1;" --skip-column-names 2>/dev/null)
case "$PAY" in
	*'"schema_version":'*) ok "payload wpisu niesie schema_version" ;;
	*)                     bad "payload BEZ schema_version: $PAY" ;;
esac
case "$PAY" in
	*"\"schema_version\":$WERSJA"*) ok "wersja zgodna ze stala klasy ($WERSJA)" ;;
	*)                              bad "wersja w payloadzie nie zgadza sie ze stala ($WERSJA): $PAY" ;;
esac

echo "== 2. DECYZJA GWARANCYJNA TEZ JA NIESIE (nie tylko jedna sciezka) =="
wp eval "wp_set_current_user( $ADM ); MP\\Registry\\WarrantyExceptions::create( $PID, null, 'Powod-testowy-245', null );" >/dev/null 2>&1
PAY_W=$(wp db query "SELECT payload FROM wp_mp_product_events WHERE product_registry_id=$PID AND event_type='EXCEPTION_CREATED' ORDER BY id DESC LIMIT 1;" --skip-column-names 2>/dev/null)
case "$PAY_W" in
	*'"schema_version":'*) ok "wpis o wyjatku gwarancyjnym tez niesie wersje" ;;
	*)                     bad "wpis o wyjatku BEZ wersji: $PAY_W" ;;
esac

echo "== 3. CZYTNIK PODAJE WERSJE WPROST =="
Z_CZYTNIKA=$(wp eval "\$h = MP\\Registry\\ProductEvents::history( $PID ); echo \$h[0]['schema_version'];" 2>/dev/null | tr -d '[:space:]')
[ "$Z_CZYTNIKA" = "$WERSJA" ] && ok "history() oddaje wersje wpisu ($Z_CZYTNIKA)" || bad "history() nie podaje wersji ('$Z_CZYTNIKA')"

echo "== 4. WERSJA NIE UDAJE ZMIANY POLA NA EKRANIE (regresja 2.38) =="
EKRAN=$(wp eval "wp_set_current_user( $ADM ); \$_GET = array( 'page' => 'mp-registry', 'historia' => $PID ); ob_start(); MP\\Registry\\Admin\\ProductsScreen::render(); echo ob_get_clean();" 2>/dev/null)
echo "$EKRAN" | grep -q 'schema_version' && bad "ekran historii pokazuje techniczne 'schema_version' jako zmiane pola" || ok "ekran nie pokazuje klucza technicznego"
echo "$EKRAN" | grep -q 'Model: ' && ok "prawdziwa zmiana pola dalej widoczna" || bad "zniknela zmiana pola z ekranu"

echo "== 5. ARCHIWIZACJA DALEJ NAZWANA ARCHIWIZACJA =="
# Payload archiwizacji ma teraz DWA klucze (archived + schema_version) — rozpoznanie
# po samym zestawie kluczy zepsuloby sie tutaj po cichu.
wp eval "wp_set_current_user( $ADM ); MP\\Registry\\Archive::archive( $PID );" >/dev/null 2>&1
EKRAN2=$(wp eval "wp_set_current_user( $ADM ); \$_GET = array( 'page' => 'mp-registry', 'historia' => $PID ); ob_start(); MP\\Registry\\Admin\\ProductsScreen::render(); echo ob_get_clean();" 2>/dev/null)
echo "$EKRAN2" | grep -q 'Przeniesiono do archiwum' && ok "archiwizacja opisana jako archiwizacja" || bad "archiwizacja pokazana jako zwykla poprawka danych"
wp eval "wp_set_current_user( $ADM ); MP\\Registry\\Archive::restore( $PID );" >/dev/null 2>&1

echo "== 6. WPIS SPRZED NAPRAWY DALEJ SIE CZYTA =="
# Dziennika nie wolno poprawiac wstecz, wiec stare wpisy zostana BEZ wersji na zawsze.
wp db query "INSERT INTO wp_mp_product_events (product_registry_id, event_type, payload, actor_id, created_at)
	VALUES ($PID, 'PRODUCT_UPDATED', '{\"model\":{\"before\":\"Model-STARY-45\",\"after\":\"Model-NOWY-45\"}}', $ADM, UTC_TIMESTAMP());" >/dev/null 2>&1
STARY=$(wp eval "\$h = MP\\Registry\\ProductEvents::history( $PID ); foreach ( \$h as \$w ) { if ( isset( \$w['payload']['model']['before'] ) && 'Model-STARY-45' === \$w['payload']['model']['before'] ) { echo \$w['schema_version']; } }" 2>/dev/null | tr -d '[:space:]')
[ "$STARY" = "0" ] && ok "stary wpis czyta sie z wersja 0 (jawnie: sprzed wprowadzenia pola)" || bad "stary wpis dal wersje '$STARY' zamiast 0"
EKRAN3=$(wp eval "wp_set_current_user( $ADM ); \$_GET = array( 'page' => 'mp-registry', 'historia' => $PID ); ob_start(); MP\\Registry\\Admin\\ProductsScreen::render(); echo ob_get_clean();" 2>/dev/null)
echo "$EKRAN3" | grep -q 'Model-STARY-45' && ok "stary wpis dalej widoczny na ekranie historii" || bad "stary wpis zniknal z ekranu"

sprzataj
for U in $ZALOZONE_KONTA; do wp user delete "$U" --yes >/dev/null 2>&1; done

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
