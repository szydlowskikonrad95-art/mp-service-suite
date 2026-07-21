#!/usr/bin/env bash
# ZYWY DOWOD C2 (formularz dynamiczny + walidacje P1.4): odmowa PRZED insertem,
# pola wg rodzaju, form_data z etykietami+PII ze schematu. Chodzi tak samo na
# poligonie i w CI. Exit 0 = wszystkie asercje przeszly.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1

# helper: liczba spraw w bazie (walidacja PRZED insertem => brak wiersza)
count() { q "SELECT COUNT(*) FROM wp_mp_service_cases"; }

# ── 1. Reklamacja bez dokumentu i daty = ODMOWA, ZERO wierszy ──────────────
BEFORE=$(count)
OUT=$(wp mp case-create --kind=reklamacja --email='jan@example.com' --serial='ABC-1' --desc='Nie dziala' 2>&1)
AFTER=$(count)
echo "$OUT" | grep -q "purchase_document: REQUIRED" && echo "$OUT" | grep -q "purchase_date: REQUIRED" \
	&& ok "reklamacja bez dokumentu+daty: bledy REQUIRED wypisane" || bad "brak bledow: $OUT"
[ "$BEFORE" = "$AFTER" ] && ok "walidacja PRZED insertem: zero nowych wierszy w bazie" || bad "wiersz powstal mimo bledow!"

# ── 2. Data z przyszlosci = DATE_FUTURE ────────────────────────────────────
OUT=$(wp mp case-create --kind=reklamacja --email='jan@example.com' --serial='ABC-1' --document='FV/1' --date='2099-01-01' --desc='x' 2>&1)
echo "$OUT" | grep -q "purchase_date: DATE_FUTURE" && ok "data z przyszlosci odrzucona (DATE_FUTURE)" || bad "data przyszla przeszla: $OUT"

# ── 3. Zla data (31 lutego) = DATE_INVALID ─────────────────────────────────
OUT=$(wp mp case-create --kind=reklamacja --email='jan@example.com' --serial='ABC-1' --document='FV/1' --date='2026-02-31' --desc='x' 2>&1)
echo "$OUT" | grep -q "purchase_date: DATE_INVALID" && ok "31 lutego odrzucone (DATE_INVALID)" || bad "zla data przeszla: $OUT"

# ── 4. Zly email = INVALID_EMAIL ───────────────────────────────────────────
OUT=$(wp mp case-create --kind=reklamacja --email='to-nie-email' --serial='ABC-1' --document='FV/1' --date='2026-03-15' --desc='x' 2>&1)
echo "$OUT" | grep -q "email: INVALID_EMAIL" && ok "zly email odrzucony (INVALID_EMAIL)" || bad "zly email przeszedl: $OUT"

# ── 5. Nieznany rodzaj = KIND_INVALID ──────────────────────────────────────
OUT=$(wp mp case-create --kind=wlamanie --email='jan@example.com' 2>&1)
echo "$OUT" | grep -q "kind: KIND_INVALID" && ok "nieznany rodzaj odrzucony (KIND_INVALID)" || bad "nieznany rodzaj przeszedl: $OUT"

# ── 6. Komplet poprawnej reklamacji = SUKCES + form_data ze schematu ───────
OUT=$(wp mp case-create --kind=reklamacja --email='jan@example.com' --serial='ABC-1' --document='FV/2026/9' --date='2026-03-15' --desc='Nie grzeje' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
[ -n "$CID" ] && ok "komplet poprawnej reklamacji: sprawa utworzona ($OUT | numer)" || bad "poprawna reklamacja odrzucona: $OUT"

# form_data niesie ETYKIETY i FLAGI PII ze schematu (nie z inputu).
LBL=$(wp eval "\$f=json_decode(\$GLOBALS['wpdb']->get_var(\$GLOBALS['wpdb']->prepare('SELECT form_data FROM wp_mp_service_cases WHERE id=%d',$CID)),true); echo \$f['issue_description']['label'] ?? 'BRAK';" 2>/dev/null)
PII=$(wp eval "\$f=json_decode(\$GLOBALS['wpdb']->get_var(\$GLOBALS['wpdb']->prepare('SELECT form_data FROM wp_mp_service_cases WHERE id=%d',$CID)),true); echo (\$f['issue_description']['pii_sensitive'] ?? false) ? 'PII' : 'nie'; echo '|'; echo (\$f['purchase_document']['pii_sensitive'] ?? false) ? 'PII' : 'nie';" 2>/dev/null)
[ "$LBL" = "Opis usterki / sprawy" ] && ok "form_data: etykieta ze schematu ('$LBL')" || bad "etykieta: '$LBL'"
[ "$PII" = "PII|PII" ] && ok "form_data: opis i dokument oznaczone pii_sensitive (ze schematu)" || bad "flagi PII: $PII"

# ── 7. Zwrot: inny zestaw pol (wymaga return_reason, nie issue_description) ─
OUT=$(wp mp case-create --kind=zwrot --email='anna@example.com' --serial='ABC-2' --document='FV/2026/10' --date='2026-03-15' 2>&1)
echo "$OUT" | grep -q "return_reason: REQUIRED" && ok "zwrot bez powodu zwrotu: REQUIRED (pola per rodzaj)" || bad "zwrot: $OUT"
OUT=$(wp mp case-create --kind=zwrot --email='anna@example.com' --serial='ABC-2' --document='FV/2026/10' --date='2026-03-15' --return-reason='Nie pasuje' 2>/dev/null)
echo "$OUT" | grep -q '^case_id=' && ok "zwrot z powodem: sprawa utworzona" || bad "poprawny zwrot odrzucony: $OUT"

echo
echo "WYNIK C2: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
