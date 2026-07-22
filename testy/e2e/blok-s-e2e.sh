#!/usr/bin/env bash
# BLOK-S — E2E PELNY PRZEBIEG 8 KROKOW KARTKI (calosciowa sciezka sprawy).
# Nie duplikuje c3-front (mechanika frontu) — spina B+C+D w JEDEN przebieg wg
# oryginalnej kartki klienta (BRIEF-ODCZYT-KARTKI kroki 1-8) i mapuje kazdy krok
# 1:1. Kroki zalezne od write-path personelu / Automatora (D) — ktore jeszcze
# nie istnieja w kodzie — sa SKIP z JAWNYM powodem (skip()), NIE fail; zaswieca
# sie zielono automatycznie gdy funkcja/listener D wejdzie do kodu.
#
# 8 krokow kartki:
#  1. Klient wybiera rodzaj + uzupelnia formularz            [LIVE — HTTP]
#  2. System sprawdza kompletnosc + zalaczniki + duplikat     [LIVE — HTTP]
#  3. Rejestr gwarancji weryfikuje serial/produkt/date (B)    [LIVE — snapshot B->C]
#  4. Sprawa z numerem SRV + termin pierwszej reakcji         [LIVE SRV / SLA=D-pending]
#  5. Silnik regul nadaje priorytet + przydziela (D)          [D-pending]
#  6. Klient dostaje potwierdzenie + podglad statusu          [LIVE — panel IDOR]
#  7. Pracownik realizuje checkliste, decyzje w historii      [D-pending / mp_case_change_status]
#  8. Przypomnienia + eskalacje + raport koncowy (D)          [D-pending]
#
# Chodzi na poligonie (MP_BASE/CAPTURE z env) i w CI. Exit 0 = zero FAIL
# (SKIP nie psuje wyniku — to jawna, zaraportowana luka koordynacyjna).
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

echo "== BLOK-S E2E: pelny przebieg 8 krokow kartki =="

# ── 0. Czysty stan (C + B produkt + przechwyt maila) ──────────────────────
wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_product_registry; DELETE FROM wp_mp_case_sla;" >/dev/null 2>&1
# Rate-limit warstwowy + marker dedup (prefiks mp_rl_ip_/em_/sn_/dd_) — bez tego
# ponowny przebieg z tym samym serialem/mailem jest odrzucany jako duplikat/limit.
wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_rl%' OR option_name LIKE '_transient_timeout_mp_rl%'" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done
rm -f "$CAPTURE"

# Produkt w rejestrze B: serial na gwarancji, z dokumentem i data zakupu — zeby
# krok 3 (weryfikacja gwarancji) mial CO sprawdzic, a snapshot niosl realne dane.
SER="S-E2E-777"; SERNORM="SE2E777"
wp db query "INSERT INTO wp_mp_product_registry
  (serial_display, serial_normalized, model, batch, purchase_document, purchase_date, warranty_until, source, archived, created_at, updated_at)
  VALUES ('$SER','$SERNORM','Piec CO-500','PARTIA-E2E','FV/2026/777','2026-03-01','2030-03-01','manual',0,UTC_TIMESTAMP(),UTC_TIMESTAMP())" >/dev/null 2>&1
PID=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_normalized='$SERNORM'")
[ -n "$PID" ] && ok "przygotowanie: produkt w rejestrze B ($SER, gwarancja do 2030) id=$PID" || bad "seed produktu B nie powiodl sie"

