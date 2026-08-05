#!/usr/bin/env bash
# ZYWY DOWOD Z7 (audyt dzialu, 2026-08-05 — DUZE): obietnica bez wykonawcy.
#
# Panel po wycofaniu zgody przy aktywnej sprawie mowil: „dane usuniemy po jego
# zakonczeniu" — ale Privacy::erase wolal TYLKO przycisk panelu i reczny eraser
# WP. Po zamknieciu sprawy dane lezaly w bazie NA ZAWSZE, chyba ze czlowiek
# kliknal jeszcze raz. FIX: dobowy cron retencji (mp_intake_retention_sweep)
# wykonuje odroczone usuniecie ta sama sciezka Privacy::erase co przycisk.
#
# Kryterium kandydata: OSTATNI wpis rejestru zgod adresu to wycofanie + zero
# spraw nieterminalnych + kartoteka zywa. EDGE: nowa zgoda PO wycofaniu (nowe
# zgloszenie tej samej osoby) ANULUJE odroczenie. Wspolna skrzynka, w ktorej
# wycofala tylko jedna osoba z kilku, NIE uruchamia kasowania cudzych danych.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
# UWAGA: q() usuwa CALE biale znaki z wyniku — oczekiwania tez pisz bez spacji.
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_attachments;" >/dev/null 2>&1
for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done

# Zgoda jak z formularza: wiersz z e-mailem i sprawa (CLI case-create zgod nie
# zapisuje — robi to front; test odtwarza to jawnie, ta sama klasa Consents).
zgoda() { # $1=email $2=case_id
	wp eval "echo MP\Intake\Consents::record('$1', $2, MP\Intake\Consents::KEY_PROCESSING, MP\Intake\Consents::VERSION, MP\Intake\Consents::processing_text());" 2>/dev/null
}
zamknij() { # $1=case_id — sciezka produkcyjna, a gdy maszyna stanow odmowi
	# przejscia wprost (nowe->zamkniete), stan wymuszamy SQL-em: testujemy
	# wykonawce odroczenia, nie maszyne stanow (te kryja osobne testy).
	wp eval "apply_filters('mp_case_change_status', null, $1, 'zamknięte', 'nowe', 1);" >/dev/null 2>&1
	wp db query "UPDATE wp_mp_service_cases SET status='zamknięte' WHERE id=$1" >/dev/null 2>&1
}

# ── A. SCENARIUSZ WADY 1:1: wycofanie przy aktywnej sprawie → zamkniecie → cron ──
OA=$(wp mp case-create --kind=zapytanie --email='odroczona@example.com' --name='Anna Odroczona' --desc='opis Anny' 2>/dev/null)
TA=$(echo "$OA" | grep '^token=' | cut -d= -f2)
CA=$(echo "$OA" | grep '^case_id=' | cut -d= -f2)
zgoda 'odroczona@example.com' "$CA" >/dev/null
wp mp case-verify "$TA" >/dev/null 2>&1
KA=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CA")

# Wycofanie DOKLADNIE jak przycisk panelu: withdraw + natychmiastowy erase.
RESA=$(wp eval "MP\Intake\Consents::withdraw($KA, MP\Intake\Consents::KEY_PROCESSING); echo json_encode(MP\Intake\Privacy::erase('odroczona@example.com'));" 2>/dev/null)
echo "$RESA" | grep -q '"items_retained":true' && ok "A1: aktywna sprawa => eraser ODRACZA (obietnica panelu pada)" || bad "A1: eraser nie odroczyl ($RESA)"
ANON_A0=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE id=$KA AND anonymized_at IS NOT NULL")
[ "$ANON_A0" = "0" ] && ok "A2: przy aktywnej sprawie dane NIE ruszone" || bad "A2: skasowano dane przy aktywnej sprawie!"

zamknij "$CA"

# WYKONAWCA OBIETNICY: przebieg crona retencji (ten sam hook co harmonogram).
wp eval "do_action('mp_intake_retention_sweep');" >/dev/null 2>&1

ANON_A1=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE id=$KA AND anonymized_at IS NOT NULL")
[ "$ANON_A1" = "1" ] && ok "A3: po zamknieciu sprawy CRON wykonal odroczone usuniecie" || bad "A3: obietnica dalej bez wykonawcy — dane leza po zamknieciu sprawy"
MAIL_A=$(q "SELECT email FROM wp_mp_customers WHERE id=$KA")
echo "$MAIL_A" | grep -q 'removed.invalid' && ok "A4: e-mail kartoteki zanonimizowany ($MAIL_A)" || bad "A4: e-mail zostal ($MAIL_A)"
ZGODA_MAIL=$(q "SELECT COUNT(*) FROM wp_mp_consents WHERE customer_id=$KA AND email NOT LIKE 'anon-%'")
[ "$ZGODA_MAIL" = "0" ] && ok "A5: e-mail w rejestrze zgod zredagowany (rozliczalnosc zostaje)" || bad "A5: PII zostalo w zgodach ($ZGODA_MAIL)"
SLAD=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CA AND event_type='PII_REDACTION'")
[ "${SLAD:-0}" -ge 1 ] 2>/dev/null && ok "A6: slad PII_REDACTION na osi sprawy (ta sama sciezka co przycisk)" || bad "A6: brak sladu redakcji ($SLAD)"

# Idempotencja: drugi przebieg niczego nie dubluje.
wp eval "do_action('mp_intake_retention_sweep');" >/dev/null 2>&1
SLAD2=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CA AND event_type='PII_REDACTION'")
[ "$SLAD2" = "$SLAD" ] && ok "A7: drugi przebieg crona = zero nowej roboty (idempotencja)" || bad "A7: cron dublowal redakcje ($SLAD -> $SLAD2)"

