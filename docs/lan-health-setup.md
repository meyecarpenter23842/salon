# Desktop HTTPS health host

After one-time setup, opening the licensed Windows main app starts the backend;
closing it or losing license access stops the backend. Staff never starts one.
The app keeps working if backend setup/port/IP/certificate fails. See Settings →
Kết nối điện thoại for status and the API URL.

## One-time setup (owner machine)

Use PowerShell 7 (`pwsh`) to run the repository script, replacing the sample IP
with the desktop's actual private IPv4 on the salon router:

```powershell
pwsh -File tools/windows/setup-lan-health.ps1 -Address 192.168.1.20
```

This generates a one-year self-signed certificate, private key and config at
%APPDATA%/HairSpaManager/lan. Windows directory permissions restrict access to
the current account. Never commit, share or put private-key.pem into a QR.
The script prints only API URL and public SHA-256 certificate fingerprint.
It refuses to overwrite config.json so a setup rerun cannot silently change
the identity trusted by a phone. Back up this directory before deliberate
certificate renewal/IP changes; those require re-pairing later.
Use a DHCP reservation to keep desktop IP stable. Restart the main app after
configuration changes. Do not copy configuration into the business SQLite DB.

For Windows Firewall, allow the application/TCP configured port on Private
profile and local subnet only, after owner review. The script changes no firewall
rules. A local health success does not prove firewall or phone connectivity.

## Check the URL

API URL example: https://192.168.1.20:8743/api/staff/v1
Health URL: https://192.168.1.20:8743/api/staff/v1/health

From a client that explicitly trusts this certificate for this test:

```text
curl --cacert certificate.pem https://192.168.1.20:8743/api/staff/v1/health
{"apiVersion":1,"status":"ok"}
```

Use the certificate copied from the owner desktop, not an arbitrary downloaded
certificate. Do not use curl -k or a trust-all mobile callback. The Android app
will support endpoint-specific pinning in a later PR; this host PR does not
provide an installable companion app or a QR pairing implementation.

Only GET health with no body/query is served. All customer/bill/checkout routes
remain unavailable. HTTPS protects transport but does not grant business access.

## Connectivity outside the salon

The phone always uses an API URL. Desktop must be running and reachable from
the phone. LAN IP works within the router; it is not automatically reachable
from 4G. Remote access requires a separately configured private network or HTTPS
tunnel to desktop. This PR does not provision those services, public DNS,
port-forwarding or router/firewall changes.

## Troubleshooting and lifecycle

- Missing config: desktop shows not configured; no listener.
- IP unavailable, port occupied, invalid/expired certificate: health cannot be
  reached; desktop stays usable. Correct configuration and restart.
- Another main app already holds the owner lock: second app refuses hosting,
  even if configured to another port. Close the first app before changing host.
- Lock file may remain after close/crash: OS handle release frees ownership.
  Never delete a live lock file to force another host.
- Closing/hiding a dialog or opening Staff does not stop main's listener.
- Main process exit/crash releases sockets and lock. Sleep/network loss makes
  mobile unreachable; clients must resync on reconnect before writes.
- Current shutdown force-closes health connections; no business commands exist.
  Draining accepted mutations transactionally is a prerequisite for Batch 3.
