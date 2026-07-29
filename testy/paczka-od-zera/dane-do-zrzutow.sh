#!/usr/bin/env bash
# Dane demo pod ZRZUTY do instrukcji klienta: polskie nazwiska, realne usterki,
# sprawy w roznych statusach. Zero "Test Oko" i "sw1@example.com".
#
# KOLEJNOSC MA ZNACZENIE: najpierw import produktow, potem sprawy — powiazanie
# sprawy z rejestrem powstaje w chwili zgloszenia i NIE jest uzupelniane wstecz.
# Sprawy zalozone przed importem zostaja bez produktu i bez statusu gwarancji.
#
# Statusy i przydzialy ida PRAWDZIWA sciezka kodu (CaseActions), zeby ekrany byly
# spojne — SQL-em zrobiloby sie ladna liste bez zdarzen i terminow SLA.
set -u
KAT="$(cd "$(dirname "$0")" && pwd)"
C="$KAT/compose.yml"
BASE="http://localhost:8097"
W() { docker compose -p mpzero -f "$C" exec -T cli wp --path=/var/www/html "$@" 2>/dev/null; }
ev() { W eval "$1" | tr -d '\r'; }

echo "== 1. produkty (import przykladowego CSV wtyczki, przez ekran importu) =="
HASLO="$(cat "$KAT/paczka/.haslo")"
J="$(mktemp)"
curl -s -c "$J" -o /dev/null --data-urlencode "log=szef" --data-urlencode "pwd=$HASLO" \
     --data-urlencode "wp-submit=Zaloguj" --data-urlencode "testcookie=1" "$BASE/wp-login.php"
LOKALNY="$KAT/../../mp-warranty-registry/przyklady/przyklad-import-produktow.csv"
N=$(curl -s -b "$J" "$BASE/wp-admin/admin.php?page=mp-registry-import" | grep -o 'name="_wpnonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
curl -s -b "$J" -o /dev/null -F "action=mp_import_upload" -F "_wpnonce=$N" \
     -F "_wp_http_referer=/wp-admin/admin.php?page=mp-registry-import" \
     -F "mp_import_file=@$LOKALNY;type=text/csv" -F "submit=Rozpocznij import" \
     "$BASE/wp-admin/admin-post.php"
JOB=$(ev 'global $wpdb; echo (int) $wpdb->get_var("SELECT id FROM {$wpdb->prefix}mp_import_jobs ORDER BY id DESC LIMIT 1");')
W mp import-resume "$JOB" >/dev/null
echo "   produktow w rejestrze: $(ev 'global $wpdb; echo (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->prefix}mp_product_registry");')"

echo "== 2. personel =="
W user create a.wisniewska a.wisniewska@serwis.example --role=mp_coordinator \
   --display_name="Anna Wiśniewska" --user_pass="$(head -c 12 /dev/urandom | base64)" >/dev/null
W user create p.zielinski p.zielinski@serwis.example --role=mp_agent \
   --display_name="Piotr Zieliński" --user_pass="$(head -c 12 /dev/urandom | base64)" >/dev/null
W user create m.dabrowska m.dabrowska@serwis.example --role=mp_agent \
   --display_name="Marta Dąbrowska" --user_pass="$(head -c 12 /dev/urandom | base64)" >/dev/null
W user update szef --display_name="Administrator" >/dev/null
KOORD=$(W user get a.wisniewska --field=ID); PIOTR=$(W user get p.zielinski --field=ID); MARTA=$(W user get m.dabrowska --field=ID)

