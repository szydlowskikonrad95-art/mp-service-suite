#!/usr/bin/env bash
# ZYWY DOWOD (audyt kosztu 27.07): jeden przebieg sweepa mogl wyslac do 500 maili.
#
# BATCH 50 x MAX_ROUNDS 10 = do 500 wiadomosci sekwencyjnie w JEDNYM zadaniu PHP.
# Zwykly hosting przepuszcza 200-500 maili/godzine, a 500 polaczen SMTP po ~0,3 s
# to kilka minut pracy — czyli takze ryzyko urwania przez limit czasu wykonania
# w polowie wysylki (czesc spraw z markerem, czesc bez).
# FIX: budzet maili na przebieg (filtr mp_sla_mail_budget). Reszta czeka na
# kolejny przebieg; markery gwarantuja, ze nic nie przepadnie ani nie pojdzie 2x.
#
# UWAGA METODOLOGICZNA: mierzymy RUCH GLOBALNY (ile markerow przybylo w calej
# tabeli), a nie los konkretnych spraw. Sweep bierze sprawy wg terminu ostrzezenia,
# a doszywanie sierot potrafi w tym samym przebiegu zalozyc terminy sprawom z
# wczesniejszych testow — wiec "ktore dokladnie" jest niestabilne, natomiast
# "ile lacznie" to dokladnie ta obietnica, ktorej pilnuje budzet.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

CZEKAJACE='SELECT COUNT(*) FROM wp_mp_case_sla WHERE deadline_at IS NOT NULL AND warning_at IS NOT NULL AND warning_at <= UTC_TIMESTAMP() AND reminder_sent_at IS NULL AND deadline_at > UTC_TIMESTAMP()'

# ── 0. Szesc spraw z wymagalnym przypomnieniem ──────────────────────────────
# Daty w SQL (BusyBox `date` w obrazie wp-cli nie zna `-d '2 hours ago'`).

for i in 1 2 3 4 5 6; do
	O=$(wp mp case-create --kind=zapytanie --email="budzet$i@example.com" --name="Budzet $i" --desc="test budzetu maili" 2>/dev/null)
	CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2)
	wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe' WHERE id=$CID" >/dev/null 2>&1
	wp db query "REPLACE INTO wp_mp_case_sla (case_id, status, sla_policy_version, deadline_at, warning_at, reminder_sent_at, escalated_at, updated_at)
		VALUES ($CID, 'nowe', 1, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 10 HOUR), DATE_SUB(UTC_TIMESTAMP(), INTERVAL 2 HOUR), NULL, NULL, DATE_SUB(UTC_TIMESTAMP(), INTERVAL 2 HOUR))" >/dev/null 2>&1
done

# Doszywanie sierot ZANIM zaczniemy mierzyc — inaczej pierwszy przebieg sweepa
# zalozylby nowe terminy w trakcie pomiaru i ruszyl licznik "czekajacych".
wp eval 'MP\Automator\Sla::reconcile_untracked(500);' >/dev/null 2>&1

# Po poz. 2.30 budzet jest WSPOLNY dla przypomnien i eskalacji, a eskalacja ma w nim
# pierwszenstwo. Sekcje 1-3 mierza SAME przypomnienia, wiec kolejka eskalacji musi byc
# pusta — inaczej mierzylyby dwie rzeczy naraz. Zdejmujemy zaleglosci po WCZESNIEJSZYCH
# testach (marker bez maila; wlasne eskalacje seedujemy dopiero w sekcji 4).
wp db query "UPDATE wp_mp_case_sla SET escalated_at = UTC_TIMESTAMP()
	WHERE deadline_at IS NOT NULL AND deadline_at <= UTC_TIMESTAMP() AND escalated_at IS NULL" >/dev/null 2>&1

PRZED=$(q "$CZEKAJACE")
[ "${PRZED:-0}" -ge 6 ] 2>/dev/null && ok "seed: co najmniej 6 spraw czeka na przypomnienie (jest $PRZED)" || bad "seed zly ($PRZED)"

# ── 1. Budzet 2 => przebieg wysyla DOKLADNIE 2 maile, reszta czeka ──────────
# pre_wp_mail => true: w kontenerze CI NIE MA serwera poczty, wiec kazda wysylka
# by padla, marker 'wyslano' nie zostalby postawiony (kod slusznie ponawia), a test
# mierzylby ponawianie zamiast budzetu. Wymuszamy determinizm.
wp eval "add_filter('pre_wp_mail', '__return_true'); add_filter('mp_sla_mail_budget', function(){ return 2; }); MP\\Automator\\Sweep::run();" >/dev/null 2>&1
PO=$(q "$CZEKAJACE")
ROZNICA=$(( PRZED - PO ))
[ "$ROZNICA" = "2" ] && ok "budzet dotrzymany: dokladnie 2 przypomnienia w przebiegu (bylo $PRZED, zostalo $PO)" || bad "budzet zlamany: wyslano $ROZNICA zamiast 2"

