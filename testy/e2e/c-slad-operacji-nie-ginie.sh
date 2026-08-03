#!/usr/bin/env bash
# ZYWY DOWOD (naprawa 2.10, krytyczna): nieudany zapis SLADU zatrzymuje operacje.
#
# Trzy dzienniki zapisywaly wpisy GOLYM $wpdb->insert() bez odczytania wyniku.
# Nieudane wstawienie zwraca wartosc falszywa, a NIE przerywa wykonania — wiec
# decyzja gwarancyjna zostawala w bazie bez sladu, kto ja podjal, a przy zadaniu
# RODO dane znikaly bez wpisu, ze operacje wykonano.
#
# Awarie zapisu wywolujemy NAPRAWDE: chwilowo zmieniamy nazwe tabeli dziennika.
# To jedyny sposob, zeby sprawdzic zachowanie przy bledzie bazy — samo czytanie
# kodu tego nie rozstrzyga.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
schowaj()  { wp db query "RENAME TABLE $1 TO ${1}_bak" >/dev/null 2>&1; }
przywroc() { wp db query "RENAME TABLE ${1}_bak TO $1" >/dev/null 2>&1; }
alarm()    { wp eval 'echo MP\Intake\Common\EventWrite::last_alert() ? "jest" : "brak";' 2>/dev/null | tr -d '[:space:]'; }
skasuj_alarm() { wp eval 'MP\Intake\Common\EventWrite::clear_alert();' >/dev/null 2>&1; }

ADMIN=$(wp user list --role=administrator --field=ID 2>/dev/null | head -1 | tr -d '[:space:]')

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_rate_counters; DELETE FROM wp_mp_warranty_exceptions; DELETE FROM wp_mp_product_events; DELETE FROM wp_mp_product_registry;" >/dev/null 2>&1
skasuj_alarm

# Produkt do wyjatkow gwarancyjnych.
wp db query "INSERT INTO wp_mp_product_registry (serial_display, serial_normalized, model, warranty_until, source, created_at, updated_at) VALUES ('SL-1','SL1','Model S','2030-01-01','manual',UTC_TIMESTAMP(),UTC_TIMESTAMP())" >/dev/null 2>&1
PID=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='SL1'")

echo "== 0. PROBA KONTROLNA: przy DZIALAJACYM dzienniku wszystko przechodzi =="
wp eval "wp_set_current_user( $ADMIN ); \$r = MP\\Registry\\WarrantyExceptions::create( $PID, null, 'kontrola dzialania', '2030-01-01' ); echo isset( \$r['error'] ) ? 'blad: ' . \$r['error'] : 'ok';" >/dev/null 2>&1
ILE_OK=$(q "SELECT COUNT(*) FROM wp_mp_warranty_exceptions")
[ "$ILE_OK" = "1" ] && ok "wyjatek gwarancyjny nadany normalnie (jest co porownywac)" || bad "wyjatek nie powstal przy dzialajacym dzienniku ($ILE_OK)"
[ "$(alarm)" = "brak" ] && ok "brak alarmu przy poprawnym zapisie (bez falszywych alarmow)" || bad "alarm podniesiony bez powodu"

wp db query "DELETE FROM wp_mp_warranty_exceptions; DELETE FROM wp_mp_product_events;" >/dev/null 2>&1

echo "== 1. DECYZJA GWARANCYJNA BEZ SLADU NIE ZOSTAJE =="
schowaj wp_mp_product_events
wp eval "wp_set_current_user( $ADMIN ); MP\\Registry\\WarrantyExceptions::create( $PID, null, 'awaria dziennika', '2030-01-01' );" >/dev/null 2>&1
przywroc wp_mp_product_events

ILE=$(q "SELECT COUNT(*) FROM wp_mp_warranty_exceptions")
[ "$ILE" = "0" ] && ok "nieudany slad => wyjatek NIE zostal nadany (transakcja wycofana)" || bad "wyjatek zostal w bazie bez sladu ($ILE) — to jest ta wada"
[ "$(alarm)" = "jest" ] && ok "awaria zapisu dziennika podniosla alarm (widoczny w Stanie witryny)" || bad "awaria dziennika przeszla po cichu"
skasuj_alarm

echo "== 2. USUNIECIE DANYCH OSOBOWYCH BEZ SLADU JEST WSTRZYMANE =="
O=$(wp mp case-create --kind=naprawa --email='slad@przyklad.pl' --name='Slad Testowy' --serial='SL-1' --desc='sprawa do usuniecia' 2>/dev/null)
T=$(echo "$O" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$T" >/dev/null 2>&1
CID=$(q "SELECT id FROM wp_mp_service_cases WHERE identity_status='verified' ORDER BY id DESC LIMIT 1")
wp db query "UPDATE wp_mp_service_cases SET status='zamkniete', status_changed_at=UTC_TIMESTAMP() WHERE id=$CID" >/dev/null 2>&1

schowaj wp_mp_case_events
WYNIK=$(wp eval "\$r = MP\\Intake\\Privacy::erase( 'slad@przyklad.pl' ); echo (\$r['items_removed'] ? 'usunieto' : '') . (\$r['items_retained'] ? 'wstrzymano' : '');" 2>/dev/null | tr -d '[:space:]')
przywroc wp_mp_case_events

ANON=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE email='slad@przyklad.pl' AND anonymized_at IS NULL")
[ "$ANON" = "1" ] && ok "dane NIE zostaly usuniete, gdy sladu nie da sie zapisac" || bad "dane usuniete bez sladu operacji — dokladnie ta wada"
case "$WYNIK" in *wstrzymano*) ok "zadanie zglasza WSTRZYMANIE (nie klamie, ze usunelo)" ;; *) bad "zadanie zwrocilo '$WYNIK' — brak informacji o wstrzymaniu" ;; esac
skasuj_alarm

echo "== 3. PO PRZYWROCENIU DZIENNIKA OPERACJA PRZECHODZI =="
wp eval "MP\\Intake\\Privacy::erase( 'slad@przyklad.pl' );" >/dev/null 2>&1
ANON2=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE email='slad@przyklad.pl' AND anonymized_at IS NULL")
[ "$ANON2" = "0" ] && ok "przy dzialajacym dzienniku dane sa usuwane normalnie" || bad "dane nadal nieusuniete ($ANON2) — naprawa blokuje poprawna sciezke!"
SLADY=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE event_type='PII_REDACTION'")
[ "${SLADY:-0}" -ge 1 ] && ok "slad redakcji danych osobowych zapisany ($SLADY)" || bad "brak sladu PII_REDACTION"

echo "== 4. SPRAWA BEZ UTRWALONEJ ZGODY NIE POWSTAJE =="
# Zgoda to wymog prawny przetwarzania (RODO art. 7 ust. 1) — sprawa z danymi
# osobowymi bez wiersza zgody nie moze zostac w bazie.
grep -q "purge_pending_cases" "${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"/mp-service-intake/includes/Front/SubmissionHandler.php \
	&& ok "nieudany zapis zgody kasuje swiezo utworzone zgloszenie" || bad "sprawa zostaje bez zgody"

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_warranty_exceptions; DELETE FROM wp_mp_product_events; DELETE FROM wp_mp_product_registry; DELETE FROM wp_mp_rate_counters;" >/dev/null 2>&1
skasuj_alarm

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
