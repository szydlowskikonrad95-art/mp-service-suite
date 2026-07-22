#!/usr/bin/env bash
# BLOK-S — TABLETOP S1-S10 jako testy integracyjne (niezmienniki calego systemu).
# Kazdy scenariusz z sesji tabletop (PAKIET-FINAL) zamieniony na test na zywym
# demo. Scenariusze zalezne od write-path personelu / Automatora (D) — jeszcze
# niezbudowanego — sa SKIP z JAWNYM powodem (nie fail); zaswieca sie zielono gdy
# funkcja/listener D wejdzie. Cross-plugin B<->C (S7, S8) to najmocniejsze
# niezmienniki — oba pluginy gotowe, testowane naprawde.
#
# S1 happy-path (ownership)        [LIVE]      S6  reaktywacja D po przestoju   [D-pending P3.3+]
# S2 unlink zalacznika (wiersz+plik)[LIVE]     S7  listener data_erased w B     [LIVE cross-plugin]
# S3 RODO en-bloc (aktywna sprawa) [LIVE]      S8  trade-off snapshotu gwar.    [LIVE cross-plugin]
# S4 fallback koordynator (wyjatek)[LIVE/D]    S9  "Przelicz SLA" bez markerow  [D-pending P3.3+]
# S5 zamkniecie+wiadomosc+reopen   [LIVE P3.2] S10 reczny reassign+CASE_ASSIGNED[LIVE P3.1]
#
# Chodzi na poligonie (MP_BASE z env) i w CI. Exit 0 = zero FAIL (SKIP = jawna,
# zaraportowana luka D-pending).
set -u

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); echo "  OK   $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
skip() { SKIP=$((SKIP+1)); echo "  SKIP $1"; }
q()    { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

clean() {
	wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_product_registry; DELETE FROM wp_mp_warranty_exceptions; DELETE FROM wp_mp_attachments; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_workflow_rules;" >/dev/null 2>&1
	wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_rl%' OR option_name LIKE '_transient_timeout_mp_rl%'" >/dev/null 2>&1
	wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
	for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done
}
# Tworzy potwierdzona sprawe, echo case_id. Bez serialu => kind 'zapytanie'
# (reklamacja WYMAGA serial+dokument+data — walidacja formularza per kategoria).
mkcase() {
	local email="$1" serial="${2:-}" kind="${3:-}"
	local args=(--email="$email" --name='TT')
	if [ -n "$serial" ]; then
		[ -z "$kind" ] && kind=reklamacja
		args+=(--kind="$kind" --serial="$serial" --document='FV/TT/1' --date='2026-03-01')
	else
		[ -z "$kind" ] && kind=zapytanie
		args+=(--kind="$kind")
	fi
	local out tok cid
	out=$(wp mp case-create "${args[@]}" --desc='tabletop' 2>/dev/null)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	wp mp case-verify "$tok" >/dev/null 2>&1
	echo "$cid"
}
seed_product() { # serial -> echo product_id
	wp db query "INSERT INTO wp_mp_product_registry (serial_display, serial_normalized, model, batch, purchase_document, purchase_date, warranty_until, source, archived, created_at, updated_at) VALUES ('$1','$1','Model-TT','P-TT','FV/TT/1','2026-03-01','2030-03-01','manual',0,UTC_TIMESTAMP(),UTC_TIMESTAMP())" >/dev/null 2>&1
	q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$1'"
}

echo "== BLOK-S TABLETOP: S1-S10 jako testy niezmiennikow =="

# ── S1: happy-path — kazdy krok ma wlasciciela (pluginu/kodu) ──────────────
echo "-- S1 happy-path (ownership pelnej sciezki) --"
clean; PID1=$(seed_product "S1SER")
CID1=$(mkcase 's1@example.com' 'S1SER')
ST=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID1")
CUST=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE id=(SELECT customer_id FROM wp_mp_service_cases WHERE id=$CID1)")
EVC=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID1 AND event_type='CASE_CREATED'")
LINK=$(q "SELECT product_registry_id FROM wp_mp_service_cases WHERE id=$CID1")
{ [ "$ST" = "nowe" ] && [ "$CUST" = "1" ] && [ "$EVC" = "1" ] && [ "$LINK" = "$PID1" ]; } \
	&& ok "S1: sprawa(C)+klient(C)+event(C)+produkt(B) — pelna sciezka ma wlasciciela na kazdym kroku" \
	|| bad "S1: sciezka niespojna (st=$ST cust=$CUST ev=$EVC link=$LINK/$PID1)"

# ── S2: kasowanie zalacznika = oznacz wiersz (deleted_at) + UNLINK pliku ────
echo "-- S2 unlink zalacznika (nigdy samo skasowanie rekordu) --"
clean; CID2=$(mkcase 's2@example.com')
ADIR=$(wp eval 'echo MP\Intake\Attachments::dir();' 2>/dev/null)
if [ -n "$ADIR" ] && [ -d "$ADIR" ]; then
	printf 'dummy-attachment-bytes' > "$ADIR/s2-test.bin" 2>/dev/null
	wp db query "INSERT INTO wp_mp_attachments (case_id, path, mime, size_bytes, original_name, retention_until, created_at) VALUES ($CID2,'s2-test.bin','application/octet-stream',22,'foto.bin', DATE_ADD(UTC_TIMESTAMP(), INTERVAL 30 DAY), UTC_TIMESTAMP())" >/dev/null 2>&1
	AID=$(q "SELECT id FROM wp_mp_attachments WHERE case_id=$CID2 LIMIT 1")
	[ -f "$ADIR/s2-test.bin" ] && [ -n "$AID" ] && ok "S2: przygotowano zalacznik (wiersz id=$AID + plik na dysku)" || bad "S2: nie przygotowano zalacznika"
	wp eval "MP\Intake\Attachments::delete($AID);" >/dev/null 2>&1
	FILE_GONE=0; [ -f "$ADIR/s2-test.bin" ] || FILE_GONE=1
	ROW_MARKED=$(q "SELECT CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END FROM wp_mp_attachments WHERE id=$AID")
	[ "$FILE_GONE" = "1" ] && ok "S2: plik ODLINKOWANY z dysku (nie sierota po skasowaniu rekordu)" || bad "S2: plik zostal na dysku (sierota)!"
	[ "$ROW_MARKED" = "1" ] && ok "S2: wiersz OZNACZONY deleted_at (slad audytu, nie twardy DELETE)" || bad "S2: wiersz nie oznaczony (marked=$ROW_MARKED)"
else
	bad "S2: katalog zalacznikow niedostepny ($ADIR)"
fi

# ── S3: RODO — aktywna sprawa => eraser ODRACZA EN BLOC (zero czesciowej anon.) ─
echo "-- S3 RODO en-bloc przy aktywnej sprawie --"
clean; CID3=$(mkcase 's3@example.com')
wp eval "MP\Intake\Consents::record('s3@example.com', $CID3, MP\Intake\Consents::KEY_PROCESSING, MP\Intake\Consents::VERSION, MP\Intake\Consents::processing_text());" >/dev/null 2>&1
RES3=$(wp eval "\$r = MP\Intake\Privacy::erase('s3@example.com'); echo (\$r['items_retained']?'RETAINED':'').'|'.(\$r['items_removed']?'REMOVED':'');" 2>/dev/null)
{ echo "$RES3" | grep -q "RETAINED" && ! echo "$RES3" | grep -q "REMOVED"; } \
	&& ok "S3: aktywna sprawa => eraser ODRACZA EN BLOC (items_retained, nic nie anonimizuje)" \
	|| bad "S3: aktywna sprawa nie odroczona en-bloc ($RES3)"
NAME_STILL=$(q "SELECT COUNT(*) FROM wp_mp_customers WHERE email='s3@example.com' AND anonymized_at IS NULL")
[ "${NAME_STILL:-0}" -ge 1 ] && ok "S3: dane klienta NIETKNIETE przy odroczeniu (zero czesciowej anonimizacji)" || bad "S3: klient tkniety mimo odroczenia"

# ── S4: wyjatek gwarancyjny na sprawe => event na osi (C listener) + mail (D) ─
echo "-- S4 fallback koordynator (wyjatek gwarancyjny) --"
clean; PID4=$(seed_product "S4SER"); CID4=$(mkcase 's4@example.com' 'S4SER')
# B-side dziala (grant wymaga admina MP => --user=1; emituje mp_warranty_exception_changed).
wp mp exception-add "S4SER" --reason='wyjatek tabletop' --case="$CID4" --until='2027-01-01' --user=1 >/dev/null 2>&1
EXOK=$(q "SELECT COUNT(*) FROM wp_mp_warranty_exceptions WHERE case_id=$CID4 AND status='active'")
[ "${EXOK:-0}" -ge 1 ] && ok "S4: wyjatek gwarancyjny przyznany w B (grant --user=1, akcja mp_warranty_exception_changed wyemitowana)" || bad "S4: wyjatek nie przyznany w B ($EXOK)"
# C-side: event EXCEPTION_APPLIED na osi sprawy — C NIE nasluchuje jeszcze mp_warranty_exception_changed.
EV4=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID4 AND event_type='EXCEPTION_APPLIED'")
if [ "${EV4:-0}" -ge 1 ]; then
	ok "S4: event EXCEPTION_APPLIED na osi sprawy (C listener mp_warranty_exception_changed)"
else
	skip "S4: EXCEPTION_APPLIED na osi — C nie nasluchuje mp_warranty_exception_changed [pending: listener C niewystawiony, jak znalezisko #9/#10]"
fi
skip "S4: mail fallback do koordynatora gdy sprawa nieprzydzielona — routing maila w D [D-pending]"

# ── S5: wiadomosci po zamknieciu + reopen (personel) ───────────────────────
echo "-- S5 wiadomosci-po-zamknieciu + reopen (P3.2) --"
clean; CID5=$(mkcase 's5@example.com')
# Zamkniecie: nowe -> zamknięte (slug z diakrytykiem, jak CORE w Statuses.php).
wp eval "apply_filters('mp_case_change_status', null, $CID5, 'zamknięte', 'nowe', 1);" >/dev/null 2>&1
ST5=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID5")
[ "$ST5" = "zamknięte" ] && ok "S5: sprawa zamknieta (nowe->zamknięte przez mp_case_change_status)" || bad "S5: nie zamknieto (status=$ST5)"
# Wiadomosc klienta na ZAMKNIETEJ sprawie = DOZWOLONA (nie zmienia statusu).
MID5=$(wp eval "echo MP\Intake\Messages::add($CID5, 'client', null, 'Pytanie juz po zamknieciu sprawy');" 2>/dev/null)
ST5B=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID5")
{ [ -n "$MID5" ] && [ "$ST5B" = "zamknięte" ]; } && ok "S5: wiadomosc na ZAMKNIETEJ sprawie dozwolona (dodana, status bez zmian)" || bad "S5: wiadomosc odrzucona/zmienila status (mid=$MID5 st=$ST5B)"
# REOPEN (personel): zamknięte -> w analizie (jedyny cel reopen wg STATE_MACHINE).
wp eval "apply_filters('mp_case_change_status', null, $CID5, 'w analizie', 'zamknięte', 1);" >/dev/null 2>&1
ST5C=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID5")
SCEV5=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID5 AND event_type='STATUS_CHANGED'")
{ [ "$ST5C" = "wanalizie" ] && [ "${SCEV5:-0}" -ge 2 ]; } && ok "S5: REOPEN zamknięte->w analizie (personel) + 2× STATUS_CHANGED na osi" || bad "S5: reopen nie zadzialal (status=$ST5C, STATUS_CHANGED=$SCEV5)"

# ── S6: reaktywacja D po przestoju (nadrabia SKUTKI regul) ──────────────────
echo "-- S6 reaktywacja D po przestoju --"
skip "S6: resync przydzialow + backfill raportow po przestoju D = silnik D [D-pending, najciezszy scenariusz]"

# ── S7: listener mp_cases_data_erased w B (per-sprawa revoked, globalne zostaja) ─
echo "-- S7 listener data_erased w B (cross-plugin C->B) --"
clean; PID7=$(seed_product "S7SER"); CID7=$(mkcase 's7@example.com' 'S7SER')
# wyjatek PER-SPRAWA (case_id NOT NULL) + wyjatek GLOBALNY na produkt (case_id NULL).
# grant wymaga admina MP => --user=1.
wp mp exception-add "S7SER" --reason='per-sprawa' --case="$CID7" --until='2027-01-01' --user=1 >/dev/null 2>&1
wp mp exception-add "S7SER" --reason='globalny' --until='2027-01-01' --user=1 >/dev/null 2>&1
EX_CASE=$(q "SELECT id FROM wp_mp_warranty_exceptions WHERE case_id=$CID7 LIMIT 1")
EX_GLOB=$(q "SELECT id FROM wp_mp_warranty_exceptions WHERE case_id IS NULL LIMIT 1")
{ [ -n "$EX_CASE" ] && [ -n "$EX_GLOB" ]; } && ok "S7: przygotowano wyjatek per-sprawa ($EX_CASE) + globalny ($EX_GLOB)" || bad "S7: nie przygotowano wyjatkow (case=$EX_CASE glob=$EX_GLOB)"
# Sygnal globalny z uninstalla C: "tabele spraw przestaly istniec"
wp eval "do_action('mp_cases_data_erased');" >/dev/null 2>&1
ST_CASE=$(q "SELECT status FROM wp_mp_warranty_exceptions WHERE id=$EX_CASE")
ST_GLOB=$(q "SELECT status FROM wp_mp_warranty_exceptions WHERE id=$EX_GLOB")
[ "$ST_CASE" = "revoked" ] && ok "S7: B zrewokowalo wyjatek PER-SPRAWA po data_erased (nie sierota)" || bad "S7: wyjatek per-sprawa nie zrewokowany (status=$ST_CASE)"
[ "$ST_GLOB" = "active" ] && ok "S7: wyjatek GLOBALNY na produkt ZOSTAJE (dotyczy produktu, nie sprawy)" || bad "S7: globalny wyjatek tkniety (status=$ST_GLOB)"

# ── S8: trade-off snapshotu — serial doimportowany PO zgloszeniu ────────────
echo "-- S8 trade-off snapshotu gwarancji (cross-plugin B<->C) --"
clean
# sprawa z serialem SPOZA rejestru => snapshot "brak danych"
CID8=$(mkcase 's8@example.com' 'S8SER')
SNAP_BEFORE=$(wp db query "SELECT warranty_snapshot FROM wp_mp_service_cases WHERE id=$CID8" --skip-column-names 2>/dev/null)
echo "$SNAP_BEFORE" | grep -qE 'brak_danych|"found":false|weryfikacja' && ok "S8: sprawa z nieznanym serialem => snapshot 'brak danych' (zamrozony na chwile zgloszenia)" || bad "S8: snapshot nie odzwierciedla braku produktu (snap=$SNAP_BEFORE)"
# TERAZ produkt doimportowany do rejestru B
PID8=$(seed_product "S8SER")
LIVE=$(wp eval "\$r=apply_filters('mp_warranty_check', null, 'S8SER', null, null); echo !empty(\$r['found'])?'FOUND':'NOTFOUND';" 2>/dev/null)
SNAP_AFTER=$(wp db query "SELECT warranty_snapshot FROM wp_mp_service_cases WHERE id=$CID8" --skip-column-names 2>/dev/null)
[ "$LIVE" = "FOUND" ] && ok "S8: 'Aktualnie' (live mp_warranty_check) widzi doimportowany produkt" || bad "S8: live check nie znalazl produktu po imporcie ($LIVE)"
[ "$SNAP_BEFORE" = "$SNAP_AFTER" ] && ok "S8: snapshot sprawy NIETKNIETY (swiadomy brak auto-rekoncyliacji — ocena wg chwili zgloszenia)" || bad "S8: snapshot przepisany wstecz (rekoncyliacja ktorej NIE ma byc)!"

# ── S9: "Przelicz SLA aktywnych" nie tyka markerow ─────────────────────────
echo "-- S9 Przelicz SLA bez ruszania markerow --"
skip "S9: przeliczenie SLA aktywnych (deadline+wersja regul, markery reminderow nietkniete) = sweep D [D-pending]"

# ── S10: reczny reassign => CASE_ASSIGNED + notify ─────────────────────────
echo "-- S10 reczny reassign (P3.1: mp_case_assign) --"
clean; CID10=$(mkcase 's10@example.com')
A10=$(wp user get s10-agent@example.com --field=ID 2>/dev/null)
[ -z "$A10" ] && A10=$(wp user create s10-agent s10-agent@example.com --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
wp user set-role "$A10" mp_agent >/dev/null 2>&1
# Reczne przypisanie przez koordynatora (actor=1) — mp_case_assign waliduje role przydzielanego.
R10=$(wp eval "\$r=apply_filters('mp_case_assign', null, $CID10, $A10, 1); echo !empty(\$r['success'])?'OK':('NIE:'.(\$r['error_code']??'?'));" 2>/dev/null)
AS10=$(q "SELECT COALESCE(assigned_to,0) FROM wp_mp_service_cases WHERE id=$CID10")
CAEV10=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID10 AND event_type='CASE_ASSIGNED'")
{ [ "$R10" = "OK" ] && [ "$AS10" = "$A10" ] && [ "${CAEV10:-0}" -ge 1 ]; } \
	&& ok "S10: reczne przypisanie mp_case_assign => assigned_to=$AS10 + event CASE_ASSIGNED (kazdy przydzial=event)" \
	|| bad "S10: reczny assign nie zadzialal (r=$R10 assigned=$AS10/$A10 ev=$CAEV10)"

echo
echo "WYNIK BLOK-S TABLETOP: $PASS ok, $FAIL fail, $SKIP skip (D-pending — jawna luka, nie blad)"
[ "$FAIL" -eq 0 ]
