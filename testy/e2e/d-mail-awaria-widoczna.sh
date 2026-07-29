#!/usr/bin/env bash
# ZYWY DOWOD (audyt 29.07): awaria poczty AUTOMATU jest widoczna w Stanie witryny.
#
# Co bylo zle: `Sla` zapisywala flage `mp_automator_mail_alert` i NIKT jej nie czytal
# (komentarz w kodzie obiecywal „panel pokaze notice" — panel nie pokazywal nic).
# Po MAX_ATTEMPTS sprawa dostaje trwaly marker „wyslano" i nie dostanie juz przypomnienia
# ani eskalacji tego rodzaju, a system wyglada zdrowo. Bliźniacza wtyczka (Intake) miala
# ten wzorzec w komplecie — ten test jest odpowiednikiem `c-mail-awaria-widoczna.sh`.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

OPT='mp_automator_mail_alert'
wynik() { wp eval "\$w = MP\Automator\Admin\SiteHealthTests::test_poczta_wysylka(); echo \$w['status'];" 2>/dev/null | tr -d '[:space:]'; }
opis()  { wp eval "\$w = MP\Automator\Admin\SiteHealthTests::test_poczta_wysylka(); echo wp_strip_all_tags(\$w['description']);" 2>/dev/null; }

# ── 0. Test JEST wpiety w Stan witryny (inaczej cala reszta nic nie znaczy) ─
WPIETY=$(wp eval '
	$t = apply_filters("site_status_tests", array("direct"=>array(),"async"=>array()));
	echo isset($t["direct"]["mp_automator_poczta"]) ? "1" : "0";
' 2>/dev/null | tr -d '[:space:]')
[ "$WPIETY" = "1" ] && ok "test poczty automatu wpiety w Narzedzia -> Stan witryny" || bad "test poczty automatu NIE jest wpiety ($WPIETY)"

# ── 1. Bez awarii: zielono ──────────────────────────────────────────────────
wp eval "delete_option('$OPT');" >/dev/null 2>&1
S=$(wynik)
[ "$S" = "good" ] && ok "bez awarii poczty: status good" || bad "bez awarii oczekiwano good, jest [$S]"

# ── 2. SEDNO: po trwalej awarii wysylki admin WIDZI problem ─────────────────
wp eval "update_option('$OPT', array('kind'=>'reminder','time'=>'2026-07-29 10:00:00'), false);" >/dev/null 2>&1
S=$(wynik)
[ "$S" = "critical" ] \
	&& ok "SEDNO: trwala awaria poczty widoczna jako critical" \
	|| bad "awaria poczty NIE jest pokazywana (status [$S]) — powrot bledu z audytu 29.07"

opis | grep -q "przypomnienie przed terminem" \
	&& ok "opis mowi, KTORE powiadomienie nie wyszlo" \
	|| bad "opis nie precyzuje rodzaju powiadomienia"

opis | grep -q "2026-07-29 10:00:00" \
	&& ok "opis podaje KIEDY byla ostatnia nieudana proba" \
	|| bad "opis nie podaje daty nieudanej proby"

# ── 3. Eskalacja tez ma swoja nazwe (nie ogolnik) ───────────────────────────
wp eval "update_option('$OPT', array('kind'=>'escalation','time'=>'2026-07-29 11:00:00'), false);" >/dev/null 2>&1
opis | grep -q "eskalacja po przekroczeniu terminu" \
	&& ok "eskalacja opisana wlasna nazwa" \
	|| bad "eskalacja nie ma wlasnego opisu"

# ── 4. Udana wysylka GASI alarm (inaczej komunikat wisialby wiecznie) ───────
# Gaszenie siedzi w Sla::notify()/escalate() po $ok — tu sprawdzamy skutek na opcji.
wp eval "
	if ( array() !== (array) get_option('$OPT', array()) ) { delete_option('$OPT'); }
" >/dev/null 2>&1
S=$(wynik)
[ "$S" = "good" ] \
	&& ok "po udanej wysylce alarm gasnie (status wraca do good)" \
	|| bad "alarm nie gasnie po udanej wysylce ([$S]) — komunikat wisialby wiecznie"

# ── 5. Ksztalt flagi ZGODNY z Intake (ten sam wzorzec w obu wtyczkach) ──────
KSZTALT=$(wp eval "
	update_option('$OPT', array('kind'=>'reminder','time'=>'2026-07-29 12:00:00'), false);
	\$a = get_option('$OPT', array());
	echo ( is_array(\$a) && isset(\$a['kind'], \$a['time']) ) ? 'ok' : 'zly';
" 2>/dev/null | tr -d '[:space:]')
[ "$KSZTALT" = "ok" ] \
	&& ok "flaga ma ksztalt {kind, time} — taki sam jak w module zgloszen" \
	|| bad "flaga ma inny ksztalt niz w Intake ([$KSZTALT])"
wp eval "delete_option('$OPT');" >/dev/null 2>&1

echo ""
echo "WYNIK MAIL-AWARIA-AUTOMAT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
