#!/usr/bin/env bash
# ZYWY DOWOD (karta sprawy personelu — READ): dane ktore renderuje ekran „MP: Sprawy".
# Sprawdza: CaseEvents::for_case (os czasu chronologiczna, struktura event_type/payload/
# actor_id/created_at, CASE_CREATED + STATUS_CHANGED po zmianie statusu) · CaseRepo::
# form_data_for_case (znormalizowany {label,value,pii_sensitive}, opis obecny) · 4 HOOKI
# KONTRAKTOWE D->C zasilajace karte: mp_case_checklist_state (pelna lista krokow rodzaju),
# mp_response_templates (lista {key,label,body}), mp_render_response_template (string;
# '' dla nieznanego klucza), mp_case_deadline ({deadline_at,warning_at,status}|null).
# Chodzi tak samo na poligonie i w CI e2e. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

ADMIN=1

# ── 0. Czysty stan + reguly domyslne (zeby powstal wiersz SLA na created) ──────
wp db query "DELETE FROM wp_mp_case_sla; DELETE FROM wp_mp_case_checklists; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_messages; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1
wp eval 'MP\Automator\Rules::maybe_seed_defaults();' >/dev/null 2>&1

mk() { # $1=kind $2=email $3=serial
	local out cid tok
	out=$(wp mp case-create --kind="$1" --email="$2" --name='Jan Kowalski' --serial="$3" --document='FV/2026/9' --date='2026-05-01' --desc='OPIS-TESTOWY-KARTA' --return-reason='zmiana zdania' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\\Intake\\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}
chs() { wp eval "apply_filters('mp_case_change_status', null, $1, '$2', '$3', $ADMIN, $4);" >/dev/null 2>&1; }

CID=$(mk reklamacja karta@example.com KART-1)
[ -n "$CID" ] && ok "seed: sprawa utworzona i zweryfikowana (id=$CID)" || bad "seed: brak case_id"
chs "$CID" "w analizie" "nowe" "null"

# Kontrakt karty: mp_case_get_context MUSI wystawiac product_registry_id (sekcja Produkt
# na karcie tego uzywa). Regresja gap 24.07: kontekst czytal id wewnetrznie, nie zwracal.
CTXPID=$(wp eval "\$c=apply_filters('mp_case_get_context', null, $CID); echo array_key_exists('product_registry_id', \$c) ? 'MA' : 'BRAK';" 2>/dev/null)
[ "$CTXPID" = "MA" ] && ok "get_context: wystawia klucz product_registry_id (dla sekcji Produkt karty)" || bad "get_context: BRAK product_registry_id ($CTXPID)"

# ── 1. CaseEvents::for_case — os czasu ────────────────────────────────────────
RAW=$(q "SELECT COUNT(*) FROM wp_mp_case_events WHERE case_id=$CID")
CNT=$(wp eval "echo count(MP\\Intake\\CaseEvents::for_case($CID));" 2>/dev/null)
[ "$CNT" = "$RAW" ] && [ "$CNT" != "0" ] && ok "for_case: zwraca wszystkie zdarzenia sprawy ($CNT = tabela $RAW)" || bad "for_case count zly (metoda=$CNT tabela=$RAW)"

# struktura pierwszego wiersza: wymagane 4 kolumny
STRUCT=$(wp eval "\$r=MP\\Intake\\CaseEvents::for_case($CID); \$x=\$r[0]; echo (isset(\$x['event_type'])?'t':'-').(array_key_exists('payload',\$x)?'p':'-').(array_key_exists('actor_id',\$x)?'a':'-').(isset(\$x['created_at'])?'c':'-');" 2>/dev/null)
[ "$STRUCT" = "tpac" ] && ok "for_case: struktura wiersza {event_type,payload,actor_id,created_at}" || bad "for_case struktura zla ($STRUCT)"

# chronologia: pierwsze = CASE_CREATED, zawiera STATUS_CHANGED, created_at rosnaco
FIRST=$(wp eval "\$r=MP\\Intake\\CaseEvents::for_case($CID); echo \$r[0]['event_type'];" 2>/dev/null)
[ "$FIRST" = "CASE_CREATED" ] && ok "for_case: pierwsze zdarzenie = CASE_CREATED (chronologicznie)" || bad "for_case pierwsze zle ($FIRST)"
HASSC=$(wp eval "\$r=MP\\Intake\\CaseEvents::for_case($CID); echo in_array('STATUS_CHANGED', array_column(\$r,'event_type'), true)?'1':'0';" 2>/dev/null)
[ "$HASSC" = "1" ] && ok "for_case: STATUS_CHANGED obecne po zmianie statusu (kartka: 'kazda decyzja w historii')" || bad "for_case brak STATUS_CHANGED ($HASSC)"
ORD=$(wp eval "\$r=MP\\Intake\\CaseEvents::for_case($CID); echo (\$r[0]['created_at'] <= \$r[count(\$r)-1]['created_at'])?'1':'0';" 2>/dev/null)
[ "$ORD" = "1" ] && ok "for_case: created_at niemalejaco (ASC)" || bad "for_case kolejnosc zla ($ORD)"

# limit dziala (min 1)
LIM=$(wp eval "echo count(MP\\Intake\\CaseEvents::for_case($CID, 1));" 2>/dev/null)
[ "$LIM" = "1" ] && ok "for_case: limit=1 respektowany" || bad "for_case limit zly ($LIM)"

# ── 2. CaseRepo::form_data_for_case — opis zgloszenia znormalizowany ──────────
FD=$(wp eval "echo count(MP\\Intake\\CaseRepo::form_data_for_case($CID));" 2>/dev/null)
[ "$FD" != "0" ] && [ -n "$FD" ] && ok "form_data_for_case: niepusty ($FD pol)" || bad "form_data_for_case pusty ($FD)"
FDJ=$(wp eval "echo wp_json_encode(MP\\Intake\\CaseRepo::form_data_for_case($CID));" 2>/dev/null)
echo "$FDJ" | grep -q '"label"' && echo "$FDJ" | grep -q '"value"' && echo "$FDJ" | grep -q '"pii_sensitive"' && ok "form_data_for_case: kazde pole ma {label,value,pii_sensitive}" || bad "form_data_for_case zla struktura"
echo "$FDJ" | grep -q 'OPIS-TESTOWY-KARTA' && ok "form_data_for_case: opis zgloszenia obecny w wartosciach" || bad "form_data_for_case: brak opisu"

# ── 3. HOOK mp_case_checklist_state (D->C): pelna lista krokow rodzaju ─────────
CHK=$(wp eval "echo count((array) apply_filters('mp_case_checklist_state', null, $CID));" 2>/dev/null)
[ "$CHK" != "0" ] && [ -n "$CHK" ] && ok "mp_case_checklist_state: pelna lista krokow rodzaju ($CHK)" || bad "mp_case_checklist_state pusty ($CHK)"
CHKJ=$(wp eval "echo wp_json_encode(apply_filters('mp_case_checklist_state', null, $CID)[0]);" 2>/dev/null)
echo "$CHKJ" | grep -q '"step_key"' && echo "$CHKJ" | grep -q '"label"' && echo "$CHKJ" | grep -q '"completed"' && ok "mp_case_checklist_state: krok {step_key,label,completed}" || bad "mp_case_checklist_state zla struktura ($CHKJ)"
# nieznana sprawa => pusta lista (nie fatal)
CHKE=$(wp eval "echo count((array) apply_filters('mp_case_checklist_state', null, 999999));" 2>/dev/null)
[ "$CHKE" = "0" ] && ok "mp_case_checklist_state: nieznana sprawa => pusto (bez fatala)" || bad "mp_case_checklist_state nieznana zla ($CHKE)"

# ── 4. HOOK mp_response_templates (D->C): dropdown odpowiedzi ─────────────────
RTJ=$(wp eval "echo wp_json_encode(apply_filters('mp_response_templates', null, 'reklamacja'));" 2>/dev/null)
echo "$RTJ" | grep -qE '^\[' && ok "mp_response_templates: zwraca liste (typ array)" || bad "mp_response_templates nie-array ($RTJ)"
RTN=$(wp eval "echo count((array) apply_filters('mp_response_templates', null, 'reklamacja'));" 2>/dev/null)
if [ "$RTN" != "0" ]; then
	echo "$RTJ" | grep -q '"key"' && echo "$RTJ" | grep -q '"label"' && echo "$RTJ" | grep -q '"body"' && ok "mp_response_templates: szablon {key,label,body} ($RTN szt.)" || bad "mp_response_templates zla struktura ($RTJ)"
	# render pierwszego szablonu => niepusty string
	RKEY=$(wp eval "\$t=apply_filters('mp_response_templates', null, 'reklamacja'); echo \$t[0]['key'];" 2>/dev/null)
	RND=$(wp eval "echo strlen((string) apply_filters('mp_render_response_template', null, '$RKEY', $CID));" 2>/dev/null)
	[ -n "$RND" ] && [ "$RND" != "0" ] && ok "mp_render_response_template: renderuje body szablonu '$RKEY' (len=$RND)" || bad "mp_render_response_template pusty dla '$RKEY' ($RND)"
else
	ok "mp_response_templates: brak szablonow dla rodzaju (dozwolone, karta pokaze puste pole)"
fi
# nieznany klucz => '' (string, nie fatal)
RBOG=$(wp eval "\$v=apply_filters('mp_render_response_template', null, 'NIE-MA-TAKIEGO', $CID); echo is_string(\$v)?('['.\$v.']'):'NIE-STRING';" 2>/dev/null)
[ "$RBOG" = "[]" ] && ok "mp_render_response_template: nieznany klucz => '' (string)" || bad "mp_render_response_template nieznany zly ($RBOG)"

# ── 5. HOOK mp_case_deadline (D->C): termin SLA sprawy ────────────────────────
SLAROW=$(q "SELECT COUNT(*) FROM wp_mp_case_sla WHERE case_id=$CID")
DLJ=$(wp eval "echo wp_json_encode(apply_filters('mp_case_deadline', null, $CID));" 2>/dev/null)
if [ "$SLAROW" != "0" ]; then
	echo "$DLJ" | grep -q '"deadline_at"' && echo "$DLJ" | grep -q '"warning_at"' && echo "$DLJ" | grep -q '"status"' && ok "mp_case_deadline: {deadline_at,warning_at,status} dla sprawy z SLA" || bad "mp_case_deadline zla struktura ($DLJ)"
else
	bad "brak wiersza SLA po created (reguly domyslne nie zasialy?)"
fi
# sprawa bez SLA => null
DLNULL=$(wp eval "echo var_export(apply_filters('mp_case_deadline', null, 888888), true);" 2>/dev/null)
[ "$DLNULL" = "NULL" ] && ok "mp_case_deadline: brak wiersza SLA => null" || bad "mp_case_deadline brak-SLA zly ($DLNULL)"

echo ""
echo "CASE-CARD: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
