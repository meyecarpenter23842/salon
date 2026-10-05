# Android companion / desktop LAN contract v1

Tracking: #86, Batch 2 #89. This PR defines wire primitives and host policy only.
No server starts from main.dart yet. No port, firewall rule, DB migration,
pairing token or Android bootstrap is enabled by this change.

## Ownership and lifecycle decision

V1 backend lives inside the licensed Windows main application, enabled explicitly
by the owner. Staff windows and Android are clients. Closing the main window
ends the backend even if Staff remains open; no background Windows service in V1.
PC shutdown/sleep or Wi-Fi loss makes mobile unavailable and disables writes.
The phone never owns a business SQLite database and never queues offline writes.

The host must acquire an exclusive OS lock before binding (covering two main
processes), retain it through shutdown, and refuse a second owner. A failed lock
or bind leaves desktop usable with LAN unavailable; no automatic alternate port.
License loss stops acceptance of new requests. Shutdown first stops new commands,
drains accepted work through repository transactions, then closes sockets/lock.
Policy types express eligibility, not lock acquisition or a running server.
The server must never depend on the UI's selectedInvoiceSessionIdProvider.

## Transport and discovery decision

Use HTTPS and WSS. Desktop generates a per-installation certificate/private key;
QR shown by the owner carries endpoint, API version, certificate SHA-256 pin and
a short-lived single-use pairing secret. Android pins that certificate for this
endpoint; never use a global trust-all callback. Pin change requires explicit
re-pair. Discovery uses QR; DHCP address change can require a new QR. No mDNS
dependency. Bind only configured LAN interfaces; no port-forwarding or UPnP.
A later spike must prove Dart/Android pin validation with a real certificate.
Do not expose device tokens, pairing secrets or customer data over plain HTTP.

Firewall setup is a deliberate owner action limited to Private network profiles
and local subnet. Do not silently open Public network rules. Default port will be
chosen/tested in the health spike; document conflicts before enabling runtime.

## Wire rules

Base path: /api/staff/v1. JSON UTF-8. UTC ISO-8601 times. Money is integer VND;
percentages must match existing domain representation. Existing TEXT entity IDs
remain opaque; no mobile-generated database authority.

GET /health beneath the base path returns exactly
{"apiVersion":1,"status":"ok"}. It proves listener liveness only, not database,
license, pairing or readiness for checkout. It reads no SQLite and leaks no salon
name, device ID, version of SQLite, path, PIN or customer data.

Protected route families planned for later implementation:

| Route | Purpose |
| --- | --- |
| POST /pair/exchange | Consume bounded, expiring single-use pairing code |
| GET /bootstrap | Authorized minimal snapshot, backendEpoch and event cursor |
| GET /events | Authenticated WebSocket; invalidate/reconcile resources |
| GET/POST /appointments, PATCH /appointments/:id/status | Schedule operations |
| GET/POST /customers | Search and create under actor permissions |
| GET /services, /products, /employees | Authorized catalog projections |
| POST /billing-sessions | Walk-in session with explicit customer |
| POST /appointments/:id/billing-session | Reuse/create active appointment bill |
| GET /billing-sessions/:sessionId | Read explicit bill |
| POST/PATCH/DELETE /billing-sessions/:sessionId/lines | Bill line operations |
| POST /billing-sessions/:sessionId/checkout | Repository checkout |

All mutations require authenticated device/actor, commandId and expectedRevision
on existing resources. Billing envelopes also carry sessionId, matching the route.
Missing target is invalid_request, never resolved from desktop selection. New
resource creation uses a separate DTO (not LanCommand) and commandId without a
fabricated resource revision. Server derives actor from auth; ignores client roles.
Price/discount/checkout use backend guards. Desktop Owner authorization must not
implicitly grant remote devices owner privileges.

Revision is a server-issued monotonically increasing integer per resource.
Desktop and mobile mutations must both advance it transactionally; updated_at
alone is insufficient. Stale revision yields revision_conflict with no writes.
Do not advertise mutation endpoints until repository revision support is present.

Idempotency scope is authenticated device + commandId. Same normalized command
and target returns its stored result; reused key with different payload returns
command_conflict. Persist successful result and business write in the same SQLite
transaction, including checkout. Check known commands before revision checks so
a committed retry returns the original result. Retention/TTL must be decided before
mutation support; no in-memory-only guarantee across restart.

Errors use {apiVersion, requestId, error:{code}} with LanErrorCode stable codes
and status mapping. Never serialize raw exception, stack, SQL or local paths.
Optional conflict details require a separate authorized DTO; no unrestricted map.
Bound body sizes, parser depth, pagination and rate limits at the server boundary.

Events carry apiVersion, backendEpoch, sequence, resourceType, resourceId,
revision and event type. They invalidate authorized snapshots, not carry PII.
A changed epoch after restart, sequence gap, expired cursor or reconnect requires
bootstrap/resync before enabling writes. Device revoke closes its event stream.
A reconnect never automatically replays mutations; reconcile ambiguous results
by commandId first.

## Evidence and remaining gate

Pure Dart contract/policy tests run in existing Ubuntu and Windows Flutter CI.
This establishes no working LAN connection. Remaining Batch 2 work is an opt-in
health host with OS ownership lock, TLS pinning/discovery spike, Android network
bootstrap isolated from Windows credential/license/SQLite startup, and an actual
Android-to-desktop LAN check. Pairing/auth and business routes follow Batch 3.
