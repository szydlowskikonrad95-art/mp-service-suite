#!/usr/bin/env bash
# ZYWY DOWOD P3.2 D-side (statusy: D = ZRODLO definicji, C = walidator przejsc):
# StatusDefs D publikuje statusy WLASNE przez filtr mp_registered_statuses;
# walidator C je widzi i przepuszcza zmiane statusu (REALNA droga mp_case_change_status).
# Rdzen 7 NIEUSUWALNY, kolizja slugow niemozliwa (sanitize_key vs diakrytyki rdzenia).
# Bez statusow wlasnych -> C zna dokladnie rdzen 7 (degraded). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
# Definicja statusu wlasnego przez PUBLICZNE API D (nie recznie do bazy).
defstat() { wp eval "echo MP\Automator\StatusDefs::upsert('$1', $2);" 2>/dev/null; }
# Zmiana statusu REALNA droga kontraktowa C (ten sam wywolanie co panel/silnik).
cs()  { wp eval "echo wp_json_encode( apply_filters('mp_case_change_status', null, $1, '$2', '$3', 1, $4) );" 2>/dev/null; }

# Tworzy+weryfikuje sprawe (status 'nowe'). Echo: case_id.
mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Czysty stan: kasuj definicje statusow wlasnych + sprawy + eventy ───────
wp eval "delete_option('mp_automator_status_defs');" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

# ── 1. DEGRADED baza: bez statusow wlasnych C zna DOKLADNIE rdzen 7 ───────────
CNT=$(wp eval 'echo count(MP\Intake\Statuses::all());' 2>/dev/null)
[ "$CNT" = "7" ] && ok "bez statusow wlasnych: C zna rdzen 7 (all()=7)" || bad "C.all()=$CNT (oczekiwano 7 — degraded)"

# ── 2. Status wlasny AKTYWNY -> filtr {label,terminal} -> walidator C go widzi ─
#   slug 'ekspertyza_zewn' = 15 znakow (MIESCI sie w VARCHAR(20) kolumny status C).
defstat "ekspertyza_zewn" "array('label'=>'Ekspertyza zewnętrzna','active'=>true,'terminal'=>false,'sla_hours'=>48,'warning_hours'=>12)" >/dev/null
INFLT=$(wp eval 'echo isset(apply_filters("mp_registered_statuses", array())["ekspertyza_zewn"]) ? "1":"0";' 2>/dev/null)
[ "$INFLT" = "1" ] && ok "status wlasny w filtrze mp_registered_statuses" || bad "status wlasny NIE w filtrze"
CEX=$(wp eval 'echo MP\Intake\Statuses::exists("ekspertyza_zewn") ? "1":"0";' 2>/dev/null)
[ "$CEX" = "1" ] && ok "walidator C widzi status wlasny (Statuses::exists=true)" || bad "C nie widzi statusu wlasnego"
CNT2=$(wp eval 'echo count(MP\Intake\Statuses::all());' 2>/dev/null)
[ "$CNT2" = "8" ] && ok "C.all()=8 (rdzen 7 + 1 wlasny)" || bad "C.all()=$CNT2 (oczekiwano 8)"

# ── 2b. GUARD dlugosci sluga = szerokosc kolumny status C (VARCHAR(20)) ───────
#   slug 21-znakowy MUSI byc odrzucony (D nie publikuje statusu, ktorego C by uciela).
LONG=$(defstat "ekspertyza_zewnetrzna" "array('label'=>'X','active'=>true,'terminal'=>false)")
[ -z "$LONG" ] && ok "slug 21-znakowy ODRZUCONY przez D (guard VARCHAR(20) kolumny C)" || bad "za dlugi slug przeszedl (slug=[$LONG]) — grozi truncacja w C!"
LONGSEEN=$(wp eval 'echo MP\Intake\Statuses::exists("ekspertyza_zewnetrzn") ? "1":"0";' 2>/dev/null)
[ "$LONGSEEN" = "0" ] && ok "uciety wariant sluga NIE trafil do walidatora C" || bad "uciety slug wyciekl do C"

