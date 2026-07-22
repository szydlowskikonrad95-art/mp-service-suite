#!/usr/bin/env bash
# DoD C sekcja 7 — a11y/WCAG 2.1 (strukturalnie): klient = instytucja publiczna.
# Sprawdza WCAG-lite na renderach: label spiety z KAZDYM polem, bledy w role=alert
# + aria-describedby, potwierdzenia w role=status, pola wymagane oznaczone.
# CLI (render przez eval). Chodzi na poligonie i w CI (e2e-import).
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_consents;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done

# ── 1. Formularz zgloszenia (z bledem — wymusza role=alert) ─────────────────
FORM=$(wp eval "echo MP\Intake\Front\FormRenderer::render(array('errors'=>array('email'=>'INVALID_EMAIL'),'values'=>array('kind'=>'reklamacja'),'notice'=>''));" 2>/dev/null)
echo "$FORM" | grep -q 'role="alert"' && ok "formularz: bledy w role=alert (asertywne dla czytnika)" || bad "formularz bez role=alert"
echo "$FORM" | grep -q '<label for="mp-f-email"' && ok "formularz: <label for> spiety z polem e-mail" || bad "brak label dla e-mail"
echo "$FORM" | grep -q 'aria-describedby=' && ok "formularz: aria-describedby (blad spiety z polem)" || bad "brak aria-describedby"
echo "$FORM" | grep -qE '(required|aria-required)' && ok "formularz: pola wymagane oznaczone" || bad "brak oznaczenia required"
# honeypot poza drzewem dostepnosci
echo "$FORM" | grep -q 'aria-hidden="true"' && ok "formularz: honeypot aria-hidden (poza a11y-tree)" || bad "honeypot nie aria-hidden"

# ── 2. Panel niezalogowany (logowanie): label + notice role=status ─────────
LOGIN=$(wp eval "wp_set_current_user(0); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)
echo "$LOGIN" | grep -q '<label for="mp-account-email"' && ok "panel-login: <label for> spiety z polem e-mail" || bad "panel-login bez label"

# ── 3. Panel zalogowany: formularze danych/wiadomosci z labelkami ──────────
O=$(wp mp case-create --kind=zapytanie --email='a11y@example.com' --name='A11y' --desc='x' 2>/dev/null)
T=$(echo "$O" | grep '^token=' | cut -d= -f2); wp mp case-verify "$T" >/dev/null 2>&1
UID1=$(wp user get 'a11y@example.com' --field=ID 2>/dev/null)
PANEL=$(wp eval "wp_set_current_user($UID1); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)
echo "$PANEL" | grep -q '<label for="mp-name"' && ok "panel: <label for> dla danych kontaktowych (art. 16)" || bad "brak label danych"
echo "$PANEL" | grep -qE '<label for="mp-msg-[0-9]+"' && ok "panel: <label for> dla pola wiadomosci" || bad "brak label wiadomosci"

# ── 4. Zadne widoczne pole tekstowe bez etykiety (formularz zgloszenia) ────
# Liczba widocznych <input type=text/email/tel + textarea> vs <label for=...>.
INPUTS=$(echo "$FORM" | grep -oE '<(input type="(text|email|tel)"|textarea)' | wc -l | tr -d ' ')
LABELS=$(echo "$FORM" | grep -oE '<label for="mp-f-' | wc -l | tr -d ' ')
{ [ "${INPUTS:-0}" -ge 1 ] && [ "${LABELS:-0}" -ge "${INPUTS:-0}" ]; } && ok "formularz: liczba etykiet >= liczba widocznych pol ($LABELS >= $INPUTS)" || bad "pola bez etykiety (inputs=$INPUTS labels=$LABELS)"

echo
echo "WYNIK a11y-forms: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
