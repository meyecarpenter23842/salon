param(
  [switch]$RequireArtifacts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$nsisPath = Join-Path $repoRoot 'installer\salon.nsi'
$packagePath = Join-Path $PSScriptRoot 'package-installer.ps1'
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$outputDir = Join-Path $repoRoot 'dist\windows-release'

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if (-not $Text.Contains($Needle)) { throw $Message }
}

$nsis = Get-Content -Raw -Encoding UTF8 -Path $nsisPath
$packageScript = Get-Content -Raw -Encoding UTF8 -Path $packagePath

Assert-Contains $nsis '!insertmacro MUI_PAGE_DIRECTORY' 'Installer phải có trang chọn thư mục.'
Assert-Contains $nsis 'InstallDirRegKey HKCU "Software\HairSpaManager" "InstallDir"' 'Installer phải nhớ thư mục cài hiện tại.'
Assert-Contains $nsis 'CreateShortcut "$DESKTOP\Salon.lnk"' 'Thiếu Desktop shortcut.'
Assert-Contains $nsis 'CreateShortcut "$SMPROGRAMS\Salon\Salon.lnk"' 'Thiếu Start Menu shortcut.'
Assert-Contains $nsis 'RequestExecutionLevel user' 'Installer phải chạy per-user để cho phép chọn ổ/thư mục mà không ép admin.'
Assert-Contains $nsis 'taskkill /IM salonmanager.exe /F' 'Silent updater phải đóng các process Salon trước khi thay binary.'
Assert-Contains $nsis 'Exec ''"$INSTDIR\salonmanager.exe"''' 'Silent updater phải mở lại Salon sau khi cài.'
Assert-Contains $packageScript 'Salon-Setup-$BuildName.exe' 'Tên artifact installer không đúng contract.'

if ($nsis -match '(?i)RMDir\s+/r\s+"?\$APPDATA' -or $nsis -match '(?i)Delete\s+"?\$APPDATA') {
  throw 'Installer/uninstaller không được xóa AppData.'
}
if ($nsis -match '(?i)HairSpaManager\\data') {
  throw 'Installer không được thao tác thư mục runtime data HairSpaManager\data.'
}

if ($RequireArtifacts) {
  $pubspec = Get-Content -Raw -Encoding UTF8 -Path $pubspecPath
  $match = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+\s*$')
  if (-not $match.Success) { throw 'Không đọc được version pubspec.' }
  $version = $match.Groups[1].Value
  $artifact = Join-Path $outputDir "Salon-Setup-$version.exe"
  if (-not (Test-Path $artifact)) { throw "Thiếu artifact installer: $artifact" }
  if ((Get-Item $artifact).Length -lt 1MB) { throw 'Installer nhỏ bất thường (<1MB).' }
}

Write-Host 'verify:installer passed.'
