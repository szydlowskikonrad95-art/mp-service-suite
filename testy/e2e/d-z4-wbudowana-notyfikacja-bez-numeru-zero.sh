#!/usr/bin/env bash
# ZYWY DOWOD Z4 (polowanie 2026-08-05, S2): rejestr zdarzen automatu pokazywal
# „reguła nr: 0" dla WBUDOWANEJ notyfikacji przydzialu (RuleEngine::notify_assignment
# i Sla loguja rule_id=0, bo wpis nie pochodzi z tabeli regul) — a tabela regul
# numeruje od 1, wiec czytelnik szukal reguly, ktorej nie ma. FIX: payload_summary
# tlumaczy rule_id=0 na „reguła: wbudowana" zamiast pokazywac numer-widmo.
#
# Kalibracja WBUDOWANA: asserty 1 i 2 PADAJA na kodzie sprzed naprawy
# („reguła nr: 0" bylo renderowane doslownie). Assert 3 to kontrola kierunku:
# prawdziwa regula z tabeli MA zachowac swoj numer.
#
# Metoda prywatna — refleksja, jak w c-wyglad-rejestr-zdarzen.sh: mierzymy
# DOKLADNIE ten napis, ktory zobaczy czlowiek w kolumnie Szczegoly.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

wywolaj() { # <payload JSON w apostrofach PHP>
	wp eval "\$m = new ReflectionMethod('MP\\Automator\\Admin\\PanelScreen', 'payload_summary'); \$m->setAccessible(true); echo \$m->invoke(null, $1);" 2>/dev/null
}

# Payload 1:1 z wpisu wbudowanej notyfikacji przydzialu (RuleEngine::notify_assignment).
WBUDOWANA=$(wywolaj "'{\"rule_id\":0,\"trigger\":\"assigned\",\"action\":\"notify\",\"template_key\":\"assignment_notify\",\"recipient_ref\":\"agent\",\"result\":\"success\",\"depth\":0}'")

case "$WBUDOWANA" in
	*"reguła nr: 0"*) bad "1: rejestr dalej pokazuje regule-widmo „reguła nr: 0”: „$WBUDOWANA”" ;;
	*) ok "1: „reguła nr: 0” zniknela z opisu wbudowanej notyfikacji" ;;
esac

case "$WBUDOWANA" in
	*wbudowan*) ok "2: wbudowana notyfikacja nazwana po imieniu: „$WBUDOWANA”" ;;
	*) bad "2: opis nie mowi, ze to wpis wbudowany: „$WBUDOWANA”" ;;
esac

# Reszta szczegolow wpisu ma przezyc zmiane etykiety.
case "$WBUDOWANA" in
	*"szablon: assignment_notify"*) ok "2b: pozostale szczegoly wpisu (szablon) nietkniete" ;;
	*) bad "2b: zmiana etykiety zgubila pozostale szczegoly: „$WBUDOWANA”" ;;
esac

# ── KONTROLA KIERUNKU: prawdziwa regula z tabeli MA zachowac numer ───────────
# Gdyby naprawa chowala numer KAZDEJ reguly, powyzsze tez by przeszlo,
# a rejestr przestalby mowic, ktora regula zadzialala.
Z_TABELI=$(wywolaj "'{\"rule_id\":3,\"trigger\":\"status_changed\",\"action\":\"notify\",\"template_key\":\"status_update\"}'")

case "$Z_TABELI" in
	*"reguła nr: 3"*) ok "3: regula z tabeli zachowala swoj numer: „$Z_TABELI”" ;;
	*) bad "3: regula z tabeli stracila numer: „$Z_TABELI”" ;;
esac

echo "── Z4: PASS=$PASS FAIL=$FAIL ──"
# Straznik kompletu: wszystko idzie przez wp eval — cichy brak startu swiecilby zielono.
if [ "$(( PASS + FAIL ))" -lt 4 ]; then
	echo "  BLAD PRZEBIEGU: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane 4."
	exit 2
fi
[ "$FAIL" -eq 0 ]
