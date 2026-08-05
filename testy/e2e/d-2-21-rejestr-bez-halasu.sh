#!/usr/bin/env bash
# ZYWY DOWOD 2.21: produkt przestaje zasypywac wlasny rejestr swoim ruchem —
# ale NIE traci przy tym odpowiedzi na pytanie „czy cron w ogole chodzi".
#
# BUG (audyt 2.21, waga srednia): rejestry zdarzen sa APPEND-ONLY z ZALOZENIA
# i to jest wymog ze specyfikacji, nie przeoczenie — dziennik rozliczalnosci nie moze
# miec kasowania. Wada nie polega wiec na braku DELETE, tylko na tym, ze produkt
# sam ten dziennik zasypuje: zdarzenie przebiegu zamiatarki ksiegowane bylo
# CO PIEC MINUT, czyli 105 120 wierszy rocznie na instalacji, na ktorej nikt nie
# zlozyl ani jednego zgloszenia. To ruch WLASNY produktu, nie ruch klienta.
#
# ⛔ KOLEJNOSC NAPRAWY BYLA CZESCIA POPRAWNOSCI: „czy zadanie sie wykonuje"
# Stan witryny czytal WLASNIE z tych wpisow. Najpierw wiec bicie serca w opcji,
# potem przelaczenie Stanu witryny na nie, i DOPIERO potem cisza w rejestrze.
# Odwrotna kolejnosc naprawilaby rachunek za miejsce i po cichu zepsula
# diagnostyke — a cicho zepsuta diagnostyka jest gorsza niz pelny rejestr,
# bo wtedy nikt sie nie dowie, ze pilnowanie terminow stanelo.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

BICIE='mp_automator_sweep_heartbeat'

