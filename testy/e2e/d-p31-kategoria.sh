#!/usr/bin/env bash
# ZYWY DOWOD P3.1 wg KATEGORII (kartka: „auto-przydzial wg kategorii produktu").
# Lancuch: produkt w rejestrze (kategoria) -> sprawa z serialem (podpina produkt)
# -> get_context.kategoria (hak mp_product_category) -> regula condition_key=kategoria
# -> przydzial. Kontrast: inna kategoria => regula nie pasuje => ASSIGNMENT_UNMATCHED.
# Wymaga zywego `wp`. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Tworzy+weryfikuje sprawe (mp_case_created odpala silnik). Echo: case_id.
mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind=reklamacja --email="$1" --name='T Test' --serial="$2" --document='FV/2026/1' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# ── 0. Czysty stan ───────────────────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events;" >/dev/null 2>&1
wp db query "DELETE FROM wp_mp_product_registry WHERE serial_normalized IN ('KATAUDIO1','KATAGD1');" >/dev/null 2>&1

# ── 1. Dwa produkty: kategoria audio i agd (w rejestrze) ──────────────────────
wp db query "INSERT INTO wp_mp_product_registry (serial_display,serial_normalized,model,batch,category,warranty_until,source,created_at,updated_at) VALUES ('KATAUDIO1','KATAUDIO1','Sluchawki','P1','audio','2030-01-01','manual',NOW(),NOW());" >/dev/null 2>&1
wp db query "INSERT INTO wp_mp_product_registry (serial_display,serial_normalized,model,batch,category,warranty_until,source,created_at,updated_at) VALUES ('KATAGD1','KATAGD1','Ekspres','P2','agd','2030-01-01','manual',NOW(),NOW());" >/dev/null 2>&1
PA=$(q "SELECT category FROM wp_mp_product_registry WHERE serial_normalized='KATAUDIO1';")
[ "$PA" = "audio" ] && ok "produkt audio w rejestrze" || bad "produkt audio: '$PA'"

# ── 2. Agent + regula: kategoria == audio => przydziel do A ───────────────────
A=$(wp user create p31k_a p31k_a@example.com --role=mp_agent --porcelain 2>/dev/null); [ -z "$A" ] && A=$(wp user get p31k_a --field=ID 2>/dev/null)
RID=$(wp eval "echo MP\Automator\Rules::insert(array('trigger_type'=>'case_created','action_type'=>'assign','enabled'=>1,'condition_key'=>'kategoria','condition_operator'=>'equals','condition_value'=>'audio','action_config'=>array('pool'=>array($A))));" 2>/dev/null)
[ -n "$RID" ] && ok "regula kategoria=audio -> A (id=$RID)" || bad "insert reguly nie zwrocil id"

# ── 3. Sprawa produktu AUDIO: get_context.kategoria=audio + przydzial do A ─────
C1=$(mkcase c1kat@example.com KATAUDIO1)
KAT=$(wp eval "\$c = apply_filters('mp_case_get_context', 'not_found', $C1); echo is_array(\$c) ? (string) \$c['kategoria'] : 'ERR';" 2>/dev/null)
[ "$KAT" = "audio" ] && ok "get_context.kategoria=audio (hak w lancuchu sprawy)" || bad "get_context.kategoria: '$KAT'"
AS1=$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$C1;")
[ "$AS1" = "$A" ] && ok "sprawa audio PRZYDZIELONA wg kategorii (assigned_to=A=$A)" || bad "sprawa audio assigned_to='$AS1' (oczek. $A)"

# ── 4. Kontrast: sprawa produktu AGD => regula (tylko audio) NIE pasuje ────────
C2=$(mkcase c2kat@example.com KATAGD1)
AS2=$(q "SELECT assigned_to FROM wp_mp_service_cases WHERE id=$C2;")
if [ -z "$AS2" ] || [ "$AS2" = "NULL" ]; then
	ok "sprawa agd NIEprzydzielona (regula audio nie pasuje)"
else
	bad "sprawa agd assigned_to='$AS2' (oczek. brak)"
fi
UM=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='ASSIGNMENT_UNMATCHED';")
[ "${UM:-0}" -ge 1 ] && ok "ASSIGNMENT_UNMATCHED zapisany dla agd (swiadomy stan)" || bad "brak ASSIGNMENT_UNMATCHED (jest ${UM:-0})"

# ── sprzatanie ───────────────────────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_product_registry WHERE serial_normalized IN ('KATAUDIO1','KATAGD1');" >/dev/null 2>&1

echo ""
echo "=== d-p31-kategoria: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
