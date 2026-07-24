#!/usr/bin/env bash
# ZYWY DOWOD C18 (poprawka #2: JSON -> formularz): panel Automatyzacji renderuje
# STRUKTURALNY builder checklist/szablonow (pola per rodzaj + add/remove) zamiast
# golego JSON — a surowy JSON zostaje jako fallback w <details> (kontrakt POST bez zmian).
# Render kontrolowany: PanelScreen::render() jako admin (wp eval, ob_start).
# Deterministyczny — nie wymaga MP_BASE. Chodzi na poligonie i w CI.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# Renderuje panel jako administrator i zwraca HTML.
HTML=$(wp eval '
	$u = get_users(array("role"=>"administrator","number"=>1,"fields"=>array("ID")));
	if (empty($u)) { echo "NO_ADMIN"; return; }
	wp_set_current_user((int)$u[0]->ID);
	ob_start();
	\MP\Automator\Admin\PanelScreen::render();
	echo ob_get_clean();
' 2>/dev/null)

has() { echo "$HTML" | grep -q "$1"; }

[ -n "$HTML" ] && [ "$HTML" != "NO_ADMIN" ] && ok "panel wyrenderowany jako admin" || bad "panel nie wyrenderowany (HTML pusty/NO_ADMIN)"

# ── Builder strukturalny obecny ──────────────────────────────────────────────
has 'mp-config-builder'     && ok "form.mp-config-builder obecny (builder aktywny)"         || bad "brak mp-config-builder"
has 'data-kind="reklamacja"' && ok "sekcja rodzaju: reklamacja"                              || bad "brak sekcji reklamacja"
has 'data-kind="naprawa"'   && ok "sekcja rodzaju: naprawa"                                  || bad "brak sekcji naprawa"
has 'data-kind="zapytanie"' && ok "sekcja rodzaju: zapytanie"                                || bad "brak sekcji zapytanie"
has 'data-kind="zwrot"'     && ok "sekcja rodzaju: zwrot"                                    || bad "brak sekcji zwrot"
has 'mp-cfg-add'            && ok "przycisk '+ dodaj' obecny (add row)"                      || bad "brak przycisku dodaj"
has 'mp-cfg-remove'         && ok "przycisk usuwania wiersza obecny"                         || bad "brak przycisku usun"
has 'mp-cfg-key'            && ok "pole klucza wiersza obecne"                               || bad "brak pola klucz"
has 'mp-cfg-label'          && ok "pole etykiety wiersza obecne"                             || bad "brak pola etykieta"
has 'mp-cfg-body'           && ok "pole tresci (szablony) obecne"                            || bad "brak pola tresci szablonu"

# ── Fallback + kontrakt POST bez zmian ───────────────────────────────────────
has 'mp-cfg-advanced'       && ok "sekcja 'Zaawansowane: edytuj jako JSON' (fallback bez JS)" || bad "brak fallbacku JSON"
has 'name="payload"'        && ok "ukryte pole payload nadal obecne (ten sam handler)"        || bad "BRAK payload — kontrakt POST zlamany!"

# ── Prefill z istniejacej konfiguracji (nie pusty) ───────────────────────────
has 'zebranie_danych'       && ok "prefill: istniejacy krok checklisty (zebranie_danych) w polach" || bad "brak prefillu checklisty"

echo ""
echo "C18-CONFIG-FORM-RENDER: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
