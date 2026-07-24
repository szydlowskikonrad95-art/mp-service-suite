=== MP Warranty & Serial Registry ===
Requires at least: 6.0
Tested up to: 6.9
Requires PHP: 8.1
Stable tag: 0.5.0
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Product, serial number, production batch and warranty registry with CSV import, warranty status and admin search.

== Description ==

Stores products, serial numbers, production batches and warranty periods in dedicated database tables. Imports registry data from CSV files (resilient to regional encodings and separators), determines warranty status automatically (active, expired, no data, verification required), detects serial number reuse across cases, supports admin-approved warranty exceptions and provides an administrative search by serial, customer, invoice or model.

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
* Kontrakt mp_product_details (detale produktu + status gwarancji dla karty sprawy w Intake). Bez zmian w danych rejestru.

= 0.4.0 =
* Version aligned to MP Service Suite v0.4.0. No functional changes in this release (Registry unchanged; the release adds the Workflow Automator — see the suite CHANGELOG).

= 0.1.0 =
* Plugin skeleton: OOP bootstrap, lifecycle (activation/deactivation/uninstall), shared mp_* roles, i18n.
