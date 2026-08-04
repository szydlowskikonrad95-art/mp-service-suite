#!/usr/bin/env bash
# ZYWY DOWOD 2.12: powiadomienie z silnika regul nie ginie po jednej odmowie poczty.
#
# BUG (audyt 2.12, waga duza): `RuleEngine::do_notify()` wysylalo powiadomienia
# o zmianie statusu, nowej wiadomosci i przydziale przez gole `Mailer::send()`.
# Gdy serwer poczty odmowil, wynik ladowal na osi sprawy jako „failed" i na tym
# sie konczylo: BEZ drugiej proby i BEZ alarmu dla administratora. Klient po
# prostu nie dostawal wiadomosci o swojej sprawie.
# Wzorzec poprawny lezal OBOK, w tym samym module: `Sla::notify()` ma ponowienie
# (attempts + zamiatarka) i alarm widoczny w Stanie witryny.
#
# FIX: wspolne gardlo `RuleEngine::deliver()` — ponowienie na jednorazowym zadaniu
# crona (bez nowej tabeli, bo to byla by migracja i zmiana odinstalowania), ta sama
# liczba prob co SLA (`Sla::MAX_ATTEMPTS`) i ten sam alarm (`Sla::ALERT_OPTION`).
#
# 🪤 PULAPKA, ktorej pilnuje kontrola nr 5: okno anty-duplikatowe zajmuje TYLKO
# pierwsza proba. Gdyby ponowienie probowalo je zajac ponownie, odbiloby sie od
# WLASNEJ rezerwacji i „ponowienie" polegaloby na cichym pominieciu maila.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

ALERT='mp_automator_mail_alert'
HOOK='mp_workflow_notify_retry'

# Ile zadan ponowienia czeka w cronie WordPressa (0 = zadnego).
ile_ponowien() {
	wp eval '
		$n = 0;
		foreach ( (array) _get_cron_array() as $slot ) {
			if ( isset( $slot["'"$HOOK"'"] ) ) {
				$n += count( $slot["'"$HOOK"'"] );
			}
		}
		echo $n;' 2>/dev/null | tr -d '[:space:]'
}

# Argumenty czekajacego ponowienia DLA WSKAZANEJ SPRAWY, rozdzielone srednikiem.
# ⛔ Po sprawie, nie „pierwsze z brzegu": harmonogram jest wspolny dla calego
# WordPressa, wiec branie pierwszego lepszego zadania wciaga smiec z innego biegu.
argumenty_ponowienia() {
	wp eval '
		foreach ( (array) _get_cron_array() as $slot ) {
			if ( ! isset( $slot["'"$HOOK"'"] ) ) {
				continue;
			}
			foreach ( $slot["'"$HOOK"'"] as $zadanie ) {
				$args = (array) $zadanie["args"];
				if ( (int) ( $args[0] ?? 0 ) === '"$1"' ) {
					echo implode( ";", $args );
					return;
				}
			}
		}' 2>/dev/null | tr -d '[:space:]'
}

# ⚠️ `wp_clear_scheduled_hook()` kasuje WYLACZNIE zadania bez argumentow — nasze
# ponowienia niosa piec argumentow, wiec tamta funkcja nie ruszalaby ich wcale
# i „sprzatanie" byloby zyczeniem. `wp_unschedule_hook()` czysci zaczep w calosci.
sprzataj_cron() {
	wp eval 'wp_unschedule_hook( "'"$HOOK"'" );' >/dev/null 2>&1
}

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. STAN ZASTANY (mierzony, nie zakladany) ────────────────────────────────
# Testy w zadaniu e2e-import chodza JEDEN PO DRUGIM na TEJ SAMEJ bazie, wiec
# stan zostawiony przez ten test wywala test kilka pozycji dalej — i to w miejscu
# bez zwiazku ze zmiana. Zapamietujemy to, co zastalismy, i oddajemy tak samo.
ALERT_ZASTANY=$(wp option get "$ALERT" --format=json 2>/dev/null)
PONOWIENIA_ZASTANE=$(ile_ponowien)

# ── 0b. Czysty stan + reguly domyslne ────────────────────────────────────────
wp db query "DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_workflow_rules;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); delete_option("mp_automator_mail_templates"); delete_option("'"$ALERT"'"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
sprzataj_cron

REGULA=$(q "SELECT COUNT(*) FROM wp_mp_workflow_rules WHERE action_type='notify'")
[ "${REGULA:-0}" -ge 1 ] 2>/dev/null && ok "regula powiadamiajaca istnieje (domyslny zestaw)" || bad "brak reguly notify — test nie ma czego sprawdzac"

