# Windows updater helper startup and recovery

Issue #93: on the owner machine, 1.8.4 downloaded/verified/backed up 1.8.5 and
exited after receiving a helper PID. No helper log was created and the installed
binary remained 1.8.4. A harmless Dart/PowerShell 5.1 probe reproduced this with
detached launch; normal hidden launch continued after Dart parent exit.

The updater now launches Windows PowerShell with normal process handles and
WindowStyle Hidden, drains output pipes, and waits for a unique PID readiness
marker before SafeWindowsUpdateService is allowed to close SQLite and exit.
The helper waits for the app's ContinuePath acknowledgment before proceeding.
Startup exit/timeout rejects the handoff and leaves Salon open. Timeout cleanup
stops only that newly launched helper. It does not kill Salon or touch its DB.

Existing safety order remains: verified installer → SQLite backup → handoff ready
→ SQLite close → app exit → helper gracefully closes remaining windows → installer
finishes → updated app starts. Missing ACK never grants permission to install.
No changes to installer version, package feed, migration or production data.

Windows CI exercises the production Dart launch API with a harmless PS5.1 probe,
including a separate Dart parent that exits before the helper writes its delayed
marker. Tests also cover failed startup and readiness timeout. These probes do
not install an application or call into salon business data.

## Recover an installation with the old updater

A repo merge does not patch an already installed 1.8.4/1.8.5 binary. Build/package
a new installer containing this fix, then install it manually once with Salon
closed (and keep the pre-update backup). Do not retry the old in-app handoff and
expect it to execute a fixed installer: the currently running app owns that flow.
Do not overwrite version metadata or publish a new release automatically.

Relevant diagnostics: %APPDATA%/HairSpaManager/logs/update_audit.log and
self_update_helper.log. A helper PID alone is no longer treated as readiness.
Successful startup records handoff_start and handoff_ready_confirmed before
installer_start. Post-restart marker checks still confirm the target app version.
