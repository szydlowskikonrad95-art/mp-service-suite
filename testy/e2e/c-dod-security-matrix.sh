#!/usr/bin/env bash
# DoD C sekcja 3 — SECURITY-SWEEP: macierz rol NEGATYWNA.
# Kazdy endpoint admina (admin-post + ajax) 3 wtyczek zwraca 403 komu NIE wolno:
# anon (niezalogowany), subscriber, mp_client. Zaden nie wykonuje akcji.
# Public (login/submit/verify) i klient (message/withdraw — ownership) testowane osobno.
# Wymaga MP_BASE. Chodzi na poligonie i w CI (e2e-import).
set -u
: "${MP_BASE:?MP_BASE wymagane}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

login() {
	local user="$1" jar="$2"
	rm -f "$jar"
	curl -s -c "$jar" -o /dev/null "$MP_BASE/wp-login.php"
	curl -s -c "$jar" -b "$jar" -o /dev/null \
		--data-urlencode "log=$user" --data-urlencode "pwd=Test12345!" \
		--data-urlencode "wp-submit=Zaloguj" --data-urlencode "redirect_to=$MP_BASE/wp-admin/" \
		"$MP_BASE/wp-login.php"
}

# Konta testowe.
for u in sub_sec cli_sec; do id=$(wp user get "$u" --field=ID 2>/dev/null); [ -n "$id" ] && wp user delete "$id" --yes >/dev/null 2>&1; done
wp user create sub_sec sub_sec@example.com --role=subscriber --user_pass='Test12345!' >/dev/null 2>&1
wp user create cli_sec cli_sec@example.com --role=mp_client --user_pass='Test12345!' >/dev/null 2>&1
login 'sub_sec' /tmp/mp-secsub-jar
login 'cli_sec' /tmp/mp-seccli-jar

# code <cookie-jar-or-empty> <endpoint-url> <action> <extra postfield>
code() {
	local jar="$1" url="$2" action="$3"
	local args=( -s -o /dev/null -w '%{http_code}' --data-urlencode "action=$action" --data-urlencode "_wpnonce=bogus" --data-urlencode "_ajax_nonce=bogus" --data-urlencode "case_id=1" --data-urlencode "product_id=1" --data-urlencode "exception_id=1" --data-urlencode "job_id=1" )
	if [ -n "$jar" ]; then args+=( -b "$jar" ); fi
	curl "${args[@]}" "$url"
}

# admin-post endpointy admina (kazdy: capability lub nonce-first => 403 dla nieuprawnionych).
AP="$MP_BASE/wp-admin/admin-post.php"
for ep in mp_intake_resend mp_import_upload mp_import_report mp_exception_add mp_exception_revoke mp_product_archive mp_product_restore mp_automator_export_csv; do
	A=$(code "" "$AP" "$ep")
	S=$(code /tmp/mp-secsub-jar "$AP" "$ep")
	C=$(code /tmp/mp-seccli-jar "$AP" "$ep")
	{ [ "$A" = "403" ] && [ "$S" = "403" ] && [ "$C" = "403" ]; } && ok "admin-post $ep: anon/subscriber/mp_client => 403" || bad "$ep: anon=$A sub=$S cli=$C (oczek. 403)"
done

# ajax endpointy admina (capability-first => wp_send_json_error 403).
AJ="$MP_BASE/wp-admin/admin-ajax.php"
for ep in mp_import_batch mp_import_reclaim; do
	A=$(code "" "$AJ" "$ep")
	S=$(code /tmp/mp-secsub-jar "$AJ" "$ep")
	C=$(code /tmp/mp-seccli-jar "$AJ" "$ep")
	{ [ "$A" = "403" ] && [ "$S" = "403" ] && [ "$C" = "403" ]; } && ok "ajax $ep: anon/subscriber/mp_client => 403" || bad "$ep: anon=$A sub=$S cli=$C (oczek. 403)"
done

echo
echo "WYNIK DoD-security-matrix: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
