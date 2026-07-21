#!/usr/bin/env bash
# ZYWY DOWOD C1 (rdzen sprawy): wspolbiezny SRV (crown-jewel), narodziny sprawy
# ze snapshotem NIOSACYM PARTIE (carry-over #1), atomowe potwierdzenie, event
# CASE_CREATED + mp_case_created DOPIERO po weryfikacji (Automator nie widzi sierot).
# Chodzi tak samo na poligonie i w CI. Exit 0 = wszystkie asercje przeszly.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

YEAR=$(date -u +%Y)

# ── 0. Czysty stan C ──────────────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp option delete $(wp option list --search='mp_pending_contact_*' --field=option_name 2>/dev/null) >/dev/null 2>&1 || true

# ── 1. CROWN-JEWEL: 30 rownoleglych procesow rwie po numery SRV = ZERO duplikatow ──
PROCS=30
for i in $(seq 1 $PROCS); do
	wp eval "echo MP\Intake\SrvCounter::next($YEAR), PHP_EOL;" >> /tmp/mp-srv-nums.txt 2>/dev/null &
done
wait
TOTAL=$(grep -c . /tmp/mp-srv-nums.txt)
UNIQ=$(sort -u /tmp/mp-srv-nums.txt | grep -c .)
COUNTER=$(q "SELECT value FROM wp_mp_srv_counters WHERE year=$YEAR")
[ "$TOTAL" = "$PROCS" ] && [ "$UNIQ" = "$PROCS" ] && ok "SRV wspolbiezny: $PROCS procesow -> $UNIQ unikalnych numerow, ZERO duplikatow" \
	|| bad "SRV: total=$TOTAL uniq=$UNIQ (duplikaty!)"
[ "$COUNTER" = "$PROCS" ] && ok "licznik roku = $PROCS (atomowe podbicie, bez zgubionych)" || bad "licznik=$COUNTER != $PROCS"
FMT=$(head -1 /tmp/mp-srv-nums.txt)
echo "$FMT" | grep -qE "^SRV/$YEAR/[0-9]{4}" && ok "format numeru: $FMT (SRV/RRRR/NNNN)" || bad "zly format: $FMT"
rm -f /tmp/mp-srv-nums.txt
wp db query "DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1

# ── 2. Seed produktu w B (z PARTIA) do snapshotu ──────────────────────────
wp db query "INSERT INTO wp_mp_product_registry (serial_display, serial_normalized, model, batch, warranty_until, source, created_at, updated_at) VALUES ('C1-SERIAL-1','C1SERIAL1','Grzejnik C1','PARTIA-C1-XYZ','2030-01-01','manual',UTC_TIMESTAMP(),UTC_TIMESTAMP())" >/dev/null 2>&1
ok "seed produktu B z partia PARTIA-C1-XYZ"

