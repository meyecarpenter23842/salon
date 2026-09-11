param(
  [string]$ReleaseDir = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($ReleaseDir)) {
  $ReleaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
}
$exe = Join-Path $ReleaseDir 'salonmanager.exe'
if (-not (Test-Path $exe)) {
  throw "Windows release executable not found: $exe"
}

$smokeAppData = Join-Path $env:TEMP "salonmanager-smoke-appdata-$PID"
New-Item -ItemType Directory -Force -Path $smokeAppData | Out-Null
$oldAppData = $env:APPDATA
$env:APPDATA = $smokeAppData

function Assert-WindowTitle([System.Diagnostics.Process]$Process, [string]$ExpectedTitle) {
  $deadline = (Get-Date).AddSeconds(5)
  do {
    if ($Process.HasExited) {
      throw "Process exited before window title could be verified: $($Process.Id)"
    }
    $Process.Refresh()
    if ($Process.MainWindowTitle -eq $ExpectedTitle) { return }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)

  throw "Unexpected window title for PID $($Process.Id). Expected '$ExpectedTitle', got '$($Process.MainWindowTitle)'."
}

$mainProcess = $null
$staffProcess = $null
try {
  $mainProcess = Start-Process -FilePath $exe -WorkingDirectory $ReleaseDir -PassThru
  Start-Sleep -Seconds 6
  if ($mainProcess.HasExited) {
    throw "salonmanager.exe main window exited during startup smoke with code $($mainProcess.ExitCode)"
  }
  Assert-WindowTitle $mainProcess 'Hair Spa Manager'

  $staffProcess = Start-Process -FilePath $exe -ArgumentList '--staff-window' -WorkingDirectory $ReleaseDir -PassThru
  Start-Sleep -Seconds 10
  if ($staffProcess.HasExited) {
    throw "salonmanager.exe --staff-window exited during startup smoke with code $($staffProcess.ExitCode)"
  }
  if ($mainProcess.HasExited) {
    throw 'Main window exited while Staff window was open.'
  }
  Assert-WindowTitle $staffProcess 'Hair Spa Manager'

  Stop-Process -Id $staffProcess.Id -Force
  $staffProcess.WaitForExit()
  Start-Sleep -Seconds 2
  if ($mainProcess.HasExited) {
    throw 'Closing Staff window also closed the main app.'
  }

  Write-Host 'Windows dual-process Staff window smoke passed.'
}
finally {
  if ($staffProcess -and -not $staffProcess.HasExited) {
    Stop-Process -Id $staffProcess.Id -Force
  }
  if ($mainProcess -and -not $mainProcess.HasExited) {
    Stop-Process -Id $mainProcess.Id -Force
  }
  $env:APPDATA = $oldAppData
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $smokeAppData
}