sprawa() { # kind email nazwisko serial dokument data opis [powod-zwrotu]
  local out token dodatkowe=()
  [ -n "${8:-}" ] && dodatkowe=(--return-reason="$8")
  out=$(W mp case-create --kind="$1" --email="$2" --name="$3" --serial="$4" \
        --document="$5" --date="$6" --desc="$7" "${dodatkowe[@]}")
  token=$(echo "$out" | grep '^token=' | cut -d= -f2 | tr -d '\r')
  [ -n "$token" ] && W mp case-verify "$token" >/dev/null
  ev 'global $wpdb; echo (int) $wpdb->get_var("SELECT id FROM {$wpdb->prefix}mp_service_cases ORDER BY id DESC LIMIT 1");'
}
status() { ev "wp_set_current_user($1); \$n=wp_create_nonce('mp_intake_case_status');
      \$_POST['_wpnonce']=\$n; \$_REQUEST['_wpnonce']=\$n; \$_POST['case_id']='$2';
      \$_POST['new_status']='$3'; \$_POST['expected_status']='$4'; \$_POST['rejection_reason_code']='';
      MP\\Intake\\Admin\\CaseActions::handle_status();" >/dev/null; }
przydziel() { ev "wp_set_current_user($1); \$n=wp_create_nonce('mp_intake_case_assign');
      \$_POST['_wpnonce']=\$n; \$_REQUEST['_wpnonce']=\$n; \$_POST['case_id']='$2';
      \$_POST['assignee']='$3'; MP\\Intake\\Admin\\CaseActions::handle_assign();" >/dev/null; }

echo "== 3. sprawy (seriale Z REJESTRU — zeby gwarancja i licznik spraw mialy sens) =="
A=$(sprawa reklamacja jan.kowalski@example.com "Jan Kowalski" SN-AUD-1001 "FV/2026/0410" 2026-04-12 "Głośnik nie łączy się przez Bluetooth, dioda miga na czerwono.")
B=$(sprawa naprawa katarzyna.nowak@example.com "Katarzyna Nowak" SN-AGD-2002 "FV/2026/0155" 2026-02-15 "Blender bardzo głośno pracuje na wysokich obrotach.")
D=$(sprawa zapytanie tomasz.wojcik@example.com "Tomasz Wójcik" "" "" "" "Czy gwarancja obejmuje wymianę baterii po dwóch latach?")
E=$(sprawa reklamacja agnieszka.mazur@example.com "Agnieszka Mazur" SN-ELN-3002 "FV/2025/1188" 2025-11-20 "Szlifierka iskrzy przy starcie, wyczuwalny zapach spalenizny.")
F=$(sprawa zwrot michal.lewandowski@example.com "Michał Lewandowski" SN-AUD-1002 "FV/2026/0410" 2026-04-12 "" "Produkt niezgodny z opisem w sklepie, nieużywany.")
G=$(sprawa reklamacja ewa.kaczmarek@example.com "Ewa Kaczmarek" SN-AGD-2001 "FV/2026/0155" 2026-02-15 "Czajnik nie grzeje wody, podświetlenie działa.")

przydziel "$KOORD" "$A" "$PIOTR"; status "$PIOTR" "$A" "w analizie" "nowe"
przydziel "$KOORD" "$B" "$MARTA"; status "$MARTA" "$B" "w analizie" "nowe"; status "$MARTA" "$B" "w naprawie" "w analizie"
przydziel "$KOORD" "$E" "$PIOTR"; status "$PIOTR" "$E" "w analizie" "nowe"; status "$PIOTR" "$E" "w naprawie" "w analizie"
przydziel "$KOORD" "$F" "$MARTA"; status "$MARTA" "$F" "w analizie" "nowe"; status "$MARTA" "$F" "zamknięte" "w analizie"

# jedna sprawa CELOWO niepotwierdzona — ekran "MP: Niepotwierdzone" ma co pokazac
W mp case-create --kind=reklamacja --email=robert.sikora@example.com --name="Robert Sikora" \
   --serial=SN-AUD-1003 --document="FV/2024/0612" --date=2024-06-30 \
   --desc="Radio wyłącza się po kilku minutach pracy." >/dev/null

echo "== 4. wyjatki gwarancyjne =="
W mp exception-add SN-AGD-2001 --reason="Gwarancja przedłużona decyzją producenta (akcja serwisowa 2026/03)" --until=2027-03-01 --user=szef >/dev/null
W mp exception-add SN-AUD-1002 --reason="Uszkodzenie transportowe uznane przy odbiorze, naprawa na koszt serwisu" --user=szef >/dev/null

echo "== stan =="
ev 'global $wpdb; foreach ($wpdb->get_results("SELECT case_number,kind,status,product_registry_id FROM {$wpdb->prefix}mp_service_cases ORDER BY id", ARRAY_A) as $r)
     printf("   %-14s %-11s %-16s produkt=%s\n", $r["case_number"], $r["kind"], $r["status"] ?: "(niepotwierdzona)", $r["product_registry_id"] ?: "—");'