CID=$(mkcase reguly-2-12@example.com RULE212-1)
[ -n "$CID" ] && ok "sprawa testowa utworzona i potwierdzona (id=$CID)" || bad "nie udalo sie utworzyc sprawy"

# ── 1. POCZTA PADA: slad + ZAPLANOWANE ponowienie (sedno 2.12) ───────────────
wp eval "add_filter('pre_wp_mail','__return_false',99); apply_filters('mp_case_change_status', null, $CID, 'w naprawie', 'nowe', 1, null);" >/dev/null 2>&1

MF=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='MAIL_FAILED'")
[ "${MF:-0}" -ge 1 ] 2>/dev/null \
	&& ok "nieudana wysylka zapisana na osi sprawy (MAIL_FAILED)" \
	|| bad "awaria poczty BEZ sladu na osi (to jest wada 2.12)"

WYNIK=$(q "SELECT payload FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='RULE_EXECUTED' ORDER BY id DESC LIMIT 1")
echo "$WYNIK" | grep -q "failed_retry_scheduled" \
	&& ok "slad mowi, ze ZAPLANOWANO ponowienie (nie samo failed)" \
	|| bad "slad nie odnotowuje ponowienia ($WYNIK)"

PON=$(ile_ponowien)
[ "${PON:-0}" -ge 1 ] 2>/dev/null \
	&& ok "ponowienie CZEKA w harmonogramie ($PON zadanie)" \
	|| bad "zadne ponowienie nie zostalo zaplanowane (to jest wada 2.12)"

# Argumenty nie moga niesc adresu e-mail — zadania crona siedza w opcji, ktora
# trafia do kopii zapasowej i do eksportu danych.
ARGS=$(argumenty_ponowienia "$CID")
printf '%s' "$ARGS" | grep -q "@" \
	&& bad "argumenty ponowienia niosa adres e-mail ($ARGS) — dane osobowe w opcji crona" \
	|| ok "argumenty ponowienia bez danych osobowych (kategoria odbiorcy, nie adres)"

# ── 2. PONOWIENIE przy dzialajacej poczcie: mail wychodzi ────────────────────
# Bierzemy DOKLADNIE te argumenty, ktore zaplanowal produkt — gdyby byly nie do
# uzycia, ponowienie w produkcji tez by nie zadzialalo.
IFS=';' read -r A_CID A_TPL A_RCP A_RULE A_ATT <<< "$ARGS"
PRZED=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='MAIL_DEDUPED'")
wp eval "add_filter('pre_wp_mail','__return_true',99); MP\Automator\RuleEngine::on_notify_retry($A_CID, '$A_TPL', '$A_RCP', $A_RULE, $A_ATT);" >/dev/null 2>&1

WYNIK2=$(q "SELECT payload FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='RULE_EXECUTED' ORDER BY id DESC LIMIT 1")
echo "$WYNIK2" | grep -q "success_after_retry" \
	&& ok "ponowienie DOSZLO do skutku (mail wyszedl za druga proba)" \
	|| bad "ponowienie nie wyslalo maila ($WYNIK2)"

# ── 3. PULAPKA DEDUP: ponowienie NIE odbija sie od wlasnej rezerwacji ────────
PO=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='MAIL_DEDUPED'")
[ "$PO" = "$PRZED" ] \
	&& ok "ponowienie nie zostalo uznane za duplikat samego siebie" \
	|| bad "ponowienie odbilo sie od okna anty-duplikatowego (ciche pominiecie maila)"

# ── 4. WYCZERPANE PROBY: alarm dla administratora ───────────────────────────
MAXP=$(wp eval 'echo MP\Automator\Sla::MAX_ATTEMPTS;' 2>/dev/null | tr -d '[:space:]')
wp eval "delete_option('$ALERT');" >/dev/null 2>&1
sprzataj_cron
wp eval "add_filter('pre_wp_mail','__return_false',99); MP\Automator\RuleEngine::on_notify_retry($CID, '$A_TPL', '$A_RCP', $A_RULE, $MAXP);" >/dev/null 2>&1

FIN=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='MAIL_FAILED_FINAL'")
[ "${FIN:-0}" -ge 1 ] 2>/dev/null \
	&& ok "po $MAXP probach slad koncowy (MAIL_FAILED_FINAL)" \
	|| bad "brak sladu koncowego po wyczerpaniu prob"

