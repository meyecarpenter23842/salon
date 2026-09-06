param(
  [switch]$RequireArtifacts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$servicePath = Join-Path $repoRoot 'lib\core\services\offline_update_service.dart'
$panelPath = Join-Path $repoRoot 'lib\features\settings\presentation\pages\windows_update_panel.dart'
$packageUpdatePath = Join-Path $PSScriptRoot 'package-update.ps1'
$outputDir = Join-Path $repoRoot 'dist\windows-release'
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if (-not $Text.Contains($Needle)) { throw $Message }
}

$service = Get-Content -Raw -Path $servicePath
$panel = Get-Content -Raw -Path $panelPath
$packageUpdate = Get-Content -Raw -Path $packageUpdatePath
$publicFeed = 'https://pub-3f0aad8b18e146eb9eb09b9529063295.r2.dev'

Assert-Contains $service $publicFeed 'Updater phải dùng đúng public R2 feed của Salon.'
Assert-Contains $service 'latest.json' 'Updater phải đọc latest.json.'
Assert-Contains $service 'SHA-256' 'Updater phải xác minh SHA-256.'
Assert-Contains $service 'pending_update.json' 'Updater phải có marker xác nhận sau restart.'
Assert-Contains $panel 'Kiểm tra cập nhật' 'UI thiếu nút Kiểm tra cập nhật.'
Assert-Contains $panel 'Tải bản cập nhật' 'UI thiếu bước tải update.'
Assert-Contains $panel 'Khởi động lại & cập nhật' 'UI thiếu bước restart & update.'
Assert-Contains $packageUpdate 'latest.json' 'package:update phải sinh latest.json.'
Assert-Contains $packageUpdate 'UPLOAD LAST' 'Script phải nhắc upload manifest cuối cùng.'

$forbiddenRuntimeTokens = @(
  'cloudflarestorage.com',
  'secretAccessKey',
  'accessKeyId',
  'accountId',
  'S3 endpoint'
)
foreach ($token in $forbiddenRuntimeTokens) {
  if ($service.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw "Runtime updater chứa token vận hành bị cấm: $token"
  }
}

if ($service -match '(?i)portable.*(copy|scan|migrat|adopt)' -or
    $service -match '(?i)(copy|scan|migrat|adopt).*portable') {
  throw 'Updater không được chứa logic adoption/migration từ portable.'
}

if ($RequireArtifacts) {
  $pubspec = Get-Content -Raw -Path $pubspecPath
  $versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+\s*$')
  if (-not $versionMatch.Success) { throw 'Không đọc được version pubspec.' }
  $version = $versionMatch.Groups[1].Value

  $installerPath = Join-Path $outputDir "Salon-Setup-$version.exe"
  $manifestPath = Join-Path $outputDir 'latest.json'
  if (-not (Test-Path $installerPath)) { throw "Thiếu installer: $installerPath" }
  if (-not (Test-Path $manifestPath)) { throw "Thiếu latest.json: $manifestPath" }

  $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
  if ($manifest.latestVersion -ne $version) {
    throw "latest.json version $($manifest.latestVersion) không khớp $version"
  }
  if ($manifest.downloadPath -ne "Salon-Setup-$version.exe") {
    throw 'latest.json downloadPath không khớp installer.'
  }
  if ([string]::IsNullOrWhiteSpace($manifest.sha256)) {
    throw 'latest.json thiếu sha256.'
  }
  $actual = (Get-FileHash -Algorithm SHA256 -Path $installerPath).Hash.ToLowerInvariant()
  if ($actual -ne $manifest.sha256.ToString().ToLowerInvariant()) {
    throw 'SHA-256 trong latest.json không khớp installer.'
  }
}

Write-Host 'verify:updater passed.'
