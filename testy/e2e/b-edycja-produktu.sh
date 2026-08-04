#!/usr/bin/env bash
# ZYWY DOWOD: poprawianie danych produktu + historia zmian.
#
# Specyfikacja, plugin 2: „historia zmian danych produktu i decyzji gwarancyjnych".
# Decyzje gwarancyjne byly logowane od poczatku, ale danych produktu NIE DALO SIE
# ZMIENIC (wchodzily wylacznie importem, ponowny import odrzucal duplikat seriala),
# wiec historia zmian danych nie miala czego zapisywac. Ten test pilnuje, ze:
#   1. poprawka zapisuje sie w rejestrze,
#   2. trafia do historii produktu jako PRODUCT_UPDATED z diffem przed/po,
#   3. numer faktury NIE laduje w historii z wartoscia (PII, MAPA-PII w DATABASE.md),
#   4. numeru seryjnego NIE da sie podmienic (klucz relacji sprawa->produkt),
#   5. bledna data i gwarancja przed zakupem sa odbijane,
#   6. produkt archiwalny jest chroniony przed edycja,
#   7. zmiana daty gwarancji REALNIE przestawia status gwarancji w zgloszeniach.
#
# Wymaga zywego `wp`. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

SERIAL='EDIT-TEST-1'
NORM='EDITTEST1'

# Czysty stan (test idempotentny — moze isc kilka razy pod rzad).
PID_OLD=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$NORM';")
if [ -n "$PID_OLD" ]; then
	wp db query "DELETE FROM wp_mp_product_events WHERE product_registry_id=$PID_OLD;" >/dev/null 2>&1
	wp db query "DELETE FROM wp_mp_product_registry WHERE id=$PID_OLD;" >/dev/null 2>&1
fi

ADM=$(wp user create edyt_adm edyt_adm@example.com --role=mp_system_admin --porcelain 2>/dev/null)
[ -z "$ADM" ] && ADM=$(wp user get edyt_adm --field=ID 2>/dev/null)

# Produkt jak po imporcie z systemu firmy — z BLEDNA data gwarancji (rok z palca).
wp db query "INSERT INTO wp_mp_product_registry
	(serial_display, serial_normalized, model, batch, category, purchase_document, purchase_date, warranty_until, source, archived, created_at, updated_at)
	VALUES ('$SERIAL','$NORM','Model-STARY','P-1','agd','FV/2026/900','2026-01-10','2024-01-10','csv_import',0,UTC_TIMESTAMP(),UTC_TIMESTAMP());" >/dev/null 2>&1

PID=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$NORM';")
[ -n "$PID" ] && ok "produkt testowy w rejestrze (id=$PID)" || { bad "nie udalo sie zalozyc produktu"; echo "WYNIK: $PASS ok, $FAIL fail"; exit 1; }

echo "== 1. Poprawka danych zapisuje sie i trafia do historii =="
OUT=$(wp eval "\$r = MP\Registry\Repo::update( $PID, array('model'=>'Model-NOWY','warranty_until'=>'2027-01-10'), $ADM ); echo isset(\$r['error']) ? 'ERR:'.\$r['error'] : 'CHANGED:'.\$r['changed'];" 2>&1)
[ "$OUT" = "CHANGED:2" ] && ok "zapisano 2 pola (zwrot: $OUT)" || bad "oczekiwano CHANGED:2, jest: $OUT"

MODEL=$(q "SELECT model FROM wp_mp_product_registry WHERE id=$PID;")
[ "$MODEL" = "Model-NOWY" ] && ok "model poprawiony w bazie" || bad "model w bazie: $MODEL"

WAR=$(q "SELECT warranty_until FROM wp_mp_product_registry WHERE id=$PID;")
[ "$WAR" = "2027-01-10" ] && ok "data gwarancji poprawiona w bazie" || bad "gwarancja w bazie: $WAR"

EV=$(q "SELECT COUNT(*) FROM wp_mp_product_events WHERE product_registry_id=$PID AND event_type='PRODUCT_UPDATED';")
[ "$EV" = "1" ] && ok "historia produktu: jeden wpis PRODUCT_UPDATED" || bad "wpisow PRODUCT_UPDATED: $EV (oczekiwano 1)"

