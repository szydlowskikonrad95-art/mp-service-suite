#!/usr/bin/env bash
# ZYWY DOWOD 2.26: identyfikator statusu wlasnego POWSTAJE z tego, co wpisal
# czlowiek — nie zostaje po nim okrojony.
#
# BUG (audyt 2.26, waga srednia): kontrakt produktu mowi, ze identyfikator statusu
# przechodzi przez `sanitize_key` (male litery, cyfry, podkreslenie, lacznik).
# Ta funkcja polskie znaki i spacje USUWA, wiec „W realizacji" dawalo `wrealizacji`,
# a „Do uzupełnienia" — `douzupenienia`. Cicho i nie do odczytania przez czlowieka.
#
# ⭐ WZORZEC NIE JEST WYMYSLONY: kategorie produktow w sasiednim module maja klucz
# `elektronarzedzia` przy etykiecie „Elektronarzędzia" — ktos swiadomie napisal go
# bez ogonka, zeby przezyl normalizacje. Robimy to samo, tylko maszynowo.
#
# ⛔ CZEGO TA POZYCJA NIE OBEJMUJE: siedmiu statusow RDZENIA z kartki („zamknięte",
# „w naprawie"...). Sa zaszyte w module zgloszen i zapisane w wierszach spraw —
# ich zmiana to MIGRACJA DANYCH, nie poprawka nazwy. Kontrola nr 5 pilnuje, ze
# zostaly nietkniete, a kontrola nr 4 — ze nadal nie da sie ich nadpisac.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

slug() { wp eval "echo MP\\Automator\\StatusDefs::slug_from_input( '$1' );" 2>/dev/null | tr -d '[:space:]'; }

# ── 1. SEDNO: polskie znaki ZAMIENIANE, spacje staja sie lacznikiem ─────────
[ "$(slug 'W realizacji')" = "w-realizacji" ] \
	&& ok "W realizacji -> w-realizacji (bylo: wrealizacji)" \
	|| bad "W realizacji -> [$(slug 'W realizacji')] — spacja nadal zjadana (to jest wada 2.26)"

[ "$(slug 'Do uzupełnienia')" = "do-uzupelnienia" ] \
	&& ok "Do uzupelnienia -> do-uzupelnienia (bylo: douzupenienia)" \
	|| bad "Do uzupelnienia -> [$(slug 'Do uzupełnienia')] — ogonek nadal znika"

[ "$(slug 'Zamknięte')" = "zamkniete" ] \
	&& ok "Zamkniete -> zamkniete (ogonek zamieniony, nie zjedzony)" \
	|| bad "Zamkniete -> [$(slug 'Zamknięte')]"

# ── 2. Wynik nadal SPELNIA kontrakt (male litery, cyfry, _ i -) ────────────
WYNIK=$(slug 'Ćwiczenie 2 — WERSJA robocza')
printf '%s' "$WYNIK" | grep -qE '^[a-z0-9_-]+$' \
	&& ok "identyfikator nadal zgodny z kontraktem ($WYNIK)" \
	|| bad "identyfikator lamie kontrakt ($WYNIK)"

# ── 3. Puste i smieciowe wejscie nie tworzy statusu-widma ──────────────────
[ -z "$(slug '   ')" ] && ok "same spacje => pusty identyfikator (status nie powstaje)" || bad "spacje daly identyfikator [$(slug '   ')]"
[ -z "$(slug '###')" ] && ok "same znaki specjalne => pusty identyfikator" || bad "smiec dal identyfikator [$(slug '###')]"

# ── 4. KOLIZJA Z RDZENIEM nadal niemozliwa ────────────────────────────────
# Nazwa statusu rdzenia z kartki po przejsciu przez regule daje INNY identyfikator,
# wiec status wlasny nie ma jak nadpisac rdzeniowego.
[ "$(slug 'zamknięte')" != "zamknięte" ] \
	&& ok "status wlasny nazwany jak rdzeniowy dostaje INNY identyfikator (brak nadpisania)" \
	|| bad "status wlasny moze nadpisac rdzeniowy!"

# ── 5. STATUSY RDZENIA NIETKNIETE (swiadomie poza zakresem tej naprawy) ───
RDZEN=$(wp eval 'echo implode( ",", array_keys( MP\Intake\Statuses::all() ) );' 2>/dev/null)
printf '%s' "$RDZEN" | grep -q "zamknięte" \
	&& ok "statusy rdzenia z kartki nietkniete (zadnej migracji danych przy okazji)" \
	|| bad "zmienily sie identyfikatory rdzenia — to migracja, nie poprawka nazwy ($RDZEN)"

echo ""
echo "WYNIK 2.26: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
