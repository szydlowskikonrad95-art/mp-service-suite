#!/usr/bin/env bash
# ZYWY DOWOD C22 (znalezisko #16 audytu 27.07 — brak indeksu na "przydzielony"):
# Tabela spraw miala indeksy na kliencie/produkcie/statusie/dacie, ale NIE na
# assigned_to — kazde "moje sprawy" pracownika i eksport CSV per pracownik
# skanowaly cala tabele (przy 5000 spraw zauwazalne na wolnym hostingu).
# Po naprawie (migracja v3): klucz zlozony (assigned_to, identity_status)
# pokrywa filtr listy I eksport; dowod = EXPLAIN uzywa klucza.
# Wymaga MP_BASE (spojnosc pakietu; test chodzi przez wp-cli).
set -u
: "${MP_BASE:?MP_BASE wymagane (adres front HTTP)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

# Aktualizacja jak po wgraniu nowej wersji: maybe_upgrade wisi na admin_init
# (wp-cli go nie odpala) — symulujemy wejscie admina. Swieza instalacja (CI)
# migruje przy aktywacji i to jest no-op.
wp eval 'MP\Intake\Lifecycle::maybe_upgrade();' >/dev/null 2>&1
WERSJA=$(wp option get mp_intake_schema_version 2>/dev/null | tr -d '[:space:]')
# Wersje bierzemy Z KODU, nie z liczby wpisanej w test: kazda kolejna migracja
# ja podnosi, a twarda liczba dawalaby czerwone CI przy poprawnej zmianie.
LATEST=$(wp eval 'echo (int) MP\Intake\Schema::LATEST;' 2>/dev/null | tr -d '[:space:]')
{ [ -n "$WERSJA" ] && [ "$WERSJA" = "$LATEST" ]; } && ok "wersja schematu intake = $LATEST (== Schema::LATEST)" || bad "wersja schematu = $WERSJA (oczekiwana $LATEST)"
{ [ -n "$WERSJA" ] && [ "$WERSJA" -ge 3 ]; } && ok "migracja v3 (indeks przydzialu) odnotowana" || bad "wersja ponizej 3 — migracji indeksu nie bylo"

# Klucz zlozony: 2 kolumny w dobrej kolejnosci.
KOL1=$(q "SELECT COLUMN_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_mp_service_cases' AND INDEX_NAME='assigned_to' AND SEQ_IN_INDEX=1")
KOL2=$(q "SELECT COLUMN_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_mp_service_cases' AND INDEX_NAME='assigned_to' AND SEQ_IN_INDEX=2")
[ "$KOL1" = "assigned_to" ] && ok "klucz assigned_to: 1. kolumna = assigned_to" || bad "brak klucza assigned_to albo zla 1. kolumna ($KOL1)"
[ "$KOL2" = "identity_status" ] && ok "klucz assigned_to: 2. kolumna = identity_status (pokrywa filtr+eksport)" || bad "brak 2. kolumny identity_status ($KOL2)"

# Dowod uzycia: planner wybiera klucz dla zapytania eksportu/filtra listy.
UZYTY=$(q "EXPLAIN SELECT id FROM wp_mp_service_cases WHERE assigned_to=12345 AND identity_status='verified'" | grep -o "assigned_to" | head -1)
[ "$UZYTY" = "assigned_to" ] && ok "EXPLAIN: zapytanie 'moje sprawy' uzywa klucza (bez skanu tabeli)" || bad "EXPLAIN nie uzywa klucza assigned_to"

# Regresja: stare indeksy zyja (dbDelta niczego nie zgubil).
for idx in case_number verify_token_hash customer_id status identity_status created_at; do
	JEST=$(q "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_mp_service_cases' AND INDEX_NAME='$idx'")
	[ "${JEST:-0}" -ge 1 ] && ok "indeks '$idx' nietkniety" || bad "indeks '$idx' ZNIKNAL po migracji"
done

echo
echo "WYNIK C22: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
