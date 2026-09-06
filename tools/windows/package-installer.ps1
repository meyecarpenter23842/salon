param(
  [string]$BuildName = '',
  [int]$BuildNumber = -1,
  [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$nsisScript = Join-Path $repoRoot 'installer\salon.nsi'
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$outputDir = Join-Path $repoRoot 'dist\windows-release'
$iconSourcePath = Join-Path $repoRoot 'icon.png'
$iconOutputPath = Join-Path $outputDir '.salon-installer-icon.ico'
$prepareIconScript = Join-Path $PSScriptRoot 'prepare-icon.ps1'

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

function Resolve-MakeNsis {
  $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  $candidates = @(
    @(
      (Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe')
      (Join-Path $env:ProgramFiles 'NSIS\makensis.exe')
    ) | Where-Object { $_ -and (Test-Path $_) }
  )

  if ($candidates.Count -gt 0) { return $candidates[0] }
  throw 'Không tìm thấy makensis.exe. Hãy cài NSIS trước khi package installer.'
}

$version = Read-SalonVersion
if ([string]::IsNullOrWhiteSpace($BuildName)) {
  $BuildName = $version.Name
}
if ($BuildNumber -lt 0) {
  $BuildNumber = $version.Number
}

if ($BuildName -notmatch '^\d+\.\d+\.\d+$') {
  throw "BuildName phải có dạng x.y.z, nhận được: $BuildName"
}
if ($BuildNumber -lt 0) {
  throw 'BuildNumber phải >= 0.'
}
if (-not (Test-Path $iconSourcePath)) {
  throw "Không tìm thấy icon nguồn: $iconSourcePath"
}
if (-not (Test-Path $prepareIconScript)) {
  throw "Không tìm thấy script tạo icon: $prepareIconScript"
}

if (-not $SkipFlutterBuild) {
  Push-Location $repoRoot
  try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get thất bại.' }

    flutter build windows --release --build-name $BuildName --build-number $BuildNumber
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows --release thất bại.' }
  }
  finally {
    Pop-Location
  }
}

$salonExe = Join-Path $releaseDir 'salonmanager.exe'
if (-not (Test-Path $salonExe)) {
  throw "Không tìm thấy Windows release: $salonExe"
}

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
& $prepareIconScript -SourcePng $iconSourcePath -OutputIco $iconOutputPath | Out-Host
if (-not (Test-Path $iconOutputPath)) {
  throw "Không tạo được icon installer: $iconOutputPath"
}

$artifactPath = Join-Path $outputDir "Salon-Setup-$BuildName.exe"
if (Test-Path $artifactPath) {
  Remove-Item -Force $artifactPath
}

$makeNsis = Resolve-MakeNsis
$fileVersion = "$BuildName.$BuildNumber"
$arguments = @(
  "/DPRODUCT_VERSION=$BuildName",
  "/DFILE_VERSION=$fileVersion",
  "/DBUILD_DIR=$releaseDir",
  "/DOUTPUT_DIR=$outputDir",
  "/DAPP_ICON=$iconOutputPath",
  $nsisScript
)

& $makeNsis @arguments
if ($LASTEXITCODE -ne 0) {
  throw "NSIS packaging thất bại với exit code $LASTEXITCODE"
}
if (-not (Test-Path $artifactPath)) {
  throw "NSIS không tạo artifact mong đợi: $artifactPath"
}

Write-Host "Installer ready: $artifactPath"
Write-Output $artifactPath