PAY=$(wp db query "SELECT payload FROM wp_mp_product_events WHERE product_registry_id=$PID ORDER BY id DESC LIMIT 1;" --skip-column-names 2>/dev/null)
echo "$PAY" | grep -q 'Model-STARY' && echo "$PAY" | grep -q 'Model-NOWY' \
	&& ok "historia trzyma wartosc PRZED i PO" || bad "diff przed/po nie zapisany: $PAY"

echo "== 2. Numer faktury NIE trafia do historii z wartoscia (PII) =="
wp eval "MP\Registry\Repo::update( $PID, array('purchase_document'=>'FV/TAJNA/777'), $ADM );" >/dev/null 2>&1
PAY2=$(wp db query "SELECT payload FROM wp_mp_product_events WHERE product_registry_id=$PID ORDER BY id DESC LIMIT 1;" --skip-column-names 2>/dev/null)
DOC=$(q "SELECT purchase_document FROM wp_mp_product_registry WHERE id=$PID;")
[ "$DOC" = "FV/TAJNA/777" ] && ok "dokument zakupu zapisany w rejestrze" || bad "dokument w bazie: $DOC"
echo "$PAY2" | grep -q 'TAJNA' && bad "PII WYCIEKLO do historii: $PAY2" || ok "numer faktury nieobecny w historii (tylko fakt zmiany)"

echo "== 3. Numeru seryjnego nie da sie podmienic =="
wp eval "MP\Registry\Repo::update( $PID, array('serial_display'=>'PODMIENIONY','serial_normalized'=>'PODMIENIONY'), $ADM );" >/dev/null 2>&1
SER=$(q "SELECT serial_display FROM wp_mp_product_registry WHERE id=$PID;")
[ "$SER" = "$SERIAL" ] && ok "serial nietkniety mimo proby podmiany" || bad "SERIAL ZMIENIONY na: $SER"

echo "== 4. Bledne dane sa odbijane =="
OUT=$(wp eval "\$r = MP\Registry\Repo::update( $PID, array('warranty_until'=>'32.13.2026'), $ADM ); echo isset(\$r['error']) ? 'ERR' : 'PRZESZLO';" 2>&1)
[ "$OUT" = "ERR" ] && ok "niepoprawna data odrzucona" || bad "niepoprawna data przeszla ($OUT)"

OUT=$(wp eval "\$r = MP\Registry\Repo::update( $PID, array('warranty_until'=>'2020-01-01'), $ADM ); echo isset(\$r['error']) ? 'ERR' : 'PRZESZLO';" 2>&1)
[ "$OUT" = "ERR" ] && ok "gwarancja przed data zakupu odrzucona" || bad "gwarancja przed zakupem przeszla ($OUT)"

WAR2=$(q "SELECT warranty_until FROM wp_mp_product_registry WHERE id=$PID;")
[ "$WAR2" = "2027-01-10" ] && ok "odrzucona proba nie ruszyla danych" || bad "dane zmienione mimo bledu: $WAR2"

echo "== 5. Brak zmian = brak wpisu w historii (bez smiecenia) =="
EV_PRZED=$(q "SELECT COUNT(*) FROM wp_mp_product_events WHERE product_registry_id=$PID;")
OUT=$(wp eval "\$r = MP\Registry\Repo::update( $PID, array('model'=>'Model-NOWY'), $ADM ); echo \$r['changed'];" 2>&1)
EV_PO=$(q "SELECT COUNT(*) FROM wp_mp_product_events WHERE product_registry_id=$PID;")
[ "$OUT" = "0" ] && [ "$EV_PRZED" = "$EV_PO" ] && ok "ta sama wartosc = 0 zmian, historia bez nowego wpisu" || bad "changed=$OUT, historia $EV_PRZED -> $EV_PO"

