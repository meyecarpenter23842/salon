import 'dart:io';

import 'package:path/path.dart' as path;

/// PowerShell handoff used by the Windows self-updater.
///
/// The helper runs outside Salon, waits for the main process to exit, asks any
/// remaining Salon windows (for example --staff-window) to close normally,
/// installs the verified NSIS package silently, waits for it to finish, and
/// only then starts the updated executable.
const windowsSelfUpdateHelperScript = r'''
param(
  [Parameter(Mandatory = $true)][string]$Installer,
  [Parameter(Mandatory = $true)][string]$Executable,
  [Parameter(Mandatory = $true)][string]$InstallDir,
  [Parameter(Mandatory = $true)][int]$ParentPid
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$logDir = if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
  Join-Path $env:TEMP 'HairSpaManager\logs'
} else {
  Join-Path $env:APPDATA 'HairSpaManager\logs'
}
$logPath = Join-Path $logDir 'self_update_helper.log'

function Write-UpdateLog([string]$Message) {
  try {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $timestamp = (Get-Date).ToUniversalTime().ToString('o')
    Add-Content -Encoding UTF8 -Path $logPath -Value "$timestamp $Message"
  } catch {
    # Logging must never decide whether the update can continue.
  }
}

function Test-ProcessAlive([int]$ProcessId) {
  return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Wait-ProcessExit([int]$ProcessId, [int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while (Test-ProcessAlive $ProcessId) {
    if ((Get-Date) -ge $deadline) { return $false }
    Start-Sleep -Milliseconds 250
  }
  return $true
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
  Write-UpdateLog "handoff_start parent=$ParentPid installer=$Installer"

  if (-not (Wait-ProcessExit $ParentPid 20)) {
    throw 'Salon chính chưa đóng sau 20 giây; hủy cập nhật để bảo vệ dữ liệu.'
  }

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
      throw 'Một cửa sổ Salon chưa đóng an toàn; hủy cập nhật thay vì force-kill.'
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
    throw "Installer thoát với mã $($installerProcess.ExitCode)."
  }

  if (-not (Test-Path $Executable)) {
    throw 'Không tìm thấy executable sau khi cài cập nhật.'
  }

  Write-UpdateLog 'installer_success_restart'
  Start-Sleep -Milliseconds 500
  Start-Process -FilePath $Executable -WorkingDirectory $InstallDir
  exit 0
} catch {
  Write-UpdateLog "handoff_error $($_.Exception.Message)"

  # If the main process already exited, reopen the existing installation so a
  # failed update never leaves the user with Salon silently closed.
  if (-not (Test-ProcessAlive $ParentPid)) {
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
    await helper.writeAsString(windowsSelfUpdateHelperScript, flush: true);
    return helper;
  }

  Future<Process> launch({
    required File helper,
    required File installer,
    required String executable,
    required String installDir,
    required int parentPid,
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
        '-ParentPid',
        '$parentPid',
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