[ "${PO:-0}" -ge 1 ] 2>/dev/null && ok "reszta CZEKA z pustym markerem (nic nie przepadlo)" || bad "reszta zniknela z kolejki ($PO)"

LOG=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SWEEP_RUN' AND payload LIKE '%\"przerwany_budzetem\":1%'")
[ "${LOG:-0}" -ge 1 ] 2>/dev/null && ok "przerwanie budzetem ZAPISANE w rejestrze (nie ciche)" || bad "brak sladu przerwania w rejestrze"

LICZNIK=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SWEEP_RUN' AND payload LIKE '%\"reminders\":2%'")
[ "${LICZNIK:-0}" -ge 1 ] 2>/dev/null && ok "licznik pokazuje REALNIE wyslane (2), nie znalezione" || bad "licznik klamie o liczbie maili"

# ── 2. Kolejny przebieg z wiekszym budzetem dobiera zaleglosc ───────────────
wp eval "add_filter('pre_wp_mail', '__return_true'); add_filter('mp_sla_mail_budget', function(){ return 500; }); MP\\Automator\\Sweep::run();" >/dev/null 2>&1
PO2=$(q "$CZEKAJACE")
[ "${PO2:-9}" = "0" ] && ok "kolejny przebieg dobral cala zaleglosc (kolejka pusta)" || bad "zaleglosc nie zeszla ($PO2)"

# ── 3. Kontrola: pusty przebieg nie wysyla nic drugi raz ───────────────────
PRZED3=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE event_type='SLA_REMINDER_SENT'")
wp eval "add_filter('pre_wp_mail', '__return_true'); MP\\Automator\\Sweep::run();" >/dev/null 2>&1
PO3=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE event_type='SLA_REMINDER_SENT'")
[ "$PRZED3" = "$PO3" ] && ok "zero podwojnych przypomnien przy pustym przebiegu" || bad "podwojna wysylka ($PRZED3 -> $PO3)"

# ═══════════════════════════════════════════════════════════════════════════
# POZ. 2.30 — BUDZET PILNOWAL TYLKO PRZYPOMNIEN, ESKALACJE WYCHODZILY POZA NIM
#
# Budzet 120 wiadomosci na przebieg (`Sweep::MAIL_BUDGET`) byl sprawdzany WYLACZNIE
# w petli przypomnien. Eskalacje szly obok: ponizej progu `Sla::DIGEST_THRESHOLD`
# to OSOBNA wiadomosc na kazda sprawe, w kazdej rundzie — czyli furtka w zabezpieczeniu,
# ktore ma chronic hosting przed lawina maili.
#
# ⭐ CZEGO NIE RUSZAMY: uzasadnienie autora, ze POWYZEJ progu dlugosc listy nie zwieksza
# liczby maili (jeden digest na cala liste), jest POPRAWNE — pilnuje tego sekcja 5.
# Eskalacja nie traci tez pierwszenstwa: przy wspolnym budzecie to ONA rezerwuje swoja
# czesc przed przypomnieniami, bo jej termin JUZ minal.
#
# Mierzymy REALNA LICZBE WIADOMOSCI w jednym przebiegu (licznik na `pre_wp_mail`),
# bo to jest dokladnie ta obietnica, ktora budzet sklada.
# ═══════════════════════════════════════════════════════════════════════════

# Ile wiadomosci wyszlo w JEDNYM przebiegu przy budzecie $1.
maile_przebiegu() {
	wp eval "
		\$GLOBALS['mp_maile'] = 0;
		add_filter( 'pre_wp_mail', function( \$przed ) { ++\$GLOBALS['mp_maile']; return true; } );
		add_filter( 'mp_sla_mail_budget', function() { return $1; } );
		MP\\Automator\\Sweep::run();
		update_option( 'mp_test_maile_przebiegu', (int) \$GLOBALS['mp_maile'], false );
	" >/dev/null 2>&1
	wp option get mp_test_maile_przebiegu 2>/dev/null | tr -d '[:space:]'
}

