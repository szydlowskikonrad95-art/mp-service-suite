#!/usr/bin/env bash
# ZYWY DOWOD M4 (recenzja zewnetrzna 1.3.12 — trzy proby wysylki SLA gina w JEDNYM przebiegu):
# Zamiatarka nadrabia zaleglosci PETLA (do 10 rund pod rzad), a kazda runda brala te same
# sprawy, dopoki marker byl pusty. Przy pelnej paczce wymagalnych przypomnien komplet
# MAX_ATTEMPTS prob spalal sie wiec w kilka sekund jednego przebiegu: kilkusekundowa
# czkawka SMTP wyczerpywala budzet ponowien, marker szedl „na sile" (MAIL_FAILED_FINAL),
# zapalal sie alarm — a powiadomienie nie wychodzilo NIGDY.
# Po naprawie: liczy sie nie tylko LICZBA prob, ale i ODSTEP miedzy nimi
# (`Sla::RETRY_INTERVAL`, kolumny reminder_attempt_at / escalation_attempt_at).
# Sprawa, ktorej wysylka wlasnie padla, wraca do gry dopiero w kolejnym przebiegu.
#
# KALIBRACJA (kod sprzed naprawy): po JEDNYM przebiegu z padnieta poczta sprawy maja
# po 3 proby i wymuszone markery — czyli przepadle przypomnienia.
# Wymaga MP_BASE (wspolny kontrakt uruchamiania). Chodzi na poligonie i w CI.
set -u
: "${MP_BASE:?MP_BASE wymagane (kontrakt uruchamiania e2e)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Przebieg zamiatarki z POCZTA, ktora pada (chwilowa awaria SMTP) albo dziala.
sweep_padajaca() { wp eval "add_filter('pre_wp_mail','__return_false',99); MP\\Automator\\Sweep::run();" >/dev/null 2>&1; }
sweep_dzialajaca() { wp eval "add_filter('pre_wp_mail','__return_true',99); MP\\Automator\\Sweep::run();" >/dev/null 2>&1; }

# ── 0. Czysta scena: koordynator (odbiorca przypomnien) + szablony ───────────
wp db query "DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases;" >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
wp eval 'delete_option("mp_sla_mail_alert");' >/dev/null 2>&1
COORD=$(wp user create m4koord m4koord@example.com --role=mp_coordinator --porcelain 2>/dev/null)
[ -z "$COORD" ] && COORD=$(wp user get m4koord --field=ID 2>/dev/null)
[ -n "$COORD" ] && ok "koordynator jest (id=$COORD) — jest komu wyslac przypomnienie" || bad "brak koordynatora"

# ── 1. PELNA PACZKA zaleglosci: 55 spraw z minionym progiem przypomnienia ────
# 55 > BATCH(50), wiec zamiatarka wchodzi w druga runde TEGO SAMEGO przebiegu —
# dokladnie ta petla spalala dawniej komplet prob w kilka sekund.
wp eval '
	global $wpdb;
	$now = gmdate( "Y-m-d H:i:s" );
	for ( $i = 1; $i <= 55; $i++ ) {
		$wpdb->insert( "wp_mp_service_cases", array(
			"case_number"     => sprintf( "SRV/2026/M4%02d", $i ),
			"kind"            => "reklamacja",
			"status"          => "nowe",
			"identity_status" => "verified",
			"priority"        => "normal",
			"created_at"      => $now,
			"updated_at"      => $now,
		) );
		$wpdb->insert( "wp_mp_case_sla", array(
			"case_id"     => (int) $wpdb->insert_id,
			"status"      => "nowe",
			"deadline_at" => gmdate( "Y-m-d H:i:s", time() + 3600 ),
			"warning_at"  => gmdate( "Y-m-d H:i:s", time() - 3600 ),
			"updated_at"  => $now,
		) );
	}
' >/dev/null 2>&1
ILE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE warning_at < UTC_TIMESTAMP() AND reminder_sent_at IS NULL")
[ "$ILE" = "55" ] && ok "55 wymagalnych przypomnien czeka (paczka pelna, petla rund wejdzie)" || bad "scena nie zbudowana — wymagalnych: $ILE"

# ── 2. JEDEN przebieg przy padnietej poczcie ─────────────────────────────────
sweep_padajaca

MAXP=$(q "SELECT MAX(reminder_attempts) FROM wp_mp_case_sla")
TKNIETE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE reminder_attempts > 0")
[ "$MAXP" = "1" ] && ok "po jednym przebiegu KAZDA sprawa ma najwyzej 1 probe (nie 3)" \
	|| bad "jeden przebieg spalil do $MAXP prob na sprawe — budzet ponowien wyczerpany w kilka sekund"