# ── B. EDGE: NOWA zgoda po wycofaniu ANULUJE odroczenie ─────────────────────
OB=$(wp mp case-create --kind=zapytanie --email='wraca@example.com' --name='Bartek Wraca' --desc='opis Bartka' 2>/dev/null)
TB=$(echo "$OB" | grep '^token=' | cut -d= -f2)
CB=$(echo "$OB" | grep '^case_id=' | cut -d= -f2)
zgoda 'wraca@example.com' "$CB" >/dev/null
wp mp case-verify "$TB" >/dev/null 2>&1
KB=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CB")

# Wycofanie przy aktywnej sprawie => odroczenie wisi.
wp eval "MP\Intake\Consents::withdraw($KB, MP\Intake\Consents::KEY_PROCESSING); MP\Intake\Privacy::erase('wraca@example.com');" >/dev/null 2>&1
zamknij "$CB"

# Ta sama osoba WRACA: nowe zgloszenie = nowa zgoda (nowszy wiersz bez withdrawn_at).
OB2=$(wp mp case-create --kind=zapytanie --email='wraca@example.com' --name='Bartek Wraca' --desc='wrocilem' 2>/dev/null)
TB2=$(echo "$OB2" | grep '^token=' | cut -d= -f2)
CB2=$(echo "$OB2" | grep '^case_id=' | cut -d= -f2)
zgoda 'wraca@example.com' "$CB2" >/dev/null
wp mp case-verify "$TB2" >/dev/null 2>&1
# Nowa sprawa tez zamknieta — zeby kryterium zgod bylo JEDYNA ochrona
# (przy otwartej sprawie chronilby juz warunek nieterminalnosci).
zamknij "$CB2"

wp eval "do_action('mp_intake_retention_sweep');" >/dev/null 2>&1
ANON_B=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE id=$KB AND anonymized_at IS NOT NULL")
[ "$ANON_B" = "0" ] && ok "B1: nowa zgoda po wycofaniu ANULUJE odroczenie — dane zostaja" || bad "B1: cron skasowal dane osoby, ktora ODNOWILA zgode!"

# ── C. BEZ WADY: sciezka natychmiastowa dziala jak dotad ────────────────────
OC=$(wp mp case-create --kind=zapytanie --email='natychmiast@example.com' --name='Celina Szybka' --desc='opis Celiny' 2>/dev/null)
TC=$(echo "$OC" | grep '^token=' | cut -d= -f2)
CC=$(echo "$OC" | grep '^case_id=' | cut -d= -f2)
zgoda 'natychmiast@example.com' "$CC" >/dev/null
wp mp case-verify "$TC" >/dev/null 2>&1
KC=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CC")
zamknij "$CC"

RESC=$(wp eval "MP\Intake\Consents::withdraw($KC, MP\Intake\Consents::KEY_PROCESSING); echo json_encode(MP\Intake\Privacy::erase('natychmiast@example.com'));" 2>/dev/null)
echo "$RESC" | grep -q '"items_removed":true' && ok "C1: klik bez aktywnej sprawy = usuniecie NATYCHMIAST (bez czekania na cron)" || bad "C1: natychmiastowa sciezka zepsuta ($RESC)"
ANON_C=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE id=$KC AND anonymized_at IS NOT NULL")
[ "$ANON_C" = "1" ] && ok "C2: kartoteka zanonimizowana od reki" || bad "C2: brak anonimizacji ($ANON_C)"

# ── D. WSPOLNA SKRZYNKA: wycofala JEDNA osoba z dwoch => cron NIE kasuje ────
OD1=$(wp mp case-create --kind=zapytanie --email='sekretariat@example.com' --name='Dorota Pierwsza' --desc='opis Doroty' 2>/dev/null)
TD1=$(echo "$OD1" | grep '^token=' | cut -d= -f2)
CD1=$(echo "$OD1" | grep '^case_id=' | cut -d= -f2)
zgoda 'sekretariat@example.com' "$CD1" >/dev/null
wp mp case-verify "$TD1" >/dev/null 2>&1
KD1=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CD1")

OD2=$(wp mp case-create --kind=zapytanie --email='sekretariat@example.com' --name='Edward Drugi' --desc='opis Edwarda' 2>/dev/null)
TD2=$(echo "$OD2" | grep '^token=' | cut -d= -f2)
CD2=$(echo "$OD2" | grep '^case_id=' | cut -d= -f2)
zgoda 'sekretariat@example.com' "$CD2" >/dev/null
wp mp case-verify "$TD2" >/dev/null 2>&1
KD2=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CD2")

if [ -n "$KD1" ] && [ -n "$KD2" ] && [ "$KD1" != "$KD2" ]; then
	ok "D0: dwie osoby pod wspolnym adresem = dwie kartoteki ($KD1, $KD2)"
else
	bad "D0: seed wspolnej skrzynki nie rozdzielil kartotek ($KD1/$KD2)"
fi

wp eval "MP\Intake\Consents::withdraw($KD1, MP\Intake\Consents::KEY_PROCESSING);" >/dev/null 2>&1
zamknij "$CD1"
zamknij "$CD2"

wp eval "do_action('mp_intake_retention_sweep');" >/dev/null 2>&1
ANON_D=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE id IN ($KD1,$KD2) AND anonymized_at IS NOT NULL")
[ "$ANON_D" = "0" ] && ok "D1: wycofanie JEDNEJ osoby nie kasuje danych DRUGIEJ (wniosek przez personel, jak w panelu)" || bad "D1: cron skasowal dane osoby, ktora zgody NIE wycofala!"

echo ""
echo "WYNIK C-Z7-RODO-ODROCZONE-USUNIECIE: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
