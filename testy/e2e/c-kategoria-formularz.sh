#!/usr/bin/env bash
# ZYWY DOWOD P1.2 (pola formularza wg KATEGORII). Sprawa z kategoria => dodatkowe
# pole kategorii ląduje w form_data; sprawa BEZ kategorii => pola bazowe (zero regresji #15).
# Wymaga zywego `wp`. Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# ── 1. Sprawa z kategoria audio + pole cat_audio_objaw -> form_data ma to pole ──
CID=$(wp eval '
 $r = MP\Intake\CaseRepo::create( array(
   "kind"     => "reklamacja",
   "category" => "audio",
   "email"    => "katform1@example.com",
   "values"   => array(
     "serial" => "KATFORMSN1", "purchase_document" => "FV/1", "purchase_date" => "2026-05-01",
     "issue_description" => "opis usterki", "cat_audio_objaw" => "trzaski w lewym kanale",
   ),
 ) );
 echo isset( $r["case_id"] ) ? $r["case_id"] : ( "ERR:" . ( $r["error"] ?? "?" ) );' 2>/dev/null)
if [[ "$CID" =~ ^[0-9]+$ ]]; then
	ok "sprawa z kategoria utworzona (id=$CID)"
	FD=$(q "SELECT form_data FROM wp_mp_service_cases WHERE id=$CID;")
	echo "$FD" | grep -q "cat_audio_objaw" && ok "pole kategorii audio ZAPISANE w form_data" || bad "brak pola kategorii w form_data"
	echo "$FD" | grep -q "trzaski" && ok "wartosc pola kategorii zapisana" || bad "brak wartosci pola kategorii"
else
	bad "create z kategoria zwrocil: $CID"
fi

# ── 2. Kontrast: sprawa BEZ kategorii -> form_data BEZ pola kategorii (zero regresji) ──
CID2=$(wp eval '
 $r = MP\Intake\CaseRepo::create( array(
   "kind"   => "reklamacja",
   "email"  => "katform2@example.com",
   "values" => array( "serial" => "KATFORMSN2", "purchase_document" => "FV/2", "purchase_date" => "2026-05-01", "issue_description" => "opis" ),
 ) );
 echo isset( $r["case_id"] ) ? $r["case_id"] : "ERR";' 2>/dev/null)
if [[ "$CID2" =~ ^[0-9]+$ ]]; then
	FD2=$(q "SELECT form_data FROM wp_mp_service_cases WHERE id=$CID2;")
	if echo "$FD2" | grep -q "cat_audio_objaw"; then
		bad "pole kategorii w sprawie BEZ kategorii — REGRESJA!"
	else
		ok "sprawa bez kategorii = form_data bez pol kategorii (zero regresji #15)"
	fi
else
	bad "create bez kategorii zwrocil: $CID2"
fi

# ── 3. fields_for: kategoria dodaje pole (na zywym WP) ──
N=$(wp eval 'echo count( MP\Intake\FormConfig::fields_for( "reklamacja" ) );' 2>/dev/null)
NC=$(wp eval 'echo count( MP\Intake\FormConfig::fields_for( "reklamacja", "audio" ) );' 2>/dev/null)
[ "${NC:-0}" -gt "${N:-0}" ] && ok "fields_for(reklamacja,audio)=$NC > fields_for(reklamacja)=$N (pole kategorii)" || bad "fields_for kat nie dodaje ($N vs $NC)"

# ── 4. Nieznana kategoria = bezpiecznie (brak dodatkowych pol) ──
NX=$(wp eval 'echo count( MP\Intake\FormConfig::fields_for( "reklamacja", "cos-obcego" ) );' 2>/dev/null)
[ "${NX:-0}" = "${N:-0}" ] && ok "nieznana kategoria = pola bazowe (bezpiecznie)" || bad "nieznana kategoria zmienila pola ($NX vs $N)"

# ── sprzatanie ──
wp db query "DELETE FROM wp_mp_service_cases WHERE id IN (${CID:-0},${CID2:-0});" >/dev/null 2>&1

echo ""
echo "=== c-kategoria-formularz: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
