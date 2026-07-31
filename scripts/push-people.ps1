# push-people (PowerShell)
#
# Dot-source this file from your PowerShell profile:
#   . "F:\002-workspace\ty-multiverse\peoplesystem-terraform-oke\scripts\push-people.ps1"
# Run scripts\install-push-people.ps1 once to add that line automatically.
#
# Keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI,
# so non-ASCII characters corrupt the string literals and break parsing.

# Bump this whenever the script changes. It is printed on every run so that a
# pasted log immediately shows which version produced it - the profile only
# re-reads this file when it loads, so a stale session is easy to miss.
$script:PushPeopleVersion = '2026.07.29-1'

# Re-reads this file into the current session. Use after the repo copy changes,
# instead of remembering `. $PROFILE` (which also re-runs everything else).
function push-people-reload {
  . "$PSCommandPath"
  Write-Host "reloaded push-people v$script:PushPeopleVersion" -ForegroundColor Green
}

function push-people {
  Write-Host "push-people v$script:PushPeopleVersion" -ForegroundColor DarkGray

  $src  = "$HOME\Pictures\images\characters"
  $work = Join-Path $src ".faststart"

  if (-not (Test-Path $src)) {
    Write-Host "[x] Directory not found: $src" -ForegroundColor Red
    return
  }

  # first level png/mp4 only (non-recursive); ignores subfolders like characters_padded\ and .faststart\
  $files = @(Get-ChildItem -Path $src -File | Where-Object { $_.Extension -eq '.png' -or $_.Extension -eq '.mp4' })
  if ($files.Count -eq 0) {
    Write-Host "[x] No png/mp4 files in $src" -ForegroundColor Red
    return
  }

  $pngs = @($files | Where-Object { $_.Extension -eq '.png' })
  $mp4s = @($files | Where-Object { $_.Extension -eq '.mp4' })
  $uploads = @($pngs | ForEach-Object { $_.FullName })

  # 0) Remux every mp4 with faststart (moov atom moved to the head).
  #    Without it the browser must download the whole clip before the first
  #    frame can play, which makes hover-to-play stall for seconds.
  #    -c copy means no re-encode: lossless and nearly as fast as a file copy.
  if ($mp4s.Count -gt 0) {
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
      Write-Host "[x] ffmpeg not found in PATH. Install it first:" -ForegroundColor Red
      Write-Host "    winget install Gyan.FFmpeg" -ForegroundColor DarkGray
      return
    }
    if (-not (Test-Path $work)) { New-Item -ItemType Directory -Path $work | Out-Null }

    Write-Host "[0/3] faststart remux: $($mp4s.Count) mp4 (-c copy, no re-encode) ..." -ForegroundColor Cyan
    $converted = 0
    $reused = 0
    $renamed = 0
    $skippedDup = 0
    $failedRemux = @()
    $taken = @{}

    # Process already-correct names first so that when both A_B.mp4 and A__B.mp4
    # exist, the properly-named one wins and the typo copy is dropped.
    $ordered = @($mp4s | Where-Object { $_.Name -notmatch '__' }) +
               @($mp4s | Where-Object { $_.Name -match '__' })

    foreach ($m in $ordered) {
      # Collapse accidental repeated underscores: A__B__C.mp4 -> A_B_C.mp4.
      # The frontend splits on '_', so a doubled underscore yields empty members
      # and the file is rejected. Fix it here instead of in every consumer.
      $targetName = [regex]::Replace($m.Name, '_{2,}', '_')

      if ($taken.ContainsKey($targetName)) {
        Write-Host "    [-] duplicate after normalize, skipping: $($m.Name)" -ForegroundColor Yellow
        $skippedDup++
        continue
      }
      $taken[$targetName] = $true

      if ($targetName -ne $m.Name) {
        Write-Host "    [~] $($m.Name) -> $targetName" -ForegroundColor Yellow
        $renamed++
      }

      $out = Join-Path $work $targetName
      # already processed and newer than the source -> reuse
      if ((Test-Path $out) -and ((Get-Item $out).LastWriteTime -gt $m.LastWriteTime)) {
        $uploads += $out
        $reused++
        continue
      }
      & ffmpeg -y -v error -i $m.FullName -c copy -movflags +faststart $out
      if ($LASTEXITCODE -eq 0) {
        $uploads += $out
        $converted++
      } else {
        Write-Host "    [!] remux failed: $($m.Name) - uploading original (still not faststart)" -ForegroundColor Yellow
        $failedRemux += $m.Name
        $uploads += $m.FullName
      }
    }
    Write-Host "      converted $converted, reused $reused, renamed $renamed, skipped-dup $skippedDup" -ForegroundColor DarkGray

    # Verify the outputs really are faststart: moov must appear before mdat.
    # Trusting ffmpeg's exit code is not enough - some files came out fine
    # according to the exit code yet still had moov at the tail, and the
    # fallback-to-original path only printed one line that was easy to miss.
    $notFastStart = @()
    foreach ($u in $uploads) {
      if (-not $u.EndsWith('.mp4')) { continue }
      try {
        $fs = [System.IO.File]::OpenRead($u)
        $buf = New-Object byte[] 2048
        $read = $fs.Read($buf, 0, 2048)
        $fs.Close()
        $text = [System.Text.Encoding]::ASCII.GetString($buf, 0, $read)
        $iMoov = $text.IndexOf('moov')
        $iMdat = $text.IndexOf('mdat')
        if ($iMdat -ge 0 -and ($iMoov -lt 0 -or $iMdat -lt $iMoov)) {
          $notFastStart += [System.IO.Path]::GetFileName($u)
        }
      } catch { }
    }

    if ($notFastStart.Count -gt 0 -or $failedRemux.Count -gt 0) {
      Write-Host ""
      Write-Host "  ================ WARNING ================" -ForegroundColor Yellow
      if ($notFastStart.Count -gt 0) {
        Write-Host "  $($notFastStart.Count) file(s) still NOT faststart (hover will stall):" -ForegroundColor Yellow
        foreach ($f in $notFastStart) { Write-Host "    - $f" -ForegroundColor Yellow }
        Write-Host "  Try a real re-encode: ffmpeg -i in.mp4 -movflags +faststart out.mp4" -ForegroundColor DarkGray
      }
      if ($failedRemux.Count -gt 0) {
        Write-Host "  $($failedRemux.Count) file(s) ffmpeg could not read (likely corrupt):" -ForegroundColor Yellow
        foreach ($f in $failedRemux) { Write-Host "    - $f" -ForegroundColor Yellow }
        Write-Host "  Inspect with: ffprobe <file>" -ForegroundColor DarkGray
      }
      Write-Host "  =========================================" -ForegroundColor Yellow
      Write-Host ""
    } else {
      Write-Host "      verified: moov is at the head for every mp4" -ForegroundColor DarkGray
    }
  }

  # 1) single scp call = single SSH handshake (per-file scp would re-handshake every time)
  Write-Host "[1/3] Uploading $($uploads.Count) files to oke-node:/tmp/ ..." -ForegroundColor Cyan
  & scp $uploads "oke-node:/tmp/"
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[x] scp failed (code $LASTEXITCODE)" -ForegroundColor Red
    return
  }

  # 2) migrate into the image-server pod (overwrite same names, keep the rest)
  # 3) build pair-videos.json manifest from the pod's real directory listing
  Write-Host "[2/3] Migrating into image-server pod ..." -ForegroundColor Cyan
  Write-Host "[3/3] Writing pair-videos.json manifest and cleaning /tmp ..." -ForegroundColor Cyan

  # single-quoted here-string: PowerShell must NOT expand $(...) or $f - the remote shell handles them.
  #
  # This is piped to ssh via STDIN, never passed as an argument. PowerShell 5.1
  # mangles double quotes when handing arguments to a native exe, which silently
  # turned printf '{"files":[' into printf '{files:[' and produced invalid JSON.
  # Feeding the script on stdin keeps every character intact.
  $remote = @'
