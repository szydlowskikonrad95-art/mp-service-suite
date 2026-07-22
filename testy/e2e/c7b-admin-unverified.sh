#!/usr/bin/env bash
# ZYWY DOWOD C7b (admin unverified + resend): capability-sweep + throttle + fresh-token.
# - lista unverified + resend PRZEZ personel (mp_agent): swiezy token (stary hash sie zmienia)
# - throttle 1/5min per sprawa: 2. resend nie zmienia tokena
# - popraw e-mail: resend z nowym mailem aktualizuje pending
# - audit-log operacji (nie eventy)
# - NEGATYWNA MACIERZ ROL: subscriber => 403, anon => 403 (capability przed nonce)
# Wymaga MP_BASE. Chodzi na poligonie i w CI (e2e-import).
set -u
: "${MP_BASE:?MP_BASE wymagane}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
cid() { echo "$1" | grep '^case_id=' | cut -d= -f2; }

# Logowanie uzytkownika haslem -> zapis cookie w jar.
login() {
	local user="$1" jar="$2"
	rm -f "$jar"
	curl -s -c "$jar" -o /dev/null "$MP_BASE/wp-login.php"
	curl -s -c "$jar" -b "$jar" -o /dev/null \
		--data-urlencode "log=$user" --data-urlencode "pwd=Test12345!" \
		--data-urlencode "wp-submit=Zaloguj" --data-urlencode "redirect_to=$MP_BASE/wp-admin/" \
		"$MP_BASE/wp-login.php"
}

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_consents;" >/dev/null 2>&1
wp db query "DELETE FROM wp_options WHERE option_name='mp_intake_audit_log' OR option_name LIKE '_transient_mp_resend_throttle%' OR option_name LIKE '_transient_timeout_mp_resend_throttle%'" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
for u in agent1 sub1; do id=$(wp user get "$u" --field=ID 2>/dev/null); [ -n "$id" ] && wp user delete "$id" --yes >/dev/null 2>&1; done

wp user create agent1 agent1@example.com --role=mp_agent --user_pass='Test12345!' >/dev/null 2>&1
wp user create sub1 sub1@example.com --role=subscriber --user_pass='Test12345!' >/dev/null 2>&1

# Dwie sprawy niepotwierdzone (CLI — bez weryfikacji).
O1=$(wp mp case-create --kind=zapytanie --email='u1@example.com' --desc='a' 2>/dev/null); CID1=$(cid "$O1")
O2=$(wp mp case-create --kind=zapytanie --email='u2@example.com' --desc='b' 2>/dev/null); CID2=$(cid "$O2")

