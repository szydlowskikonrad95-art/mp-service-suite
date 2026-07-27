#!/usr/bin/env bash
# ZYWY DOWOD (RODO — audyt kosztu 27.07): porzucone zgloszenia zyly wiecznie.
#
# Kto wypelnil formularz i nie kliknal linku potwierdzajacego, zostawial w bazie
# sprawe RAZEM z danymi kontaktowymi (e-mail, imie, telefon w opcji
# mp_pending_contact_*) — NA ZAWSZE. Okno potwierdzenia to 72 h, wiec po nim taka
# sprawa nie ma jak ruszyc: zostaje martwy rekord z danymi osobowymi bez podstawy
# retencji. FIX: dzienny cron kasuje porzucone starsze niz 30 dni (prog na filtrze).
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

DAWNO=$(date -u -d '60 days ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u -v-60d '+%Y-%m-%d %H:%M:%S')

# ── 0. Trzy sprawy: porzucona stara / porzucona swieza / POTWIERDZONA stara ──
O1=$(wp mp case-create --kind=zapytanie --email='porzucona@example.com' --name='Piotr Porzucony' --desc='nie klikal linku' 2>/dev/null)
STARA=$(echo "$O1" | grep '^case_id=' | cut -d= -f2)
wp db query "UPDATE wp_mp_service_cases SET created_at='$DAWNO' WHERE id=$STARA" >/dev/null 2>&1

O2=$(wp mp case-create --kind=zapytanie --email='swieza@example.com' --name='Sara Swieza' --desc='moze jeszcze kliknie' 2>/dev/null)
SWIEZA=$(echo "$O2" | grep '^case_id=' | cut -d= -f2)

O3=$(wp mp case-create --kind=zapytanie --email='potwierdzona@example.com' --name='Karol Klient' --desc='klikniety link' 2>/dev/null)
POTW=$(echo "$O3" | grep '^case_id=' | cut -d= -f2)
wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe', created_at='$DAWNO', verified_at='$DAWNO' WHERE id=$POTW" >/dev/null 2>&1

OPCJA_PRZED=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name='mp_pending_contact_$STARA'")
[ "${OPCJA_PRZED:-0}" -ge 1 ] 2>/dev/null && ok "seed: dane kontaktowe porzuconej sprawy sa w bazie" || bad "seed: brak opcji kontaktu ($OPCJA_PRZED)"

# ── 1. Przebieg retencji ────────────────────────────────────────────────────
SKASOWANE=$(wp eval 'echo MP\Intake\CaseRepo::purge_abandoned_pending();' 2>/dev/null | tr -d '[:space:]')
[ "${SKASOWANE:-0}" -ge 1 ] 2>/dev/null && ok "retencja skasowala porzucone zgloszenia ($SKASOWANE)" || bad "nic nie skasowane ($SKASOWANE)"

ZOSTALA=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id=$STARA")
[ "$ZOSTALA" = "0" ] && ok "porzucona sprawa sprzed 60 dni USUNIETA" || bad "porzucona sprawa dalej w bazie"

OPCJA_PO=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name='mp_pending_contact_$STARA'")
[ "$OPCJA_PO" = "0" ] && ok "dane kontaktowe (PII) usuniete razem ze sprawa" || bad "PII zostalo w wp_options!"

ZDARZENIA=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$STARA")
[ "$ZDARZENIA" = "0" ] && ok "os zdarzen porzuconej sprawy posprzatana" || bad "zdarzenia zostaly ($ZDARZENIA)"

# ── 2. KONTROLA: swieza porzucona NIETKNIETA (klient moze jeszcze kliknac) ──
SWIEZA_JEST=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id=$SWIEZA")
[ "$SWIEZA_JEST" = "1" ] && ok "swieze zgloszenie NIETKNIETE (okno potwierdzenia szanowane)" || bad "skasowano swieze zgloszenie!"

SWIEZA_OPCJA=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name='mp_pending_contact_$SWIEZA'")
[ "${SWIEZA_OPCJA:-0}" -ge 1 ] 2>/dev/null && ok "dane swiezej sprawy nietkniete" || bad "skasowano dane swiezej sprawy!"

# ── 3. KONTROLA: POTWIERDZONA sprawa sprzed 60 dni ZOSTAJE (to juz robota) ──
POTW_JEST=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id=$POTW")
[ "$POTW_JEST" = "1" ] && ok "stara POTWIERDZONA sprawa nietknieta (retencja tyczy tylko porzuconych)" || bad "skasowano potwierdzona sprawe klienta!"

# ── 4. Prog konfigurowalny filtrem ──────────────────────────────────────────
wp db query "UPDATE wp_mp_service_cases SET created_at=DATE_SUB(UTC_TIMESTAMP(), INTERVAL 5 DAY) WHERE id=$SWIEZA" >/dev/null 2>&1
wp eval "add_filter('mp_intake_pending_retention_days', function(){ return 3; }); MP\\Intake\\CaseRepo::purge_abandoned_pending();" >/dev/null 2>&1
PO_FILTRZE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id=$SWIEZA")
[ "$PO_FILTRZE" = "0" ] && ok "prog retencji sterowalny filtrem (3 dni => sprzatniete)" || bad "filtr progu nie dziala"

echo ""
echo "WYNIK C-RETENCJA-PORZUCONYCH: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
