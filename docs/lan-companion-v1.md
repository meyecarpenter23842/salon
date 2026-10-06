# Android companion / desktop LAN contract v1

Current tracking: #104/#111; #86/#89 are historical handoff records. This page
describes implemented behavior through #110, replacing the earlier route proposal.
For operators use [salon-operations.md](salon-operations.md); physical acceptance
uses [salon-qa-acceptance.md](salon-qa-acceptance.md).

## Ownership and lifecycle

The licensed Windows main application owns the HTTPS backend and business SQLite.
Staff remains a separate process using the same database. Main shutdown/license
loss stops the host; Staff does not take ownership. No background Windows service,
VPS or phone business database is required for LAN V1.

An exclusive OS lock and in-process guard prevent two main hosts. Bind/lock/TLS
failure leaves desktop usable with LAN unavailable; no automatic port fallback.
The configured interface is private IPv4, default TCP port 8743. Firewall setup
is an explicit owner action restricted to Private profile/LocalSubnet, without
router forwarding, UPnP or automatic Public rules.

## Transport and discovery

Implemented transport is pinned HTTPS with bounded JSON responses. No WebSocket
event stream is implemented. Desktop generates and protects a machine-only
certificate/private key; Android verifies the certificate DER SHA-256 pin,
validity and endpoint on every request, rejecting redirects. Never use trust-all.

The implemented QR has exactly kind/version/url/pin, not a pairing code/token.
Android scan/paste requires endpoint/pin confirmation; it fills connection inputs,
then pinned health and owner pairing follow separately. DHCP changes update the
URL while retaining the same certificate identity. A pin change requires explicit
verification/re-pair; an uncertain command blocks switching salon identity.
See [lan-health-setup.md](lan-health-setup.md).

## Implemented routes

Base path: /api/staff/v1. JSON UTF-8; money is integer VND, IDs are opaque TEXT
identities. Desktop-selected bill is never implicit authority for a phone command.

| Method / suffix | Behavior |
|---|---|
| GET /health | Anonymous exactly apiVersion/status; no business SQLite or salon details |
| POST /pair/exchange | Expiring one-use code, named device/token, pending owner approval |
| GET /pair/status | State of that authenticated device only |
| GET /bootstrap | Approved device identity, read permissions and write role |
| GET /customers, /invoices, /appointments | Authorized bounded presentation lists |
| GET /editor | Authorized customer/appointment/session/invoice snapshot with epoch/revision |
| GET /catalog | Authorized paged customers/services/products/employees/sessions |
| POST /commands | Authorized typed operation with commandId and epoch/revision preconditions |
| GET /commands?commandId=... | Result lookup scoped to the authenticated device |
| GET /changes | Authorized bounded epoch/cursor/reset/changed invalidation watermark |

There are no HTTP owner administration routes. Desktop approval and canReadSalon
grant are separate; write roles none/staff/cashier/owner are stored by the desktop,
not accepted from the command payload. Price/discount require the phone owner
role; payment/checkout require cashier or owner. QR and health never grant roles.

Customer/appointment edits, walk-in/appointment bills, bill lines, employee/price/
discount/payment and checkout call existing domain repositories inside the
command transaction. Server-generated resource revisions advance for desktop and
mobile changes. Stale epoch/revision fails with revision_conflict and no business
writes. Successful results and writes are committed atomically to SQLite journal;
device+commandId replay returns the recorded result before revision/epoch checks.
A reused ID with changed command reports command_conflict. Successful journal
entries have no automatic TTL. See [phone-write-foundation.md](phone-write-foundation.md)
and [android-write-workflows.md](android-write-workflows.md).

Errors use stable apiVersion/requestId/error-code envelopes without raw SQL,
paths, stack traces or secrets. Body/query/response sizes, pagination, rate and
concurrent request limits are enforced in the host/client. Read authority is
checked before and after reading; write authority spans the transaction.

## Refresh and recovery

Changes are an invalidation watermark, not event history or private records.
Foreground polling is approximately 5 seconds plus network time. Desktop/Staff
observe SQLite total_changes/data_version; no file-size/mtime heuristic.
Missing/future cursors or backend epoch changes require fresh reads.

Offline foreground retains drafts/routes but disables writes; reconnect verifies
authority and reloads snapshots before saving. Background/revoke closes private
routes/dialogs. Pending uncertain commands remain in Android Keystore storage;
no automatic replay/offline write queue. The user checks a command's result before
an explicit retry. See [lan-resync.md](lan-resync.md).

## Evidence and remaining gate

Existing full CI exercises real fixture SQLite/TLS/OS locks, permissions, revisions,
atomic checkout/replay, QR widgets, reconnect and Windows/Staff/installer/updater/
NSIS/APK builds. Flutter engine renders are review evidence.

Physical Android camera, Keystore/network behavior, Wi-Fi isolation/firewall,
sleep/restart and owner UX acceptance remain #111. Owner currently has no device;
leave those gates pending. Other-network/4G access remains #112. No local app
build/test, new checkout, installation/release or production migration is
performed by this QA source change.
