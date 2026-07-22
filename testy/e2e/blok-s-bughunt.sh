#!/usr/bin/env bash
# BLOK-S — BUG-HUNT 12 PERSON na formularzu Intake + panelu (zywe demo).
# Metoda: SCIAGA-BUG-HUNT.md (destylat bugbash + agentic-beta-testers). Napedzamy
# DZIALAJACY produkt adwersaryjnie i asertujemy ODPORNOSC (atak => system broni
# sie: odrzuca/sanityzuje/escapuje, nigdy 500 ani wyciek). Kazdy atak = twardy
# test w repo (zasada "audytor->test"). Person ★-krytycznych bronimy mechanicznie;
# person UX-jakosciowych nie da sie zmechanizowac — pokryte a11y + eksploracja
# (jawnie w podsumowaniu, cichy skip = klamstwo "przetestowane").
#
# ★ chaos_gremlin · ★ technical_exploit · ★ privacy_paranoid · ★ methodical_newcomer
# (UX-eksploracyjne: speedrunner, skeptical_exec, overloaded_manager, calm_operator,
#  adhd_founder, feature_explorer, interactive_explorer, hybrid_auditor)
#
# Chodzi na poligonie (MP_BASE z env) i w CI. Exit 0 = zero FAIL (= zero bugow;
# bug znaleziony => FAIL z krokami odtworzenia w tekscie asercji).
set -u