AL=$(wp option get "$ALERT" --format=json 2>/dev/null)
{ [ -n "$AL" ] && [ "$AL" != "false" ]; } \
	&& ok "alarm dla administratora podniesiony (ten sam co przy SLA)" \
	|| bad "poczta padla na dobre, a administrator nie ma alarmu (to jest wada 2.12)"

PON2=$(ile_ponowien)
[ "${PON2:-0}" = "0" ] \
	&& ok "po wyczerpaniu prob NIE planujemy kolejnych (brak petli)" \
	|| bad "ponawianie leci w nieskonczonosc ($PON2 zadan)"

# ── 5. PRZYPADEK BEZ PROBLEMU: poczta dziala => zero halasu ──────────────────
wp eval "delete_option('$ALERT');" >/dev/null 2>&1
sprzataj_cron
CID2=$(mkcase reguly-2-12-ok@example.com RULE212-2)
wp eval "add_filter('pre_wp_mail','__return_true',99); apply_filters('mp_case_change_status', null, $CID2, 'w naprawie', 'nowe', 1, null);" >/dev/null 2>&1

MF2=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID2 AND event_type IN ('MAIL_FAILED','MAIL_FAILED_FINAL')")
[ "${MF2:-1}" = "0" ] \
	&& ok "udana wysylka nie zasmieca osi falszywa awaria" \
	|| bad "udana wysylka zapisala awarie ($MF2)"

PON3=$(ile_ponowien)
[ "${PON3:-1}" = "0" ] \
	&& ok "udana wysylka nie planuje ponowien" \
	|| bad "ponowienie zaplanowane mimo udanej wysylki ($PON3)"

AL2=$(wp option get "$ALERT" --format=json 2>/dev/null)
{ [ -z "$AL2" ] || [ "$AL2" = "false" ]; } \
	&& ok "udana wysylka nie podnosi alarmu" \
	|| bad "alarm podniesiony mimo udanej wysylki ($AL2)"

# ── 6. SPRZATANIE ZE SPRAWDZENIEM (sprzatanie bez kontroli to zyczenie) ─────
sprzataj_cron

if [ -n "$ALERT_ZASTANY" ] && [ "$ALERT_ZASTANY" != "false" ]; then
	wp eval "update_option('$ALERT', json_decode('$ALERT_ZASTANY', true), false);" >/dev/null 2>&1
else
	wp eval "delete_option('$ALERT');" >/dev/null 2>&1
fi

AL_KONIEC=$(wp option get "$ALERT" --format=json 2>/dev/null)
[ "${AL_KONIEC:-}" = "${ALERT_ZASTANY:-}" ] \
	&& ok "alarm poczty oddany w stanie zastanym (nastepny test nie dziedziczy naszego)" \
	|| bad "zostawiamy alarm w innym stanie niz zastany (zastany=$ALERT_ZASTANY, koniec=$AL_KONIEC)"

# Nie wolno zostawic WIECEJ, niz zastalismy. Mniej wolno: `wp_unschedule_hook`
# czysci zaczep w calosci, wiec zabiera tez smiec z wczesniejszych biegow — a to
# jest poprawa, nie szkoda (zadania tego zaczepu tworza wylacznie nasze testy).
PON_KONIEC=$(ile_ponowien)
[ "${PON_KONIEC:-0}" -le "${PONOWIENIA_ZASTANE:-0}" ] 2>/dev/null \
	&& ok "harmonogram nie rosnie po nas (zastano $PONOWIENIA_ZASTANE, zostaje $PON_KONIEC)" \
	|| bad "zostawiamy $PON_KONIEC zadan ponowienia (zastano $PONOWIENIA_ZASTANE) — wybuchnie u kogos dalej"

# Sprawy testowe: kasujemy PO NUMERACH, nie hurtem — cudzych danych nie ruszamy.
for ID in "$CID" "$CID2"; do
	[ -n "$ID" ] && wp db query "DELETE FROM wp_mp_service_cases WHERE id=$ID; DELETE FROM wp_mp_workflow_events WHERE case_id=$ID; DELETE FROM wp_mp_case_events WHERE case_id=$ID; DELETE FROM wp_mp_case_sla WHERE case_id=$ID;" >/dev/null 2>&1
done

ZOSTALO=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id IN ($CID, $CID2)")
[ "${ZOSTALO:-1}" = "0" ] \
	&& ok "sprawy testowe posprzatane (nastepny test nie policzy ich jako swoich)" \
	|| bad "zostawiamy $ZOSTALO naszych spraw w bazie"

echo ""
echo "WYNIK 2.12: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