echo "== 6. Produkt archiwalny chroniony =="
wp db query "UPDATE wp_mp_product_registry SET archived=1 WHERE id=$PID;" >/dev/null 2>&1
OUT=$(wp eval "\$r = MP\Registry\Repo::update( $PID, array('model'=>'Model-W-ARCHIWUM'), $ADM ); echo isset(\$r['error']) ? 'ERR' : 'PRZESZLO';" 2>&1)
[ "$OUT" = "ERR" ] && ok "edycja archiwalnego odrzucona" || bad "edycja archiwalnego przeszla"
wp db query "UPDATE wp_mp_product_registry SET archived=0 WHERE id=$PID;" >/dev/null 2>&1

echo "== 7. Poprawka daty REALNIE przestawia status gwarancji w zgloszeniach =="
# Sedno wymogu: zla data w imporcie = klient slyszy „gwarancja wygasla".
# Po poprawce ten sam produkt musi dawac „aktywna" — inaczej edycja jest ozdobna.
wp eval "MP\Registry\Repo::update( $PID, array('warranty_until'=>'2020-06-01','purchase_date'=>'2019-01-01'), $ADM );" >/dev/null 2>&1
ST1=$(wp eval "\$d = apply_filters('mp_product_details', null, $PID); echo \$d['warranty_status'];" 2>/dev/null | tr -d '[:space:]')
wp eval "MP\Registry\Repo::update( $PID, array('warranty_until'=>'2030-06-01'), $ADM );" >/dev/null 2>&1
ST2=$(wp eval "\$d = apply_filters('mp_product_details', null, $PID); echo \$d['warranty_status'];" 2>/dev/null | tr -d '[:space:]')
[ "$ST1" != "$ST2" ] && ok "status gwarancji zmienil sie po poprawce daty ($ST1 -> $ST2)" || bad "status nie zareagowal na poprawke ($ST1 -> $ST2)"

echo "== 8. Karta sprawy ostrzega, gdy dane poprawiono PO zgloszeniu =="
# Plakietka na karcie trzyma decyzje z chwili zgloszenia (swiadomie, naprawa 1.0.1),
# ale wiersz „Gwarancja do" pokazuje wartosc BIEZACA. Bez ostrzezenia pracownik widzi
# date 2030 obok czerwonego „wygasla" i nie wie, czemu wierzyc.
SNAP='{"status":"wygasla","warranty_until":"2020-06-01","schema_version":1}'
POWOD=$(wp eval "\$w = MP\Intake\Admin\CaseCard::warranty_view( json_decode('$SNAP', true), array('warranty_until'=>'2030-06-01') ); echo \$w['powod'];" 2>/dev/null)
echo "$POWOD" | grep -qi "poprawiono w rejestrze" && ok "rozjazd snapshot vs rejestr => ostrzezenie na karcie" || bad "brak ostrzezenia o poprawce (powod: $POWOD)"

STATUS_SNAP=$(wp eval "\$w = MP\Intake\Admin\CaseCard::warranty_view( json_decode('$SNAP', true), array('warranty_until'=>'2030-06-01') ); echo \$w['status'];" 2>/dev/null | tr -d '[:space:]')
[ "$STATUS_SNAP" = "wygasla" ] && ok "plakietka nadal pokazuje decyzje z chwili zgloszenia" || bad "plakietka zmieniona na: $STATUS_SNAP"

POWOD2=$(wp eval "\$w = MP\Intake\Admin\CaseCard::warranty_view( json_decode('{\"status\":\"aktywna\",\"warranty_until\":\"2030-06-01\",\"schema_version\":1}', true), array('warranty_until'=>'2030-06-01') ); echo \$w['powod'];" 2>/dev/null)
echo "$POWOD2" | grep -qi "poprawiono w rejestrze" && bad "ostrzezenie pokazuje sie BEZ zmiany danych" || ok "brak zmiany = brak ostrzezenia (bez falszywych alarmow)"

# Sprzatanie po sobie.
wp db query "DELETE FROM wp_mp_product_events WHERE product_registry_id=$PID;" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_product_registry WHERE id=$PID;" >/dev/null 2>&1
wp user delete "$ADM" --yes >/dev/null 2>&1

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
