# Installs push-people into your PowerShell profile.
#
# Run once:
#   powershell -ExecutionPolicy Bypass -File "F:\002-workspace\ty-multiverse\peoplesystem-terraform-oke\scripts\install-push-people.ps1"
#
# It appends a single dot-source line to $PROFILE pointing at push-people.ps1,
# so future edits to that file take effect without touching the profile again.
# Safe to re-run: the line is only added if it is not already there.

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'push-people.ps1'
if (-not (Test-Path $scriptPath)) {
  Write-Host "[x] Not found: $scriptPath" -ForegroundColor Red
  exit 1
}

$marker = '# >>> ty-multiverse push-people >>>'
$line   = ". `"$scriptPath`""

# Ensure the profile file and its directory exist
$profileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDir)) {
  New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
  Write-Host "[+] Created $profileDir" -ForegroundColor DarkGray
}
if (-not (Test-Path $PROFILE)) {
  # UTF8 with BOM so PowerShell 5.1 never misreads the file as ANSI
  New-Item -ItemType File -Path $PROFILE -Force | Out-Null
  Write-Host "[+] Created $PROFILE" -ForegroundColor DarkGray
}

$content = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue
if ($null -eq $content) { $content = '' }

if ($content -like "*$marker*") {
  Write-Host "[=] Already installed in $PROFILE" -ForegroundColor Yellow
} else {
  $block = "`r`n$marker`r`n$line`r`n# <<< ty-multiverse push-people <<<`r`n"
  Add-Content -Path $PROFILE -Value $block -Encoding UTF8
  Write-Host "[ok] Added to $PROFILE" -ForegroundColor Green
}

# Load it into the current session too, so there is nothing else to do
. $scriptPath

if (Get-Command push-people -ErrorAction SilentlyContinue) {
  Write-Host "[ok] push-people is available in this session." -ForegroundColor Green
} else {
  Write-Host "[!] push-people did not load - check $scriptPath" -ForegroundColor Yellow
  exit 1
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
  Write-Host "[!] ffmpeg is NOT in PATH. push-people needs it for the faststart step." -ForegroundColor Yellow
  Write-Host "    winget install Gyan.FFmpeg" -ForegroundColor DarkGray
} else {
  Write-Host "[ok] ffmpeg found." -ForegroundColor Green
}

Write-Host ""
Write-Host "Next: run  push-people" -ForegroundColor Cyan
