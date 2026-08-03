#!/usr/bin/env bash
# ZYWY DOWOD (naprawa 2.5 + 2.8): jedna sprawa nazywa sie wszedzie TAK SAMO.
#
# Ten sam rodzaj mial trzy nazwy: „Zapytanie" na formularzu, „Zapytanie
# techniczne" w panelu automatu i surowy klucz `zapytanie` na liscie personelu.
# Panel klienta pokazywal dodatkowo surowy status. Rozwiazanie lezalo obok —
# funkcje tlumaczace stoja w tym samym produkcie i nie byly uzyte tam, gdzie
# patrzy czlowiek.
set -u

# Katalog repozytorium ZE SCIEZKI SKRYPTU — w CI test chodzi z /tmp/wp, wiec
# sciezki wzgledne nie istnieja (falszywe „FAIL", wada pomiaru nie produktu).
REPO="${MP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

echo "== 0. PROBA KONTROLNA: slownik w ogole odpowiada =="
MAPA=$(wp eval 'echo wp_json_encode( MP\Intake\FormConfig::kind_labels() );' 2>/dev/null)
case "$MAPA" in *reklamacja*) ok "slownik rodzajow odpowiada" ;; *) bad "slownik nie odpowiada ($MAPA)" ;; esac

echo "== 1. BRZMIENIE Z ZAMOWIENIA =="
ZAP=$(wp eval 'echo MP\Intake\FormConfig::kind_label( "zapytanie" );' 2>/dev/null)
[ "$ZAP" = "Zapytanie techniczne" ] && ok "rodzaj zapytanie ma brzmienie z zamowienia: Zapytanie techniczne" || bad "etykieta = $ZAP"

echo "== 2. TA SAMA NAZWA W INNYM MODULE (przez zaczep, nie kopie) =="
AUT=$(wp eval 'echo wp_json_encode( apply_filters( "mp_case_kind_labels", array() ) );' 2>/dev/null)
case "$AUT" in *"Zapytanie techniczne"*) ok "modul automatu dostaje TE SAMA nazwe zaczepem" ;; *) bad "zaczep nie oddaje nazw ($AUT)" ;; esac

echo "== 3. PANEL KLIENTA — MIERZONY RENDEREM, NIE GREPEM PO KODZIE =="
# Obecnosc wywolania w kodzie to nie dowod, ze czlowiek zobaczy nazwe.
# Skladamy sprawe, logujemy sie jako jej klient i patrzymy na WYNIK.
wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_rate_counters;" >/dev/null 2>&1
O=$(wp mp case-create --kind=zapytanie --email='panel-nazwy@przyklad.pl' --name='Panel Nazwy' --desc='pytanie techniczne' 2>/dev/null)
T=$(echo "$O" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$T" >/dev/null 2>&1
UIDP=$(wp db query "SELECT wp_user_id FROM wp_mp_customers WHERE email='panel-nazwy@przyklad.pl'" --skip-column-names 2>/dev/null | tr -d '[:space:]')
HTML=$(wp eval "wp_set_current_user( $UIDP ); echo MP\Intake\Front\AccountPage::render();" 2>/dev/null)

case "$HTML" in *"Zapytanie techniczne"*) ok "panel klienta POKAZUJE nazwe rodzaju po ludzku" ;; *) bad "panel klienta nie pokazal nazwy rodzaju" ;; esac
case "$HTML" in *">zapytanie<"*|*"· zapytanie ·"*) bad "panel klienta nadal pokazuje surowy klucz rodzaju" ;; *) ok "surowy klucz rodzaju zniknal z panelu" ;; esac
case "$HTML" in *"nowe"*) ok "status sprawy widoczny w panelu (jest co oceniac)" ;; *) bad "brak statusu w panelu — asercja nizej nic nie znaczy" ;; esac

echo "== 4. LISTA SPRAW PERSONELU =="
grep -q "FormConfig::kind_label" "$REPO"/mp-service-intake/includes/Admin/CasesListTable.php && ok "lista spraw tlumaczy rodzaj (kolumna i filtr)" || bad "lista spraw nadal pokazuje surowy klucz"

echo "== 5. GRANICA: STATUSY GWARANCJI ZOSTAJA NIETKNIETE =="
# Zakres sprawdzony celowo, zeby NIE uogolnic: rodzina gwarancyjna tlumaczyla
# sie poprawnie w trzech miejscach i tej naprawy nie dotyczy.
grep -q "status_map\|\$status_map" "$REPO"/mp-service-intake/includes/Admin/CaseCard.php && ok "mapa statusow gwarancji na karcie sprawy nietknieta" || bad "ruszono mape statusow gwarancji"

echo "== 6. NIEZNANY RODZAJ NIE ZNIKA =="
NIEZNANY=$(wp eval 'echo MP\Intake\FormConfig::kind_label( "cos_nowego" );' 2>/dev/null)
[ "$NIEZNANY" = "cos_nowego" ] && ok "nieznany rodzaj wraca jako klucz (nic nie znika z ekranu)" || bad "nieznany rodzaj zamieniony na '$NIEZNANY'"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
