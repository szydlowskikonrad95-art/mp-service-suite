#!/usr/bin/env bash
# ZYWY DOWOD C23 (znalezisko #1 audytu 27.07 — sprawa zawieszona NA ZAWSZE, cicho):
# Awaria (pad PHP / restart MySQL) w trakcie weryfikacji, PO atomowym UPDATE
# a PRZED emisja CASE_CREATED, zostawia sprawe potwierdzona, o ktorej Automator
# nigdy sie nie dowie: SLA stoi, nikt nie przydziela, klient czeka. Powtorny
# klik linku trafia w "juz potwierdzone" i niczego nie doslesie. CZWARTY raz
# ten sam wzorzec cichej awarii w projekcie.
# Po naprawie: sweep SLA (D) na starcie emituje kontraktowy tick
# `mp_sla_sweep_tick`, a C doszywa sieroty: dopina klienta (dane kontaktowe
# wciaz czekaja w mp_pending_contact_*), DOSYLA zdarzenie narodzin + akcje
# `mp_case_created` => Automator prowizjonuje SLA/przydzial. Bufor 10 min
# odsiewa weryfikacje trwajace wlasnie teraz. Test "Stanu witryny" pokazuje
# zaleglosc, gdyby doszywanie nie dzialalo.
# Wymaga MP_BASE (spojnosc pakietu; test chodzi przez wp-cli).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
# UWAGA: q() usuwa CALE biale znaki z wyniku — oczekiwania tez pisz bez spacji.
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_attachments; DELETE FROM wp_mp_case_sla;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done

STARA=$(date -u -d '20 minutes ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u -v-20M '+%Y-%m-%d %H:%M:%S')
TERAZ=$(date -u '+%Y-%m-%d %H:%M:%S')

# ── Sierota po awarii: UPDATE weryfikacji przeszedl, reszta ucieta ───────────
O1=$(wp mp case-create --kind=zapytanie --email='sierota@example.com' --name='Stefan Sierota' --desc='sprawa sieroty' 2>/dev/null)
C1=$(echo "$O1" | grep '^case_id=' | cut -d= -f2)
wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe', verified_at='$STARA' WHERE id=$C1" >/dev/null 2>&1

# ── Kontrola bufora wieku: weryfikacja "trwajaca teraz" ──────────────────────
O2=$(wp mp case-create --kind=zapytanie --email='swiezak@example.com' --name='Swiezy Przypadek' --desc='przed chwila' 2>/dev/null)
C2=$(echo "$O2" | grep '^case_id=' | cut -d= -f2)
wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe', verified_at='$TERAZ' WHERE id=$C2" >/dev/null 2>&1

# Diagnostyka PRZED: sierota widoczna w zapytaniu Stanu witryny.
PRZED=$(wp eval 'echo count(MP\Intake\CaseRepo::unlaunched_ids(10,20));' 2>/dev/null | tr -d '[:space:]')
[ "$PRZED" = "1" ] && ok "diagnostyka widzi 1 sierote (swiezak odsiany buforem wieku)" || bad "diagnostyka: $PRZED sierot (oczekiwana 1)"

# ── Pelny lancuch: przebieg sweepa D emituje tick, C doszywa ─────────────────
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1

EV1=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$C1 AND event_type='CASE_CREATED'")
[ "$EV1" = "1" ] && ok "sierota dostala zdarzenie narodzin (dosylka przez sweep)" || bad "brak dosylki CASE_CREATED ($EV1)"
CUST1=$(q "SELECT COALESCE(customer_id,0) FROM wp_mp_service_cases WHERE id=$C1")
[ "$CUST1" != "0" ] && ok "klient dopiety z czekajacych danych kontaktowych (id=$CUST1)" || bad "klient niedopiety (sprawa dalej bez wlasciciela)"
NAZWA=$(q "SELECT name FROM wp_mp_customers WHERE id=${CUST1:-0}")
[ "$NAZWA" = "StefanSierota" ] && ok "dane kontaktowe sieroty odzyskane w calosci" || bad "dane klienta puste/obce ($NAZWA)"
SLA1=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$C1")
[ "$SLA1" = "1" ] && ok "Automator obudzony: SLA sprawy prowizjonowane" || bad "SLA nie ruszylo mimo dosylki ($SLA1)"
OPCJA=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name='mp_pending_contact_$C1'")
[ "$OPCJA" = "0" ] && ok "dane tymczasowe sprzatniete po dopieciu" || bad "opcja pending zostala"

EV2=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$C2 AND event_type='CASE_CREATED'")
[ "$EV2" = "0" ] && ok "bufor wieku: swiezej weryfikacji sweep NIE dotyka (bez podwojnej emisji)" || bad "sweep dotknal swieza weryfikacje ($EV2)"

# ── Idempotencja: drugi przebieg niczego nie dubluje ─────────────────────────
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1
EV1B=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$C1 AND event_type='CASE_CREATED'")
[ "$EV1B" = "1" ] && ok "drugi przebieg = zero duplikatow zdarzenia" || bad "zdarzenie zdublowane ($EV1B)"

PO=$(wp eval 'echo count(MP\Intake\CaseRepo::unlaunched_ids(10,20));' 2>/dev/null | tr -d '[:space:]')
[ "$PO" = "0" ] && ok "diagnostyka po doszyciu: zero zaleglosci" || bad "zaleglosc zostala ($PO)"

echo
echo "WYNIK C23: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
