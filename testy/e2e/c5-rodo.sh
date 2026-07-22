#!/usr/bin/env bash
# ZYWY DOWOD C5 (zgody + wiadomosci + RODO): zgoda zamrozona przy zgloszeniu,
# wiadomosci na sprawie, eraser (anonimizacja + redakcja messages/form_data-PII +
# kasacja zalacznikow + B redact reason + odroczenie EN BLOC dla aktywnej sprawy),
# exporter (dane+sprawy+wiadomosci), wycofanie zgody. Chodzi na poligonie i w CI.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_attachments; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_product_registry;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

# Produkt B z partia (do snapshotu + reason wyjatku dla B-redact).
wp db query "INSERT INTO wp_mp_product_registry (serial_display, serial_normalized, model, batch, warranty_until, source, created_at, updated_at) VALUES ('RODO-1','RODO1','Model RODO','PARTIA-R','2030-01-01','manual',UTC_TIMESTAMP(),UTC_TIMESTAMP())" >/dev/null 2>&1
PID=$(q "SELECT id FROM wp_mp_product_registry LIMIT 1")

# ── 1. Zgloszenie z opisem (PII) -> zgoda zamrozona w consents ─────────────
OUT=$(wp mp case-create --kind=reklamacja --email='rodo@example.com' --name='Jan RODO' --serial='RODO-1' --document='FV/R/1' --date='2026-03-15' --desc='Moj numer PESEL to tajne' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
TOKEN=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
# CLI nie zbiera zgody -> zapisz recznie tak jak front (test jednostki consents).
wp eval "MP\Intake\Consents::record('rodo@example.com', $CID, MP\Intake\Consents::KEY_PROCESSING, MP\Intake\Consents::VERSION, MP\Intake\Consents::processing_text());" >/dev/null 2>&1
CTXT=$(q "SELECT LEFT(consent_text,20) FROM wp_mp_consents WHERE case_id=$CID")
[ -n "$CTXT" ] && ok "zgoda zamrozona z pelnym tekstem (rozliczalnosc art. 7)" || bad "brak zapisanej zgody"

# Weryfikacja -> klient + podpiecie zgody + event CONSENT_RECORDED.
wp mp case-verify "$TOKEN" >/dev/null 2>&1
CUSTID=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CID")
CONS_CUST=$(q "SELECT customer_id FROM wp_mp_consents WHERE case_id=$CID")
[ -n "$CUSTID" ] && [ "$CONS_CUST" = "$CUSTID" ] && ok "po weryfikacji: zgoda podpieta do klienta ($CUSTID)" || bad "zgoda niepodpieta (cust=$CUSTID cons=$CONS_CUST)"
q "SELECT event_type FROM wp_mp_case_events WHERE case_id=$CID" | grep -q "CONSENT_RECORDED" && ok "event CONSENT_RECORDED zapisany" || bad "brak eventu CONSENT_RECORDED"

# ── 2. Wiadomosci na sprawie (P1.5) ────────────────────────────────────────
MID=$(wp eval "echo MP\Intake\Messages::add($CID, 'client', null, 'Dzien dobry, moj adres to ul. Testowa 5');" 2>/dev/null)
wp eval "MP\Intake\Messages::add($CID, 'staff', 1, 'Przyjelismy zgloszenie.');" >/dev/null 2>&1
MCOUNT=$(q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CID")
[ "$MCOUNT" = "2" ] && ok "wiadomosci klient+serwis zapisane (historia P1.5)" || bad "wiadomosci: $MCOUNT"
# mp_case_add_system_message (listener kontraktowy od D).
wp eval "echo apply_filters('mp_case_add_system_message', null, $CID, 'Raport koncowy sprawy.');" >/dev/null 2>&1
SYS=$(q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CID AND author_type='system'")
[ "$SYS" = "1" ] && ok "mp_case_add_system_message dopisal wiadomosc systemowa (kontrakt D)" || bad "system message: $SYS"

# ── 3. Wyjatek gwarancyjny z reason (do B-redact) + zalacznik ──────────────
wp eval "wp_set_current_user(1); MP\Intake\Customers::get(1); \$r = apply_filters('mp_warranty_check', null, 'RODO-1', $CID, null); global \$wpdb; \$wpdb->insert('wp_mp_warranty_exceptions', array('product_registry_id'=>$PID,'case_id'=>$CID,'status'=>'active','valid_from'=>gmdate('Y-m-d H:i:s'),'reason'=>'Klient Jan Kowalski, PESEL w opisie','created_by'=>1,'created_at'=>gmdate('Y-m-d H:i:s')));" >/dev/null 2>&1
wp db query "INSERT INTO wp_mp_attachments (case_id, path, mime, size_bytes, original_name, retention_until, created_at) VALUES ($CID,'aaaa-bbbb','image/jpeg',100,'foto.jpg','2030-01-01 00:00:00',UTC_TIMESTAMP())" >/dev/null 2>&1

# ── 4. Eraser dla AKTYWNEJ sprawy => ODROCZENIE EN BLOC (nic nie tykane) ────
RES=$(wp eval "\$r = MP\Intake\Privacy::erase('rodo@example.com'); echo (\$r['items_retained']?'RETAINED':'').'|'.(\$r['items_removed']?'REMOVED':'');" 2>/dev/null)
echo "$RES" | grep -q "RETAINED" && ! echo "$RES" | grep -q "REMOVED" && ok "sprawa AKTYWNA => eraser ODRACZA EN BLOC (items_retained, nic nie anonimizuje)" || bad "aktywna sprawa nie odroczona: $RES"
ANON_STILL=$(q "SELECT anonymized_at FROM wp_mp_customers WHERE id=$CUSTID")
[ -z "$ANON_STILL" ] || [ "$ANON_STILL" = "NULL" ] && ok "dane klienta NIETKNIETE przy odroczeniu" || bad "klient zanonimizowany mimo aktywnej sprawy!"

# ── 5. Zamknij sprawe -> eraser wykonuje pelna anonimizacje ────────────────
wp db query "UPDATE wp_mp_service_cases SET status='zamkniete' WHERE id=$CID" >/dev/null 2>&1
RES2=$(wp eval "\$r = MP\Intake\Privacy::erase('rodo@example.com'); echo (\$r['items_removed']?'REMOVED':'NIE');" 2>/dev/null)
[ "$RES2" = "REMOVED" ] && ok "sprawa zamknieta => eraser anonimizuje (items_removed)" || bad "eraser nie zadzialal: $RES2"

ANON=$(q "SELECT anonymized_at FROM wp_mp_customers WHERE id=$CUSTID")
[ -n "$ANON" ] && [ "$ANON" != "NULL" ] && ok "klient zanonimizowany (anonymized_at ustawione, wiersz ZOSTAJE)" || bad "brak anonimizacji"
WPU=$(q "SELECT COALESCE(wp_user_id,'NULL') FROM wp_mp_customers WHERE id=$CUSTID")
[ "$WPU" = "NULL" ] && ok "konto WP odpiete od klienta" || bad "konto WP nieodpiete ($WPU)"

# messages zredagowane, form_data PII zredagowane, zalacznik skasowany.
MRED=$(q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CID AND body='[ZREDAGOWANO-RODO]'")
[ "$MRED" -ge 2 ] && ok "wiadomosci klienta zredagowane ($MRED)" || bad "wiadomosci niezredagowane: $MRED"
FRED=$(wp eval "\$f=json_decode(\$GLOBALS['wpdb']->get_var(\$GLOBALS['wpdb']->prepare('SELECT form_data FROM wp_mp_service_cases WHERE id=%d',$CID)),true); echo \$f['issue_description']['value'] ?? 'BRAK';" 2>/dev/null)
[ "$FRED" = "[ZREDAGOWANO-RODO]" ] && ok "form_data: opis (PII) zredagowany" || bad "opis niezredagowany: $FRED"
ADEL=$(q "SELECT COUNT(*) FROM wp_mp_attachments WHERE case_id=$CID AND deleted_at IS NULL")
[ "$ADEL" = "0" ] && ok "zalaczniki sprawy skasowane (RODO)" || bad "zalaczniki zostaly: $ADEL"
# B-redact: reason wyjatku zredagowany.
RREASON=$(q "SELECT reason FROM wp_mp_warranty_exceptions WHERE case_id=$CID")
echo "$RREASON" | grep -qi "zredagowano" && ok "B zredagowal reason wyjatku (mp_privacy_redact_for_customer)" || bad "reason wyjatku niezredagowany: $RREASON"
q "SELECT event_type FROM wp_mp_case_events WHERE case_id=$CID" | grep -q "PII_REDACTION" && ok "event PII_REDACTION zapisany" || bad "brak eventu PII_REDACTION"

# ── 6. Exporter zwraca dane klienta + sprawy + wiadomosci ──────────────────
# (po anonimizacji email zmieniony; utworz swiezego klienta do eksportu)
OUT2=$(wp mp case-create --kind=zapytanie --email='export@example.com' --desc='pytanie' 2>/dev/null)
T2=$(echo "$OUT2" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$T2" >/dev/null 2>&1
EXP=$(wp eval "\$e = MP\Intake\Privacy::export('export@example.com'); echo count(\$e['data']).'|'.(\$e['done']?'DONE':'');" 2>/dev/null)
GROUPS=$(echo "$EXP" | cut -d'|' -f1)
[ "${GROUPS:-0}" -ge 2 ] && echo "$EXP" | grep -q "DONE" && ok "exporter zwraca dane klienta+sprawy ($GROUPS grup, done)" || bad "exporter: $EXP"

# ── 7. Wycofanie zgody (self-service, art. 7(3)) ───────────────────────────
EXPCUST=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE case_number IS NOT NULL ORDER BY id DESC LIMIT 1")
wp eval "MP\Intake\Consents::record('export@example.com', NULL, 'processing', '1.0', 'tekst'); global \$wpdb; \$wpdb->query(\$wpdb->prepare('UPDATE wp_mp_consents SET customer_id=%d WHERE email=%s', $EXPCUST, 'export@example.com'));" >/dev/null 2>&1
WDR=$(wp eval "echo MP\Intake\Consents::withdraw($EXPCUST, 'processing') ? 'TAK' : 'NIE';" 2>/dev/null)
[ "$WDR" = "TAK" ] && ok "wycofanie zgody self-service dziala (art. 7(3))" || bad "wycofanie zgody nie dziala: $WDR"

echo
echo "WYNIK C5: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
