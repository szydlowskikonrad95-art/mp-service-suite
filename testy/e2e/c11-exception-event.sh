#!/usr/bin/env bash
# ZYWY DOWOD #11: wyjatek gwarancyjny (B) => wpis na osi zdarzen sprawy (C).
# Kontrakt EVENT_MODEL.md: listener C na mp_warranty_exception_changed zapisuje
# EXCEPTION_APPLIED (stan 'active') / EXCEPTION_REVOKED (stan 'revoked') do
# wp_mp_case_events; payload STRUKTURALNY {exception_id} — NO-PII (bez reason);
# case_id=NULL (wyjatek globalny) => NO-OP.
# Realna droga: wp mp exception-add/revoke (B) -> do_action PO COMMIT -> listener C.
# Tylko wp-cli (bez HTTP). Chodzi na poligonie i w CI (e2e-import).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

clean() {
	wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_product_registry; DELETE FROM wp_mp_warranty_exceptions;" >/dev/null 2>&1
	for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done
}

seed_product() { # serial -> echo product_id
	wp db query "INSERT INTO wp_mp_product_registry (serial_display, serial_normalized, model, batch, purchase_document, purchase_date, warranty_until, source, archived, created_at, updated_at) VALUES ('$1','$1','Model-EX','P-EX','FV/EX/1','2026-03-01','2030-03-01','manual',0,UTC_TIMESTAMP(),UTC_TIMESTAMP())" >/dev/null 2>&1
	q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$1'"
}

mkcase() { # email serial -> echo case_id (potwierdzona)
	local out tok cid
	out=$(wp mp case-create --email="$1" --name='EX' --kind=reklamacja --serial="$2" --document='FV/EX/1' --date='2026-03-01' --desc='exc-test' 2>/dev/null)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	wp mp case-verify "$tok" >/dev/null 2>&1
	echo "$cid"
}

echo "== C11: wyjatek gwarancyjny => os zdarzen sprawy =="

REASON_PII="Klient Jan Kowalski reklamuje - poufny powod wyjatku"

# ── 1. Wyjatek NA SPRAWE (active) => EXCEPTION_APPLIED + payload {exception_id} ──
clean
PID=$(seed_product "EX-SER-1"); CID=$(mkcase 'exc@example.com' 'EX-SER-1')
[ -n "$CID" ] && [ "$CID" -gt 0 ] 2>/dev/null && ok "scena: sprawa #$CID utworzona i potwierdzona" || bad "scena: sprawa nie powstala (CID=$CID)"

wp mp exception-add "EX-SER-1" --reason="$REASON_PII" --case="$CID" --until='2027-01-01' --user=1 >/dev/null 2>&1
EXC_ID=$(q "SELECT id FROM wp_mp_warranty_exceptions WHERE case_id=$CID AND status='active' ORDER BY id DESC LIMIT 1")
[ -n "$EXC_ID" ] && [ "$EXC_ID" -gt 0 ] 2>/dev/null && ok "B: wyjatek #$EXC_ID przyznany (emisja mp_warranty_exception_changed active)" || bad "B: wyjatek nie przyznany (EXC_ID=$EXC_ID)"

APPLIED=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='EXCEPTION_APPLIED'")
[ "${APPLIED:-0}" = "1" ] && ok "C listener: EXCEPTION_APPLIED na osi sprawy (dokladnie 1)" || bad "brak/duplikat EXCEPTION_APPLIED na osi (=$APPLIED)"

PAYLOAD=$(q "SELECT payload FROM wp_mp_case_events WHERE case_id=$CID AND event_type='EXCEPTION_APPLIED' ORDER BY id DESC LIMIT 1")
[ "$PAYLOAD" = "{\"exception_id\":$EXC_ID}" ] && ok "payload strukturalny = {exception_id:$EXC_ID}" || bad "payload nie zgadza sie z kontraktem (=$PAYLOAD)"

# NO-PII: payload nie niesie reason ani danych klienta.
if echo "$PAYLOAD" | grep -qiE 'reason|Kowalski|poufny|reklamuje'; then
	bad "NO-PII zlamane: payload zawiera reason/dane osobowe (=$PAYLOAD)"
else
	ok "NO-PII: payload bez reason i danych osobowych"
fi

# Actor uchwycony (admin robiacy operacje = --user=1), nie system-null.
ACTOR=$(q "SELECT actor_id FROM wp_mp_case_events WHERE case_id=$CID AND event_type='EXCEPTION_APPLIED' ORDER BY id DESC LIMIT 1")
[ "$ACTOR" = "1" ] && ok "actor_id=1 (admin uchwycony w evencie)" || bad "actor_id nieoczekiwany (=$ACTOR)"

# ── 2. Cofniecie wyjatku (revoked) => EXCEPTION_REVOKED ─────────────────────
wp mp exception-revoke "$EXC_ID" --user=1 >/dev/null 2>&1
REVOKED=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='EXCEPTION_REVOKED'")
[ "${REVOKED:-0}" = "1" ] && ok "C listener: EXCEPTION_REVOKED na osi sprawy (stan revoked)" || bad "brak/duplikat EXCEPTION_REVOKED na osi (=$REVOKED)"
# APPLIED nadal 1 (os append-only — cofniecie nie kasuje wpisu nadania).
APPLIED2=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='EXCEPTION_APPLIED'")
[ "${APPLIED2:-0}" = "1" ] && ok "os append-only: EXCEPTION_APPLIED nadal 1 po cofnieciu" || bad "os naruszona po cofnieciu (APPLIED=$APPLIED2)"

# ── 3. Wyjatek GLOBALNY (case_id=NULL) => NO-OP na osi spraw ────────────────
clean
PID_G=$(seed_product "EX-GLOB")
wp mp exception-add "EX-GLOB" --reason='globalny na produkt' --until='2027-01-01' --user=1 >/dev/null 2>&1
GEXC=$(q "SELECT COUNT(*) FROM wp_mp_warranty_exceptions WHERE case_id IS NULL AND status='active'")
[ "${GEXC:-0}" -ge 1 ] && ok "B: wyjatek globalny przyznany (case_id NULL, emisja active)" || bad "B: wyjatek globalny nie przyznany (=$GEXC)"
GEV=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE event_type IN ('EXCEPTION_APPLIED','EXCEPTION_REVOKED')")
[ "${GEV:-0}" = "0" ] && ok "no-op: wyjatek globalny nie tworzy wpisu na osi spraw (case_id NULL)" || bad "no-op zlamane: globalny wyjatek dodal wpis na osi (=$GEV)"

echo
echo "WYNIK C11: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
