#!/usr/bin/env bash
# ZYWY DOWOD P3.3 dedup-okno: identyczny mail (adresat+WYRENDEROWANA tresc) w oknie
# jest POMIJANY (MAIL_DEDUPED); dwie ROZNE informacje NIGDY nie sa dedupowane.
# Okno konfigurowalne per typ (wiadomosci 300 s, domyslne 60 s). Rezerwacja jest
# ATOMOWA — ta sama, co przy dedupie zgloszen w module C (2.23); transient zostaje
# tylko jako droga ratunkowa przy braku modulu C.
# Exit 0 = OK.
set -u

# Sprzatanie NA WEJSCIU (pulapka #6: zostawiona rezerwacja dedupu wywala powtorke
# testu w miejscu bez zwiazku ze zmiana). To samo na wyjsciu, nizej.
sprzatnij_dedup() {
	wp db query "DELETE FROM wp_mp_rate_counters WHERE rl_key LIKE 'mp_adedup_%'" >/dev/null 2>&1
	wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"%transient%mp_adedup%\"") as $o) delete_option($o);' >/dev/null 2>&1
}
sprzatnij_dedup

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
CAP="$(wp eval 'echo WP_CONTENT_DIR;' 2>/dev/null)/mp-mail-capture.jsonl"
capclear() { : > "$CAP"; }
capcount() { if [ -s "$CAP" ]; then grep -c '' "$CAP" 2>/dev/null; else echo 0; fi; }

mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Okna dedupu (jednostkowo) ─────────────────────────────────────────────
W1=$(wp eval 'echo MP\Automator\MailDedup::window_for("status_changed_client");' 2>/dev/null)
[ "$W1" = "60" ] && ok "okno domyslne = 60 s (status_changed_client)" || bad "zle okno domyslne ($W1)"
W2=$(wp eval 'echo MP\Automator\MailDedup::window_for("message_from_client");' 2>/dev/null)
[ "$W2" = "300" ] && ok "okno wiadomosci = 300 s (anty-spam: 5 wiad w 3 min != 5 maili)" || bad "zle okno wiadomosci ($W2)"
# override z opcji
wp eval 'update_option("mp_automator_dedup_windows", array("status_changed_client"=>10));' >/dev/null 2>&1
W3=$(wp eval 'echo MP\Automator\MailDedup::window_for("status_changed_client");' 2>/dev/null)
[ "$W3" = "10" ] && ok "override z opcji dziala (10 s)" || bad "override nie zadzialal ($W3)"
wp eval 'delete_option("mp_automator_dedup_windows");' >/dev/null 2>&1

# claim: okno 0 = brak dedupu; drugi identyczny w oknie = false
C1=$(wp eval 'echo MP\Automator\MailDedup::claim("a@b.com","tresc X",0) ? "1":"0";' 2>/dev/null)
[ "$C1" = "1" ] && ok "okno=0 => dedup wylaczony (zawsze wolno)" || bad "okno=0 blokuje"
K1=$(wp eval 'echo MP\Automator\MailDedup::claim("z@b.com","body1",60) ? "1":"0";' 2>/dev/null)
K2=$(wp eval 'echo MP\Automator\MailDedup::claim("z@b.com","body1",60) ? "1":"0";' 2>/dev/null)
K3=$(wp eval 'echo MP\Automator\MailDedup::claim("z@b.com","body2",60) ? "1":"0";' 2>/dev/null)
{ [ "$K1" = "1" ] && [ "$K2" = "0" ] && [ "$K3" = "1" ]; } && ok "claim: 1. wolno, 2. identyczny=BLOK, inny body=wolno" || bad "claim zle dziala ($K1$K2$K3)"

# dedup_key POMIJA zmienny {{data}} (H:i) — fix flaky granicy minuty. Body do wyslania
# niesie prawdziwa date; klucz dedupu zostawia {{data}} literalne => stabilny w czasie.
DKS=$(wp eval '$r = MP\Automator\MailTemplates::render("status_changed_client", array("case_number"=>"SRV/2026/9999","status"=>"w analizie")); echo ( is_array($r) && false !== strpos($r["dedup_key"], "{{data}}") && false === strpos($r["body"], "{{data}}") ) ? "OK" : "NO";' 2>/dev/null)
[ "$DKS" = "OK" ] && ok "dedup_key stabilny: body niesie date, dedup_key pomija {{data}} (fix flaky d-p33d)" || bad "dedup_key nie pomija {{data}} ($DKS)"

