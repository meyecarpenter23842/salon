# Requires PowerShell 7 (.NET certificate PEM export support).
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Address,
  [int]$Port = 8743,
  [string]$Directory = (Join-Path $env:APPDATA 'HairSpaManager\lan')
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw 'Run with PowerShell 7 (pwsh).'
}
$lanIp = [System.Net.IPAddress]::Parse($Address)
$lanBytes = $lanIp.GetAddressBytes()
$lanPrivate = $lanBytes.Length -eq 4 -and (
  $lanBytes[0] -eq 127 -or $lanBytes[0] -eq 10 -or
  ($lanBytes[0] -eq 172 -and $lanBytes[1] -ge 16 -and $lanBytes[1] -le 31) -or
  ($lanBytes[0] -eq 192 -and $lanBytes[1] -eq 168))
if (-not $lanPrivate -or $Port -lt 1 -or $Port -gt 65535) {
  throw 'Use a specific private IPv4 or loopback address and valid port.'
}
$lanDirectory = [System.IO.Path]::GetFullPath($Directory)
$lanConfigPath = Join-Path $lanDirectory 'config.json'
if (Test-Path -LiteralPath $lanConfigPath) {
  throw 'Configuration already exists. Back it up before changing identity/IP.'
}
New-Item -ItemType Directory -Path $lanDirectory -Force | Out-Null
if ($IsWindows) {
  $lanAcl = Get-Acl -LiteralPath $lanDirectory
  $lanAcl.SetAccessRuleProtection($true, $false)
  $lanSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  $lanRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $lanSid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
  $lanAcl.AddAccessRule($lanRule)
  Set-Acl -LiteralPath $lanDirectory -AclObject $lanAcl
}
$lanRsa = [System.Security.Cryptography.RSA]::Create(2048)
$lanCert = $null
try {
  $lanRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
    'CN=Salon Desktop', $lanRsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
  $lanSan = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
  $lanSan.AddIpAddress($lanIp)
  $lanRequest.CertificateExtensions.Add($lanSan.Build())
  $lanRequest.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new(
      $false, $false, 0, $true))
  $lanRequest.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
      [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor
      [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment, $true))
  $lanCert = $lanRequest.CreateSelfSigned(
    [DateTimeOffset]::UtcNow.AddMinutes(-5), [DateTimeOffset]::UtcNow.AddYears(1))
  $lanCertPath = Join-Path $lanDirectory 'certificate.pem'
  $lanKeyPath = Join-Path $lanDirectory 'private-key.pem'
  [System.IO.File]::WriteAllText($lanCertPath, $lanCert.ExportCertificatePem())
  [System.IO.File]::WriteAllText($lanKeyPath, $lanRsa.ExportPkcs8PrivateKeyPem())
  @{ address = $Address; port = $Port; certificatePath = $lanCertPath;
     privateKeyPath = $lanKeyPath } | ConvertTo-Json |
    Set-Content -LiteralPath $lanConfigPath -Encoding utf8
  $lanSha = [System.Security.Cryptography.SHA256]::HashData($lanCert.RawData)
  Write-Output "API URL: https://${Address}:${Port}/api/staff/v1"
  Write-Output "Certificate SHA-256: $([Convert]::ToHexString($lanSha).ToLowerInvariant())"
  Write-Output 'No firewall rule was changed. Restart the licensed desktop main app.'
} finally {
  if ($null -ne $lanCert) { $lanCert.Dispose() }
  $lanRsa.Dispose()
}
