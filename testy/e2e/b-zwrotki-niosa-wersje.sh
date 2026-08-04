#!/usr/bin/env bash
# ZYWY DOWOD (2.27, strona rejestru): zwrotki rejestru niosa wersje schematu.
#
# `API-KONTRAKT.md:10` stawia to bezwarunkowo: „Zwrotki niosa schema_version".
# W calym produkcie pole trafialo do odpowiedzi DOKLADNIE DWA RAZY
# (`WarrantyCheck.php:93` i `WorkflowEvents.php:115`). Odbiorca, ktory zgodnie
# z kontraktem sprawdza wersje PRZED odczytem danych, przy pozostalych punktach
# styku nie dostawal jej wcale — kontrakt obiecywal wiecej, niz kod dowozil.
#
# Ten test pilnuje, ze:
#   1. zwrotka `mp_product_details` niesie wersje (dotad nie niosla),
#   2. zwrotka `mp_privacy_redact_for_customer` niesie ja na OBU sciezkach,
#   3. zwrotka `mp_warranty_check` dalej ja niesie (kontrola, ze nic nie zepsulem),
#   4. wersje sa czytane ze STALYCH klas, nie wpisane w test,
#   5. dotychczasowe pola zwrotek zostaly nietkniete (zero regresji u odbiorcy),
#   6. zwrotki SKALARNE zostaja skalarami — tam wersji dolozyc sie nie da.
#
# ⛔ ZAKRES: to zamyka strone REJESTRU. Zwrotki modulu zgloszen sa poza granica
# tego buildera i zostaja otwarte — patrz opis PR.
#
# Wymaga zywego `wp`. Exit 0 = OK. Test sprzata po sobie (wspolna baza w CI).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

SERIAL='ZWR-TEST-1'
NORM='ZWRTEST1'

sprzataj() {
	P=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$NORM';")
	if [ -n "$P" ]; then
		wp db query "DELETE FROM wp_mp_warranty_exceptions WHERE product_registry_id=$P;" >/dev/null 2>&1
		wp db query "DELETE FROM wp_mp_product_events WHERE product_registry_id=$P;" >/dev/null 2>&1
		wp db query "DELETE FROM wp_mp_product_registry WHERE id=$P;" >/dev/null 2>&1
	fi
}

sprzataj

wp db query "INSERT INTO wp_mp_product_registry
	(serial_display, serial_normalized, model, batch, category, purchase_document, purchase_date, warranty_until, source, archived, created_at, updated_at)
	VALUES ('$SERIAL','$NORM','Model-Z','P-27','agd','FV/2026/27','2026-01-10','2030-01-10','csv_import',0,UTC_TIMESTAMP(),UTC_TIMESTAMP());" >/dev/null 2>&1
PID=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$NORM';")

# ⛔ Numerow wersji NIE wpisujemy — czytamy je ze stalych klas, wiec test przezyje
# podniesienie ksztaltu zwrotki (wtedy ma sie zmienic stala, nie test).
W_DETAILS=$(wp eval 'echo MP\Registry\Repo::DETAILS_SCHEMA_VERSION;' 2>/dev/null | tr -d '[:space:]')
W_REDACT=$(wp eval 'echo MP\Registry\WarrantyExceptions::REDACT_SCHEMA_VERSION;' 2>/dev/null | tr -d '[:space:]')
W_CHECK=$(wp eval 'echo MP\Registry\WarrantyCheck::SCHEMA_VERSION;' 2>/dev/null | tr -d '[:space:]')

if [ -z "$PID" ]; then
	bad "nie udalo sie zalozyc produktu do proby"
	sprzataj
	echo "WYNIK: $PASS ok, $FAIL fail"
	exit 1
fi

echo "== 0. STALE WERSJI ISTNIEJA =="
[ -n "$W_DETAILS" ] && ok "Repo::DETAILS_SCHEMA_VERSION = $W_DETAILS" || bad "brak stalej wersji dla zwrotki mp_product_details"
[ -n "$W_REDACT" ]  && ok "WarrantyExceptions::REDACT_SCHEMA_VERSION = $W_REDACT" || bad "brak stalej wersji dla zwrotki mp_privacy_redact_for_customer"
[ -n "$W_CHECK" ]   && ok "WarrantyCheck::SCHEMA_VERSION = $W_CHECK (kontrola: ta byla od poczatku)" || bad "brak stalej wersji dla zwrotki mp_warranty_check"

echo "== 1. ZWROTKA mp_product_details NIESIE WERSJE =="
D_WER=$(wp eval "\$d = apply_filters( 'mp_product_details', null, $PID ); echo isset( \$d['schema_version'] ) ? \$d['schema_version'] : 'BRAK';" 2>/dev/null | tr -d '[:space:]')
[ "$D_WER" = "$W_DETAILS" ] && [ -n "$W_DETAILS" ] \
	&& ok "zwrotka niesie wersje zgodna ze stala ($D_WER)" \
	|| bad "zwrotka mp_product_details: wersja '$D_WER', stala '$W_DETAILS'"

