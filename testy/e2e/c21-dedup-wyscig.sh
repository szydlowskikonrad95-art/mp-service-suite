#!/usr/bin/env bash
# ZYWY DOWOD C21 (znalezisko #4 audytu 27.07 — dedup peka przy rownoleglych POST-ach):
# Dawny schemat check-then-set (sprawdzenie przed utworzeniem sprawy, marker
# dopiero po sukcesie) przepuszczal DWA rownolegle identyczne zgloszenia:
# dwie sprawy w bazie, dwa maile do klienta.
# Po naprawie: atomowa REZERWACJA (claim) pod unikalnym kluczem PRZED
# utworzeniem sprawy — z N rownoleglych POST-ow przechodzi DOKLADNIE JEDEN.
# Semantyka D5 zachowana: odrzucona walidacja zwalnia rezerwacje (retry po
# bledzie nie jest duplikatem), sukces utrwala okno 15 min od sukcesu.
# Wymaga MP_BASE. Chodzi na poligonie i w CI.
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
# UWAGA: q() usuwa CALE biale znaki z wyniku — oczekiwania tez pisz bez spacji.
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_attachments; DELETE FROM wp_mp_rate_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

# ── Scenariusz A: atomowosc rezerwacji (API) ─────────────────────────────────
C1=$(wp eval 'var_export(MP\Intake\RateLimit::claim_submission("atom@example.com","SR-1","zapytanie"));' 2>/dev/null)
[ "$C1" = "true" ] && ok "pierwsza rezerwacja przyznana" || bad "pierwsza rezerwacja odrzucona ($C1)"
C2=$(wp eval 'var_export(MP\Intake\RateLimit::claim_submission("atom@example.com","SR-1","zapytanie"));' 2>/dev/null)
[ "$C2" = "false" ] && ok "druga rezerwacja tego samego zgloszenia ODRZUCONA" || bad "druga rezerwacja przeszla — dedup dziurawy ($C2)"
CHK=$(wp eval 'var_export(MP\Intake\RateLimit::check("","atom@example.com","SR-1","zapytanie"));' 2>/dev/null)
echo "$CHK" | grep -q "duplicate" && ok "check() widzi duplikat (komunikat dla klienta)" || bad "check() nie widzi duplikatu ($CHK)"
wp eval 'MP\Intake\RateLimit::release_claim("atom@example.com","SR-1","zapytanie");' >/dev/null 2>&1
C3=$(wp eval 'var_export(MP\Intake\RateLimit::claim_submission("atom@example.com","SR-1","zapytanie"));' 2>/dev/null)
[ "$C3" = "true" ] && ok "po zwolnieniu (odrzucona walidacja) rezerwacja znow dostepna — D5" || bad "release nie zwalnia ($C3)"
# Inne zgloszenie (inny rodzaj) nie koliduje.
C4=$(wp eval 'var_export(MP\Intake\RateLimit::claim_submission("atom@example.com","SR-1","naprawa"));' 2>/dev/null)
[ "$C4" = "true" ] && ok "inny rodzaj sprawy = osobny klucz (bez falszywego duplikatu)" || bad "inny rodzaj zablokowany ($C4)"

