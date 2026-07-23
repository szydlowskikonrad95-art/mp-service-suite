=== MP Service Intake ===
Requires at least: 6.9
Tested up to: 6.9
Requires PHP: 8.1
Stable tag: 0.4.0
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Service and warranty claim intake: dynamic request form, SRV case numbers, customer account, RODO/GDPR tools, spam protection.

== Description ==

Accepts service and warranty requests through a front-end form embedded on a WordPress page. Form fields and required attachments adapt to the request type (complaint, repair, technical question, return) and product category. Every case receives a race-safe SRV/YYYY/NNNN number.

Key features:

* Dynamic front-end form (Gutenberg block + `[mp_intake_form]` shortcode) with per-type validation.
* E-mail verification of every submission (one-time magic link, confirmed by a button — a plain link preview never confirms the case).
* Customer account (`mp_client`) with passwordless login: live case status, message history, contact-data editing (GDPR art. 16), and self-service consent withdrawal + data erasure (GDPR art. 7(3)/17).
* Hardened attachments: MIME detected by content (`finfo`), size/count limits, EXIF stripped from images, per-file ownership check on every download.
* Spam protection: honeypot, time trap, layered rate-limit (IP / e-mail / serial) and a hard 15-minute duplicate guard.
* Staff screen for unverified submissions (fix e-mail + resend a fresh link, throttled) with an operation audit log.
* GDPR eraser + exporter wired into WordPress privacy tools; consent text is frozen per row for accountability.

Part of the MP Service Suite (three cooperating plugins; each one also works standalone in a reduced mode, never causing fatal errors). The plugin UI and e-mails are in Polish (source language); every string is internationalized via the text domain, so the plugin can be translated to other languages. No separate .po/.mo is bundled because Polish is the base language.

== Installation ==

1. Upload the plugin ZIP in **Plugins → Add New → Upload Plugin**, then activate it.
2. Activation creates two pages automatically: the request form (`Zgłoszenie serwisowe`) and the customer panel (`Panel zgłoszeń`). You can move or rename them.
3. Set **Settings → General → Site Language** to Polish and the timezone to `Europe/Warsaw` so dates and messages display correctly.
4. Make sure your hosting can send e-mail (see the FAQ) — the plugin relies on `wp_mail()` for verification and login links.
5. The PHP extension `fileinfo` must be enabled for attachments (the plugin shows an admin notice if it is missing).

== Frequently Asked Questions ==

= Verification / login e-mails do not arrive =

The plugin sends e-mail through WordPress `wp_mail()`. Reliable delivery is the responsibility of your hosting / an SMTP plugin — install and configure an SMTP plugin (e.g. one that points to your provider's SMTP server). Without working outgoing mail, customers cannot confirm submissions or log in.

= Are attachment files protected from direct URL access? =

Yes on **Apache / LiteSpeed** (a `.htaccess deny` is written to the upload folder). **nginx ignores `.htaccess`** — on nginx add a server rule:
`location ^~ /wp-content/uploads/mp-attachments/ { deny all; return 403; }`
Regardless of the web server, files are always served through a PHP endpoint that checks ownership, so the direct URL is only a secondary layer. See `dokumentacja-techniczna/SECURITY.md`.

= What does this plugin NOT do? =

* It does **not** deliver e-mail by itself — that depends on your hosting/SMTP.
* It does **not** strip metadata from PDF attachments (only images are re-encoded/cleaned).
* It does **not** run the workflow automation (auto-assignment, SLA, status e-mails) — that is the separate *MP Workflow Automator* plugin.
* Its rate-limit uses transients; under a persistent object cache the counters live in the cache rather than the database.

== Changelog ==

= 0.4.0 =
* Contract functions for the Workflow Automator: case context, assignment, status change (optimistic-lock), paginated cases query (role-aware, minimized), checklist authorization (ownership + event), read-only status list.
* Submission form now dynamic by case type client-side (all fields in DOM; return-reason works first time).
* Guarantee exceptions recorded on the case timeline (EXCEPTION_APPLIED/REVOKED, NO-PII).
* Rate-limit by real client IP (mp_intake_client_ip filter) for reverse-proxy/Cloudflare setups.
* GDPR fix: correct terminal status "zamknięte" so erasure is no longer deferred indefinitely.
* Client front polish (admin bar hidden for clients, CSS, panel CTA) + panel WCAG contrast ≥ 4.5:1.

= 0.3.0 =
* Customer account + passwordless login + panel (live status, message history).
* GDPR: contact-data editing (art. 16), self-service consent withdrawal + erasure (art. 7(3)/17), eraser/exporter, consent e-mail redaction on erasure.
* Verification hardened to POST-confirm (mail scanners no longer auto-confirm).
* Spam protection: layered rate-limit + hard duplicate guard.
* Serial reuse flag (`possible_duplicate`) for recent verified cases of the same product.
* Staff screen for unverified submissions: fix e-mail + resend (throttled) + operation audit log.
* Safe upgrade without reactivation (schema migrates on admin load).

= 0.1.0 =
* Plugin skeleton: OOP bootstrap, lifecycle (activation/deactivation/uninstall), shared mp_* roles, i18n.
