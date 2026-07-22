#!/usr/bin/env bash
# BLOK-S — a11y/WCAG sweep (klient = INSTYTUCJA PUBLICZNA => a11y to WYMOG).
# Uzupelnia a11y-forms.sh (DoD C par.7: labelki/role=alert na formularzu) o:
#  (1) GUARD img-alt w ZRODLE — kazdy <img>/wp_get_attachment_image z alt (grep
#      BRAMKA par.7); dzis 0 obrazow => guard trzyma regresje na przyszlosc,
#  (2) WCAG-lite render sweep WSZYSTKICH powierzchni (formularz + panel wylogowany
#      + panel zalogowany + admin): kazdy <img> z alt, kazdy przycisk z NAZWA
#      dostepna, ZERO duplikatow id (regula axe duplicate-id).
# Warstwa statyczna/strukturalna. Pelny axe-core (przebieg DOM w przegladarce)
# = osobny krok (Node+Chromium) — do decyzji straznika (CI vs manual przed oddaniem);
# tu NIE udajemy ze axe sie odpalilo (dowod nie slowo).
#
# CLI (render przez eval). Chodzi na poligonie i w CI. Exit 0 = zero FAIL.
set -u

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); echo "  OK   $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
skip() { SKIP=$((SKIP+1)); echo "  SKIP $1"; }
q()    { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Sprawdza jeden render HTML pod katem 3 regul axe. $1=nazwa powierzchni, $2=html.
check_surface() {
	local name="$1" html="$2"
	# a) kazdy <img> ma alt=
	local imgs alt_imgs
	imgs=$(echo "$html" | grep -oE '<img\b' | wc -l | tr -d ' ')
	alt_imgs=$(echo "$html" | grep -oE '<img\b[^>]*\balt=' | wc -l | tr -d ' ')
	if [ "${imgs:-0}" -eq 0 ]; then
		ok "$name: brak <img> (nic bez alt)"
	elif [ "${alt_imgs:-0}" -ge "${imgs:-0}" ]; then
		ok "$name: kazdy <img> ma alt ($alt_imgs/$imgs)"
	else
		bad "$name: <img> bez alt ($alt_imgs/$imgs) — WCAG 1.1.1"
	fi
	# b) przyciski maja NAZWE dostepna (zero pustych <button></button>; submit z value/aria)
	local empty_btn bad_submit
	empty_btn=$(echo "$html" | grep -oE '<button\b[^>]*>[[:space:]]*</button>' | wc -l | tr -d ' ')
	bad_submit=$(echo "$html" | grep -oE '<input\b[^>]*type="submit"[^>]*>' | grep -vE 'value="[^"]+"|aria-label="[^"]+"' | wc -l | tr -d ' ')
	{ [ "${empty_btn:-0}" -eq 0 ] && [ "${bad_submit:-0}" -eq 0 ]; } \
		&& ok "$name: przyciski maja nazwe dostepna (zero pustych button/submit bez value)" \
		|| bad "$name: przycisk bez nazwy (puste button=$empty_btn, submit bez value=$bad_submit) — WCAG 4.1.2"
	# c) ZERO duplikatow id na elementach WIDOCZNYCH/interaktywnych. Ukryte inputy
	# (m.in. wp_nonce_field, ktore WP core zawsze stempluje id=nazwa) sa POMIJANE:
	# WCAG 2.2 usunelo SC 4.1.1 (duplicate-id), a axe-core wycofal regule
	# `duplicate-id` — zostala tylko `duplicate-id-aria`. Powtorzony id ukrytego
	# nonce na panelu wielo-formularzowym NIE jest bariera dla czytnika.
	local visible dups
	visible=$(echo "$html" | sed -E 's/<input[^>]*type="hidden"[^>]*>//g')
	dups=$(echo "$visible" | grep -oE 'id="[^"]*"' | sort | uniq -d | wc -l | tr -d ' ')
	[ "${dups:-0}" -eq 0 ] && ok "$name: zero duplikatow id na elementach widocznych (axe duplicate-id-aria; ukryte nonce pominiete)" || bad "$name: duplikaty id na widocznych elementach ($dups) — axe duplicate-id-aria"
}

echo "== BLOK-S a11y/WCAG sweep =="

# ── 1. GUARD img-alt w ZRODLE (BRAMKA par.7) ───────────────────────────────
echo "-- 1. guard img-alt w kodzie pluginow --"
SRC_IMG=0
for base in mp-service-intake mp-warranty-registry mp-workflow-automator; do
	D="$(wp eval 'echo WP_PLUGIN_DIR;' 2>/dev/null)/$base"
	[ -d "$D" ] || continue
	# <img> bez alt= w kodzie PHP (poza katalogiem testow — tu go nie ma)
	HITS=$(grep -rn '<img\b' "$D" --include="*.php" 2>/dev/null | grep -vE '\balt=' | wc -l | tr -d ' ')
	SRC_IMG=$((SRC_IMG + HITS))
done
[ "${SRC_IMG:-0}" -eq 0 ] && ok "kod pluginow: zero <img> bez alt (guard regresji aktywny)" || bad "kod pluginow: $SRC_IMG <img> bez alt — WCAG 1.1.1"

# ── 2. WCAG-lite render sweep powierzchni ──────────────────────────────────
echo "-- 2. render sweep powierzchni (img-alt + nazwy przyciskow + dup-id) --"
wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_consents;" >/dev/null 2>&1
wp db query "DELETE FROM wp_options WHERE option_name LIKE '_transient_mp_rl%'" >/dev/null 2>&1
for u in $(wp user list --role=mp_client --field=ID 2>/dev/null); do wp user delete "$u" --yes >/dev/null 2>&1; done

# a) Formularz zgloszenia (czysty + z bledem)
FORM=$(wp eval "echo MP\Intake\Front\FormRenderer::render(array('errors'=>array(),'values'=>array('kind'=>'reklamacja'),'notice'=>''));" 2>/dev/null)
[ -n "$FORM" ] && check_surface "formularz" "$FORM" || bad "formularz: render pusty"
FORM_ERR=$(wp eval "echo MP\Intake\Front\FormRenderer::render(array('errors'=>array('email'=>'INVALID_EMAIL'),'values'=>array('kind'=>'reklamacja'),'notice'=>''));" 2>/dev/null)
[ -n "$FORM_ERR" ] && check_surface "formularz-z-bledem" "$FORM_ERR" || skip "formularz-z-bledem: render pusty"

# b) Panel wylogowany (formularz logowania)
LOGIN=$(wp eval "wp_set_current_user(0); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)
[ -n "$LOGIN" ] && check_surface "panel-wylogowany" "$LOGIN" || bad "panel-wylogowany: render pusty"

# c) Panel zalogowany (sprawa klienta)
O=$(wp mp case-create --kind=zapytanie --email='a11y-s@example.com' --name='A11y' --desc='x' 2>/dev/null)
T=$(echo "$O" | grep '^token=' | cut -d= -f2); wp mp case-verify "$T" >/dev/null 2>&1
UID1=$(wp user get 'a11y-s@example.com' --field=ID 2>/dev/null)
if [ -n "$UID1" ]; then
	PANEL=$(wp eval "wp_set_current_user($UID1); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)
	[ -n "$PANEL" ] && check_surface "panel-zalogowany" "$PANEL" || bad "panel-zalogowany: render pusty"
else
	skip "panel-zalogowany: nie zalozono konta klienta"
fi

# d) Admin: ekran spraw niepotwierdzonych (jesli renderowalny bez zadan HTTP)
ADMIN=$(wp eval "wp_set_current_user(1); set_current_screen('toplevel_page_mp-unverified'); if (class_exists('MP\\\\Intake\\\\Admin\\\\UnverifiedScreen') && method_exists('MP\\\\Intake\\\\Admin\\\\UnverifiedScreen','render')) { ob_start(); @MP\Intake\Admin\UnverifiedScreen::render(); echo ob_get_clean(); }" 2>/dev/null)
if [ -n "$ADMIN" ]; then
	check_surface "admin-unverified" "$ADMIN"
else
	skip "admin-unverified: ekran wymaga kontekstu zadania admina (pokryty c7b) — sweep renderowalnych powierzchni frontu"
fi

echo
echo "WYNIK BLOK-S a11y: $PASS ok, $FAIL fail, $SKIP skip"
[ "$FAIL" -eq 0 ]