set -u
POD=$(kubectl get pod -l app=image-server -o jsonpath="{.items[0].metadata.name}")
if [ -z "$POD" ]; then echo "ERROR: image-server pod not found"; exit 1; fi

n=0
for f in /tmp/*.png /tmp/*.mp4; do
  [ -f "$f" ] || continue
  kubectl cp "$f" "$POD:/images/people/$(basename "$f")" >/dev/null 2>&1 && n=$((n+1))
done
echo "migrated $n files into $POD"

# manifest: the frontend "build video cache" reads this in ONE request instead of
# brute-forcing thousands of HEAD probes. It is also the only way 3+ person
# videos (A_B_C.mp4) can ever be discovered - probing those is O(N^3).
# Remove leftover double-underscore typos that are now redundant.
# Only deletes A__B.mp4 when the collapsed A_B.mp4 also exists, so the content
# is provably still present - never deletes anything unique.
kubectl exec "$POD" -- sh -c 'cd /images/people 2>/dev/null || exit 0
for f in *__*.mp4; do
  [ -e "$f" ] || continue
  g=$(printf "%s" "$f" | sed "s/__*/_/g")
  if [ "$g" != "$f" ] && [ -e "$g" ]; then
    rm -f "$f" && echo "removed redundant $f (kept $g)"
  fi
