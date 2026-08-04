#!/usr/bin/env bash
# ZYWY DOWOD (poz. 2.60): powod wyjatku gwarancyjnego znika przy zadaniu RODO
# z OBU kopii, nie z jednej.
#
# CO BYLO ZLE: produkt sam uznaje ten tekst za wymagajacy usuniecia — rejestr redaguje
# swoja kopie (`WarrantyExceptions::privacy_redact`). Ale odpowiedz o gwarancji razem
# z PELNYM powodem jest przy zakladaniu sprawy ZAMRAZANA w migawce
# (`warranty_snapshot` w tabeli spraw), a redakcja danych sprawy czyscila WYLACZNIE
# `form_data`. Tekst uznany przez produkt za wymagajacy redakcji zostawal w bazie
# w drugiej kopii — mimo WYKONANEGO zadania usuniecia danych.
#
# ⛔ Rejestr NIE MOZE tego posprzatac sam: migawka lezy w tabeli modulu zgloszen, a
# pisanie po cudzych tabelach lapie `build/lint-cudze-tabele.php`. Dlatego naprawa
# siedzi w `CaseRepo::redact_pii_for_cases` — tam, gdzie ta kolumna nalezy.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
qraw(){ wp db query "$1" --skip-column-names 2>/dev/null; }

POWOD='Zgoda kierownika dla Jana Kowalskiego, tel. 555-111-222'
SERIAL='SEK-2-60'
MAIL='migawka260@example.com'

# ── 0. Produkt + AKTYWNY wyjatek gwarancyjny Z POWODEM (kolejnosc ma znaczenie) ─
# Wyjatek musi istniec ZANIM powstanie sprawa — migawka zamraza to, co widzi
# w chwili zgloszenia. Wyjatek zalozony pozniej nie trafilby do migawki wcale.
wp db query "DELETE FROM wp_mp_warranty_exceptions WHERE reason = '$POWOD'" >/dev/null 2>&1
wp db query "INSERT INTO wp_mp_product_registry (serial_display, serial_normalized, model, batch, warranty_until, source, created_at, updated_at)
	VALUES ('$SERIAL','SEK260','Model 260','PARTIA-260','2020-01-01','manual',UTC_TIMESTAMP(),UTC_TIMESTAMP())" >/dev/null 2>&1
PID=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='SEK260' ORDER BY id DESC LIMIT 1")
wp db query "INSERT INTO wp_mp_warranty_exceptions (product_registry_id, case_id, status, valid_from, valid_until, reason, created_by, created_at)
	VALUES ($PID, NULL, 'active', UTC_TIMESTAMP(), NULL, '$POWOD', 1, UTC_TIMESTAMP())" >/dev/null 2>&1
WYJ=$(q "SELECT COUNT(*) FROM wp_mp_warranty_exceptions WHERE product_registry_id=$PID AND status='active'")
[ "${WYJ:-0}" -ge 1 ] 2>/dev/null && ok "przygotowanie: produkt $PID z aktywnym wyjatkiem gwarancyjnym" || bad "nie udalo sie zalozyc wyjatku ($WYJ)"

