#!/usr/bin/env bash
# ZYWY DOWOD 2.6 (druga polowa): ekran „Zgloszenia niepotwierdzone" nie wypycha
# strony poza okno przegladarki.
#
# BUG: tabela `fixed` z kilkoma kolumnami nie miescila sie i przewijala CALA
# STRONE w poziomie. Zmierzony nadmiar: 165 px przy szerokosci 1280, 216 przy
# 1024, 243 przy 768, 318 przy 390 — czyli im wezszy ekran, tym gorzej.
#
# NAPRAWA: tabela zamknieta we wlasnym obszarze przewijanym. ⛔ Wzorzec CELOWO
# TEN SAM co w blizniaczym ekranie automatora (`role="region"` + `tabindex="0"`
# + etykieta) — dwa rozne sposoby na ten sam problem w jednym produkcie znaczyly
# by, ze kazdy nastepny ekran trzeba naprawiac od nowa.
#
# ⚠️ Test mierzy ZAWARTOSC EKRANU, nie plik CSS. Sprawdzanie, czy w arkuszu stoi
# regula, przeszloby nawet wtedy, gdyby ekran tej klasy w ogole nie uzywal.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

STEMPEL="$$-$(date +%s)"

# Sprawa NIEPOTWIERDZONA — bez niej pierwsza tabela w ogole sie nie renderuje
# i test nie mialby czego zbadac.
wp mp case-create --kind=reklamacja --email="okno-${STEMPEL}@example.com" --name='T Okno' \
	--serial="OKNO-${STEMPEL}" --document='FV/2026/9' --date='2026-05-01' --desc='x' >/dev/null 2>&1

ILE_PENDING=$(wp db query "SELECT COUNT(*) FROM wp_mp_service_cases WHERE identity_status='pending'" --skip-column-names 2>/dev/null | tr -d '[:space:]')
[ "${ILE_PENDING:-0}" -ge 1 ] 2>/dev/null \
	&& ok "stan wyjsciowy: jest zgloszenie niepotwierdzone do pokazania" \
	|| bad "brak zgloszen niepotwierdzonych — ekran bylby pusty, test nic nie dowiedzie"