# ── 1. Integracja: ten sam status_changed 2x w oknie => 1 mail + MAIL_DEDUPED ─
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'delete_option("mp_automator_seed_version"); delete_option("mp_automator_mail_templates"); MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1
CID=$(mkcase dedup@example.com DED-1)
capclear
wp eval "apply_filters('mp_case_change_status', null, $CID, 'w analizie', 'nowe', 1, null);" >/dev/null 2>&1
# ponowna IDENTYCZNA emisja status_changed (ten sam old->new, ta sama minuta => identyczny body)
wp eval "do_action('mp_case_status_changed', $CID, 'nowe', 'w analizie', 1);" >/dev/null 2>&1
[ "$(capcount)" = "1" ] && ok "2x identyczna zmiana w oknie => DOKLADNIE 1 mail (2. zdedupowany)" || bad "dedup nie zadzialal ($(capcount) maili)"
MD=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE case_id=$CID AND event_type='MAIL_DEDUPED'")
[ "$MD" = "1" ] && ok "MAIL_DEDUPED zaksiegowany (audyt: czemu klient nie dostal 2. maila)" || bad "brak MAIL_DEDUPED ($MD)"

# ── 2. ROZNY status w oknie => osobny mail (rozne informacje NIGDY dedupowane) ─
capclear
wp eval "apply_filters('mp_case_change_status', null, $CID, 'zaakceptowane', 'w analizie', 1, null);" >/dev/null 2>&1
[ "$(capcount)" = "1" ] && ok "rozny status w oknie => osobny mail (inny body, nie dedupowany)" || bad "rozna informacja zdedupowana! ($(capcount))"

# NO-PII w MAIL_DEDUPED
PAY=$(q "SELECT payload FROM wp_mp_workflow_events WHERE event_type='MAIL_DEDUPED' LIMIT 1")
echo "$PAY" | grep -q 'dedup@example.com' && bad "adres w logu MAIL_DEDUPED (PII!)" || ok "MAIL_DEDUPED bez adresu (NO-PII)"

# ── 3. POZYCJA 2.23: JEDNA odpowiedz produktu na „nie zrob tego dwa razy" ────
# Co bylo zle: ten sam problem byl rozwiazany w dwoch modulach na dwa sposoby i z
# dwoma poziomami pewnosci. Modul C odsiewa podwojne zgloszenia ATOMOWA rezerwacja
# klucza w tabeli (wp_mp_rate_counters), a modul D odsiewal podwojne maile
# transientem, czyli sprawdz-potem-zapisz. Dwa rownolegle zadania (cron i klikniecie,
# dwa wywolania webhooka) widzialy pusty klucz OBA i wysylaly ten sam mail dwa razy.
sprzatnij_dedup

# (a) Rezerwacja maila laduje w TEJ SAMEJ atomowej tabeli, co rezerwacja zgloszenia.
wp eval 'MP\Automator\MailDedup::claim("spojnosc@example.com","tresc spojnosci",60);' >/dev/null 2>&1
REZ=$(q "SELECT COUNT(*) FROM wp_mp_rate_counters WHERE rl_key LIKE 'mp_adedup_%'")
[ "$REZ" = "1" ] \
	&& ok "SEDNO 2.23: rezerwacja maila idzie tym samym mechanizmem, co dedup zgloszen (jedna tabela, jedna odpowiedz)" \
	|| bad "mail dedupuje sie inaczej niz zgloszenia — dwa mechanizmy, dwa poziomy pewnosci ($REZ)"

# (b) PRAWDZIWY WYSCIG: 6 rownoleglych procesow probuje wyslac te same 30 maili.
# Procesy startuja rownoczesnie (czekaja do wspolnego znacznika czasu), zeby zderzyc
# sie naprawde. Kazdy mail ma wyjsc DOKLADNIE RAZ: 30 zgod, zero maili przepuszczonych
# dwa razy. Na kodzie sprzed naprawy: 124 zgody i 29 maili wyslanych wielokrotnie.
sprzatnij_dedup
TMPD=$(mktemp -d)
START=$(( $(date +%s) + 3 ))
for i in 1 2 3 4 5 6; do
	wp eval "
		\$s = $START;
		while ( time() < \$s ) { usleep( 2000 ); }
		// Wynik kazdej proby leci NA BIEZACO — gdyby proces mial padnac w polowie,
		// jego dotychczasowe zgody sa juz policzone. Inaczej test mylilby zgubiona
		// rezerwacje z procesem, ktory umarl i zabral swoj wynik.
		for ( \$n = 1; \$n <= 30; \$n++ ) {
			if ( MP\\Automator\\MailDedup::claim( 'wyscig@example.com', 'mail $START nr ' . \$n, 60 ) ) {
				echo \$n . \"\\n\";
				flush();
			}
		}
	" >"$TMPD/$i" 2>/dev/null &