# ── 4. Budzet 2 przy 3 zaleglych eskalacjach i 3 czekajacych przypomnieniach ─
# ⛔ ODBIORCA JEST WARUNKIEM POMIARU: bez konta koordynatora `Sla::notify()` konczy sie
# „brak odbiorcy" (marker bez maila) i licznik pokazalby zero niezaleznie od budzetu.
# Konto kasujemy na koncu sekcji — zostawione zmienia sklad personelu innym testom.
wp user delete mp-budzet-koordynator --yes >/dev/null 2>&1
KOORD=$(wp user create mp-budzet-koordynator budzet-koordynator@example.com \
	--role=mp_coordinator --user_pass=Budzet-2-30 --porcelain 2>/dev/null | tr -d '[:space:]')
[ -n "$KOORD" ] && ok "odbiorca eskalacji istnieje (koordynator $KOORD)" || bad "nie udalo sie zalozyc koordynatora"

# Trzy sprawy PO TERMINIE (3 < DIGEST_THRESHOLD => mail NA KAZDA, nie digest).
ESK_IDS=""
for i in 1 2 3; do
	O=$(wp mp case-create --kind=zapytanie --email="eskalacja$i@example.com" --name="Eskalacja $i" --desc="test budzetu eskalacji" 2>/dev/null)
	CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2)
	wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe' WHERE id=$CID" >/dev/null 2>&1
	wp db query "REPLACE INTO wp_mp_case_sla (case_id, status, sla_policy_version, deadline_at, warning_at, reminder_sent_at, escalated_at, updated_at)
		VALUES ($CID, 'nowe', 1, DATE_SUB(UTC_TIMESTAMP(), INTERVAL 3 HOUR), DATE_SUB(UTC_TIMESTAMP(), INTERVAL 5 HOUR), DATE_SUB(UTC_TIMESTAMP(), INTERVAL 4 HOUR), NULL, UTC_TIMESTAMP())" >/dev/null 2>&1
	ESK_IDS="${ESK_IDS:+$ESK_IDS,}$CID"
done

# Trzy sprawy z wymagalnym przypomnieniem (termin jeszcze w przyszlosci).
PRZ_IDS=""
for i in 1 2 3; do
	O=$(wp mp case-create --kind=zapytanie --email="przypomnienie$i@example.com" --name="Przypomnienie $i" --desc="test pierwszenstwa eskalacji" 2>/dev/null)
	CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2)
	wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe' WHERE id=$CID" >/dev/null 2>&1
	wp db query "REPLACE INTO wp_mp_case_sla (case_id, status, sla_policy_version, deadline_at, warning_at, reminder_sent_at, escalated_at, updated_at)
		VALUES ($CID, 'nowe', 1, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 10 HOUR), DATE_SUB(UTC_TIMESTAMP(), INTERVAL 2 HOUR), NULL, NULL, UTC_TIMESTAMP())" >/dev/null 2>&1
	PRZ_IDS="${PRZ_IDS:+$PRZ_IDS,}$CID"
done

ESK_CZEKA=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id IN ($ESK_IDS) AND escalated_at IS NULL")
PRZ_CZEKA=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id IN ($PRZ_IDS) AND reminder_sent_at IS NULL")
[ "$ESK_CZEKA" = "3" ] && [ "$PRZ_CZEKA" = "3" ] \
	&& ok "seed: 3 zalegle eskalacje + 3 czekajace przypomnienia" \
	|| bad "seed sekcji 4 zly (eskalacje=$ESK_CZEKA, przypomnienia=$PRZ_CZEKA)"

# SEDNO POZYCJI: przebieg z budzetem 2 ma wyslac DWIE wiadomosci — nie dwie plus
# trzy eskalacje obok budzetu.
MAILE=$(maile_przebiegu 2)
[ "${MAILE:-0}" = "2" ] \
	&& ok "SEDNO 2.30: caly przebieg zmiescil sie w budzecie (2 wiadomosci)" \
	|| bad "budzet zlamany: przebieg wyslal $MAILE wiadomosci przy budzecie 2 (eskalacje poza budzetem)"

ESK_PO=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id IN ($ESK_IDS) AND escalated_at IS NOT NULL")
PRZ_PO=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id IN ($PRZ_IDS) AND reminder_sent_at IS NULL")
[ "${ESK_PO:-0}" = "2" ] \
	&& ok "eskalacje maja PIERWSZENSTWO w budzecie: wyszly 2 z 3, trzecia czeka" \
	|| bad "rozdzial budzetu zly: eskalowano $ESK_PO z 3"