# Agent + regula przydzialu (P3.1): auto-przydzial na mp_case_created wymaga reguly
# ASSIGN z pula agentow (silnik filtruje pule po cap mp_agent). Ustawiamy PRZED
# zgloszeniem, bo mp_case_created leci przy potwierdzeniu (krok 4). Agent przezywa
# miedzy przebiegami (idempotencja); regule sialem od nowa.
wp db query "DELETE FROM wp_mp_workflow_rules;" >/dev/null 2>&1
AGENT_UID=$(wp user get e2e-agent@example.com --field=ID 2>/dev/null)
[ -z "$AGENT_UID" ] && AGENT_UID=$(wp user create e2e-agent e2e-agent@example.com --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
wp user set-role "$AGENT_UID" mp_agent >/dev/null 2>&1
wp eval "MP\Automator\Rules::insert(array('trigger_type'=>'case_created','condition_key'=>'','action_type'=>'assign','action_config'=>array('pool'=>array($AGENT_UID),'notify_agent'=>true),'priority'=>10,'enabled'=>1,'source'=>'system','system_key'=>'e2e_assign'));" >/dev/null 2>&1
{ [ -n "$AGENT_UID" ] && [ "$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules")" = "1" ]; } \
	&& ok "przygotowanie: agent mp_agent (uid=$AGENT_UID) + regula auto-przydzialu ASSIGN (P3.1)" \
	|| bad "przygotowanie: agent/regula nie ustawione (agent=$AGENT_UID)"

# ── KROK 1+2: klient wypelnia formularz -> system waliduje (HTTP jak klient) ─
PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
HTML=$(cget "$BASE$PAGE_PATH")
NONCE=$(echo "$HTML" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
echo "$HTML" | grep -q 'name="action" value="mp_intake_submit"' && ok "KROK 1: formularz zgloszenia renderuje sie na zywej stronie" || bad "KROK 1: brak formularza na stronie"
[ -n "$NONCE" ] && ok "KROK 2: formularz niesie nonce (CSRF) — walidacja wejscia aktywna" || bad "KROK 2: brak nonce"

cget -c "$JAR" -b "$JAR" -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
	--data-urlencode "mp_ts=$(( $(date +%s) - 30 ))" \
	--data-urlencode "kind=reklamacja" --data-urlencode "email=e2e-klient@example.com" \
	--data-urlencode "name=Anna E2E" \
	--data-urlencode "serial=$SER" --data-urlencode "purchase_document=FV/2026/777" \
	--data-urlencode "purchase_date=2026-03-01" --data-urlencode "issue_description=Piec nie grzeje po tygodniu" \
	--data-urlencode "mp_consent=1" \
	"$BASE/wp-admin/admin-post.php"
CID=$(q "SELECT id FROM wp_mp_service_cases WHERE status IS NULL AND identity_status='pending' ORDER BY id DESC LIMIT 1")
[ -n "$CID" ] && ok "KROK 2: poprawne zgloszenie przeszlo walidacje -> sprawa unverified (id=$CID)" || bad "KROK 2: sprawa unverified nie powstala"

# ── KROK 3: rejestr gwarancji (B) — snapshot niosacy realne dane produktu ──
SNAP_PID=$(q "SELECT product_registry_id FROM wp_mp_service_cases WHERE id=$CID")
SNAP=$(wp db query "SELECT warranty_snapshot FROM wp_mp_service_cases WHERE id=$CID" --skip-column-names 2>/dev/null)
[ "$SNAP_PID" = "$PID" ] && ok "KROK 3: sprawa dowiazana do produktu z rejestru B (product_registry_id=$PID)" || bad "KROK 3: brak dowiazania produktu (snap_pid=$SNAP_PID != $PID)"
echo "$SNAP" | grep -q 'aktywna' && ok "KROK 3: snapshot gwarancji zamrozony na moment zgloszenia (status=aktywna z B)" || bad "KROK 3: snapshot nie niesie statusu gwarancji z B (snap=$SNAP)"

# ── KROK 4a: potwierdzenie maila -> narodziny sprawy: SRV + status nowe ─────
sleep 1
TOKEN=$(grep 'mp_intake_verify' "$CAPTURE" 2>/dev/null | grep -oE 'token=[^" \\]+' | head -1 | sed 's/token=//')
[ -n "$TOKEN" ] && ok "KROK 4: mail magic-link niesie token weryfikacji" || bad "KROK 4: brak tokenu w mailu"
cget -c "$JAR" -D - -o /tmp/mp-s-verify.html "$BASE/wp-admin/admin-post.php?action=mp_intake_verify&token=$TOKEN" >/dev/null
VNONCE=$(grep -o 'name="_mp_nonce" value="[^"]*"' /tmp/mp-s-verify.html | head -1 | sed 's/.*value="//;s/"//')
cget -c "$JAR" -b "$JAR" -o /tmp/mp-s-confirm.html \
	--data-urlencode "action=mp_intake_verify_confirm" --data-urlencode "_mp_nonce=$VNONCE" \
	--data-urlencode "token=$TOKEN" "$BASE/wp-admin/admin-post.php"
ST=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
[ "$ST" = "nowe" ] && ok "KROK 4: po potwierdzeniu sprawa verified, status='nowe'" || bad "KROK 4: status po weryfikacji='$ST' (oczek. nowe)"
CNUM=$(q "SELECT case_number FROM wp_mp_service_cases WHERE id=$CID")
echo "$CNUM" | grep -qE "^SRV/[0-9]{4}/[0-9]{4}$" && ok "KROK 4: nadany numer SRV: $CNUM (format SRV/RRRR/NNNN)" || bad "KROK 4: zly/brak numeru SRV: $CNUM"
# status_changed_at ustawiony przy weryfikacji = start zegara SLA (dziura K1 audytu)
SCA=$(q "SELECT COALESCE(status_changed_at,'NULL') FROM wp_mp_service_cases WHERE id=$CID")
VER=$(q "SELECT COALESCE(verified_at,'NULL') FROM wp_mp_service_cases WHERE id=$CID")
{ [ "$SCA" != "NULL" ] && [ "$SCA" = "$VER" ]; } && ok "KROK 4: status_changed_at=verified_at ustawiony (zegar terminu pierwszej reakcji wystartowal)" || bad "KROK 4: status_changed_at nie ustawiony przy weryfikacji (SCA=$SCA VER=$VER) — sprawa bez zegara SLA (K1)"
# Narodziny niosa CASE_CREATED, NIE status_changed (semantyka kontraktu)
EVN=$(q "SELECT event_type FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CASE_CREATED'")
[ "$EVN" = "CASE_CREATED" ] && ok "KROK 4: event CASE_CREATED w historii (narodziny; nie status_changed)" || bad "KROK 4: brak CASE_CREATED"
SC_CNT=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='STATUS_CHANGED'")
[ "$SC_CNT" = "0" ] && ok "KROK 4: przejscie zalozycielskie NULL->nowe NIE emituje STATUS_CHANGED (semantyka)" || bad "KROK 4: narodziny bledne — jest STATUS_CHANGED ($SC_CNT)"

# ── KROK 4b/8a: termin pierwszej reakcji (wiersz SLA) — zaklada D na mp_case_created ─
SLA_ROW=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID")
if [ "${SLA_ROW:-0}" -ge 1 ]; then
	ok "KROK 4/8: D zalozyl wiersz SLA (termin pierwszej reakcji) na mp_case_created"
else
	skip "KROK 4/8: wiersz case_sla nieutworzony — D nasluchuje mp_case_created (P3.1 auto-przydzial dziala), ale foundowanie SLA to P3.3+ [zaswieci gdy SLA wejdzie]"
fi

# ── KROK 5: silnik regul nadaje priorytet + przydziela (D) ─────────────────
ASSIGNED=$(q "SELECT COALESCE(assigned_to,0) FROM wp_mp_service_cases WHERE id=$CID")
CA_EV=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CASE_ASSIGNED'")
{ [ "${ASSIGNED:-0}" = "${AGENT_UID:-x}" ] && [ "${CA_EV:-0}" -ge 1 ]; } \
	&& ok "KROK 5: silnik regul D (P3.1) auto-przydzielil sprawe do agenta z puli (assigned_to=$ASSIGNED) + event CASE_ASSIGNED" \
	|| bad "KROK 5: auto-przydzial nie zadzialal (assigned_to=$ASSIGNED oczek=$AGENT_UID · CASE_ASSIGNED=$CA_EV)"

# ── KROK 6: klient dostaje potwierdzenie (SRV mailem) + podglad statusu ─────
sleep 1
grep -q "$CNUM" "$CAPTURE" 2>/dev/null && ok "KROK 6: 2. mail potwierdzajacy niesie numer SRV ($CNUM)" || bad "KROK 6: brak maila z SRV"
grep -q "SRV/" /tmp/mp-s-confirm.html && bad "KROK 6: strona potwierdzenia ZDRADZA SRV (ma byc tylko mailem)" || ok "KROK 6: strona potwierdzenia neutralna (SRV wylacznie mailem)"
# Panel klienta: widzi WLASNA sprawe, status na zywo, IDOR-safe.
UID1=$(q "SELECT wp_user_id FROM wp_mp_customers c JOIN wp_mp_service_cases s ON s.customer_id=c.id WHERE s.id=$CID")
if [ -n "$UID1" ] && [ "$UID1" != "0" ]; then
	PANEL=$(wp eval "wp_set_current_user($UID1); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)
	echo "$PANEL" | grep -q "$CNUM" && ok "KROK 6: panel klienta pokazuje wlasna sprawe ($CNUM) ze statusem na zywo" || bad "KROK 6: panel nie pokazuje sprawy klienta"
	# IDOR: druga sprawa innego klienta nie moze wyciec do tego panelu.
	O2=$(wp mp case-create --kind=zapytanie --email='obcy-e2e@example.com' --name='Obcy' --desc='x' 2>/dev/null)
	T2=$(echo "$O2" | grep '^token=' | cut -d= -f2); wp mp case-verify "$T2" >/dev/null 2>&1
	CNUM2=$(q "SELECT case_number FROM wp_mp_service_cases WHERE customer_id=(SELECT id FROM wp_mp_customers WHERE email='obcy-e2e@example.com')")
	echo "$PANEL" | grep -q "$CNUM2" && bad "KROK 6: IDOR — panel klienta A pokazuje sprawe klienta B ($CNUM2)!" || ok "KROK 6: IDOR-safe — sprawa obcego klienta NIE wycieka do panelu"
else
	bad "KROK 6: sprawa nie zalozyla konta klienta (wp_user_id pusty)"
fi

# ── KROK 7: pracownik realizuje checkliste, decyzje w historii ──────────────
# Zmiana statusu WYLACZNIE mp_case_change_status (§C kontraktu). Checklista =
# mp_case_checklist_authorize. Detekcja: czy funkcje kontraktowe C sa wystawione.
HAS_CHG=$(wp eval 'echo has_filter("mp_case_change_status")?1:0;' 2>/dev/null)
HAS_CHK=$(wp eval 'echo has_filter("mp_case_checklist_authorize")?1:0;' 2>/dev/null)
if [ "${HAS_CHG:-0}" = "1" ]; then
	# Personel przenosi sprawe nowe -> w analizie (optimistic-lock).
	wp eval "apply_filters('mp_case_change_status', null, $CID, 'w analizie', 'nowe', 1);" >/dev/null 2>&1
	ST2=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
	# UWAGA: q() robi tr -d [:space:] => "w analizie" czytany jako "wanalizie".
	[ "$ST2" = "wanalizie" ] && ok "KROK 7: personel zmienil status (nowe->w analizie) przez mp_case_change_status" || bad "KROK 7: zmiana statusu nie zadzialala (status=$ST2)"
	SC2=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='STATUS_CHANGED'")
	[ "${SC2:-0}" -ge 1 ] && ok "KROK 7: zmiana statusu zapisana w historii (STATUS_CHANGED)" || bad "KROK 7: brak eventu STATUS_CHANGED"
else
	skip "KROK 7: funkcja kontraktowa mp_case_change_status NIE wystawiona przez C [pending: write-path personelu — decyzja czy C czy D]"
fi
if [ "${HAS_CHK:-0}" = "1" ]; then
	ok "KROK 7: funkcja checklisty mp_case_checklist_authorize wystawiona"
else
	skip "KROK 7: checklista mp_case_checklist_authorize niewystawiona [D-pending: definicje krokow + zapis stanu w D]"
fi

# ── KROK 8: przypomnienia + eskalacje + raport koncowy (D) ──────────────────
# Raport koncowy = D wola mp_case_add_system_message (author_type=system) przy
# przejsciu w 'zamknięte'. Ta funkcja C JEST wystawiona — sprawdzamy, ze dziala
# jako listener (sam raport wygeneruje D). Reminder/eskalacja = sweep D.
HAS_SYS=$(wp eval 'echo has_filter("mp_case_add_system_message")?1:0;' 2>/dev/null)
[ "${HAS_SYS:-0}" = "1" ] && ok "KROK 8: listener raportu koncowego (mp_case_add_system_message) wystawiony przez C" || bad "KROK 8: brak listenera mp_case_add_system_message"
# Realna eskalacja/reminder wychodzi ze sweepa D (wiersz SLA + termin) — D-pending.
skip "KROK 8: przypomnienia/eskalacje SLA — sweep D niezbudowany [D-pending: mp_sla_notified -> eventy SLA_* na osi]"
skip "KROK 8: raport koncowy przy zamknieciu — generuje D po przejsciu w 'zamknięte' [D-pending]"

echo
echo "WYNIK BLOK-S E2E: $PASS ok, $FAIL fail, $SKIP skip (D-pending — jawna luka, nie blad)"
[ "$FAIL" -eq 0 ]