done
wait
ZGODY=$(cat "$TMPD"/* 2>/dev/null | grep -c '[0-9]')
KOLIZJE=$(cat "$TMPD"/* 2>/dev/null | grep '[0-9]' | sort | uniq -d | grep -c '[0-9]')
rm -rf "$TMPD"
# Dowod ma pokazac TRZY rzeczy, w tej kolejnosci:
#  1. ZADNA rezerwacja nie ginie — tyle maili wychodzi, ile powinno (30 z 30).
#     Zgubiona rezerwacja znaczy, ze mail nie poszedl do NIKOGO, a nikt sie o tym
#     nie dowiedzial. Na kodzie sprzed naprawy ginelo 1-4 na kazde 30.
#  2. Dalej NIE MA dubla — po to ten mechanizm w ogole istnieje. Przed naprawa
#     dubel wychodzil realnie, ok. raz na 90-180 kluczy.
#  3. Bez nacisku nic sie nie zmienilo (nizej, punkt c).
{ [ "$ZGODY" = "30" ] && [ "$KOLIZJE" = "0" ]; } \
	&& ok "SEDNO 2.23: 6 procesow x 30 maili rownolegle => KAZDY mail wyszedl DOKLADNIE raz (30 zgod, 0 kolizji)" \
	|| bad "wyscig: $ZGODY zgod na 30 maili, $KOLIZJE przepuszczonych wiecej niz raz — zgubiona rezerwacja to mail, ktory nie poszedl do nikogo"
[ "$KOLIZJE" = "0" ] \
	&& ok "zaden mail nie wyszedl dwa razy (to jest jedyny powod, dla ktorego ta rezerwacja istnieje)" \
	|| bad "$KOLIZJE maili wyszlo wiecej niz raz — klient dostaje dublet"

# (c) Semantyka bez zmian: inna tresc w tym samym oknie przechodzi.
INNA=$(wp eval "echo MP\\Automator\\MailDedup::claim( 'wyscig@example.com', 'INNA tresc $START', 60 ) ? '1' : '0';" 2>/dev/null)
[ "$INNA" = "1" ] \
	&& ok "inna tresc w tym samym oknie dalej przechodzi (dedup lapie duplikaty, nie rozne informacje)" \
	|| bad "inna tresc zablokowana — dedup lapie za szeroko ($INNA)"

# BEZ NACISKU nic sie nie zmienilo: jeden proces, ten sam klucz trzy razy pod rzad
# => pierwszy przechodzi, dwa kolejne odbijaja sie; inny klucz przechodzi.
BEZ_NACISKU=$(wp eval "
	\$k = 'spokojny $START';
	\$a = MP\\Automator\\MailDedup::claim( 'spokoj@example.com', \$k, 60 ) ? '1' : '0';
	\$b = MP\\Automator\\MailDedup::claim( 'spokoj@example.com', \$k, 60 ) ? '1' : '0';
	\$c = MP\\Automator\\MailDedup::claim( 'spokoj@example.com', \$k, 60 ) ? '1' : '0';
	\$d = MP\\Automator\\MailDedup::claim( 'spokoj@example.com', \$k . ' inny', 60 ) ? '1' : '0';
	echo \$a . \$b . \$c . \$d;
" 2>/dev/null | tr -d '[:space:]')
[ "$BEZ_NACISKU" = "1001" ] \
	&& ok "bez nacisku zachowanie bez zmian: 1. przechodzi, 2. i 3. odbite, inna tresc przechodzi" \
	|| bad "zachowanie bez nacisku sie zmienilo ($BEZ_NACISKU, oczekiwane 1001)"

sprzatnij_dedup
POZOSTALO=$(q "SELECT COUNT(*) FROM wp_mp_rate_counters WHERE rl_key LIKE 'mp_adedup_%'")
[ "$POZOSTALO" = "0" ] \
	&& ok "test posprzatal rezerwacje po sobie (wspolna baza w CI)" \
	|| bad "zostaly rezerwacje dedupu — nastepny test dostanie falszywy duplikat ($POZOSTALO)"

capclear
echo ""
echo "D-P33D-DEDUP: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
