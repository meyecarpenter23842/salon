param(
  [switch]$RequireArtifacts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$servicePath = Join-Path $repoRoot 'lib\core\services\offline_update_service.dart'
$safeServicePath = Join-Path $repoRoot 'lib\core\services\safe_windows_update_service.dart'
$handoffPath = Join-Path $repoRoot 'lib\core\services\windows_self_update_handoff.dart'
$panelPath = Join-Path $repoRoot 'lib\features\settings\presentation\pages\windows_update_panel.dart'
$installerScriptPath = Join-Path $repoRoot 'installer\salon.nsi'
$databasePath = Join-Path $repoRoot 'lib\core\database\salon_database.dart'
$packageUpdatePath = Join-Path $PSScriptRoot 'package-update.ps1'
$outputDir = Join-Path $repoRoot 'dist\windows-release'
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$packageJsonPath = Join-Path $repoRoot 'package.json'

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if (-not $Text.Contains($Needle)) { throw $Message }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Message) {
  if ($Text.Contains($Needle)) { throw $Message }
}

$service = Get-Content -Raw -Encoding UTF8 -Path $servicePath
$safeService = Get-Content -Raw -Encoding UTF8 -Path $safeServicePath
$handoff = Get-Content -Raw -Encoding UTF8 -Path $handoffPath
$panel = Get-Content -Raw -Encoding UTF8 -Path $panelPath
$installer = Get-Content -Raw -Encoding UTF8 -Path $installerScriptPath
$database = Get-Content -Raw -Encoding UTF8 -Path $databasePath
$packageUpdate = Get-Content -Raw -Encoding UTF8 -Path $packageUpdatePath
$publicFeed = 'https://pub-3f0aad8b18e146eb9eb09b9529063295.r2.dev'

Assert-Contains $service $publicFeed 'Updater phải dùng đúng public R2 feed của Salon.'
Assert-Contains $service 'latest.json' 'Updater phải đọc latest.json.'
Assert-Contains $service 'SHA-256' 'Updater phải xác minh SHA-256.'
Assert-Contains $service 'pending_update.json' 'Updater phải có marker xác nhận sau restart.'

Assert-Contains $panel 'Kiểm tra cập nhật' 'UI thiếu nút Kiểm tra cập nhật.'
Assert-Contains $panel 'Cập nhật ngay' 'UI phải có một nút Cập nhật ngay tự tải và cài.'
Assert-Contains $panel 'SafeWindowsUpdateService' 'UI phải dùng safe self-update handoff.'

Assert-Contains $safeService 'BackupService' 'Updater an toàn phải tạo SQLite safety backup.'
Assert-Contains $safeService 'createBackup()' 'Updater an toàn phải gọi createBackup trước khi cài.'
Assert-Contains $safeService 'SalonDatabase.instance.close()' 'Updater phải đóng SQLite trước khi thoát app.'
Assert-Contains $safeService 'WindowsSelfUpdateHandoff' 'Updater phải bàn giao sang helper ngoài tiến trình.'
Assert-Contains $safeService 'exit(0)' 'Salon phải thoát sau khi đóng DB để helper cài đè binary.'
Assert-Contains $safeService 'self_update_helper.log' 'Updater phải truyền một helper log path ổn định để chẩn đoán lỗi sau handoff.'
Assert-Contains $safeService 'helperPid' 'Updater audit phải ghi PID của helper đã launch.'

Assert-Contains $handoff 'Start-Sleep -Milliseconds 900' 'Helper phải cho Salon thời gian ngắn để đóng DB và thoát trước khi cài.'
Assert-Contains $handoff 'CloseMainWindow()' 'Helper phải đóng các cửa sổ Salon còn lại theo cách graceful.'
Assert-Contains $handoff '[string]$LogPath' 'Helper phải nhận log path tuyệt đối từ app.'
Assert-Contains $handoff 'ascii.encode(windowsSelfUpdateHelperScript)' 'Dart phải ghi helper bằng ASCII để Windows PowerShell 5.1 không phụ thuộc code page.'
Assert-NotContains $handoff 'ParentPid' 'Helper không được chờ parent PID vì có thể kẹt timeout và mở lại bản cũ.'
Assert-NotContains $handoff 'Wait-ProcessExit' 'Helper không được phụ thuộc parent PID wait.'
Assert-Contains $handoff '-Wait' 'Helper phải chờ installer hoàn tất trước khi restart Salon.'
Assert-Contains $handoff 'Start-Process -FilePath $Executable' 'Helper phải tự mở lại Salon sau update.'
Assert-NotContains $handoff 'taskkill' 'Helper không được force-kill Salon.'
Assert-NotContains $installer 'taskkill' 'NSIS không được force-kill Salon khi SQLite có thể đang mở.'

