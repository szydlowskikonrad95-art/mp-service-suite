#!/usr/bin/env bash
# C26 — trzy dziury WIDOKU zlapane przy robieniu zrzutow do instrukcji klienta:
#  1. ZWROT na liscie spraw pokazywal „— bez opisu", bo kolumna „Czego dotyczy"
#     czytala TYLKO issue_description, a formularz zwrotu zbiera return_reason.
#  2. Historia sprawy zaczynala sie surowym kodem CASE_CREATED (brak w mapie etykiet),
#     w otoczeniu polskich wpisow („Zmiana statusu", „Przydzial sprawy").
#  3. Priorytet na karcie pokazywal techniczna wartosc („normal") zamiast po polsku.
# Kazdy punkt = to, co ZOBACZY klient, nie stan bazy.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
ev()  { wp eval "$1" 2>/dev/null; }

# ── 1. ZWROT: powod zwrotu widoczny na liscie ───────────────────────────────
OUT=$(wp mp case-create --kind=zwrot --email='zwrot-c26@example.com' --name='Klient Zwrot' \
      --serial='SN-C26-0001' --document='FV/C26/1' --date='2026-05-05' \
      --return-reason='Rozmiar niezgodny z opisem, produkt nieuzywany' 2>/dev/null)
TOK=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$TOK" >/dev/null 2>&1
CID=$(ev 'global $wpdb; echo (int) $wpdb->get_var("SELECT id FROM {$wpdb->prefix}mp_service_cases ORDER BY id DESC LIMIT 1");')

KOL=$(ev "wp_set_current_user(1);
	require_once ABSPATH . 'wp-admin/includes/class-wp-list-table.php';
	require_once ABSPATH . 'wp-admin/includes/screen.php';
	set_current_screen('toplevel_page_mp-cases');
	\$t = new MP\\Intake\\Admin\\CasesListTable('mp-cases');
	echo \$t->column_temat( array( 'id' => $CID ) );")
case "$KOL" in
	*"Rozmiar niezgodny"*) ok "zwrot: kolumna „Czego dotyczy” pokazuje powod zwrotu" ;;
	*) bad "zwrot: kolumna pokazuje [$KOL] zamiast powodu zwrotu" ;;
esac

# opis usterki ma PIERWSZENSTWO, gdy sa oba (reklamacja z opisem = bez zmian)
OUT2=$(wp mp case-create --kind=reklamacja --email='opis-c26@example.com' --name='Klient Opis' \
       --serial='SN-C26-0002' --document='FV/C26/2' --date='2026-05-05' \
       --desc='Urzadzenie nie wlacza sie po tygodniu' 2>/dev/null)
TOK2=$(echo "$OUT2" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$TOK2" >/dev/null 2>&1
CID2=$(ev 'global $wpdb; echo (int) $wpdb->get_var("SELECT id FROM {$wpdb->prefix}mp_service_cases ORDER BY id DESC LIMIT 1");')
KOL2=$(ev "wp_set_current_user(1);
	require_once ABSPATH . 'wp-admin/includes/class-wp-list-table.php';
	require_once ABSPATH . 'wp-admin/includes/screen.php';
	set_current_screen('toplevel_page_mp-cases');
	\$t = new MP\\Intake\\Admin\\CasesListTable('mp-cases');
	echo \$t->column_temat( array( 'id' => $CID2 ) );")
case "$KOL2" in
	*"nie wlacza sie"*) ok "reklamacja: opis usterki nadal ma pierwszenstwo (zero regresji)" ;;
	*) bad "reklamacja: kolumna pokazuje [$KOL2] zamiast opisu usterki" ;;
esac

# ── 2. Historia sprawy: zero surowych kodow zdarzen ─────────────────────────
KARTA=$(ev "wp_set_current_user(1); ob_start(); MP\\Intake\\Admin\\CaseCard::render($CID2, 'mp-cases'); echo ob_get_clean();")
SUROWE=$(echo "$KARTA" | grep -oE '\b[A-Z][A-Z_]{5,}\b' | sort -u | head -5)
[ -z "$SUROWE" ] && ok "historia sprawy: zadnego surowego kodu zdarzenia" \
	|| { bad "historia sprawy pokazuje surowy kod:"; echo "$SUROWE" | sed 's/^/      /'; }

# ── 3. Priorytet po polsku ──────────────────────────────────────────────────
case "$KARTA" in
	*">normal<"*|*"> normal <"*) bad "karta sprawy: priorytet pokazany technicznie („normal”)" ;;
	*) ok "karta sprawy: priorytet nie pokazuje technicznej wartosci" ;;
esac
echo "$KARTA" | grep -qE 'Priorytet' && ok "karta sprawy: wiersz „Priorytet” obecny" || bad "brak wiersza Priorytet"

echo
echo "WYNIK C26: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