# ── Scenariusz B: PRAWDZIWY wyscig — 6 rownoleglych POST-ow przez HTTP ───────
PAGE_ID=$(wp option get mp_intake_form_page_id 2>/dev/null)
PAGE_PATH=$(wp post url "$PAGE_ID" 2>/dev/null | sed 's#^https\?://[^/]*##')
SITE_HOST=$(wp option get home 2>/dev/null | sed 's#^https\?://##;s#/.*##')
HOSTHDR=(); [ -n "$SITE_HOST" ] && HOSTHDR=(-H "Host: $SITE_HOST")
HTML=$(curl -s "${HOSTHDR[@]}" "$MP_BASE$PAGE_PATH")
NONCE=$(echo "$HTML" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
[ -n "$NONCE" ] && ok "nonce formularza pobrany" || bad "brak nonce formularza"

TS=$(( $(date +%s) - 60 ))
for i in 1 2 3 4 5 6; do
	curl -s "${HOSTHDR[@]}" -o /dev/null \
		--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
		--data-urlencode "mp_ts=$TS" \
		--data-urlencode "kind=zapytanie" --data-urlencode "email=wyscig-dedup@example.com" \
		--data-urlencode "issue_description=to samo zgloszenie rownolegle" \
		--data-urlencode "mp_consent=1" \
		"$MP_BASE/wp-admin/admin-post.php" &
done
wait

ILE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE JSON_UNQUOTE(JSON_EXTRACT(form_data,'\$.issue_description'))='to samo zgloszenie rownolegle' OR id IN (SELECT case_id FROM wp_mp_consents WHERE email='wyscig-dedup@example.com')")
[ "$ILE" = "1" ] && ok "6 rownoleglych POST-ow => DOKLADNIE 1 sprawa (dedup atomowy)" || bad "rownolegle POST-y stworzyly $ILE spraw (oczekiwana 1)"

# ── Scenariusz C: odrzucona walidacja => retry NIE jest duplikatem (HTTP) ────
# Reklamacja bez wymaganych pol => blad walidacji (po rezerwacji) => release.
curl -s "${HOSTHDR[@]}" -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
	--data-urlencode "mp_ts=$TS" \
	--data-urlencode "kind=reklamacja" --data-urlencode "email=retry@example.com" \
	--data-urlencode "mp_consent=1" \
	"$MP_BASE/wp-admin/admin-post.php"
ILE_R1=$(q "SELECT COUNT(*) FROM wp_mp_consents WHERE email='retry@example.com'")
[ "$ILE_R1" = "0" ] && ok "niepelna reklamacja odrzucona walidacja (zero spraw)" || bad "niepelne zgloszenie przeszlo ($ILE_R1)"
# Poprawiony retry TEGO SAMEGO zgloszenia — musi przejsc od razu (release zadzialal).
curl -s "${HOSTHDR[@]}" -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
	--data-urlencode "mp_ts=$TS" \
	--data-urlencode "kind=reklamacja" --data-urlencode "email=retry@example.com" \
	--data-urlencode "serial=BEZ-REJESTRU-1" --data-urlencode "purchase_document=FV/77" \
	--data-urlencode "purchase_date=2026-03-15" --data-urlencode "issue_description=poprawiony opis" \
	--data-urlencode "mp_consent=1" \
	"$MP_BASE/wp-admin/admin-post.php"
ILE_R2=$(q "SELECT COUNT(*) FROM wp_mp_consents WHERE email='retry@example.com'")
[ "$ILE_R2" = "1" ] && ok "poprawiony retry przeszedl od razu (rezerwacja zwolniona po bledzie)" || bad "retry zablokowany albo zdublowany ($ILE_R2)"

# ── Scenariusz D: drugi POST po sukcesie = grzeczny komunikat duplikatu ──────
curl -s "${HOSTHDR[@]}" -o /dev/null \
	--data-urlencode "action=mp_intake_submit" --data-urlencode "_mp_nonce=$NONCE" \
	--data-urlencode "mp_ts=$TS" \
	--data-urlencode "kind=reklamacja" --data-urlencode "email=retry@example.com" \
	--data-urlencode "serial=BEZ-REJESTRU-1" --data-urlencode "purchase_document=FV/77" \
	--data-urlencode "purchase_date=2026-03-15" --data-urlencode "issue_description=poprawiony opis" \
	--data-urlencode "mp_consent=1" \
	"$MP_BASE/wp-admin/admin-post.php"
ILE_R3=$(q "SELECT COUNT(*) FROM wp_mp_consents WHERE email='retry@example.com'")
[ "$ILE_R3" = "1" ] && ok "ponowne wyslanie po sukcesie NIE tworzy drugiej sprawy" || bad "duplikat po sukcesie przeszedl ($ILE_R3)"

echo
echo "WYNIK C21: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
