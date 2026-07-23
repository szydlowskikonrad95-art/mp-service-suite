#!/usr/bin/env bash
# ZYWY DOWOD (kontrakt C->D): hook `mp_all_statuses` eksponuje PELNA liste statusow
# read-only = rdzen 7 (nieusuwalny) + wlasne z mp_registered_statuses. C = kanoniczne
# zrodlo (Statuses::all); panel admina D konsumuje przez ten hook (bez siegania w klase C).
# Exit 0 = OK.
set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

HAS=$(wp eval 'echo has_filter("mp_all_statuses")?"1":"0";' 2>/dev/null | tr -d '[:space:]')
[ "$HAS" = "1" ] && ok "hook mp_all_statuses zarejestrowany (C boot)" || bad "brak hooka mp_all_statuses"

CNT=$(wp eval '$s=apply_filters("mp_all_statuses", array()); echo count($s);' 2>/dev/null | tr -d '[:space:]')
[ "$CNT" = "7" ] && ok "pelna lista = rdzen 7 (bez wlasnych zdefiniowanych)" || bad "count=$CNT (oczek 7)"

T=$(wp eval '$s=apply_filters("mp_all_statuses", array()); echo ($s["nowe"]["terminal"]?"1":"0").($s["odrzucone"]["terminal"]?"1":"0").($s["zamknięte"]["terminal"]?"1":"0");' 2>/dev/null | tr -d '[:space:]')
[ "$T" = "011" ] && ok "terminalnosc wg FLAGI (nowe=0, odrzucone=1, zamknięte=1)" || bad "terminalnosc zla ($T, oczek 011)"

# wlasny status z mp_registered_statuses DOCHODZI do pelnej listy (rdzen + wlasne)
MERGE=$(wp eval 'add_filter("mp_registered_statuses", function($s){ $s=(array)$s; $s["test_wlasny"]=array("label"=>"Własny test","terminal"=>false); return $s; }); $s=apply_filters("mp_all_statuses", array()); echo (isset($s["test_wlasny"])?"1":"0").":".count($s);' 2>/dev/null | tr -d '[:space:]')
[ "$MERGE" = "1:8" ] && ok "wlasny status z mp_registered_statuses scalony (rdzen 7 + 1 wlasny = 8)" || bad "scalanie wlasnych zle ($MERGE, oczek 1:8)"

# rdzen NIEUSUWALNY: proba nadpisania 'nowe' przez filtr wlasnych nie zmienia terminalnosci rdzenia
GUARD=$(wp eval 'add_filter("mp_registered_statuses", function($s){ $s=(array)$s; $s["nowe"]=array("label"=>"HACK","terminal"=>true); return $s; }); $s=apply_filters("mp_all_statuses", array()); echo $s["nowe"]["terminal"]?"1":"0";' 2>/dev/null | tr -d '[:space:]')
[ "$GUARD" = "0" ] && ok "rdzen NIEUSUWALNY: filtr wlasnych NIE nadpisuje 'nowe' (terminal nadal 0)" || bad "rdzen nadpisany przez wlasne! ($GUARD)"

echo ""
echo "C-ALL-STATUSES: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