SPALONE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE reminder_sent_at IS NOT NULL")
[ "$SPALONE" = "0" ] && ok "zaden marker NIE zostal ustawiony na sile (przypomnienia wciaz zyja)" \
	|| bad "$SPALONE przypomnien przepadlo na stale po jednej czkawce SMTP"

FINAL=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type = 'MAIL_FAILED_FINAL'")
[ "$FINAL" = "0" ] && ok "brak wpisow MAIL_FAILED_FINAL (nic nie zostalo spisane na straty)" \
	|| bad "$FINAL spraw spisanych na straty w jednym przebiegu"

# Stempel proby musi byc zapisany — to on rozsuwa ponowienia.
STEMPLE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE reminder_attempt_at IS NOT NULL")
[ "$STEMPLE" = "$TKNIETE" ] && ok "kazda proba zostawila stempel czasu ($STEMPLE z $TKNIETE)" \
	|| bad "proby bez stempla czasu ($STEMPLE z $TKNIETE) — odstep nie ma sie na czym oprzec"

# ── 3. Kolejny przebieg OD RAZU niczego nie dokłada (odstep dziala) ──────────
sweep_padajaca
MAXP2=$(q "SELECT MAX(reminder_attempts) FROM wp_mp_case_sla")
[ "$MAXP2" = "1" ] && ok "przebieg tuz po poprzednim NIE zjada kolejnej proby" \
	|| bad "proba spalona natychmiast (max=$MAXP2) — ponowienia nadal nierozsuniete"

# ── 4. Po odstepie ponowienie JEDNAK nastepuje (to nie jest cisza) ───────────
ODSTEP=$(wp eval 'echo MP\Automator\Sla::RETRY_INTERVAL;' 2>/dev/null | tr -d '[:space:]')
[ -n "$ODSTEP" ] && ok "odstep ponowien zadeklarowany w kodzie ($ODSTEP s)" || bad "brak stalej RETRY_INTERVAL"
wp db query "UPDATE wp_mp_case_sla SET reminder_attempt_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL $(( ${ODSTEP:-240} + 60 )) SECOND);" >/dev/null 2>&1

sweep_padajaca
MAXP3=$(q "SELECT MAX(reminder_attempts) FROM wp_mp_case_sla")
[ "$MAXP3" = "2" ] && ok "po uplywie odstepu przebieg ponawia probe (2 z $(wp eval 'echo MP\Automator\Sla::MAX_ATTEMPTS;' 2>/dev/null | tr -d '[:space:]'))" \
	|| bad "ponowienie po odstepie NIE nastapilo (max=$MAXP3) — powiadomienie utknelo"

# ── 5. Poczta wraca => przypomnienie JEDNAK wychodzi (sedno naprawy) ─────────
wp db query "UPDATE wp_mp_case_sla SET reminder_attempt_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL $(( ${ODSTEP:-240} + 60 )) SECOND);" >/dev/null 2>&1
sweep_dzialajaca
WYSLANE=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE reminder_sent_at IS NOT NULL")
# ⛔ Sam marker to ZA MALO na dowod: kod sprzed naprawy tez konczyl z kompletem
# markerow — tyle ze czesc ustawil NA SILE, bez wysylki. Liczy sie wiec para:
# markery sa I nikt nie zostal spisany na straty.
SPISANE=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type = 'MAIL_FAILED_FINAL'")
{ [ "$WYSLANE" = "55" ] && [ "$SPISANE" = "0" ]; } \
	&& ok "po powrocie poczty przypomnienia WYSZLY (55 z 55, zero spisanych na straty)" \
	|| bad "przypomnienia nie doszly do skutku (markery: $WYSLANE z 55, spisanych na straty: $SPISANE)"

# ── Sprzatanie ───────────────────────────────────────────────────────────────
# ⛔ KOORDYNATOR TEZ ZNIKA. Testy „brak koordynatora => MAIL_SKIPPED" (d-p34a)
# licza WSZYSTKICH uzytkownikow z ta rola w calej instalacji — koordynator
# zostawiony przez cudzy test cicho psuje ich scenariusz przy nastepnym przebiegu.
wp db query "DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_service_cases WHERE case_number LIKE 'SRV/2026/M4%';" >/dev/null 2>&1
wp user delete "$COORD" --yes >/dev/null 2>&1
wp eval 'delete_option("mp_sla_mail_alert");' >/dev/null 2>&1

echo
echo "WYNIK M4: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