# ── 1. Agent widzi liste + nonce resendu ────────────────────────────────────
login 'agent1' /tmp/mp-agent-jar
PAGE=$(curl -s -b /tmp/mp-agent-jar "$MP_BASE/wp-admin/admin.php?page=mp-intake-unverified")
SRV1=$(q "SELECT case_number FROM wp_mp_service_cases WHERE id=$CID1")
echo "$PAGE" | grep -q "$SRV1" && ok "agent widzi sprawe niepotwierdzona na liscie ($SRV1)" || bad "brak sprawy na liscie admina"
N1=$(echo "$PAGE" | grep -o "name=\"case_id\" value=\"$CID1\".*" | grep -o 'name="_wpnonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$N1" ] && ok "nonce resendu dla sprawy pobrany" || bad "brak nonce resendu"

# ── 2. Resend przez agenta: swiezy token (hash sie zmienia) + audit ─────────
OLDH=$(q "SELECT verify_token_hash FROM wp_mp_service_cases WHERE id=$CID1")
curl -s -b /tmp/mp-agent-jar -o /dev/null \
	--data-urlencode "action=mp_intake_resend" --data-urlencode "case_id=$CID1" \
	--data-urlencode "_wpnonce=$N1" --data-urlencode "email=u1@example.com" \
	"$MP_BASE/wp-admin/admin-post.php"
NEWH=$(q "SELECT verify_token_hash FROM wp_mp_service_cases WHERE id=$CID1")
{ [ -n "$NEWH" ] && [ "$NEWH" != "$OLDH" ]; } && ok "resend = SWIEZY token (stary hash uniewazniony)" || bad "token nie zmieniony (old=$OLDH new=$NEWH)"
AUD=$(wp eval "echo count(array_filter(MP\Intake\Audit::entries(), function(\$e){ return \$e['action']==='resend'; }));" 2>/dev/null)
[ "${AUD:-0}" -ge 1 ] && ok "audit-log: operacja resend zapisana ($AUD)" || bad "brak wpisu audit resend"

# ── 3. Throttle 1/5min: 2. resend nie zmienia tokena ────────────────────────
curl -s -b /tmp/mp-agent-jar -o /dev/null \
	--data-urlencode "action=mp_intake_resend" --data-urlencode "case_id=$CID1" \
	--data-urlencode "_wpnonce=$N1" --data-urlencode "email=u1@example.com" \
	"$MP_BASE/wp-admin/admin-post.php"
H3=$(q "SELECT verify_token_hash FROM wp_mp_service_cases WHERE id=$CID1")
[ "$H3" = "$NEWH" ] && ok "throttle 1/5min: 2. resend ZABLOKOWANY (token bez zmian)" || bad "throttle przepuscil 2. resend"

# ── 4. Popraw e-mail przy resendzie (sprawa 2, bez throttle) ────────────────
N2=$(echo "$PAGE" | grep -o "name=\"case_id\" value=\"$CID2\".*" | grep -o 'name="_wpnonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
curl -s -b /tmp/mp-agent-jar -o /dev/null \
	--data-urlencode "action=mp_intake_resend" --data-urlencode "case_id=$CID2" \
	--data-urlencode "_wpnonce=$N2" --data-urlencode "email=poprawiony@example.com" \
	"$MP_BASE/wp-admin/admin-post.php"
NEWMAIL=$(wp eval "echo MP\Intake\CaseRepo::pending_email($CID2);" 2>/dev/null)
[ "$NEWMAIL" = "poprawiony@example.com" ] && ok "popraw e-mail: pending zaktualizowany ($NEWMAIL)" || bad "e-mail niepoprawiony ($NEWMAIL)"

# ── 5. NEGATYWNA MACIERZ ROL: subscriber => 403 ─────────────────────────────
login 'sub1' /tmp/mp-sub-jar
CODE_SUB=$(curl -s -b /tmp/mp-sub-jar -o /dev/null -w '%{http_code}' \
	--data-urlencode "action=mp_intake_resend" --data-urlencode "case_id=$CID1" \
	--data-urlencode "_wpnonce=$N1" --data-urlencode "email=x@x.pl" \
	"$MP_BASE/wp-admin/admin-post.php")
[ "$CODE_SUB" = "403" ] && ok "subscriber => 403 (capability blokuje przed nonce)" || bad "subscriber nie dostal 403 ($CODE_SUB)"

# ── 6. NEGATYWNA MACIERZ ROL: anon => 403 ───────────────────────────────────
CODE_ANON=$(curl -s -o /dev/null -w '%{http_code}' \
	--data-urlencode "action=mp_intake_resend" --data-urlencode "case_id=$CID1" \
	--data-urlencode "_wpnonce=$N1" --data-urlencode "email=x@x.pl" \
	"$MP_BASE/wp-admin/admin-post.php")
[ "$CODE_ANON" = "403" ] && ok "anon => 403 (nopriv handler + capability)" || bad "anon nie dostal 403 ($CODE_ANON)"

# Sprawa niezmieniona przez subscriber/anon.
HFIN=$(q "SELECT verify_token_hash FROM wp_mp_service_cases WHERE id=$CID1")
[ "$HFIN" = "$NEWH" ] && ok "subscriber/anon NIE ruszyli tokena sprawy" || bad "token zmieniony przez nieuprawnionego!"

echo
echo "WYNIK C7b: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