done'

# Only combo videos matter: the frontend needs A_B.mp4 / A_B_C.mp4. Solo clips
# (Wavo.mp4, Draeny2.mp4 ...) have no underscore and are ignored anyway, so
# filtering them here keeps the manifest small and skips oddly-encoded names.
kubectl exec "$POD" -- ls -1 /images/people 2>/dev/null \
  | grep '\.mp4$' | grep '_' > /tmp/_mp4s.txt
v=$(wc -l < /tmp/_mp4s.txt | tr -d ' ')

# This block deliberately contains NO double-quote character anywhere.
# PowerShell 5.1 strips double quotes when handing arguments to a native exe,
# which silently turned printf {"files":[ into printf {files:[ and produced
# invalid JSON that nobody noticed. The quote is generated at runtime via \042,
# so no transport can break it again.
Q=$(printf '\042')
{
  printf '{'
  printf '%sfiles%s:[' "$Q" "$Q"
  first=1
  while IFS= read -r line; do
    if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
    printf '%s%s%s' "$Q" "$line" "$Q"
  done < /tmp/_mp4s.txt
  printf ']}'
  printf '\n'
} > /tmp/pair-videos.json

expected_head=$(printf '{%sfiles%s:[' "$Q" "$Q")
actual_head=$(head -c 10 /tmp/pair-videos.json)
if [ "$actual_head" != "$expected_head" ]; then
  echo "ERROR: manifest is malformed - not uploading"
  echo "  expected: $expected_head"
  echo "  actual  : $actual_head"
  rm -f /tmp/*.png /tmp/*.mp4 /tmp/_mp4s.txt /tmp/pair-videos.json
  exit 1
fi

if kubectl cp /tmp/pair-videos.json "$POD:/images/people/pair-videos.json" >/dev/null 2>&1; then
  echo "manifest written: $v combo videos"
  echo "  3+ person entries: $(grep -c '_.*_' /tmp/_mp4s.txt || true)"
else
  echo "WARN: manifest upload failed"
fi

rm -f /tmp/*.png /tmp/*.mp4 /tmp/_mp4s.txt /tmp/pair-videos.json
echo "cleaned /tmp"
'@

  # Pipe on stdin - see the note above. Never `& ssh oke-node $remote`.
  $remote | & ssh oke-node bash -s
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] remote step exited with code $LASTEXITCODE" -ForegroundColor Yellow
    return
  }

  # [verify] Fetch the manifest from the SAME public URL the frontend uses.
  # A successful upload is not proof: previously the file landed but its content
  # was not valid JSON, so the frontend silently fell back to probing and the
  # 3-person videos never showed up. Verify the end state, not the step.
  $url = "https://peoplesystem.tatdvsonorth.com/images/people/pair-videos.json"
  Write-Host ""
  Write-Host "[verify] $url" -ForegroundColor Cyan
  try {
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $resp = Invoke-WebRequest -Uri "$url`?t=$stamp" -UseBasicParsing -TimeoutSec 20
    $json = $resp.Content | ConvertFrom-Json
    $total = @($json.files).Count
    $tri = @($json.files | Where-Object { ($_ -split '_').Count -ge 3 }).Count
    Write-Host "  [ok] manifest valid: $total videos, $tri with 3+ people" -ForegroundColor Green
    if ($tri -eq 0) {
      Write-Host "  [!] no 3+ person videos found - check filenames look like A_B_C.mp4" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "  [x] manifest check FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "      The frontend will fall back to probing and 3-person videos" -ForegroundColor Red
    Write-Host "      will NOT appear. Do not skip this." -ForegroundColor Red
  }

  Write-Host ""
  Write-Host "[ok] Done. Hard-refresh (Ctrl+Shift+R), then click 'build video cache'" -ForegroundColor Green
  Write-Host "     once on the palais group page." -ForegroundColor Green
}
