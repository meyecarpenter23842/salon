param(
  [Parameter(Mandatory = $true)]
  [string]$SourcePng,

  [Parameter(Mandatory = $true)]
  [string]$OutputIco
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path $SourcePng)) {
  throw "Missing icon source PNG: $SourcePng"
}

Add-Type -AssemblyName System.Drawing

if (-not ('SalonIconNative' -as [type])) {
  Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class SalonIconNative {
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
'@
}

function New-SingleFrameIconBytes(
  [System.Drawing.Image]$Source,
  [int]$Size
) {
  $bitmap = New-Object System.Drawing.Bitmap(
    $Size,
    $Size,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
  )
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $hIcon = [IntPtr]::Zero
  $stream = $null

  try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.DrawImage($Source, 0, 0, $Size, $Size)

    $hIcon = $bitmap.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    $stream = New-Object System.IO.MemoryStream
    $icon.Save($stream)
    return $stream.ToArray()
  }
  finally {
    if ($stream) { $stream.Dispose() }
    if ($hIcon -ne [IntPtr]::Zero) {
      [void][SalonIconNative]::DestroyIcon($hIcon)
    }
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

function Read-SingleFramePayload([byte[]]$IcoBytes) {
  if ($IcoBytes.Length -lt 22) {
    throw 'Generated single-frame ICO is invalid.'
  }

  $count = [BitConverter]::ToUInt16($IcoBytes, 4)
  if ($count -ne 1) {
    throw "Expected one icon frame, got $count."
  }

  $length = [BitConverter]::ToUInt32($IcoBytes, 14)
  $offset = [BitConverter]::ToUInt32($IcoBytes, 18)
  if ($offset + $length -gt $IcoBytes.Length) {
    throw 'Generated ICO payload is truncated.'
  }

  $payload = New-Object byte[] $length
  [Array]::Copy($IcoBytes, $offset, $payload, 0, $length)

  return @{
    Width = $IcoBytes[6]
    Height = $IcoBytes[7]
    ColorCount = $IcoBytes[8]
    Reserved = $IcoBytes[9]
    Planes = [BitConverter]::ToUInt16($IcoBytes, 10)
    BitCount = [BitConverter]::ToUInt16($IcoBytes, 12)
    Payload = $payload
  }
}

$source = [System.Drawing.Image]::FromFile((Resolve-Path $SourcePng).Path)
try {
  $sizes = @(16, 24, 32, 48, 64, 128, 256)
  $frames = @()

  foreach ($size in $sizes) {
    $single = New-SingleFrameIconBytes $source $size
    $frame = Read-SingleFramePayload $single
    $frame['Size'] = $size
    $frames += $frame
  }

  $directoryLength = 6 + (16 * $frames.Count)
  $offset = $directoryLength

  $outDir = Split-Path -Parent $OutputIco
  if ($outDir) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  }

  $fileStream = [System.IO.File]::Open(
    $OutputIco,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None
  )
  $writer = New-Object System.IO.BinaryWriter($fileStream)

  try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$frames.Count)

    foreach ($frame in $frames) {
      $sizeByte = if ($frame['Size'] -eq 256) { [byte]0 } else { [byte]$frame['Size'] }
      $writer.Write($sizeByte)
      $writer.Write($sizeByte)
      $writer.Write([byte]$frame['ColorCount'])
      $writer.Write([byte]0)
      $writer.Write([UInt16]$frame['Planes'])
      $writer.Write([UInt16]$frame['BitCount'])
      $writer.Write([UInt32]$frame['Payload'].Length)
      $writer.Write([UInt32]$offset)
      $offset += $frame['Payload'].Length
    }

    foreach ($frame in $frames) {
      $writer.Write([byte[]]$frame['Payload'])
    }
  }
  finally {
    $writer.Dispose()
    $fileStream.Dispose()
  }
}
finally {
  $source.Dispose()
}

Write-Host "Installer icon ready: $OutputIco"
