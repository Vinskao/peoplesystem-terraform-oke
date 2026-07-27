# Installs push-people into your PowerShell profile.
#
# Run once:
#   powershell -ExecutionPolicy Bypass -File "F:\002-workspace\ty-multiverse\peoplesystem-terraform-oke\scripts\install-push-people.ps1"
#   . $PROFILE      <-- REQUIRED afterwards: -File runs in a CHILD process,
#                       so it cannot define functions in your current window.
#
# It appends a dot-source line to $PROFILE pointing at push-people.ps1, so future
# edits to that file take effect without touching the profile again.
# Any pre-existing inline "function push-people" in the profile is commented out,
# because two definitions in one file is a trap: whichever loads last silently wins.
#
# Safe to re-run. A timestamped backup of the profile is made before any change.
# Keep this file ASCII-only (PowerShell 5.1 reads BOM-less UTF-8 as ANSI).

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'push-people.ps1'
if (-not (Test-Path $scriptPath)) {
  Write-Host "[x] Not found: $scriptPath" -ForegroundColor Red
  exit 1
}

$beginMarker = '# >>> ty-multiverse push-people >>>'
$endMarker   = '# <<< ty-multiverse push-people <<<'
$sourceLine  = ". `"$scriptPath`""

# --- ensure profile exists -------------------------------------------------
$profileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDir)) {
  New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
  Write-Host "[+] Created $profileDir" -ForegroundColor DarkGray
}
if (-not (Test-Path $PROFILE)) {
  New-Item -ItemType File -Path $PROFILE -Force | Out-Null
  Write-Host "[+] Created $PROFILE" -ForegroundColor DarkGray
}

$lines = @(Get-Content -Path $PROFILE -ErrorAction SilentlyContinue)
if ($null -eq $lines) { $lines = @() }

# --- backup ----------------------------------------------------------------
if ($lines.Count -gt 0) {
  $backup = "$PROFILE.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  Copy-Item -Path $PROFILE -Destination $backup -Force
  Write-Host "[+] Backup: $backup" -ForegroundColor DarkGray
}

# --- drop any previous marker block (we re-append at the end) ---------------
$kept = New-Object System.Collections.Generic.List[string]
$inBlock = $false
$hadBlock = $false
foreach ($line in $lines) {
  if ($line -like "*$beginMarker*") { $inBlock = $true; $hadBlock = $true; continue }
  if ($line -like "*$endMarker*")   { $inBlock = $false; continue }
  if (-not $inBlock) { $kept.Add($line) }
}

# --- comment out a legacy inline "function push-people" ---------------------
# Two definitions in one profile is exactly why the old version kept winning.
$legacyStart = -1
for ($i = 0; $i -lt $kept.Count; $i++) {
  if ($kept[$i] -match '^\s*function\s+push-people\b') { $legacyStart = $i; break }
}

if ($legacyStart -ge 0) {
  # brace-match to find the end of the function
  $depth = 0
  $legacyEnd = -1
  $started = $false
  for ($i = $legacyStart; $i -lt $kept.Count; $i++) {
    $opens  = ([regex]::Matches($kept[$i], '\{')).Count
    $closes = ([regex]::Matches($kept[$i], '\}')).Count
    if ($opens -gt 0) { $started = $true }
    $depth += $opens - $closes
    if ($started -and $depth -le 0) { $legacyEnd = $i; break }
  }

  if ($legacyEnd -ge $legacyStart) {
    for ($i = $legacyStart; $i -le $legacyEnd; $i++) { $kept[$i] = "# [ty-mv disabled] " + $kept[$i] }
    Write-Host "[+] Commented out the old inline push-people (lines $($legacyStart+1)-$($legacyEnd+1))" -ForegroundColor Yellow
  } else {
    # Braces did not balance - do not touch it, just warn loudly.
    Write-Host "[!] Found an inline push-people at line $($legacyStart+1) but could not" -ForegroundColor Yellow
    Write-Host "    determine where it ends. Please delete it manually, otherwise it may" -ForegroundColor Yellow
    Write-Host "    keep overriding the repo version." -ForegroundColor Yellow
  }
}

# --- append our block at the very end so it always wins ---------------------
$kept.Add('')
$kept.Add($beginMarker)
$kept.Add($sourceLine)
$kept.Add($endMarker)

Set-Content -Path $PROFILE -Value $kept -Encoding UTF8
if ($hadBlock) {
  Write-Host "[ok] Updated $PROFILE" -ForegroundColor Green
} else {
  Write-Host "[ok] Added to $PROFILE" -ForegroundColor Green
}

# --- environment checks ----------------------------------------------------
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
  Write-Host "[!] ffmpeg is NOT in PATH. push-people needs it for the faststart step." -ForegroundColor Yellow
  Write-Host "    winget install Gyan.FFmpeg" -ForegroundColor DarkGray
} else {
  Write-Host "[ok] ffmpeg found." -ForegroundColor Green
}

# --- tell the truth about scope -------------------------------------------
# When run as `powershell -File ...` this is a CHILD process: nothing we define
# here can reach the caller's session. Only a dot-sourced run can.
$dotSourced = ($MyInvocation.InvocationName -eq '.')
if ($dotSourced) {
  . $scriptPath
  Write-Host "[ok] push-people loaded into THIS session." -ForegroundColor Green
  Write-Host ""
  Write-Host "Next: run  push-people" -ForegroundColor Cyan
} else {
  Write-Host ""
  Write-Host "IMPORTANT: this ran in a child process, so your current window still" -ForegroundColor Yellow
  Write-Host "has the OLD push-people loaded. Reload the profile first:" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "    . `$PROFILE" -ForegroundColor Cyan
  Write-Host "    push-people" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Sanity check - the new version prints [0/3] faststart remux ... first." -ForegroundColor DarkGray
  Write-Host "If you still see [1/2] Uploading, the old one is still loaded." -ForegroundColor DarkGray
}
