#!/usr/bin/env bash
# ZYWY DOWOD (cz.1 pkt 3, trzecia czesc): sprawa krazaca miedzy statusami ma ZIELONY
# termin — i mimo to produkt ja teraz NAZYWA.
#
# CO BYLO ZLE: termin SLA liczy sie od `status_changed_at` (`Sla::compute_terms` ->
# `SlaConfig::deadline_for`), wiec KAZDA zmiana statusu restartuje zegar. Sprawa
# odbijana miedzy statusami ma zawsze swiezy, zielony termin, a panel pokazuje
# „wszystko w terminie" przy reklamacji sprzed miesiaca. W calym module nie bylo
# ZADNEJ wielkosci, ktora liczylaby sie od poczatku sprawy i nie restartowala.
#
# ⛔ CZEGO TA NAPRAWA NIE RUSZA: samej podstawy terminow. Tak zaprojektowano maszyne
# stanow i tak zostaje. Dokladamy OSOBNA miare, ktora sie nie restartuje.
#
# ⭐ SEDNO TEGO DOWODU: sekcja 2 pokazuje, ze termin JEST zielony (czyli wada z paczki
# jest prawdziwa), a sekcja 3, ze produkt mimo to widzi problem. Kontrola, ktora
# pokazywalaby samo wykrycie, nie udowodnilaby, ze bylo co wykrywac.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ── 0. Prog: RACHUNEK z konfiguracji, nie liczba z sufitu ──────────────────
PROG=$(wp eval 'echo (int) MP\Automator\Sla::stale_threshold_hours();' 2>/dev/null | tr -d '[:space:]')
RACHUNEK=$(wp eval '
	$suma = 0;
	foreach ( MP\Automator\SlaConfig::core_effective() as $k ) { $suma += (int) $k["sla_hours"]; }
	echo (int) ceil( $suma * MP\Automator\SlaConfig::slowest_priority_modifier() );
' 2>/dev/null | tr -d '[:space:]')
[ -n "$PROG" ] && [ "$PROG" = "$RACHUNEK" ] \
	&& ok "prog krazenia wyprowadzony z konfiguracji terminow: $PROG godz." \
	|| bad "prog nie zgadza sie z rachunkiem (prog=$PROG, rachunek=$RACHUNEK)"

# Filtr ma dzialac na zywym WP — warstwa jednostkowa tego nie sprawdzi.
NADPISANY=$(wp eval 'add_filter("mp_sla_stale_hours", function(){ return 999; }); echo (int) MP\Automator\Sla::stale_threshold_hours();' 2>/dev/null | tr -d '[:space:]')
[ "$NADPISANY" = "999" ] \
	&& ok "filtr mp_sla_stale_hours nadpisuje prog (wdrozeniowiec ma go czym zmienic)" \
	|| bad "filtr progu nie dziala ($NADPISANY)"

# ── 1. Sprawa, ktora KRAZY: potwierdzona dawno, status zmieniony przed chwila ─
OUT=$(wp mp case-create --kind=reklamacja --email=krazenie@example.com --name='Jan Kowalski' \
	--serial=SEK-KRAZ --document='FV/2026/77' --date='2026-05-01' --desc='sprawa krazaca' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
NUMER=$(echo "$OUT" | grep '^case_number=' | cut -d= -f2)
TOKEN=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp eval "MP\\Intake\\CaseRepo::verify('$TOKEN');" >/dev/null 2>&1

# Potwierdzona 60 dni temu (wiecej niz prog), ale status ruszony PRZED CHWILA —
# dokladnie tak wyglada sprawa przestawiana w kolko miedzy statusami.
STARE=$(( PROG + 480 ))
wp db query "UPDATE wp_mp_service_cases
	SET created_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL $((STARE + 24)) HOUR),
	    verified_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL $STARE HOUR),
	    status_changed_at = UTC_TIMESTAMP(),
	    status = 'w analizie'
	WHERE id=$CID" >/dev/null 2>&1

# Termin przeliczany tak jak w produkcie — od ostatniej zmiany statusu.
wp eval "MP\\Automator\\Sla::provision($CID);" >/dev/null 2>&1

# Sprawa swieza — kontrola przeciwna (nie moze trafic na liste).
OUT2=$(wp mp case-create --kind=reklamacja --email=swieza@example.com --name='Anna Nowak' \
	--serial=SEK-SWIEZA --document='FV/2026/78' --date='2026-05-01' --desc='sprawa swieza' 2>/dev/null)
CID2=$(echo "$OUT2" | grep '^case_id=' | cut -d= -f2)
NUMER2=$(echo "$OUT2" | grep '^case_number=' | cut -d= -f2)
TOKEN2=$(echo "$OUT2" | grep '^token=' | cut -d= -f2)
wp eval "MP\\Intake\\CaseRepo::verify('$TOKEN2');" >/dev/null 2>&1

