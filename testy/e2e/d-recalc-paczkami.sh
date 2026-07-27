#!/usr/bin/env bash
# ZYWY DOWOD (audyt kosztu 27.07): „Przelicz SLA" bez paczkowania = timeout.
#
# Dotad zapytanie o sprawy szlo BEZ LIMIT, a potem petla robila zapytanie
# kontekstu + UPDATE na KAZDY wiersz. Przy 15 tys. spraw (skala po ~2 latach)
# jedno kliniecie to ~30 tys. zapytan w jednym zadaniu PHP — na wspoldzielonym
# hostingu pewny timeout, w dodatku w POLOWIE przeliczania.
# FIX: paczka + dokanczanie w tle (zdarzenie jednorazowe), przeliczanie
# idempotentne, markery i liczniki nietkniete.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_case_sla;" >/dev/null 2>&1
wp eval "wp_clear_scheduled_hook(MP\\Automator\\Sla::RECALC_CONTINUE_HOOK);" >/dev/null 2>&1

# ── 0. Piec spraw z wierszem terminu ────────────────────────────────────────
IDS=""
for i in 1 2 3 4 5; do
	O=$(wp mp case-create --kind=zapytanie --email="recalc$i@example.com" --name="Recalc $i" --desc="paczkowanie" 2>/dev/null)
	CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2)
	wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe' WHERE id=$CID" >/dev/null 2>&1
	wp eval "MP\\Automator\\Sla::on_case_created($CID);" >/dev/null 2>&1
	IDS="$IDS $CID"
done
ILE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla")
[ "$ILE" = "5" ] && ok "seed: 5 spraw z terminem" || bad "seed zly ($ILE)"

# ── 1. Paczka 2 => przelicza 2 i PLANUJE dokanczanie ────────────────────────
DOTKNIETE=$(wp eval 'echo MP\Automator\Sla::recompute_open(0, 2);' 2>/dev/null | tr -d '[:space:]')
[ "$DOTKNIETE" = "2" ] && ok "paczka dotrzymana: przeliczone 2 z 5" || bad "paczka zlamana ($DOTKNIETE)"

ZAPLANOWANE=$(wp eval "echo wp_next_scheduled(MP\\Automator\\Sla::RECALC_CONTINUE_HOOK, array((int) trim('$(echo $IDS | cut -d' ' -f2)'))) ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]')
[ "$ZAPLANOWANE" = "tak" ] && ok "dokanczanie ZAPLANOWANE w tle (reszta nie przepada)" || bad "brak zaplanowanego dokanczania ($ZAPLANOWANE)"

# ── 2. Dokanczanie przelicza reszte i zapisuje slad ─────────────────────────
PO_ID=$(echo $IDS | cut -d' ' -f2)
wp eval "MP\\Automator\\Sla::continue_recompute($PO_ID);" >/dev/null 2>&1
SLAD=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SLA_RECALCULATED' AND payload LIKE '%dokanczanie_w_tle%'")
[ "${SLAD:-0}" -ge 1 ] 2>/dev/null && ok "dokanczanie zapisane w rejestrze operacji" || bad "brak sladu dokanczania"

# ── 3. Kontrola: markery przypomnien NIETKNIETE przez przeliczanie ──────────
PIERWSZA=$(echo $IDS | cut -d' ' -f1)
wp db query "UPDATE wp_mp_case_sla SET reminder_sent_at=UTC_TIMESTAMP() WHERE case_id=$PIERWSZA" >/dev/null 2>&1
wp eval 'MP\Automator\Sla::recompute_open(0, 100);' >/dev/null 2>&1
MARKER=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$PIERWSZA AND reminder_sent_at IS NOT NULL")
[ "$MARKER" = "1" ] && ok "przeliczenie NIE resetuje markera przypomnienia (zero podwojnych maili)" || bad "marker skasowany przez przeliczenie!"

# ── 4. Kontrola: maly zbior => ZERO planowania w tle (bez smiecenia cronem) ──
wp eval "wp_clear_scheduled_hook(MP\\Automator\\Sla::RECALC_CONTINUE_HOOK);" >/dev/null 2>&1
wp eval 'MP\Automator\Sla::recompute_open(0, 100);' >/dev/null 2>&1
PUSTE=$(wp eval "echo wp_next_scheduled(MP\\Automator\\Sla::RECALC_CONTINUE_HOOK) ? 'zaplanowane' : 'czysto';" 2>/dev/null | tr -d '[:space:]')
[ "$PUSTE" = "czysto" ] && ok "komplet w jednej paczce => nic nie planuje w tle" || bad "niepotrzebne zadanie w tle ($PUSTE)"

echo ""
echo "WYNIK D-RECALC-PACZKAMI: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