echo "== 2. DOTYCHCZASOWE POLA ZWROTKI NIETKNIETE (zero regresji u odbiorcy) =="
BRAKUJE=0
for POLE in id serial model batch purchase_document purchase_date warranty_until warranty_status archived; do
	JEST=$(wp eval "\$d = apply_filters( 'mp_product_details', null, $PID ); echo array_key_exists( '$POLE', (array) \$d ) ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]')
	if [ "$JEST" != "tak" ]; then
		BRAKUJE=$((BRAKUJE + 1))
		echo "  --   brakuje pola '$POLE'"
	fi
done
[ "$BRAKUJE" -eq 0 ] \
	&& ok "komplet dotychczasowych pol zwrotki na miejscu (9 pol sprawdzonych po kolei)" \
	|| bad "zwrotka zgubila $BRAKUJE z 9 dotychczasowych pol"

echo "== 3. ZWROTKA mp_privacy_redact_for_customer NIESIE WERSJE NA OBU SCIEZKACH =="
# Sciezka A: brak spraw klienta (pusta lista) — wczesne wyjscie z funkcji.
P_PUSTA=$(wp eval "\$r = apply_filters( 'mp_privacy_redact_for_customer', null, 1, array() ); echo isset( \$r['schema_version'] ) ? \$r['schema_version'] : 'BRAK';" 2>/dev/null | tr -d '[:space:]')
[ "$P_PUSTA" = "$W_REDACT" ] && [ -n "$W_REDACT" ] \
	&& ok "sciezka bez spraw: wersja obecna ($P_PUSTA)" \
	|| bad "sciezka bez spraw: wersja '$P_PUSTA', stala '$W_REDACT'"
# Sciezka B: z lista spraw — pelne zapytanie do bazy.
P_PELNA=$(wp eval "\$r = apply_filters( 'mp_privacy_redact_for_customer', null, 1, array( 999999 ) ); echo isset( \$r['schema_version'] ) ? \$r['schema_version'] : 'BRAK';" 2>/dev/null | tr -d '[:space:]')
[ "$P_PELNA" = "$W_REDACT" ] && [ -n "$W_REDACT" ] \
	&& ok "sciezka z lista spraw: wersja obecna ($P_PELNA)" \
	|| bad "sciezka z lista spraw: wersja '$P_PELNA', stala '$W_REDACT'"
P_SUKCES=$(wp eval "\$r = apply_filters( 'mp_privacy_redact_for_customer', null, 1, array() ); echo array_key_exists( 'success', (array) \$r ) && array_key_exists( 'redacted_count', (array) \$r ) ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]')
[ "$P_SUKCES" = "tak" ] && ok "pola success i redacted_count nietkniete" || bad "zwrotka RODO zgubila swoje pola"

echo "== 4. ZWROTKA mp_warranty_check DALEJ NIESIE WERSJE (proba kontrolna) =="
C_WER=$(wp eval "\$c = apply_filters( 'mp_warranty_check', null, '$SERIAL', null, null ); echo isset( \$c['schema_version'] ) ? \$c['schema_version'] : 'BRAK';" 2>/dev/null | tr -d '[:space:]')
[ "$C_WER" = "$W_CHECK" ] && [ -n "$W_CHECK" ] \
	&& ok "zwrotka sprawdzenia gwarancji dalej z wersja ($C_WER)" \
	|| bad "zwrotka mp_warranty_check: wersja '$C_WER', stala '$W_CHECK'"

echo "== 5. ZWROTKI SKALARNE ZOSTAJA SKALARAMI =="
# ⚠️ Uczciwie: `mp_serial_usage_count` i `mp_product_category` oddaja LICZBE i NAPIS,
# a nie tablice. Wersji nie da sie tam dolozyc bez zlamania kontraktu u odbiorcy —
# i tego wlasnie ten blok pilnuje, zeby nikt tego nie „naprawil" w zlym kierunku.
TYP_LICZ=$(wp eval "\$v = apply_filters( 'mp_serial_usage_count', null, '$SERIAL' ); echo gettype( \$v );" 2>/dev/null | tr -d '[:space:]')
case "$TYP_LICZ" in
	array) bad "mp_serial_usage_count zmienil sie w tablice — to zlamanie kontraktu u odbiorcy" ;;
	*)     ok "mp_serial_usage_count dalej skalar ($TYP_LICZ)" ;;
esac
TYP_KAT=$(wp eval "\$v = apply_filters( 'mp_product_category', null, $PID ); echo gettype( \$v );" 2>/dev/null | tr -d '[:space:]')
case "$TYP_KAT" in
	array) bad "mp_product_category zmienil sie w tablice — to zlamanie kontraktu u odbiorcy" ;;
	*)     ok "mp_product_category dalej skalar ($TYP_KAT)" ;;
esac

sprzataj

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
