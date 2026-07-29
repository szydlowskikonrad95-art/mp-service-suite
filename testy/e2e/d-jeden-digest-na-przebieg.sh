#!/usr/bin/env bash
# ZYWY DOWOD (audyt 29.07): zalegle eskalacje ida w JEDNEJ paczce, nie w dziesieciu.
#
# Co bylo zle: eskalacje szly ta sama paczka co przypomnienia (BATCH=50), a prog
# „zbiorczego maila" (`Sla::DIGEST_THRESHOLD`) liczy sie na PRZEKAZANEJ LISCIE.
# Po dluzszym przestoju 500 zaleglych eskalacji = 10 rund x 50 = DZIESIEC osobnych
# „zbiorczych" maili do koordynatora w ciagu jednego przebiegu (5 minut) — dokladnie
# ta lawina, przed ktora digest mial chronic.
#
# Przy okazji wyszlo drugie: gdy eskalacja NIE MOGLA sie wyslac (brak odbiorcy),
# stary kod kręcił sie 10 rund po TYCH SAMYCH sprawach i liczyl je wielokrotnie
# (licznik pokazywal 500 przy realnych 120).
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

ILE=120   # > BATCH(50), zeby stary podzial na paczki byl widoczny

# ── 0. Czysty stan + ILE zaleglych eskalacji ────────────────────────────────
wp eval '
	global $wpdb;
	$wpdb->query("DELETE FROM {$wpdb->prefix}mp_case_sla");
	$wpdb->query("DELETE FROM {$wpdb->prefix}mp_workflow_events");
	$past = gmdate("Y-m-d H:i:s", time() - 3600);
	for ( $i = 1; $i <= '"$ILE"'; $i++ ) {
		$wpdb->insert("{$wpdb->prefix}mp_case_sla", array(
			"case_id" => 9000 + $i, "status" => "nowe", "sla_policy_version" => 1,
			"deadline_at" => $past, "warning_at" => $past,
			"reminder_sent_at" => $past, "escalated_at" => null, "updated_at" => $past,
		));
	}
' >/dev/null 2>&1

DO_ESK=$(wp eval 'global $wpdb; echo (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->prefix}mp_case_sla WHERE escalated_at IS NULL");' 2>/dev/null | tr -d '[:space:]')
[ "$DO_ESK" = "$ILE" ] \
	&& ok "stan wyjsciowy: $ILE zaleglych eskalacji (wiecej niz jedna paczka po 50)" \
	|| bad "nie udalo sie przygotowac zaleglosci ($DO_ESK)"

# ── 1. SEDNO: caly zalegly zestaw w JEDNEJ rundzie ──────────────────────────
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1

PRZEBIEG=$(wp eval '
	global $wpdb;
	echo (string) $wpdb->get_var("SELECT payload FROM {$wpdb->prefix}mp_workflow_events
		WHERE event_type = \"SWEEP_RUN\" AND payload LIKE \"%rounds%\" ORDER BY id DESC LIMIT 1");
' 2>/dev/null)

# ⚠️ Wzorzec MUSI konczyc sie granica pola. `"rounds":1` pasuje tez do `"rounds":10`,
# wiec pierwsza wersja tej kontroli przechodzila na WADLIWYM kodzie (zlapane kalibracja).
echo "$PRZEBIEG" | grep -qE '"rounds":1[,}]' \
	&& ok "SEDNO: caly zestaw obsluzony w JEDNEJ rundzie (jeden zbiorczy mail, nie lawina)" \
	|| bad "przebieg poszedl w wielu rundach — grozi kilka „zbiorczych\" maili naraz ($PRZEBIEG)"

# ── 2. Licznik nie zawyza: tyle eskalacji, ile realnie bylo spraw ───────────
echo "$PRZEBIEG" | grep -q "\"escalations\":$ILE" \
	&& ok "licznik eskalacji = $ILE (tyle, ile realnie bylo spraw)" \
	|| bad "licznik eskalacji zawyzony — te same sprawy liczone wielokrotnie ($PRZEBIEG)"

# ── 3. Przypomnienia NIE dostaly wiekszego limitu (to jeden mail NA SPRAWE) ─
# Gdyby ktos „przy okazji" podniosl limit przypomnien, jeden przebieg moglby wyslac
# setki OSOBNYCH maili — eskalacja powyzej progu to jeden mail na cala liste, wiec
# tylko ONA moze miec wiekszy limit. Czytamy STALE Z KODU (refleksja), nie tekst
# z pliku: test chodzi z katalogu WordPressa, gdzie zrodel repo po prostu nie ma
# (pierwsza wersja tej kontroli grepowala plik i falszywie alarmowala).
STALE=$(wp eval '
	$r = new ReflectionClass( "MP\Automator\Sweep" );
	$b = $r->getConstant( "BATCH" );
	$e = $r->getConstant( "ESCALATION_BATCH" );
	echo ( false !== $b && false !== $e && $e > $b ) ? "ok:$b:$e" : "zle:$b:$e";
' 2>/dev/null | tr -d '[:space:]')
case "$STALE" in
	ok:*) ok "eskalacje maja WLASNY, wiekszy limit niz przypomnienia ($STALE)" ;;
	*)    bad "limity przypomnien i eskalacji rozjechaly sie ($STALE)" ;;
esac

# ── 4. Powtorny przebieg nie eskaluje tego samego drugi raz ────────────────
wp eval 'global $wpdb; $wpdb->query("UPDATE {$wpdb->prefix}mp_case_sla SET escalated_at = updated_at");' >/dev/null 2>&1
wp eval 'MP\Automator\Sweep::run();' >/dev/null 2>&1
DRUGI=$(wp eval '
	global $wpdb;
	echo (string) $wpdb->get_var("SELECT payload FROM {$wpdb->prefix}mp_workflow_events
		WHERE event_type = \"SWEEP_RUN\" AND payload LIKE \"%rounds%\" ORDER BY id DESC LIMIT 1");
' 2>/dev/null)
echo "$DRUGI" | grep -q '"escalations":0' \
	&& ok "sprawy juz eskalowane NIE ida drugi raz (idempotencja markera)" \
	|| bad "powtorny przebieg eskalowal ponownie — grozi dubel u koordynatora ($DRUGI)"

echo ""
echo "WYNIK JEDEN-DIGEST: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