$helperMatch = [regex]::Match(
  $handoff,
  "(?s)const windowsSelfUpdateHelperScript = r'''(.*?)''';"
)
if (-not $helperMatch.Success) {
  throw 'Không trích được PowerShell self-update helper để kiểm tra cú pháp.'
}
$helperScript = $helperMatch.Groups[1].Value
$nonAscii = @($helperScript.ToCharArray() | Where-Object { [int][char]$_ -gt 127 })
if ($nonAscii.Count -gt 0) {
  throw 'PowerShell self-update helper source phải chỉ chứa ASCII để tương thích Windows PowerShell 5.1.'
}

# Production writes this helper without a UTF-8 BOM. Parse an actual ASCII file
# instead of only ParseInput so CI exercises the same file-decoding boundary that
# previously broke on Windows PowerShell 5.1.
$tempHelper = Join-Path $env:TEMP "salon-self-update-verify-$PID.ps1"
try {
  [System.IO.File]::WriteAllText(
    $tempHelper,
    $helperScript,
    (New-Object System.Text.ASCIIEncoding)
  )
  $tokens = $null
  $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile(
    $tempHelper,
    [ref]$tokens,
    [ref]$parseErrors
  )
  if ($parseErrors.Count -gt 0) {
    throw "PowerShell self-update helper có lỗi cú pháp/file encoding: $($parseErrors[0].Message)"
  }
}
finally {
  Remove-Item -Force $tempHelper -ErrorAction SilentlyContinue
}

Assert-Contains $database "Platform.environment['APPDATA']" 'Database Windows phải nằm dưới AppData.'
Assert-Contains $installer 'InstallDir "$LOCALAPPDATA\Programs\Salon"' 'Installer phải cài binary ngoài thư mục database.'
if ($installer -match '(?im)^\s*(Delete|RMDir).*APPDATA') {
  throw 'Installer/uninstaller không được xóa dữ liệu AppData.'
}

Assert-Contains $packageUpdate 'latest.json' 'package:update phải sinh latest.json.'
Assert-Contains $packageUpdate 'UPLOAD LAST' 'Script phải nhắc upload manifest cuối cùng.'
Assert-Contains $packageUpdate 'package.json' 'package:update phải kiểm tra version mà Key Manager release profile đọc.'
Assert-Contains $packageUpdate 'Version lệch' 'package:update phải chặn package.json/pubspec version mismatch.'

$forbiddenRuntimeTokens = @(
  'cloudflarestorage.com',
  'secretAccessKey',
  'accessKeyId',
  'accountId',
  'S3 endpoint'
)
foreach ($token in $forbiddenRuntimeTokens) {
  foreach ($runtimeText in @($service, $safeService, $handoff)) {
    if ($runtimeText.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
      throw "Runtime updater chứa token vận hành bị cấm: $token"
    }
  }
}

if ($service -match '(?i)portable.*(copy|scan|migrat|adopt)' -or
    $service -match '(?i)(copy|scan|migrat|adopt).*portable') {
  throw 'Updater không được chứa logic adoption/migration từ portable.'
}

$pubspec = Get-Content -Raw -Encoding UTF8 -Path $pubspecPath
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+\s*$')
if (-not $versionMatch.Success) { throw 'Không đọc được version pubspec.' }
$version = $versionMatch.Groups[1].Value
$package = Get-Content -Raw -Encoding UTF8 -Path $packageJsonPath | ConvertFrom-Json
if ($package.version.ToString().Trim() -ne $version) {
  throw "package.json version $($package.version) không khớp pubspec $version"
}

if ($RequireArtifacts) {
  $installerPath = Join-Path $outputDir "Salon-Setup-$version.exe"
  $manifestPath = Join-Path $outputDir 'latest.json'
  if (-not (Test-Path $installerPath)) { throw "Thiếu installer: $installerPath" }
  if (-not (Test-Path $manifestPath)) { throw "Thiếu latest.json: $manifestPath" }

  $manifest = Get-Content -Raw -Encoding UTF8 -Path $manifestPath | ConvertFrom-Json
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
