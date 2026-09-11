import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// PowerShell handoff used by the Windows self-updater.
///
/// The helper runs outside Salon, gives the current process a short grace
/// period to finish closing SQLite and exit, asks any remaining Salon windows
/// (for example --staff-window) to close normally, installs the verified NSIS
/// package silently, waits for it to finish, and only then starts the updated
/// executable.
const windowsSelfUpdateHelperScript = r'''
param(
  [Parameter(Mandatory = $true)][string]$Installer,
  [Parameter(Mandatory = $true)][string]$Executable,
  [Parameter(Mandatory = $true)][string]$InstallDir,
  [Parameter(Mandatory = $true)][string]$LogPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$logPath = $LogPath
$logDir = Split-Path -Parent $logPath

function Write-UpdateLog([string]$Message) {
  try {
    if (-not [string]::IsNullOrWhiteSpace($logDir)) {
      New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    $timestamp = (Get-Date).ToUniversalTime().ToString('o')
    Add-Content -Encoding UTF8 -Path $logPath -Value "$timestamp $Message"
  } catch {
    # Logging must never decide whether the update can continue.
  }
}

function Get-RemainingSalonProcesses {
  return @(
    Get-Process -Name 'salonmanager' -ErrorAction SilentlyContinue
  )
}

function Wait-AllSalonProcessesExit([int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while (@(Get-RemainingSalonProcesses).Count -gt 0) {
    if ((Get-Date) -ge $deadline) { return $false }
    Start-Sleep -Milliseconds 250
  }
  return $true
}

try {
  Write-UpdateLog "handoff_start installer=$Installer"

  # Match Key Manager's external handoff model: start outside Salon, wait
  # briefly for SQLite close/app exit, then close any remaining Salon windows.
  Start-Sleep -Milliseconds 900

  $remaining = @(Get-RemainingSalonProcesses)
  if ($remaining.Count -gt 0) {
    Write-UpdateLog "closing_remaining_windows count=$($remaining.Count)"
    foreach ($process in $remaining) {
      try {
        $null = $process.CloseMainWindow()
      } catch {
        Write-UpdateLog "close_window_failed pid=$($process.Id)"
      }
    }

    if (-not (Wait-AllSalonProcessesExit 15)) {
      throw 'A Salon window did not close safely; aborting instead of force-killing.'
    }
  }

  $installerArgs = @('/S', "/D=$InstallDir")
  Write-UpdateLog 'installer_start'
  $installerProcess = Start-Process `
    -FilePath $Installer `
    -ArgumentList $installerArgs `
    -Wait `
    -PassThru

  if ($installerProcess.ExitCode -ne 0) {
    throw "Installer exited with code $($installerProcess.ExitCode)."
  }

  if (-not (Test-Path $Executable)) {
    throw 'Updated executable was not found after install.'
  }

  Write-UpdateLog 'installer_success_restart'
  Start-Sleep -Milliseconds 500
  Start-Process -FilePath $Executable -WorkingDirectory $InstallDir
  exit 0
} catch {
  Write-UpdateLog "handoff_error $($_.Exception.Message)"

  # If no Salon process remains, reopen the existing installation so a failed
  # update never leaves the user with Salon silently closed.
  if (@(Get-RemainingSalonProcesses).Count -eq 0) {
    try {
      if (Test-Path $Executable) {
        Start-Process -FilePath $Executable -WorkingDirectory $InstallDir
      }
    } catch {
      Write-UpdateLog "restart_after_failure_error $($_.Exception.Message)"
    }
  }
  exit 1
}
''';

class WindowsSelfUpdateHandoff {
  const WindowsSelfUpdateHandoff();

  Future<File> writeHelper(Directory cacheDirectory) async {
    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }
    final helper = File(
      path.join(cacheDirectory.path, 'salon-self-update.ps1'),
    );
    // Windows PowerShell 5.1 treats UTF-8 without BOM as an ANSI code page.
    // Keep the generated helper strictly ASCII so its parser is independent of
    // the machine locale/ACP. ascii.encode also fails fast if a future edit
    // accidentally introduces a non-ASCII source character.
    await helper.writeAsBytes(
      ascii.encode(windowsSelfUpdateHelperScript),
      flush: true,
    );
    return helper;
  }

  Future<Process> launch({
    required File helper,
    required File installer,
    required String executable,
    required String installDir,
    required String logPath,
  }) {
    return Process.start(
      _powershellExecutable(),
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        helper.path,
        '-Installer',
        installer.path,
        '-Executable',
        executable,
        '-InstallDir',
        installDir,
        '-LogPath',
        logPath,
      ],
      mode: ProcessStartMode.detached,
    );
  }

  String _powershellExecutable() {
    final systemRoot = Platform.environment['SystemRoot']?.trim();
    if (systemRoot != null && systemRoot.isNotEmpty) {
      return path.join(
        systemRoot,
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      );
    }
    return 'powershell.exe';
  }
}