[ -n "$NUMER" ] && [ -n "$NUMER2" ] \
	&& ok "seed: sprawa krazaca $NUMER (w obsludze $STARE godz.) i swieza $NUMER2" \
	|| bad "seed zly (krazaca=$NUMER, swieza=$NUMER2)"

# ── 2. WADA Z PACZKI JEST PRAWDZIWA: termin tej sprawy jest ZIELONY ────────
ZIELONY=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID AND deadline_at > UTC_TIMESTAMP()")
[ "${ZIELONY:-0}" = "1" ] \
	&& ok "SEDNO: termin sprawy krazacej jest ZIELONY (zegar zrestartowany zmiana statusu)" \
	|| bad "sprawa nie ma zielonego terminu — ten dowod nie pokazuje tego, co mial ($ZIELONY)"

PRZETERMINOWANE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID AND deadline_at <= UTC_TIMESTAMP()")
[ "${PRZETERMINOWANE:-1}" = "0" ] \
	&& ok "pilnowanie terminow NIE zglasza tej sprawy — i nigdy nie zglosi" \
	|| bad "sprawa jednak jest po terminie ($PRZETERMINOWANE)"

# ── 3. A PRODUKT MIMO TO JA NAZYWA ────────────────────────────────────────
# ⛔ `mp_cases_query` RESPEKTUJE ROLE wolajacego, a `wp eval` bez `--user` to uzytkownik 0,
# ktory nie widzi zadnej sprawy. Pierwsza wersja tej kontroli pytala bez konta i dostawala
# pusta liste — czyli „nie wykryto" znaczylo „nie mialem prawa zobaczyc". Panel i Stan
# witryny chodza u zalogowanego administratora, wiec pytamy tak samo.
LISTA=$(wp eval --user=1 '
	$w = MP\Automator\Sla::stale_cases( 50 );
	foreach ( $w["sprawy"] as $s ) { echo $s["case_number"] . "=" . (int) $s["godzin_w_obsludze"] . ";"; }
' 2>/dev/null)

echo "$LISTA" | grep -q "$NUMER=" \
	&& ok "sprawa krazaca JEST na liscie spraw krazacych" \
	|| bad "sprawa krazaca nie zostala wykryta ($LISTA)"

echo "$LISTA" | grep -q "$NUMER2=" \
	&& bad "swieza sprawa trafila na liste — falszywy alarm" \
	|| ok "swieza sprawa NIE trafila na liste (brak falszywego alarmu)"

GODZIN=$(echo "$LISTA" | tr ';' '\n' | grep "^$NUMER=" | cut -d= -f2)
[ -n "$GODZIN" ] && [ "$GODZIN" -ge "$PROG" ] 2>/dev/null \
	&& ok "liczba godzin w obsludze policzona i nie restartuje sie ($GODZIN >= $PROG)" \
	|| bad "zla liczba godzin w obsludze ($GODZIN)"

# ── 4. Stan witryny mowi o tym administratorowi ───────────────────────────
ZDROWIE=$(wp eval --user=1 '
	$w = MP\Automator\Admin\SiteHealthTests::test_sprawy_krazace();
	echo ( $w["status"] ?? "" ) . "|" . wp_strip_all_tags( (string) ( $w["description"] ?? "" ) );
' 2>/dev/null)

echo "$ZDROWIE" | grep -q '^recommended|' \
	&& ok "Stan witryny ZGLASZA problem (status recommended)" \
	|| bad "Stan witryny milczy o sprawach krazacych ($ZDROWIE)"

echo "$ZDROWIE" | grep -q "$NUMER" \
	&& ok "Stan witryny podaje NUMER sprawy — admin wie, ktorej dotyczy" \
	|| bad "Stan witryny nie mowi, o ktora sprawe chodzi ($ZDROWIE)"

# ── 5. Sprawa ZAMKNIETA przestaje krazyc ──────────────────────────────────
wp eval "apply_filters('mp_case_change_status', null, $CID, 'zamknięte', 'w analizie', 1, null);" >/dev/null 2>&1
PO_ZAMKNIECIU=$(wp eval --user=1 '
	$w = MP\Automator\Sla::stale_cases( 50 );
	foreach ( $w["sprawy"] as $s ) { echo $s["case_number"] . ";"; }
' 2>/dev/null)
echo "$PO_ZAMKNIECIU" | grep -q "$NUMER" \
	&& bad "zamknieta sprawa nadal liczona jako krazaca" \
	|| ok "po zamknieciu sprawa znika z listy (nie straszymy zalatwionymi)"

echo ""
echo "WYNIK CZ1-3-KRAZENIE: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