# ── 1. Sprawa zakladana, gdy wyjatek JUZ stoi => powod wpada do migawki ────
OUT=$(wp mp case-create --kind=reklamacja --email="$MAIL" --name='Jan Kowalski' \
	--serial="$SERIAL" --document='FV/260/1' --date='2026-03-15' --desc='opis zgloszenia' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
TOKEN=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$TOKEN" >/dev/null 2>&1

MIGAWKA_PRZED=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id=$CID AND warranty_snapshot LIKE '%555-111-222%'")
[ "${MIGAWKA_PRZED:-0}" = "1" ] \
	&& ok "przygotowanie: powod wyjatku JEST zamrozony w migawce sprawy $CID" \
	|| bad "migawka nie zawiera powodu — ten dowod nie mialby czego sprawdzac ($MIGAWKA_PRZED)"

# ── 2. Zamkniecie sprawy REALNA droga (eraser odracza sprawy aktywne) ─────
wp eval "apply_filters('mp_case_change_status', null, $CID, 'zamknięte', 'nowe', 1, null);" >/dev/null 2>&1
STATUS=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
[ "$STATUS" = "zamknięte" ] && ok "sprawa zamknieta (eraser nie odroczy)" || bad "sprawa nie zamknieta ($STATUS)"

# ── 3. ZADANIE RODO ───────────────────────────────────────────────────────
WYNIK=$(wp eval "\$r = MP\\Intake\\Privacy::erase('$MAIL'); echo empty(\$r['items_removed']) ? 'NIC' : 'USUNIETO';" 2>/dev/null | tr -d '[:space:]')
[ "$WYNIK" = "USUNIETO" ] && ok "zadanie usuniecia danych wykonane (items_removed)" || bad "eraser nic nie zrobil ($WYNIK)"

# ── 4. SEDNO: powod znika z OBU kopii ─────────────────────────────────────
W_MIGAWCE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id=$CID AND warranty_snapshot LIKE '%555-111-222%'")
[ "${W_MIGAWCE:-1}" = "0" ] \
	&& ok "SEDNO 2.60: powodu NIE MA juz w migawce gwarancji sprawy" \
	|| bad "powod wyjatku zostal w migawce mimo wykonanego zadania RODO"

ZNACZNIK=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id=$CID AND warranty_snapshot LIKE '%ZREDAGOWANO-RODO%'")
[ "${ZNACZNIK:-0}" = "1" ] \
	&& ok "migawka niesie ZNACZNIK redakcji, nie pusta wartosc (widac, ze redagowano)" \
	|| bad "brak znacznika redakcji w migawce ($ZNACZNIK)"

# ⭐ WYSZLO PRZY KALIBRACJI I JEST WAZNE: wyjatek PRODUKTOWY (case_id NULL) zostaje
# w rejestrze nietkniety — i tak MA byc. Rejestr redaguje powody wyjatkow POWIAZANYCH
# ZE SPRAWAMI klienta (`WHERE case_id IN (...)`), bo wyjatek zalozony na PRODUKT nie
# jest danymi tego klienta: dotyczy egzemplarza i obowiazuje takze innym sprawom.
# Skasowanie go na zadanie jednej osoby zniszczyloby cudze dane.
#
# ⛔ I dopiero to domyka sens tej naprawy: migawke moze wypelnic WYLACZNIE wyjatek
# produktowy (w chwili zakladania sprawy jej numeru jeszcze nie ma, wiec wyjatku
# powiazanego ze sprawa nie da sie zamrozic). Czyli kopia w sprawie to JEDYNA kopia,
# ktora jest danymi tego klienta — i jedyna, ktorej dotad nie sprzatal nikt.
W_REJESTRZE=$(q "SELECT COUNT(*) FROM wp_mp_warranty_exceptions WHERE product_registry_id=$PID AND reason LIKE '%555-111-222%'")
[ "${W_REJESTRZE:-0}" = "1" ] \
	&& ok "wyjatek PRODUKTOWY zostaje w rejestrze (to dane egzemplarza, nie klienta)" \
	|| bad "redakcja siegnela wyjatku produktowego — to cudze dane ($W_REJESTRZE)"

# Kontrola przekrojowa: tekst nie moze zostac w ZADNEJ kolumnie spraw TEGO klienta.
# ⚠️ Zawezenie do klienta jest konieczne, a nie wygodne: zadanie RODO dotyczy JEGO
# danych, wiec sprawy innych osob (i sprawy zostawione przez wczesniejsze przebiegi
# tego testu) nie moga wchodzic do pomiaru. Pierwsza wersja liczyla cala tabele
# i pokazywala „2" takze po poprawnej redakcji — mierzyla smieci, nie produkt.
GDZIEKOLWIEK=$(q "SELECT COUNT(*) FROM wp_mp_service_cases
	WHERE customer_id = (SELECT customer_id FROM wp_mp_service_cases WHERE id=$CID)
	AND ( warranty_snapshot LIKE '%555-111-222%' OR form_data LIKE '%555-111-222%' )")
[ "${GDZIEKOLWIEK:-1}" = "0" ] \
	&& ok "tekstu nie ma w ZADNEJ kolumnie tabeli spraw" \
	|| bad "tekst nadal gdzies w tabeli spraw ($GDZIEKOLWIEK)"

# ── 5. Reszta migawki NIETKNIETA — redagujemy powod, nie dane techniczne ──
MODEL=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id=$CID AND warranty_snapshot LIKE '%PARTIA-260%'")
[ "${MODEL:-0}" = "1" ] \
	&& ok "partia i reszta migawki zostaja (to dane produktu, nie osobowe)" \
	|| bad "redakcja zjadla dane techniczne migawki ($MODEL)"

# ── Sprzatanie danych podlozonych przez ten test ──────────────────────────
wp db query "DELETE FROM wp_mp_warranty_exceptions WHERE product_registry_id=$PID" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_product_registry WHERE id=$PID" >/dev/null 2>&1

echo ""
echo "WYNIK 2.60-MIGAWKA: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