# ── 3. Status NIEAKTYWNY nie jest publikowany (C go NIE zwaliduje) ────────────
defstat "wstrzymana" "array('label'=>'Wstrzymana','active'=>false,'terminal'=>false)" >/dev/null
INA=$(wp eval 'echo isset(apply_filters("mp_registered_statuses", array())["wstrzymana"]) ? "1":"0";' 2>/dev/null)
[ "$INA" = "0" ] && ok "status nieaktywny POMINIETY w filtrze (C go nie widzi)" || bad "status nieaktywny wyciekl do filtra"

# ── 4. Terminalnosc wg FLAGI (nie nazwy): wlasny terminalny -> C is_terminal ──
defstat "archiwum_wewnetrzne" "array('label'=>'Archiwum','active'=>true,'terminal'=>true)" >/dev/null
IT=$(wp eval 'echo MP\Intake\Statuses::is_terminal("archiwum_wewnetrzne") ? "1":"0";' 2>/dev/null)
[ "$IT" = "1" ] && ok "wlasny status terminalny: C is_terminal=true (flaga, nie nazwa)" || bad "flaga terminal nie dotarla do C"

# ── 5. KOLIZJA z rdzeniem NIEMOZLIWA: slug 'zamknięte' -> sanitize_key -> 'zamknite' ─
SLUG=$(defstat "zamknięte" "array('label'=>'PROBA-NADPISANIA','active'=>true,'terminal'=>false)")
[ "$SLUG" = "zamknite" ] && ok "upsert('zamknięte') zapisany jako 'zamknite' (sanitize_key zdjal ę)" || bad "slug po sanityzacji=[$SLUG] (oczekiwano zamknite)"
CORELBL=$(wp eval 'echo MP\Intake\Statuses::all()["zamknięte"]["label"];' 2>/dev/null)
[ "$CORELBL" = "zamknięte" ] && ok "rdzen 'zamknięte' NIETKNIETY (label != PROBA-NADPISANIA)" || bad "rdzen nadpisany! label=[$CORELBL]"
CORETERM=$(wp eval 'echo MP\Intake\Statuses::is_terminal("zamknięte") ? "1":"0";' 2>/dev/null)
[ "$CORETERM" = "1" ] && ok "rdzen 'zamknięte' nadal terminalny" || bad "rdzen 'zamknięte' stracil terminalnosc!"

# ── 6. REALNA DROGA: zmiana statusu na wlasny przechodzi walidacje C ──────────
CID=$(mkcase st@example.com STAT-1)
[ "$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")" = "nowe" ] && ok "sprawa 'nowe' (case_id=$CID)" || bad "sprawa nie 'nowe'"
R=$(cs "$CID" "ekspertyza_zewn" "nowe" "null")
echo "$R" | grep -q '"success":true' && ok "change_status nowe->ekspertyza_zewn: walidator C ZAAKCEPTOWAL status wlasny" || bad "zmiana na status wlasny odrzucona ($R)"
# ROUND-TRIP: status W BAZIE = doslownie to co wyslano (zero truncacji — pilnuje guard sluga).
[ "$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")" = "ekspertyza_zewn" ] && ok "status w bazie = 'ekspertyza_zewn' (round-trip bez truncacji)" || bad "status nie zmieniony/uciety w bazie"

# ── 7. CRUD statusu = wpis CONFIG_CHANGED w rejestrze operacji D (kto/kiedy) ──
CC=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='CONFIG_CHANGED' AND payload LIKE '%\"object\":\"status\"%'")
[ "$CC" -ge 1 ] 2>/dev/null && ok "CONFIG_CHANGED zapisany dla CRUD statusu ($CC szt.)" || bad "brak CONFIG_CHANGED dla statusu"

# ── 8. delete() zdejmuje status z publikacji (C przestaje go widziec) ─────────
wp eval "MP\Automator\StatusDefs::delete('archiwum_wewnetrzne');" >/dev/null 2>&1
GONE=$(wp eval 'echo MP\Intake\Statuses::exists("archiwum_wewnetrzne") ? "1":"0";' 2>/dev/null)
[ "$GONE" = "0" ] && ok "delete: status wlasny znika z walidatora C" || bad "status wlasny zostal po delete"

# ── Sprzatanie (nie zostawiaj smiecia na poligonie) ──────────────────────────
wp eval "delete_option('mp_automator_status_defs');" >/dev/null 2>&1
echo ""
echo "D-P32B-STATUSY-D: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
