=== MP Workflow Automator ===
Requires at least: 6.0
Tested up to: 6.9
Requires PHP: 8.1
Stable tag: 0.5.0
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Rules engine for service cases: automatic assignment, statuses, e-mail notifications, SLA deadlines, checklists, reports.

== Description ==

Automates the service workflow: assigns cases to staff based on product category, country, language or priority, manages configurable case statuses, sends e-mail notifications to customers and staff on every relevant change, tracks SLA deadlines with reminders before and escalations after the deadline, provides per-type checklists and response templates, and exports CSV reports.

Part of the MP Service Suite (three cooperating plugins; each one also works standalone in a reduced mode, never causing fatal errors). The plugin UI and e-mails are in Polish (source language); every string is internationalized via the text domain, so the plugin can be translated to other languages. No separate .po/.mo is bundled because Polish is the base language.

== Requirements ==

* WordPress 6.x (6.0 or newer)
* PHP 8.1 or newer
* MySQL 8.0+ or MariaDB 10.6+
* HTTPS -- the suite handles passwordless (magic-link) login and customer personal data.
* WP-Cron enabled -- scheduled tasks rely on it: SLA deadlines, reminders and escalations (Workflow Automator), background CSV imports (Registry) and data-retention cleanup (Intake).

Developed and tested on WordPress 6.9.4, PHP 8.1-8.5, MariaDB 11.8.

== Changelog ==

= 0.5.0 =
* Powiadomienie e-mail pracownika przy zmianie statusu (self-skip dla autora zmiany). Walidacja JSON konfiguracji (bez cichej utraty), filtr SWEEP_RUN w domyślnym widoku rejestru zdarzeń.

= 0.4.0 =
* Rules engine + round-robin auto-assignment on case creation (structural rules, loop guard).
* Custom case statuses provider + status change action via the C contract.
* Notification e-mails: assignment, status change, client/staff messages (safe egress, per-type dedup).
* SLA: deadline bookkeeping, 5-minute sweep (reminders/escalations), resync + no-avalanche digest, admin "Recalculate SLA".
* Per-type checklists (toggle authorized by Intake, ownership enforced) + per-type response templates with a visible marker whitelist.
* CSV export of cases + summary (capability-gated, audited, anti-formula-injection, minimized data via the cases-query contract).
* Admin panel wiring all backend handlers; all data read from Intake/Registry only through mp_* contract hooks.

= 0.1.0 =
* Plugin skeleton: OOP bootstrap, lifecycle (activation/deactivation/uninstall), shared mp_* roles, i18n.