EKRAN=$(wp eval "
	wp_set_current_user(1);
	ob_start();
	MP\\Intake\\Admin\\UnverifiedScreen::render_page();
	echo ob_get_clean();" 2>/dev/null)

# ── 0. Proba kontrolna: ekran w ogole sie wyrenderowal ────────────────────
ILE_TABEL=$(printf '%s' "$EKRAN" | grep -o '<table' | grep -c . || true)
[ "${ILE_TABEL:-0}" -ge 1 ] 2>/dev/null \
	&& ok "ekran wyrenderowany, ma $ILE_TABEL tabel(e)" \
	|| bad "ekran nie wyrenderowal ZADNEJ tabeli — dalsze kontrole nic nie znaczyly by"

# ── 1. SEDNO: KAZDA tabela siedzi w obszarze przewijanym ──────────────────
# Liczymy obszary i tabele. Sprawdzanie „czy jest chociaz jeden obszar" przeszloby
# nawet wtedy, gdyby druga tabela dalej wypychala strone.
ILE_OBSZAROW=$(printf '%s' "$EKRAN" | grep -o 'mp-intake-table-scroll' | grep -c . || true)

[ "${ILE_OBSZAROW:-0}" -ge "${ILE_TABEL:-1}" ] 2>/dev/null \
	&& ok "SEDNO: kazda tabela ekranu ma wlasny obszar przewijany ($ILE_OBSZAROW/$ILE_TABEL)" \
	|| bad "tabel $ILE_TABEL, a obszarow przewijanych $ILE_OBSZAROW — ktoras dalej wypycha strone (wada 2.6)"

# ── 2. Obszar da sie przewinac SAMA KLAWIATURA ────────────────────────────
# Bez `tabindex` obszar przewijany jest niedostepny dla osoby bez myszy — czyli
# naprawa wygladu zrobilaby nowa bariere.
ILE_TABINDEX=$(printf '%s' "$EKRAN" | grep -o 'class="mp-intake-table-scroll" role="region" tabindex="0"' | grep -c . || true)

[ "${ILE_TABINDEX:-0}" -ge "${ILE_TABEL:-1}" ] 2>/dev/null \
	&& ok "kazdy obszar ma role=region i tabindex=0 (przewijalny klawiatura)" \
	|| bad "obszary bez role=region/tabindex=0 ($ILE_TABINDEX) — nowa bariera zamiast naprawy"

# ── 3. Obszar MA NAZWE — inaczej czytnik ekranu oglasza „region" i tyle ───
printf '%s' "$EKRAN" | grep -q 'class="mp-intake-table-scroll" role="region" tabindex="0" aria-label="[^"]\+"' \
	&& ok "obszary maja etykiete (czytnik mowi, co to za tabela)" \
	|| bad "obszar bez etykiety — czytnik oglasza samo „region"

# ── 4. Arkusz panelu jest ZAREJESTROWANY dla tego ekranu ──────────────────
# Sam znacznik w HTML nic nie da, jesli regula przewijania nigdzie nie dojedzie.
# ⚠️ Identyfikator ekranu powstaje dopiero przy budowie menu, a menu nie buduje sie
# w wierszu polecen. Bez wywolania `add_menu()` kontrola mierzylaby WLASNE
# narzedzie (pusty identyfikator) i meldowala wade produktu tam, gdzie jej nie ma.
ZAREJESTROWANY=$(wp eval "
	wp_set_current_user(1);
	require_once ABSPATH . 'wp-admin/includes/plugin.php';
	MP\\Intake\\Admin\\UnverifiedScreen::add_menu();
	MP\\Intake\\Admin\\UnverifiedScreen::enqueue( 'toplevel_page_' . MP\\Intake\\Admin\\UnverifiedScreen::PAGE_SLUG );
	echo wp_style_is( 'mp-intake-admin', 'enqueued' ) ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]')

[ "$ZAREJESTROWANY" = "tak" ] \
	&& ok "arkusz panelu wpiety na tym ekranie" \
	|| bad "arkusz panelu NIE wpiety ([$ZAREJESTROWANY]) — obszar nie mialby czym sie przewijac"

# ── 5. ...ale TYLKO na tym ekranie ────────────────────────────────────────
# Styl jednego ekranu nie ma prawa ladowac sie na kazdej stronie panelu.
NIE_WSZEDZIE=$(wp eval "
	wp_set_current_user(1);
	require_once ABSPATH . 'wp-admin/includes/plugin.php';
	MP\\Intake\\Admin\\UnverifiedScreen::add_menu();
	MP\\Intake\\Admin\\UnverifiedScreen::enqueue( 'index.php' );
	echo wp_style_is( 'mp-intake-admin', 'enqueued' ) ? 'wszedzie' : 'tylko-tam';" 2>/dev/null | tr -d '[:space:]')

[ "$NIE_WSZEDZIE" = "tylko-tam" ] \
	&& ok "arkusz nie laduje sie na innych ekranach panelu" \
	|| bad "arkusz laduje sie POZA swoim ekranem ([$NIE_WSZEDZIE])"

# ── 6. SPRZATANIE ─────────────────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_service_cases WHERE pending_email LIKE 'okno-${STEMPEL}%' OR id IN (SELECT * FROM (SELECT c.id FROM wp_mp_service_cases c LEFT JOIN wp_mp_customers k ON k.id=c.customer_id WHERE k.email LIKE 'okno-${STEMPEL}%') x)" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_customers WHERE email LIKE 'okno-${STEMPEL}%'" >/dev/null 2>&1
ok "dane testowe posprzatane"

echo ""
echo "WYNIK 2.6: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
