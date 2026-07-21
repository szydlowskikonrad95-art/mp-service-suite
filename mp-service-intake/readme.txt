=== MP Service Intake ===
Requires at least: 6.9
Tested up to: 6.9
Requires PHP: 8.1
Stable tag: 0.1.0
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Service and warranty claim intake: dynamic request form, SRV case numbers, customer account, spam protection.

== Description ==

Accepts service and warranty requests through a front-end form embedded on a WordPress page. Form fields and required attachments adapt to the request type (complaint, repair, technical question, return) and product category. Every case receives a race-safe SRV/YYYY/NNNN number. Customers get an account with live case status and message history.

Part of the MP Service Suite (three cooperating plugins; each one also works standalone in a reduced mode, never causing fatal errors). The plugin UI and e-mails are fully translatable (Polish translation included).

== Changelog ==

= 0.1.0 =
* Plugin skeleton: OOP bootstrap, lifecycle (activation/deactivation/uninstall), shared mp_* roles, i18n.
