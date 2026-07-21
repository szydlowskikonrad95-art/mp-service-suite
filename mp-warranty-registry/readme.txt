=== MP Warranty & Serial Registry ===
Requires at least: 6.9
Tested up to: 6.9
Requires PHP: 8.1
Stable tag: 0.1.0
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Product, serial number, production batch and warranty registry with CSV import, warranty status and admin search.

== Description ==

Stores products, serial numbers, production batches and warranty periods in dedicated database tables. Imports registry data from CSV files (resilient to regional encodings and separators), determines warranty status automatically (active, expired, no data, verification required), detects serial number reuse across cases, supports admin-approved warranty exceptions and provides an administrative search by serial, customer, invoice or model.

Part of the MP Service Suite (three cooperating plugins; each one also works standalone in a reduced mode, never causing fatal errors). The plugin UI and e-mails are fully translatable (Polish translation included).

== Changelog ==

= 0.1.0 =
* Plugin skeleton: OOP bootstrap, lifecycle (activation/deactivation/uninstall), shared mp_* roles, i18n.
