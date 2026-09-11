param(
  [switch]$RequireArtifacts,
  [switch]$RequireSignedArtifacts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$nsisPath = Join-Path $repoRoot 'installer\salon.nsi'
$packagePath = Join-Path $PSScriptRoot 'package-installer.ps1'
$handoffPath = Join-Path $repoRoot 'lib\core\services\windows_self_update_handoff.dart'
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$outputDir = Join-Path $repoRoot 'dist\windows-release'
$iconPath = Join-Path $outputDir '.salon-installer-icon.ico'

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if (-not $Text.Contains($Needle)) { throw $Message }
}

function Assert-ValidAuthenticodeSignature([string]$Path) {
  $signature = Get-AuthenticodeSignature -FilePath $Path
  if ($signature.Status -ne 'Valid') {
    throw "Authenticode signature không hợp lệ cho $Path: $($signature.Status)"
  }
}

function Get-IconBitmapHash([System.Drawing.Icon]$Icon) {
  $bitmap = $Icon.ToBitmap()
  $stream = New-Object System.IO.MemoryStream
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $stream.ToArray()
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
    $stream.Dispose()
    $bitmap.Dispose()
  }
}

function Assert-EmbeddedInstallerIcon([string]$ArtifactPath, [string]$SourceIconPath) {
  Add-Type -AssemblyName System.Drawing

  if (-not ('SalonShellIcon' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class SalonShellIcon {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern uint ExtractIconEx(
        string szFileName,
        int nIconIndex,
        IntPtr[] phiconLarge,
        IntPtr[] phiconSmall,
        uint nIcons);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
'@
  }

  $largeHandles = New-Object IntPtr[] 1
  $smallHandles = New-Object IntPtr[] 1
  $count = [SalonShellIcon]::ExtractIconEx(
    $ArtifactPath,
    0,
    $largeHandles,
    $smallHandles,
    1
  )
  if ($count -lt 1 -or $largeHandles[0] -eq [IntPtr]::Zero -or $smallHandles[0] -eq [IntPtr]::Zero) {
    throw 'Không extract được icon shell từ installer.'
  }

  $largeIcon = $null
  $smallIcon = $null
  $sourceLarge = $null
  $sourceSmall = $null
  try {
    $largeIcon = [System.Drawing.Icon]([System.Drawing.Icon]::FromHandle($largeHandles[0]).Clone())
    $smallIcon = [System.Drawing.Icon]([System.Drawing.Icon]::FromHandle($smallHandles[0]).Clone())
    $sourceLarge = New-Object System.Drawing.Icon($SourceIconPath, 32, 32)
    $sourceSmall = New-Object System.Drawing.Icon($SourceIconPath, 16, 16)

    if ((Get-IconBitmapHash $largeIcon) -ne (Get-IconBitmapHash $sourceLarge)) {
      throw 'Icon shell 32x32 trong installer không khớp icon Salon.'
    }
    if ((Get-IconBitmapHash $smallIcon) -ne (Get-IconBitmapHash $sourceSmall)) {
      throw 'Icon shell 16x16 trong installer không khớp icon Salon.'
    }
  }
  finally {
    if ($largeIcon) { $largeIcon.Dispose() }
    if ($smallIcon) { $smallIcon.Dispose() }
    if ($sourceLarge) { $sourceLarge.Dispose() }
    if ($sourceSmall) { $sourceSmall.Dispose() }
    if ($largeHandles[0] -ne [IntPtr]::Zero) { [void][SalonShellIcon]::DestroyIcon($largeHandles[0]) }
    if ($smallHandles[0] -ne [IntPtr]::Zero) { [void][SalonShellIcon]::DestroyIcon($smallHandles[0]) }
  }
}

$nsis = Get-Content -Raw -Encoding UTF8 -Path $nsisPath
$packageScript = Get-Content -Raw -Encoding UTF8 -Path $packagePath
$handoff = Get-Content -Raw -Encoding UTF8 -Path $handoffPath

Assert-Contains $nsis '!insertmacro MUI_PAGE_DIRECTORY' 'Installer phải có trang chọn thư mục.'
Assert-Contains $nsis 'InstallDirRegKey HKCU "Software\HairSpaManager" "InstallDir"' 'Installer phải nhớ thư mục cài hiện tại.'
Assert-Contains $nsis 'CreateShortcut "$DESKTOP\Hair Spa Manager.lnk"' 'Thiếu Desktop shortcut Hair Spa Manager.'
Assert-Contains $nsis 'CreateShortcut "$SMPROGRAMS\Hair Spa Manager\Hair Spa Manager.lnk"' 'Thiếu Start Menu shortcut Hair Spa Manager.'
Assert-Contains $nsis 'RequestExecutionLevel user' 'Installer phải chạy per-user để cho phép chọn ổ/thư mục mà không ép admin.'
Assert-Contains $nsis '!define MUI_FINISHPAGE_RUN "$INSTDIR\salonmanager.exe"' 'Installer tương tác phải cho phép mở Salon sau khi cài.'
Assert-Contains $handoff 'CloseMainWindow()' 'Silent updater phải đóng các cửa sổ Salon còn lại theo cách graceful.'
Assert-Contains $handoff '-Wait' 'Silent updater phải chờ installer hoàn tất trước khi mở lại Salon.'
Assert-Contains $handoff 'Start-Process -FilePath $Executable' 'Silent updater helper phải tự mở lại Salon.'
Assert-Contains $nsis '!define MUI_ICON "${APP_ICON}"' 'Installer phải dùng icon Salon qua MUI_ICON.'
Assert-Contains $nsis '!define MUI_UNICON "${APP_ICON}"' 'Uninstaller phải dùng icon Salon qua MUI_UNICON.'
Assert-Contains $packageScript 'icon.png' 'Package installer phải dùng icon.png làm nguồn icon.'
Assert-Contains $packageScript 'prepare-icon.ps1' 'Package installer phải tạo ICO đa kích thước trước khi chạy NSIS.'
Assert-Contains $packageScript '"/DAPP_ICON=$iconOutputPath"' 'Package installer phải truyền APP_ICON cho NSIS.'
Assert-Contains $packageScript 'Salon-Setup-$BuildName.exe' 'Tên artifact installer không đúng contract.'
Assert-Contains $packageScript 'SALON_SIGNING_THUMBPRINT' 'Package installer phải hỗ trợ certificate thumbprint từ môi trường local.'
Assert-Contains $packageScript 'signtool.exe' 'Package installer phải dùng Windows SignTool cho Authenticode.'
Assert-Contains $packageScript 'Invoke-CodeSign $salonExe' 'Windows app executable phải được ký trước khi đóng gói khi signing được bật.'
Assert-Contains $packageScript 'Invoke-CodeSign $artifactPath' 'Installer phải được ký sau khi NSIS đóng gói khi signing được bật.'

if ($nsis -match '(?i)taskkill' -or $handoff -match '(?i)taskkill') {
  throw 'Updater không được force-kill Salon khi SQLite có thể đang mở.'
}
if ($nsis -match '(?i)RMDir\s+/r\s+"?\$APPDATA' -or $nsis -match '(?i)Delete\s+"?\$APPDATA') {
  throw 'Installer/uninstaller không được xóa AppData.'
}
if ($nsis -match '(?i)HairSpaManager\\data') {
  throw 'Installer không được thao tác thư mục runtime data HairSpaManager\data.'
}

if ($RequireSignedArtifacts -and -not $RequireArtifacts) {
  throw 'RequireSignedArtifacts yêu cầu RequireArtifacts.'
}

if ($RequireArtifacts) {
  $pubspec = Get-Content -Raw -Encoding UTF8 -Path $pubspecPath
  $match = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+\s*$')
  if (-not $match.Success) { throw 'Không đọc được version pubspec.' }
  $version = $match.Groups[1].Value
  $artifact = Join-Path $outputDir "Salon-Setup-$version.exe"
  if (-not (Test-Path $artifact)) { throw "Thiếu artifact installer: $artifact" }
  if ((Get-Item $artifact).Length -lt 1MB) { throw 'Installer nhỏ bất thường (<1MB).'
  }
  if (-not (Test-Path $iconPath)) { throw "Thiếu icon installer đã tạo: $iconPath" }

  Assert-EmbeddedInstallerIcon $artifact $iconPath

  if ($RequireSignedArtifacts) {
    $releaseExe = Join-Path $repoRoot 'build\windows\x64\runner\Release\salonmanager.exe'
    if (-not (Test-Path $releaseExe)) { throw "Thiếu Windows executable để verify signature: $releaseExe" }
    Assert-ValidAuthenticodeSignature $releaseExe
    Assert-ValidAuthenticodeSignature $artifact
  }
}

Write-Host 'verify:installer passed.'
