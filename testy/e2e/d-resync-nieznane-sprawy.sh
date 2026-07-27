#!/usr/bin/env bash
# ZYWY DOWOD (audyt 27.07, soczewka „awarie"): DRUGI wariant cichej sieroty.
#
# Reconcile z audytu #1 rozpoznaje sieroty po BRAKU zdarzenia narodzin w C.
# Nie widzi wiec przypadku, gdy w chwili potwierdzenia Automator byl WYLACZONY
# (auto-update, tryb odzyskiwania WP, konserwacja): C zapisuje CASE_CREATED i
# emituje akcje POPRAWNIE — tylko nikt jej nie slucha. Sprawa ma komplet sladow
# u siebie, klient widzi „potwierdzone", a nigdy nie dostanie przydzialu ani
# terminu. Cicho, na zawsze.
#
# FIX: sweep D porownuje liste spraw zweryfikowanych (kontrakt mp_cases_verified_ids
# — same ID, zero danych osobowych) z wlasna tabela terminow i doszywa roznice.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

STARA=$(date -u -d '20 minutes ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u -v-20M '+%Y-%m-%d %H:%M:%S')

# ── 1. Sprawa potwierdzona, gdy Automator byl wylaczony ─────────────────────
O1=$(wp mp case-create --kind=zapytanie --email='resync@example.com' --name='Rena Resync' --desc='automator byl wylaczony' 2>/dev/null)
C1=$(echo "$O1" | grep '^case_id=' | cut -d= -f2)
[[ "$C1" =~ ^[0-9]+$ ]] && ok "seed: sprawa (id=$C1)" || bad "seed: brak sprawy ($C1)"

# C zrobil SWOJE: weryfikacja + zdarzenie narodzin. D tego nie uslyszal (byl OFF),
# wiec u niego nie ma wiersza terminu — dokladnie ten stan odtwarzamy.
wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe', verified_at='$STARA' WHERE id=$C1" >/dev/null 2>&1
wp eval "MP\\Intake\\CaseEvents::log($C1, MP\\Intake\\CaseEvents::CASE_CREATED, array('case_number'=>'TEST'), null);" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_case_sla WHERE case_id=$C1" >/dev/null 2>&1

EV=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$C1 AND event_type='CASE_CREATED'")
[ "$EV" = "1" ] && ok "stan wyjsciowy: sprawa MA zdarzenie narodzin" || bad "seed zdarzenia nie zadzialal ($EV)"
SLA0=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$C1")
[ "$SLA0" = "0" ] && ok "stan wyjsciowy: Automator NIE zna tej sprawy (brak terminu)" || bad "sprawa juz znana ($SLA0)"

# ── 2. SEDNO: stary mechanizm tej sprawy NIE WIDZI ──────────────────────────
STARY=$(wp eval "echo in_array($C1, MP\\Intake\\CaseRepo::unlaunched_ids(10, 100), true) ? 'widzi' : 'nie-widzi';" 2>/dev/null | tr -d '[:space:]')
[ "$STARY" = "nie-widzi" ] \
	&& ok "reconcile #1 tej sieroty NIE wykrywa (dlatego potrzebny drugi mechanizm)" \
	|| bad "reconcile #1 jednak ja widzi — znalezisko do ponownej oceny ($STARY)"

# ── 3. Przebieg sweepa doszywa sprawe ───────────────────────────────────────
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1

SLA1=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$C1")
[ "$SLA1" = "1" ] && ok "sprawa doszyta: termin SLA zalozony" || bad "termin NIE zalozony ($SLA1)"

AUDYT=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$C1 AND payload LIKE '%resync_untracked%'")
[ "${AUDYT:-0}" -ge 1 ] 2>/dev/null && ok "doszycie ZAPISANE w rejestrze operacji" || bad "brak sladu doszycia w rejestrze"

# ── 4. Kontrola: drugi przebieg NIE robi tego drugi raz ─────────────────────
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1
AUDYT2=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$C1 AND payload LIKE '%resync_untracked%'")
[ "$AUDYT2" = "$AUDYT" ] \
	&& ok "drugi przebieg NIE doszywa ponownie (idempotencja)" \
	|| bad "podwojne doszycie ($AUDYT -> $AUDYT2)"

# ── 5. Kontrola: sprawa NIEPOTWIERDZONA zostaje nietknieta ──────────────────
O2=$(wp mp case-create --kind=zapytanie --email='pending-resync@example.com' --name='Piotr Pending' --desc='nie klikal linku' 2>/dev/null)
C2=$(echo "$O2" | grep '^case_id=' | cut -d= -f2)
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1
SLA2=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=${C2:-0}")
[ "${SLA2:-0}" = "0" ] \
	&& ok "sprawa niepotwierdzona NIE dostaje terminu (bufor weryfikacji nietkniety)" \
	|| bad "niepotwierdzona sprawa dostala termin! ($SLA2)"

echo ""
echo "WYNIK D-RESYNC: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
