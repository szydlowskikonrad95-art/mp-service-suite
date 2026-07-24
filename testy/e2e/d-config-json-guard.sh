#!/usr/bin/env bash
# ZYWY DOWOD (hardening PanelScreen D): walidacja JSON configu checklist/szablonow.
# BUG (audyt 24.07): bledny JSON w <textarea> => json_decode null => zapis PUSTEGO
# configu (cicha UTRATA istniejacej konfiguracji). FIX: bledny JSON przy niepustej
# tresci NIE nadpisuje (poprzednia zachowana) + redirect z komunikatem; puste pole =
# swiadome wyczyszczenie (dozwolone). Testuje handler wprost (rejestracja za is_admin).
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# ── 0. Uzytkownik system-admin (cap wymagany przez handler) ──────────────────
SADMIN=$(wp user get sadminq --field=ID 2>/dev/null)
[ -z "$SADMIN" ] && SADMIN=$(wp user create sadminq sadminq@example.com --role=mp_system_admin --user_pass=x --porcelain 2>/dev/null)
[ -n "$SADMIN" ] && ok "seed: system-admin (id=$SADMIN)" || bad "seed: brak system-admina"

# handler wolany WPROST (rejestracja admin-post za is_admin, w CLI=false); nonce w tym samym evalu.
save_cfg() { # $1=uid $2=Klasa(Checklist|Response) $3=nonce_action $4=payload
	wp eval "wp_set_current_user($1); \$n=wp_create_nonce('$3'); \$_POST['_wpnonce']=\$n; \$_REQUEST['_wpnonce']=\$n; \$_POST['payload']='$4'; MP\\Automator\\${2}Templates::handle_config();" >/dev/null 2>&1
}
cnt() { wp eval "echo count((array) get_option('$1', array()));" 2>/dev/null; }

# ══════════════════ CHECKLIST ══════════════════
OPT_CH='mp_automator_checklist_templates'
wp eval "update_option('$OPT_CH', array('reklamacja'=>array(array('key'=>'x','label'=>'X'))), false);" >/dev/null 2>&1
[ "$(cnt "$OPT_CH")" = "1" ] && ok "checklist: config bazowy ustawiony (1 rodzaj)" || bad "checklist: baza zla ($(cnt "$OPT_CH"))"

# BLEDNY JSON => config NIE nadpisany (poprzedni zachowany)
save_cfg "$SADMIN" Checklist mp_automator_checklist_config '{zepsuty-json'
[ "$(cnt "$OPT_CH")" = "1" ] && ok "checklist: BLEDNY JSON nie skasowal configu (zachowany, 1 rodzaj)" || bad "checklist: bledny JSON WYCZYSCIL config!! ($(cnt "$OPT_CH"))"

# JSON = nie-obiekt (np. liczba) tez traktowany jak blad => zachowany
save_cfg "$SADMIN" Checklist mp_automator_checklist_config '12345'
[ "$(cnt "$OPT_CH")" = "1" ] && ok "checklist: JSON nie-obiekt (liczba) tez nie kasuje" || bad "checklist: nie-obiekt skasowal ($(cnt "$OPT_CH"))"

# PUSTE pole => swiadome wyczyszczenie (dozwolone, zapisuje pusty)
save_cfg "$SADMIN" Checklist mp_automator_checklist_config ''
[ "$(cnt "$OPT_CH")" = "0" ] && ok "checklist: puste pole = swiadome wyczyszczenie (config pusty)" || bad "checklist: puste nie wyczyscilo ($(cnt "$OPT_CH"))"

# ══════════════════ RESPONSE ══════════════════
OPT_RE='mp_automator_response_templates'
wp eval "update_option('$OPT_RE', array('naprawa'=>array(array('key'=>'k','label'=>'L','body'=>'B'))), false);" >/dev/null 2>&1
[ "$(cnt "$OPT_RE")" = "1" ] && ok "response: config bazowy ustawiony (1 rodzaj)" || bad "response: baza zla ($(cnt "$OPT_RE"))"

save_cfg "$SADMIN" Response mp_automator_response_config '{tez-zepsuty'
[ "$(cnt "$OPT_RE")" = "1" ] && ok "response: BLEDNY JSON nie skasowal configu" || bad "response: bledny JSON WYCZYSCIL config!! ($(cnt "$OPT_RE"))"

save_cfg "$SADMIN" Response mp_automator_response_config ''
[ "$(cnt "$OPT_RE")" = "0" ] && ok "response: puste pole = swiadome wyczyszczenie" || bad "response: puste nie wyczyscilo ($(cnt "$OPT_RE"))"

echo ""
echo "CONFIG-JSON-GUARD: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