[ "${PRZ_PO:-0}" = "3" ] \
	&& ok "przypomnienia ustapily eskalacjom (zadne nie zjadlo ich czesci budzetu)" \
	|| bad "przypomnienia wzialy budzet przed eskalacjami (czeka $PRZ_PO z 3)"

PAYLOAD=$(q "SELECT payload FROM wp_mp_workflow_events WHERE event_type='SWEEP_RUN' ORDER BY id DESC LIMIT 1")
echo "$PAYLOAD" | grep -qE '"escalation_mails":2[,}]' \
	&& ok "rejestr podaje, ile MAILI kosztowaly eskalacje (2) — budzet jest sprawdzalny" \
	|| bad "rejestr nie mowi nic o mailach eskalacji ($PAYLOAD)"

# NIC NIE PRZEPADA: odlozona eskalacja ma pusty marker, wiec bierze ja kolejny przebieg.
MAILE2=$(maile_przebiegu 500)
ESK_PO2=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id IN ($ESK_IDS) AND escalated_at IS NOT NULL")
[ "${ESK_PO2:-0}" = "3" ] \
	&& ok "odlozona eskalacja wyszla kolejnym przebiegiem (nic nie przepadlo)" \
	|| bad "odlozona eskalacja nie doszla ($ESK_PO2 z 3)"

DUBEL=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id IN ($ESK_IDS) AND event_type='SLA_ESCALATED'")
[ "${DUBEL:-0}" = "3" ] \
	&& ok "kazda sprawa eskalowana DOKLADNIE raz (brak dubla po odlozeniu)" \
	|| bad "eskalacje policzone na osi sprawy $DUBEL razy zamiast 3"

# ── 5. STRAZ NAD TYM, CO AUTOR ZROBIL DOBRZE: digest to JEDEN mail na cala liste ─
# ⚠️ Ta sekcja przechodzi TAKZE przed naprawa — i o to chodzi. Pilnuje, ze domkniecie
# dziury w budzecie nie odebralo eskalacjom masowym ich zbiorczej wysylki: szesc spraw
# (> DIGEST_THRESHOLD) ma kosztowac JEDNA wiadomosc, nawet gdy budzet wynosi 1.
DIG_IDS=""
for i in 1 2 3 4 5 6; do
	O=$(wp mp case-create --kind=zapytanie --email="digest$i@example.com" --name="Digest $i" --desc="test progu zbiorczego" 2>/dev/null)
	CID=$(echo "$O" | grep '^case_id=' | cut -d= -f2)
	wp db query "UPDATE wp_mp_service_cases SET identity_status='verified', status='nowe' WHERE id=$CID" >/dev/null 2>&1
	wp db query "REPLACE INTO wp_mp_case_sla (case_id, status, sla_policy_version, deadline_at, warning_at, reminder_sent_at, escalated_at, updated_at)
		VALUES ($CID, 'nowe', 1, DATE_SUB(UTC_TIMESTAMP(), INTERVAL 3 HOUR), DATE_SUB(UTC_TIMESTAMP(), INTERVAL 5 HOUR), DATE_SUB(UTC_TIMESTAMP(), INTERVAL 4 HOUR), NULL, UTC_TIMESTAMP())" >/dev/null 2>&1
	DIG_IDS="${DIG_IDS:+$DIG_IDS,}$CID"
done

MAILE3=$(maile_przebiegu 1)
DIG_PO=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id IN ($DIG_IDS) AND escalated_at IS NOT NULL")
[ "${MAILE3:-0}" = "1" ] \
	&& ok "szesc zaleglych eskalacji = JEDNA wiadomosc (uzasadnienie autora zostaje w mocy)" \
	|| bad "digest rozpadl sie na $MAILE3 wiadomosci"
[ "${DIG_PO:-0}" = "6" ] \
	&& ok "zbiorczy mail objal WSZYSTKIE szesc spraw, mimo budzetu 1" \
	|| bad "digest objal tylko $DIG_PO z 6 spraw"

# ── Sprzatanie: konto koordynatora znika, inaczej zmienia sklad personelu ────
wp user delete mp-budzet-koordynator --yes >/dev/null 2>&1
wp option delete mp_test_maile_przebiegu >/dev/null 2>&1
ZOSTAL=$(wp user get mp-budzet-koordynator --field=ID 2>/dev/null | tr -d '[:space:]')
[ -z "$ZOSTAL" ] && ok "konto testowe koordynatora posprzatane" || bad "konto koordynatora zostalo ($ZOSTAL)"

echo ""
echo "WYNIK D-BUDZET-MAILI: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