BASE="${MP_BASE:-http://localhost:8090}"
CAPTURE="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
JAR="$(mktemp)"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); echo "  OK   $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
skip() { SKIP=$((SKIP+1)); echo "  SKIP $1"; }
q()    { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

SITE_HOST=$(wp option get home 2>/dev/null | sed 's#^https\?://##;s#/.*##')
HOSTHDR=(); [ -n "$SITE_HOST" ] && HOSTHDR=(-H "Host: $SITE_HOST")
cget() { curl -s "${HOSTHDR[@]}" "$@"; }

clean() {
	wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_product_registry; DELETE FROM wp_mp_consents;" >/dev/null 2>&1
	wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_rl%' OR option_name LIKE '_transient_timeout_mp_rl%'" >/dev/null 2>&1
	wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
	for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done
	rm -f "$CAPTURE"
}
nonce() { cget "$1" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//'; }

PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
PAGE_URL="$BASE$PAGE_PATH"
POST_URL="$BASE/wp-admin/admin-post.php"

echo "== BLOK-S BUG-HUNT: 12 person na formularzu + panelu =="

# ═══ ★ privacy_paranoid — "po co ci moje dane?" ═══════════════════════════
echo "-- privacy_paranoid: zgoda + NO-PII-IN-LOG --"
clean; N=$(nonce "$PAGE_URL")
# Atak: wyslij BEZ zgody RODO => musi odrzucic (zero spraw).
cget -c "$JAR" -b "$JAR" -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$N" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 30 ))" \
	--data-urlencode "kind=zapytanie" --data-urlencode "email=paranoid@example.com" \
	--data-urlencode "name=Jan Kowalski" --data-urlencode "issue_description=pytanie" \
	"$POST_URL"
NOCONSENT=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE identity_status='pending'")
[ "${NOCONSENT:-0}" = "0" ] && ok "privacy: zgloszenie BEZ zgody RODO ODRZUCONE (zero spraw)" || bad "privacy: BUG — sprawa powstala bez zgody! (kroki: submit bez mp_consent => $NOCONSENT spraw)"
# Atak: PII w logu zdarzen. Zloz poprawnie i sprawdz, ze payload eventow NIE
# niesie surowego maila/nazwiska/opisu (NO-PII-IN-LOG, events sa strukturalne).
clean; N=$(nonce "$PAGE_URL")
cget -c "$JAR" -b "$JAR" -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$N" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 30 ))" \
	--data-urlencode "kind=zapytanie" --data-urlencode "email=pii-leak@secret.xx" \
	--data-urlencode "name=TajneNazwisko Kowalski" --data-urlencode "issue_description=Moj PESEL 99010112345" \
	--data-urlencode "mp_consent=1" "$POST_URL"
sleep 1
TOKEN=$(grep 'mp_intake_verify' "$CAPTURE" 2>/dev/null | grep -oE 'token=[^" \\]+' | head -1 | sed 's/token=//')
VH=$(cget -c "$JAR" -o /tmp/mp-bh-v.html "$POST_URL?action=mp_intake_verify&token=$TOKEN"); VN=$(grep -o 'name="_mp_nonce" value="[^"]*"' /tmp/mp-bh-v.html | head -1 | sed 's/.*value="//;s/"//')
cget -c "$JAR" -b "$JAR" -o /dev/null --data-urlencode "action=mp_intake_verify_confirm" --data-urlencode "_mp_nonce=$VN" --data-urlencode "token=$TOKEN" "$POST_URL"
PII=$(wp db query "SELECT GROUP_CONCAT(payload) FROM wp_mp_case_events" --skip-column-names 2>/dev/null)
if echo "$PII" | grep -qiE "pii-leak@secret\.xx|TajneNazwisko|99010112345"; then
	bad "privacy: BUG — PII w payload eventow (NO-PII-IN-LOG zlamane; kroki: zloz sprawe, grep wp_mp_case_events.payload)"
else
	ok "privacy: NO-PII-IN-LOG — payload eventow bez surowego maila/nazwiska/PESEL (tylko referencje)"
fi

# ═══ ★ technical_exploit — "nie gram wg zasad" ════════════════════════════
echo "-- technical_exploit: XSS + SQLi + IDOR --"
# Reflected XSS: <script> w opisie + bledny email => re-render formularza musi ESCAPOWAC.
clean; N=$(nonce "$PAGE_URL")
XSSHTML=$(cget -c "$JAR" -b "$JAR" \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$N" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 30 ))" \
	--data-urlencode "kind=zapytanie" --data-urlencode "email=nie-email" \
	--data-urlencode "name=<script>alert(1)</script>" \
	--data-urlencode "issue_description=<script>alert('xss')</script>" \
	--data-urlencode "mp_consent=1" "$POST_URL")
if echo "$XSSHTML" | grep -q "<script>alert"; then
	bad "technical: BUG — reflected XSS (surowy <script> w re-renderze; kroki: submit name=<script>, bledny email)"
else
	ok "technical: reflected XSS zablokowany — wartosci escapowane w re-renderze (brak surowego <script>)"
fi
# SQLi: serial jako payload wstrzykniecia => prepared statement, zero bledu SQL.
clean; N=$(nonce "$PAGE_URL")
SQLHTML=$(cget -c "$JAR" -b "$JAR" \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$N" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 30 ))" \
	--data-urlencode "kind=reklamacja" --data-urlencode "email=sqli@example.com" \
	--data-urlencode "serial=' OR '1'='1" --data-urlencode "purchase_document=FV/1" \
	--data-urlencode "purchase_date=2026-03-01" --data-urlencode "issue_description=x" \
	--data-urlencode "mp_consent=1" "$POST_URL")
DBERR=$(q "SELECT 1")  # sanity: baza zyje po ataku
if echo "$SQLHTML" | grep -qiE "SQL syntax|mysqli|You have an error|Fatal error"; then
	bad "technical: BUG — SQLi/blad SQL wyciekl w odpowiedzi (kroki: serial=' OR '1'='1)"
else
	ok "technical: SQLi — serial-wstrzykniecie potraktowane doslownie (prepared; zero bledu SQL, baza zyje=$DBERR)"
fi
# IDOR: panel klienta A nie moze zobaczyc sprawy klienta B.
clean
OA=$(wp mp case-create --kind=zapytanie --email='idor-a@example.com' --name='A' --desc='a' 2>/dev/null); TA=$(echo "$OA"|grep '^token='|cut -d= -f2); wp mp case-verify "$TA" >/dev/null 2>&1
OB=$(wp mp case-create --kind=zapytanie --email='idor-b@example.com' --name='B' --desc='b' 2>/dev/null); TB=$(echo "$OB"|grep '^token='|cut -d= -f2); wp mp case-verify "$TB" >/dev/null 2>&1
UIDA=$(wp user get 'idor-a@example.com' --field=ID 2>/dev/null)
CNUMB=$(q "SELECT case_number FROM wp_mp_service_cases WHERE customer_id=(SELECT id FROM wp_mp_customers WHERE email='idor-b@example.com')")
PANELA=$(wp eval "wp_set_current_user($UIDA); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)
echo "$PANELA" | grep -q "$CNUMB" && bad "technical: BUG — IDOR, panel klienta A pokazuje sprawe B ($CNUMB)" || ok "technical: IDOR — panel klienta A NIE widzi sprawy klienta B"

# ═══ ★ chaos_gremlin — "co jak zrobie TO?" ════════════════════════════════
echo "-- chaos_gremlin: przeciazenie + braki + duplikat --"
# Ogromny opis (50k znakow) => brak 500, system stabilny.
clean; N=$(nonce "$PAGE_URL"); BIG=$(printf 'A%.0s' $(seq 1 50000))
CODE=$(cget -c "$JAR" -b "$JAR" -o /dev/null -w '%{http_code}' \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$N" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 30 ))" \
	--data-urlencode "kind=zapytanie" --data-urlencode "email=chaos@example.com" \
	--data-urlencode "name=Chaos" --data-urlencode "issue_description=$BIG" \
	--data-urlencode "mp_consent=1" "$POST_URL")
{ [ "$CODE" != "500" ] && [ -n "$CODE" ]; } && ok "chaos: opis 50k znakow obsluzony bez 500 (HTTP $CODE, LONGTEXT stabilny)" || bad "chaos: BUG — 500 na duzym opisie (HTTP $CODE)"
# Braki: reklamacja bez wymaganych pol => walidacja odrzuca.
clean; N=$(nonce "$PAGE_URL")
cget -c "$JAR" -b "$JAR" -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$N" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 30 ))" \
	--data-urlencode "kind=reklamacja" --data-urlencode "email=braki@example.com" \
	--data-urlencode "issue_description=bez serialu" --data-urlencode "mp_consent=1" "$POST_URL"
BRAKI=$(q "SELECT COUNT(*) FROM wp_mp_service_cases")
[ "${BRAKI:-0}" = "0" ] && ok "chaos: reklamacja bez wymaganych pol (serial/dokument/data) ODRZUCONA" || bad "chaos: BUG — reklamacja bez wymaganych pol przeszla ($BRAKI)"

# ═══ ★ methodical_newcomer — "jestem tu nowy" (overlap a11y) ══════════════
echo "-- methodical_newcomer: etykiety + prowadzenie bledem --"
FORM=$(cget "$PAGE_URL")
{ echo "$FORM" | grep -q '<label for=' && echo "$FORM" | grep -qE '(required|aria-required)'; } \
	&& ok "newcomer: formularz ma etykiety <label for> + oznaczenia pol wymaganych (nie zgaduje)" \
	|| bad "newcomer: BUG — brak etykiet/oznaczen wymaganych (mylacy dla nowego)"

# ═══ Persony UX-eksploracyjne (nie do mechanizacji) ═══════════════════════
echo "-- persony UX-jakosciowe (eksploracja, nie auto-asercja) --"
skip "UX: speedrunner/skeptical_exec/overloaded_manager/calm_operator/adhd_founder/feature_explorer/interactive_explorer/hybrid_auditor — obciazenie poznawcze, stany ladowania, hierarchia [eksploracja manualna + a11y-forms; nie mechaniczne]"

echo
echo "== PODSUMOWANIE POKRYCIA =="
echo "  Auto-asercja (★): privacy_paranoid (zgoda + NO-PII), technical_exploit (XSS+SQLi+IDOR), chaos_gremlin (przeciazenie+braki), methodical_newcomer (etykiety)"
echo "  Eksploracja/a11y: 8 person UX-jakosciowych (jawnie NIE auto-asertowane)"
echo
echo "WYNIK BLOK-S BUG-HUNT: $PASS ok, $FAIL fail, $SKIP skip"
[ "$FAIL" -eq 0 ]
