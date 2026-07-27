#!/usr/bin/env bash
# C27 — RODO w panelu klienta: nieodwracalna akcja MUSI mieć krok potwierdzenia.
#
# Znalezisko z przegladu UI (27.07): przycisk „Wycofaj zgodę i usuń moje dane"
# wysylal formularz od razu — jedno klikniecie wycofywalo zgode na WSZYSTKICH
# sprawach i uruchamialo usuwanie danych. Przycisk siedzial bezposrednio pod
# niewinnym „Zapisz dane", wiec pudlo kciukiem na telefonie = utrata danych.
# System ma juz wzorzec na to (potwierdzenie zgloszenia i logowanie linkiem:
# klikniecie prowadzi na ekran z przyciskiem) — tutaj go brakowalo.
#
# Sprawdzamy TO, CO WIDZI I ROBI KLIENT: pierwszy POST nie moze nic zmienic,
# dopiero drugi (swiadome potwierdzenie) wykonuje operacje.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
ev()  { wp eval "$1" 2>/dev/null; }

# unikalny adres na przebieg: test KASUJE dane, wiec powtorka na tym samym
# koncie startowalaby juz po anonimizacji (falszywy czerwony).
EMAIL="rodo-c27-$$@example.com"

# ── seed: klient z potwierdzona sprawa ──────────────────────────────────────
OUT=$(wp mp case-create --kind=reklamacja --email="$EMAIL" --name='Klient C27' \
      --serial='SN-C27-1' --document='FV/C27/1' --date='2026-05-05' \
      --desc='Sprzet nie wlacza sie po tygodniu' 2>/dev/null)
TOK=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$TOK" >/dev/null 2>&1
UID_K=$(wp user get "$EMAIL" --field=ID 2>/dev/null)
[ -n "$UID_K" ] && ok "seed: konto klienta zalozone (uid=$UID_K)" || bad "seed: brak konta klienta"

# Skutek wycofania, ktory powstaje ZAWSZE: wpis CONSENT_WITHDRAWN na sprawach
# klienta (audit-trail art. 7). Mierzymy jego, bo zgode zapisuje dopiero realny
# formularz — CLI case-create jej nie tworzy.
zdarzen_wycofania() {
	ev "global \$wpdb; \$p = \$wpdb->prefix;
		echo (int) \$wpdb->get_var(\"SELECT COUNT(*) FROM {\$p}mp_case_events e
			JOIN {\$p}mp_service_cases c ON c.id = e.case_id
			WHERE e.event_type = 'CONSENT_WITHDRAWN'
			  AND c.customer_id IN (SELECT id FROM {\$p}mp_customers WHERE wp_user_id = $UID_K)\");"
}

[ "$(zdarzen_wycofania)" = "0" ] && ok "seed: brak wpisow o wycofaniu (czysty start)" || bad "seed: konto juz po wycofaniu"

# ── 1. PIERWSZY POST (klikniecie przycisku) NIE MOZE nic zmienic ────────────
ev "wp_set_current_user($UID_K);
	\$n = wp_create_nonce('mp_intake_withdraw');
	\$_POST['_mp_nonce'] = \$n; \$_REQUEST['_mp_nonce'] = \$n;
	add_filter('wp_redirect', function(\$l){ throw new \\Exception('REDIRECT:'.\$l); }, 1);
	try { MP\\Intake\\Front\\AccountPage::handle_withdraw(); } catch (\\Exception \$e) { echo \$e->getMessage(); }" \
	> /tmp/mp-c27-krok1.txt 2>/dev/null
KROK1=$(cat /tmp/mp-c27-krok1.txt)

if [ "$(zdarzen_wycofania)" = "0" ]; then
	ok "pierwsze klikniecie NIC nie zmienilo (jest krok potwierdzenia)"
else
	bad "pierwsze klikniecie JUZ wycofalo zgode na sprawach — brak potwierdzenia"
fi
case "$KROK1" in
	*mp_withdraw*|*potwierdz*) ok "pierwsze klikniecie prowadzi na ekran potwierdzenia" ;;
	*) bad "brak przekierowania na potwierdzenie (dostalem: ${KROK1:0:120})" ;;
esac

# ── 2. Ekran potwierdzenia mowi, CO ZNIKNIE, a co zostanie ──────────────────
EKRAN=$(ev "wp_set_current_user($UID_K); \$_GET['mp_withdraw']='potwierdz';
	echo MP\\Intake\\Front\\AccountPage::render();")
echo "$EKRAN" | grep -q 'mp_intake_withdraw_confirm' && ok "ekran potwierdzenia ma wlasny formularz" || bad "brak formularza potwierdzenia"
echo "$EKRAN" | grep -qiE "nieodwracaln|nie mo(ż|z)na cofn" && ok "ekran uprzedza, ze operacja jest nieodwracalna" || bad "ekran nie uprzedza o nieodwracalnosci"

# ── 3. DOPIERO potwierdzenie wykonuje operacje ──────────────────────────────
ev "wp_set_current_user($UID_K);
	\$n = wp_create_nonce('mp_intake_withdraw_confirm');
	\$_POST['_mp_nonce'] = \$n; \$_REQUEST['_mp_nonce'] = \$n;
	add_filter('wp_redirect', function(\$l){ throw new \\Exception('OK'); }, 1);
	try { MP\\Intake\\Front\\AccountPage::handle_withdraw_confirm(); } catch (\\Exception \$e) {}" >/dev/null 2>&1

[ "$(zdarzen_wycofania)" -ge 1 ] && ok "potwierdzenie wykonalo operacje (slad w historii sprawy)" || bad "po potwierdzeniu BRAK sladu wycofania"

# ── 4. Blok RODO stoi POD lista spraw, nie miedzy profilem a sprawami ───────
PANEL=$(ev "wp_set_current_user($UID_K); echo MP\\Intake\\Front\\AccountPage::render();")
POZ_RODO=$(echo "$PANEL" | awk '{print index($0, "mp-account__privacy")}' | head -1)
POZ_SPRAWY=$(echo "$PANEL" | awk '{print index($0, "Twoje zg")}' | head -1)
if [ -n "$POZ_RODO" ] && [ -n "$POZ_SPRAWY" ] && [ "$POZ_RODO" -gt "$POZ_SPRAWY" ]; then
	ok "blok RODO jest PONIZEJ listy spraw (nie rozdziela profilu od zgloszen)"
else
	bad "blok RODO nadal nad lista spraw (RODO=$POZ_RODO, sprawy=$POZ_SPRAWY)"
fi

echo
echo "WYNIK C27: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
