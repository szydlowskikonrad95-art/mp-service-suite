#!/usr/bin/env bash
# ZYWY DOWOD (audyt maszyny stanow 27.07): bramka terminalna chronila TYLKO status.
#
# Sprawa ZAMKNIETA/ODRZUCONA dawala sie dalej przydzielic i zmienic jej pilnosc —
# leciala akcja mp_case_assigned, MAIL do pracownika i wpis na osi zamknietej
# sprawy. Zamknieta sprawa nie jest w robocie; do pracy wraca przez WZNOWIENIE
# (koordynator), nie przez boczne drzwi.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ── 0. Pracownik + sprawa otwarta ───────────────────────────────────────────
AG=$(wp user get agentzamk --field=ID 2>/dev/null)
[ -z "$AG" ] && AG=$(wp user create agentzamk agentzamk@example.com --role=mp_agent --user_pass=x --porcelain 2>/dev/null)

# naprawa (jak reklamacja) WYMAGA serialu, dokumentu i daty zakupu.
O=$(wp mp case-create --kind=naprawa --email='zamknieta@example.com' --name='Zofia Zamknieta' --desc='bramka terminalna' --serial='MPZAMK001' --document='FV/2026/901' --date='2026-05-02' 2>/dev/null)
CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2)
wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe' WHERE id=$CID" >/dev/null 2>&1
[[ "$CID" =~ ^[0-9]+$ ]] && ok "seed: sprawa otwarta (id=$CID)" || bad "seed zly ($CID)"

# ── 1. Przypadek BEZ problemu: sprawa OTWARTA przyjmuje przydzial ───────────
WYNIK_OK=$(wp eval "\$r = MP\\Intake\\CaseRepo::assign($CID, $AG, 0); echo empty(\$r['success']) ? ('BLAD:' . (\$r['error_code'] ?? '?')) : 'ok';" 2>/dev/null | tr -d '[:space:]')
[ "$WYNIK_OK" = "ok" ] && ok "sprawa otwarta: przydzial DZIALA (bramka nie jest za szeroka)" || bad "otwarta sprawa odrzucila przydzial ($WYNIK_OK)"

# ── 2. Zamykamy sprawe i probujemy przydzielic ponownie ─────────────────────
wp db query "UPDATE wp_mp_service_cases SET status='zamknięte', assigned_to=NULL WHERE id=$CID" >/dev/null 2>&1
EV_PRZED=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CASE_ASSIGNED'")

KOD=$(wp eval "\$r = MP\\Intake\\CaseRepo::assign($CID, $AG, 0); echo \$r['error_code'] ?? ( empty(\$r['success']) ? 'brak-kodu' : 'PRZESZLO' );" 2>/dev/null | tr -d '[:space:]')
[ "$KOD" = "CASE_CLOSED" ] && ok "zamknieta sprawa: przydzial ODMOWIONY (CASE_CLOSED)" || bad "przydzial zamknietej sprawy: $KOD"

PRZYPISANY=$(q "SELECT COALESCE(assigned_to,0) FROM wp_mp_service_cases WHERE id=$CID")
[ "$PRZYPISANY" = "0" ] && ok "sprawa NIE ma przypisanego pracownika" || bad "przydzial jednak zapisany ($PRZYPISANY)"

EV_PO=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID AND event_type='CASE_ASSIGNED'")
[ "$EV_PO" = "$EV_PRZED" ] && ok "zero wpisow na osi zamknietej sprawy (i zero maili)" || bad "wpis mimo odmowy ($EV_PRZED -> $EV_PO)"

# ── 3. To samo dla pilnosci ─────────────────────────────────────────────────
KODP=$(wp eval "\$r = MP\\Intake\\CaseRepo::set_priority($CID, 'high', 0); echo \$r['error_code'] ?? ( empty(\$r['success']) ? 'brak-kodu' : 'PRZESZLO' );" 2>/dev/null | tr -d '[:space:]')
[ "$KODP" = "CASE_CLOSED" ] && ok "zamknieta sprawa: zmiana pilnosci ODMOWIONA" || bad "pilnosc zmieniona na zamknietej ($KODP)"

PRIO=$(q "SELECT priority FROM wp_mp_service_cases WHERE id=$CID")
[ "$PRIO" != "high" ] && ok "pilnosc nietknieta ($PRIO)" || bad "pilnosc jednak zmieniona"

# ── 4. Kontrola: po WZNOWIENIU sprawa znow przyjmuje przydzial ──────────────
wp db query "UPDATE wp_mp_service_cases SET status='w analizie' WHERE id=$CID" >/dev/null 2>&1
KODW=$(wp eval "\$r = MP\\Intake\\CaseRepo::assign($CID, $AG, 0); echo empty(\$r['success']) ? ('BLAD:' . (\$r['error_code'] ?? '?')) : 'ok';" 2>/dev/null | tr -d '[:space:]')
[ "$KODW" = "ok" ] && ok "po wznowieniu przydzial znow mozliwy (droga powrotu istnieje)" || bad "wznowiona sprawa dalej zablokowana ($KODW)"

echo ""
echo "WYNIK C-ZAMKNIETA-BRAMKA: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
