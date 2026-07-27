#!/usr/bin/env bash
# ZYWY DOWOD C20 (znalezisko #8 audytu 27.07 — wyscig RODO przy usuwaniu danych):
# Klient zada usuniecia danych, a rownolegle dopina sie jego nowa sprawa.
# Przed naprawa: nowa sprawa zostawala z PELNYM PII przy "usunietym" kliencie,
# poza spisem redakcji, a raport klamal "dane usunieto".
# Po naprawie (transakcja + blokada wiersza klienta + recheck spisu):
# - przebieg 1: sprawa dopinana W OKNIE (po spisie, przed anonimizacja —
#   symulacja przez filtr mp_privacy_redact_for_customer, surowy UPDATE bez
#   wlasnej transakcji) => eraser ODRACZA, rollback cofa czesciowa redakcje
#   I wstrzykniete wpiecie (nic nie wisi przy anonimie),
# - przebieg 2: wyscig DOKONCZONY tuz przed blokada (commitowany UPDATE) =>
#   klasyczne odroczenie: aktywna dopieta sprawa jest w spisie,
# - przebieg 3: po zamknieciu sprawy eraser dokancza usuwanie DO ZERA
#   (klient zanonimizowany, wiadomosci i PII dopietej sprawy zredagowane).
# Pliki zalacznikow kasowane dopiero PO commicie (rollback nie przywraca plikow).
# Wymaga MP_BASE (spojnosc z reszta pakietu; sam test chodzi przez wp-cli).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
# UWAGA: q() usuwa CALE biale znaki z wyniku — oczekiwania tez pisz bez spacji.
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_attachments;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done

# ── Przygotowanie: Ewa (zamknieta sprawa + wiadomosc) i cudza sprawa-intruz ──
OE=$(wp mp case-create --kind=zapytanie --email='wyscig@example.com' --name='Ewa Testowa' --desc='opis Ewy' 2>/dev/null)
TE=$(echo "$OE" | grep '^token=' | cut -d= -f2)
CE=$(echo "$OE" | grep '^case_id=' | cut -d= -f2)
wp mp case-verify "$TE" >/dev/null 2>&1
CUSTE=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CE")
wp eval "MP\Intake\Messages::add($CE, 'client', 1, 'tajna wiadomosc Ewy');" >/dev/null 2>&1
wp eval "apply_filters('mp_case_change_status', null, $CE, 'zamknięte', 'nowe', 1);" >/dev/null 2>&1

OI=$(wp mp case-create --kind=zapytanie --email='intruz@example.com' --name='Igor Intruz' --desc='opis Igora' 2>/dev/null)
TI=$(echo "$OI" | grep '^token=' | cut -d= -f2)
CIC=$(echo "$OI" | grep '^case_id=' | cut -d= -f2)
wp mp case-verify "$TI" >/dev/null 2>&1
CUSTI=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CIC")

# ── Przebieg 1: dopiecie W OKNIE WYSCIGU => odroczenie + pelny rollback ──────
RES1=$(wp eval "
add_filter('mp_privacy_redact_for_customer', function(\$r, \$cid, \$ids) {
	// Symulacja wyscigu: dopiecie sprawy po spisie, przed anonimizacja.
	// Surowy UPDATE (bez CaseRepo) — nie otwiera wlasnej transakcji.
	global \$wpdb;
	\$wpdb->query(\"UPDATE wp_mp_service_cases SET customer_id=$CUSTE WHERE id=$CIC\");
	return \$r;
}, 5, 3);
echo json_encode(MP\Intake\Privacy::erase('wyscig@example.com'));
" 2>/dev/null)

echo "$RES1" | grep -q '"items_retained":true' && ok "wyscig wykryty => eraser ODROCZYL (items_retained)" || bad "eraser nie odroczyl mimo dopietej sprawy ($RES1)"
echo "$RES1" | grep -q '"items_removed":false' && ok "raport NIE klamie, ze usunieto" || bad "raport twierdzi 'usunieto' mimo sprawy z PII ($RES1)"

ANON1=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE id=$CUSTE AND anonymized_at IS NOT NULL")
[ "$ANON1" = "0" ] && ok "klient NIE zanonimizowany w pol drogi" || bad "klient zanonimizowany mimo odroczenia"
MSG1=$(q "SELECT body FROM wp_mp_messages WHERE case_id=$CE AND author_type='client'")
[ "$MSG1" = "tajnawiadomoscEwy" ] && ok "rollback COFNAL czesciowa redakcje wiadomosci" || bad "wiadomosc w pol drogi zredagowana/utracona ($MSG1)"
WLASC1=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CIC")
[ "$WLASC1" = "$CUSTI" ] && ok "rollback cofnal tez wpiecie — sprawa u prawowitego klienta, nie przy anonimie" || bad "sprawa wisi nie tam gdzie trzeba ($WLASC1)"

# ── Przebieg 2: wyscig DOKONCZONY przed blokada => aktywna sprawa w spisie ───
wp db query "UPDATE wp_mp_service_cases SET customer_id=$CUSTE WHERE id=$CIC" >/dev/null 2>&1
RES2=$(wp eval "echo json_encode(MP\Intake\Privacy::erase('wyscig@example.com'));" 2>/dev/null)
echo "$RES2" | grep -q '"items_retained":true' && ok "dopieta AKTYWNA sprawa widziana => odroczenie EN BLOC" || bad "eraser usunal mimo aktywnej dopietej sprawy ($RES2)"
ANON2=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE id=$CUSTE AND anonymized_at IS NOT NULL")
[ "$ANON2" = "0" ] && ok "klient dalej nietkniety (czeka na zamkniecie sprawy)" || bad "klient zanonimizowany z aktywna sprawa"

# ── Przebieg 3: sprawa zamknieta => usuwanie dokonczone DO ZERA ──────────────
wp eval "apply_filters('mp_case_change_status', null, $CIC, 'zamknięte', 'nowe', 1);" >/dev/null 2>&1
RES3=$(wp eval "echo json_encode(MP\Intake\Privacy::erase('wyscig@example.com'));" 2>/dev/null)
echo "$RES3" | grep -q '"items_removed":true' && ok "po zamknieciu spraw eraser DOKONCZYL usuwanie" || bad "eraser nie dokonczyl ($RES3)"

ANON3=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE id=$CUSTE AND anonymized_at IS NOT NULL")
[ "$ANON3" = "1" ] && ok "klient zanonimizowany" || bad "klient wciaz z danymi"
MARKER=$(wp eval 'echo MP\Intake\Messages::REDACTED;' 2>/dev/null | tr -d '[:space:]')
MSG3=$(q "SELECT body FROM wp_mp_messages WHERE case_id=$CE AND author_type='client'")
[ -n "$MARKER" ] && [ "$MSG3" = "$MARKER" ] && ok "wiadomosc Ewy zredagowana ($MARKER)" || bad "wiadomosc niezredagowana ($MSG3)"
OPIS3=$(q "SELECT form_data FROM wp_mp_service_cases WHERE id=$CIC")
echo "$OPIS3" | grep -q "opisIgora" && bad "PII dopietej sprawy przezylo pelny eraser" || ok "PII dopietej sprawy zredagowane w przebiegu koncowym"

echo
echo "WYNIK C20: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