# ── 3. Narodziny sprawy: create (unverified) -> event NIE powstaje jeszcze ──
OUT=$(wp mp case-create --kind=reklamacja --email='jan@example.com' --name='Jan Testowy' --serial='C1-SERIAL-1' --desc='Nie grzeje' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
CNUM=$(echo "$OUT" | grep '^case_number=' | cut -d= -f2)
TOKEN=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
[ -n "$CID" ] && [ -n "$TOKEN" ] && ok "sprawa niepotwierdzona utworzona: $CNUM (case_id=$CID)" || bad "create nie zwrocil danych"

ST=$(q "SELECT COALESCE(status,'NULL') FROM wp_mp_service_cases WHERE id=$CID")
IDST=$(q "SELECT identity_status FROM wp_mp_service_cases WHERE id=$CID")
[ "$ST" = "NULL" ] && [ "$IDST" = "pending" ] && ok "status=NULL, identity=pending (unverified)" || bad "status=$ST identity=$IDST"

# W bazie tylko HASH tokenu, nie surowy.
RAWINDB=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE verify_token_hash='$TOKEN'")
[ "$RAWINDB" = "0" ] && ok "w bazie tylko HASH tokenu (surowy nie wystepuje)" || bad "surowy token w bazie!"

# Carry-over #1: snapshot NIESIE PARTIE.
SNAP_BATCH=$(wp eval "\$s=json_decode(\$GLOBALS['wpdb']->get_var(\$GLOBALS['wpdb']->prepare('SELECT warranty_snapshot FROM wp_mp_service_cases WHERE id=%d',$CID)),true); echo \$s['batch'] ?? 'BRAK';" 2>/dev/null)
[ "$SNAP_BATCH" = "PARTIA-C1-XYZ" ] && ok "⭐ snapshot sprawy NIESIE PARTIE: $SNAP_BATCH (carry-over #1)" || bad "snapshot bez partii: $SNAP_BATCH"

# Automator nie widzi sierot: ZERO eventow przed weryfikacja.
EV=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID")
[ "$EV" = "0" ] && ok "unverified NIE pisze do case_events (append-only nienaruszone)" || bad "event powstal przed weryfikacja! ($EV)"

# ── 4. Potwierdzenie magic-linkiem: narodziny (status nowe, event, hook) ───
CREATED_FIRED=$(wp eval "
add_action('mp_case_created', function(\$id){ echo 'FIRED:'.\$id; });
\$r = MP\Intake\CaseRepo::verify('$TOKEN');
echo PHP_EOL . (isset(\$r['case_id']) ? 'OK:'.\$r['case_number'] : 'ERR:'.\$r['error']);
" 2>/dev/null)
echo "$CREATED_FIRED" | grep -q "FIRED:$CID" && ok "mp_case_created odpalony PRZY weryfikacji" || bad "hook nie odpalil: $CREATED_FIRED"
echo "$CREATED_FIRED" | grep -q "OK:$CNUM" && ok "verify zwrocil numer sprawy" || bad "verify: $CREATED_FIRED"

ST2=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
IDST2=$(q "SELECT identity_status FROM wp_mp_service_cases WHERE id=$CID")
[ "$ST2" = "nowe" ] && [ "$IDST2" = "verified" ] && ok "po weryfikacji: status=nowe, identity=verified" || bad "status=$ST2 identity=$IDST2"

EV2=$(q "SELECT event_type FROM wp_mp_case_events WHERE case_id=$CID")
[ "$EV2" = "CASE_CREATED" ] && ok "event CASE_CREATED zapisany DOPIERO teraz" || bad "eventy po weryfikacji: $EV2"

# Payload eventu STRUKTURALNY (bez wolnego tekstu / opisu usterki).
LEAK=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND (payload LIKE '%Nie grzeje%' OR payload LIKE '%jan@example%')")
[ "$LEAK" = "0" ] && ok "payload eventu NO-PII (bez opisu/maila)" || bad "PII w evencie!"

# Klient utworzony i podpiety przy weryfikacji.
CUSTID=$(q "SELECT customer_id FROM wp_mp_service_cases WHERE id=$CID")
CUSTMAIL=$(q "SELECT email FROM wp_mp_customers WHERE id=$CUSTID")
[ "$CUSTMAIL" = "jan@example.com" ] && ok "klient utworzony i podpiety przy weryfikacji" || bad "klient: id=$CUSTID mail=$CUSTMAIL"

# ── 5. Ponowne uzycie tego samego tokenu = odmowa (jednorazowosc) ──────────
REUSE=$(wp eval "\$r=MP\Intake\CaseRepo::verify('$TOKEN'); echo isset(\$r['error'])?'DENIED':'ALLOWED';" 2>/dev/null)
[ "$REUSE" = "DENIED" ] && ok "token jednorazowy: drugie uzycie odrzucone" || bad "token uzyty drugi raz!"

# ── 6. Sprawa bez produktu (zapytanie bez serialu) = snapshot NULL ─────────
OUT2=$(wp mp case-create --kind=zapytanie --email='anna@example.com' 2>/dev/null)
CID2=$(echo "$OUT2" | grep '^case_id=' | cut -d= -f2)
SNAP2=$(q "SELECT COALESCE(warranty_snapshot,'NULL') FROM wp_mp_service_cases WHERE id=$CID2")
PROD2=$(q "SELECT COALESCE(product_registry_id,'NULL') FROM wp_mp_service_cases WHERE id=$CID2")
[ "$SNAP2" = "NULL" ] && [ "$PROD2" = "NULL" ] && ok "sprawa bez produktu: snapshot i product_id = NULL" || bad "snapshot=$SNAP2 prod=$PROD2"

# ── 7. Token nieznany = odmowa (bez enumeracji) ───────────────────────────
UNK=$(wp eval "\$r=MP\Intake\CaseRepo::verify('nieistniejacy-token-xyz'); echo isset(\$r['error'])?'DENIED':'ALLOWED';" 2>/dev/null)
[ "$UNK" = "DENIED" ] && ok "nieznany token odrzucony" || bad "nieznany token przeszedl!"

echo
echo "WYNIK C1: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