ile_sweep_run() { q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='SWEEP_RUN'"; }
stan_crona()    { wp eval 'echo (string) ( MP\Automator\Admin\SiteHealthTests::test_cron()["status"] ?? "brak" );' 2>/dev/null | tr -d '[:space:]'; }

# ── 0. Stan zastany ─────────────────────────────────────────────────────────
BICIE_ZASTANE=$(wp option get "$BICIE" 2>/dev/null | tr -d '[:space:]')
wp eval "delete_option('$BICIE');" >/dev/null 2>&1

# ⚠️ NAJPIERW OPROZNIAMY ZALEGLOSCI, dopiero potem mierzymy „cichy przebieg".
# Pierwsza wersja tego testu kasowala wszystkie wiersze terminow i mierzyla
# nastepny przebieg jako cichy — a ten ratowal wtedy sprawy bez terminu, czyli
# ROBIL ROBOTE i slusznie zostawial wpis. Mierzylabym wlasne przygotowanie.
for _ in 1 2 3; do wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1; done

# ── 1. SEDNO: cichy przebieg NIE dokłada wiersza do rejestru ────────────────
PRZED=$(ile_sweep_run)
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1
PO=$(ile_sweep_run)
[ "${PO:-1}" = "${PRZED:-0}" ] \
	&& ok "przebieg bez pracy NIE dokłada wiersza do rejestru (rejestr: $PO)" \
	|| bad "cichy przebieg dopisal wiersz ($PRZED -> $PO) — to jest wada 2.21"

# ── 2. ...ale ZOSTAWIA bicie serca, czyli dowod, ze chodzil ─────────────────
BICIE_PO=$(wp option get "$BICIE" 2>/dev/null | tr -d '[:space:]')
[ -n "$BICIE_PO" ] \
	&& ok "cichy przebieg zostawil bicie serca ($BICIE_PO)" \
	|| bad "brak bicia serca — nie ma jak stwierdzic, ze cron chodzil"

# ── 3. Bicie serca jest NADPISYWANE, nie dopisywane ─────────────────────────
ILE_WIERSZY=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name='$BICIE'")
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1
ILE_WIERSZY2=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name='$BICIE'")
{ [ "$ILE_WIERSZY" = "1" ] && [ "$ILE_WIERSZY2" = "1" ]; } \
	&& ok "bicie serca to JEDNA nadpisywana wartosc (nie rosnie z kazdym przebiegiem)" \
	|| bad "bicie serca sie mnozy ($ILE_WIERSZY -> $ILE_WIERSZY2)"

# ── 4. DIAGNOSTYKA ZOSTAJE: swieze bicie => Stan witryny spokojny ──────────
STAN=$(stan_crona)
[ "$STAN" != "critical" ] \
	&& ok "swieze bicie serca => Stan witryny nie alarmuje (status=$STAN)" \
	|| bad "Stan witryny alarmuje mimo swiezego przebiegu (status=$STAN)"

# ── 5. DIAGNOSTYKA DZIALA: stare bicie => Stan witryny ALARMUJE ────────────
# To jest kontrola, ktora pilnuje, ze nie naprawilismy rachunku za miejsce
# kosztem diagnostyki. Cofamy bicie serca o godzine (prog to dwa interwaly).
wp eval "update_option('$BICIE', gmdate('Y-m-d H:i:s', time() - 3600), false);" >/dev/null 2>&1
STAN_STARY=$(stan_crona)
[ "$STAN_STARY" = "critical" ] \
	&& ok "stare bicie serca => Stan witryny KRZYCZY, ze pilnowanie terminow stoi" \
	|| bad "Stan witryny nie zauwazyl, ze cron stanal (status=$STAN_STARY) — diagnostyka zepsuta"

# ── 5b. Rejestr NIE ROZSTRZYGA JUZ w druga strone ──────────────────────────
# Pytanie kontrolne: czy diagnostyka czyta OBA zrodla i wystarcza jej jedno?
# Gdyby tak bylo, stary wpis w rejestrze uspokajalby ja mimo martwego bicia
# serca — albo swieze bicie nie przebijaloby starego wpisu. Sprawdzamy OBIE
# strony: tu swieze bicie + STARY rejestr ma dawac spokoj (rejestr nie alarmuje).
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1
wp db query "UPDATE wp_mp_workflow_events SET created_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL 60 MINUTE) WHERE event_type='SWEEP_RUN'" >/dev/null 2>&1
STAN_MIESZANY=$(stan_crona)
[ "$STAN_MIESZANY" = "good" ] \
	&& ok "swieze bicie serca przebija stary wpis w rejestrze (rejestr juz nie rozstrzyga)" \
	|| bad "stary wpis w rejestrze psuje ocene mimo swiezego bicia serca (status=$STAN_MIESZANY)"

# ── 6. ZAPAS dla instalacji sprzed tej wersji: brak bicia => czyta rejestr ──
wp eval "delete_option('$BICIE');" >/dev/null 2>&1
wp eval 'MP\Automator\WorkflowEvents::log( MP\Automator\WorkflowEvents::SWEEP_RUN, array( "test" => 1 ), null );' >/dev/null 2>&1
wp db query "UPDATE wp_mp_workflow_events SET created_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL 60 MINUTE) WHERE event_type='SWEEP_RUN' ORDER BY id DESC LIMIT 1" >/dev/null 2>&1
STAN_ZAPAS=$(stan_crona)
[ "$STAN_ZAPAS" = "critical" ] \
	&& ok "bez bicia serca Stan witryny nadal czyta rejestr (aktualizacja nie oslepia go)" \
	|| bad "po aktualizacji, przed pierwszym przebiegiem, Stan witryny przestal widziec historie (status=$STAN_ZAPAS)"

# ── 7. Przebieg, ktory COS ZROBIL, nadal zostawia wpis w rejestrze ─────────
# Cisza dotyczy WYLACZNIE przebiegow bez pracy — dziennik rozliczalnosci ma
# dalej notowac to, co sie naprawde wydarzylo.
wp db query "DELETE FROM wp_mp_workflow_events WHERE event_type='SWEEP_RUN'" >/dev/null 2>&1
PAST=$(q "SELECT DATE_SUB(UTC_TIMESTAMP(), INTERVAL 60 MINUTE)")
wp db query "INSERT INTO wp_mp_case_sla (case_id, status, sla_policy_version, deadline_at, warning_at, reminder_sent_at, updated_at) VALUES (880001, 'nowe', 1, '$PAST', '$PAST', '$PAST', '$PAST')" >/dev/null 2>&1
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1
PO_PRACY=$(ile_sweep_run)
[ "${PO_PRACY:-0}" -ge 1 ] 2>/dev/null \
	&& ok "przebieg, ktory cos zrobil, ZOSTAWIA wpis w rejestrze (rozliczalnosc bez zmian)" \
	|| bad "przebieg z praca nie zostawil sladu — cisza poszla za daleko"

# ── 8. SPRZATANIE ZE SPRAWDZENIEM ─────────────────────────────────────────
wp db query "DELETE FROM wp_mp_case_sla WHERE case_id=880001; DELETE FROM wp_mp_workflow_events WHERE event_type='SWEEP_RUN'" >/dev/null 2>&1
if [ -n "$BICIE_ZASTANE" ]; then
	wp eval "update_option('$BICIE', '$BICIE_ZASTANE', false);" >/dev/null 2>&1
else
	wp eval "delete_option('$BICIE');" >/dev/null 2>&1
fi
BICIE_KONIEC=$(wp option get "$BICIE" 2>/dev/null | tr -d '[:space:]')
[ "${BICIE_KONIEC:-}" = "${BICIE_ZASTANE:-}" ] \
	&& ok "bicie serca oddane w stanie zastanym" \
	|| bad "zostawiamy inne bicie serca niz zastane"

ZOSTALO=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=880001")
[ "${ZOSTALO:-1}" = "0" ] \
	&& ok "podlozony wiersz terminu usuniety" \
	|| bad "zostawiamy podlozony wiersz terminu"

echo ""
echo "WYNIK 2.21: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
