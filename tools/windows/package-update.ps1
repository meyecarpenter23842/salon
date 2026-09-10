param(
  [string]$BuildName = '',
  [int]$BuildNumber = -1,
  [switch]$SkipFlutterBuild,
  [string]$Message = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$packageJsonPath = Join-Path $repoRoot 'package.json'
$outputDir = Join-Path $repoRoot 'dist\windows-release'
$installerScript = Join-Path $PSScriptRoot 'package-installer.ps1'

function Read-SalonVersion {
  $raw = Get-Content -Raw -Encoding UTF8 -Path $pubspecPath
  $match = [regex]::Match($raw, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$')
  if (-not $match.Success) {
    throw "Không đọc được version dạng x.y.z+build trong pubspec.yaml"
  }
  return @{
    Name = $match.Groups[1].Value
    Number = [int]$match.Groups[2].Value
  }
}

function Read-ReleaseManagerVersion {
  if (-not (Test-Path $packageJsonPath)) {
    throw "Không tìm thấy package.json dùng bởi Key Manager release profile."
  }
  $package = Get-Content -Raw -Encoding UTF8 -Path $packageJsonPath | ConvertFrom-Json
  $value = $package.version.ToString().Trim()
  if ($value -notmatch '^\d+\.\d+\.\d+$') {
    throw "package.json version phải có dạng x.y.z, nhận được: $value"
  }
  return $value
}

$version = Read-SalonVersion
$releaseManagerVersion = Read-ReleaseManagerVersion

if ([string]::IsNullOrWhiteSpace($BuildName)) {
  $BuildName = $version.Name
}
if ($BuildNumber -lt 0) {
  $BuildNumber = $version.Number
}

# Key Manager release profile reads package.json.version while the Flutter/NSIS
# package is built from pubspec.yaml. Refuse to publish split-brain metadata.
if ($releaseManagerVersion -ne $version.Name) {
  throw "Version lệch: package.json=$releaseManagerVersion nhưng pubspec.yaml=$($version.Name). Đồng bộ version trước khi release."
}
if ($BuildName -ne $version.Name) {
  throw "BuildName=$BuildName không khớp pubspec.yaml=$($version.Name). Hãy bump version trong source thay vì override khi release."
}

if ([string]::IsNullOrWhiteSpace($Message)) {
  $Message = "Salon $BuildName đã sẵn sàng cập nhật."
}

$installerArgs = @{
  BuildName = $BuildName
  BuildNumber = $BuildNumber
}
if ($SkipFlutterBuild) {
  $installerArgs.SkipFlutterBuild = $true
}
& $installerScript @installerArgs | Out-Host

$installerPath = Join-Path $outputDir "Salon-Setup-$BuildName.exe"
if (-not (Test-Path $installerPath)) {
  throw "Không tìm thấy installer: $installerPath"
}

$hash = (Get-FileHash -Algorithm SHA256 -Path $installerPath).Hash.ToLowerInvariant()
$manifestPath = Join-Path $outputDir 'latest.json'
$manifest = [ordered]@{
  latestVersion = $BuildName
  minimumSupportedVersion = ''
  required = $false
  title = "Salon $BuildName"
  message = $Message
  notes = @()
  downloadPath = "Salon-Setup-$BuildName.exe"
  releaseNotesPath = ''
  publishedAt = (Get-Date).ToUniversalTime().ToString('o')
  sha256 = $hash
}

$json = $manifest | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText(
  $manifestPath,
  $json,
  (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ''
Write-Host 'Update artifacts ready:'
Write-Host "  1. $installerPath"
Write-Host "  2. $manifestPath"
Write-Host ''
Write-Host 'R2 manual upload order:'
Write-Host "  1. Salon-Setup-$BuildName.exe"
Write-Host '  2. latest.json  (UPLOAD LAST)'
Write-Host ''
Write-Host 'No upload/release was performed by this script.'
