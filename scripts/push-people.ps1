# push-people (PowerShell)
#
# Dot-source this file from your PowerShell profile:
#   . "F:\002-workspace\ty-multiverse\peoplesystem-terraform-oke\scripts\push-people.ps1"
# Run scripts\install-push-people.ps1 once to add that line automatically.
#
# Keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI,
# so non-ASCII characters corrupt the string literals and break parsing.

function push-people {
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
    foreach ($m in $mp4s) {
      $out = Join-Path $work $m.Name
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
        Write-Host "    [!] remux failed: $($m.Name) - uploading original" -ForegroundColor Yellow
        $uploads += $m.FullName
      }
    }
    Write-Host "      converted $converted, reused $reused" -ForegroundColor DarkGray
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
# Only combo videos matter: the frontend needs A_B.mp4 / A_B_C.mp4. Solo clips
# (Wavo.mp4, Draeny2.mp4 ...) have no underscore and are ignored anyway, so
# filtering them here keeps the manifest small and skips oddly-encoded names.
kubectl exec "$POD" -- ls -1 /images/people 2>/dev/null \
  | grep '\.mp4$' | grep '_' > /tmp/_mp4s.txt
v=$(wc -l < /tmp/_mp4s.txt | tr -d ' ')
{
  printf '{"files":['
  first=1
  while IFS= read -r line; do
    if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
    printf '"%s"' "$line"
  done < /tmp/_mp4s.txt
  printf ']}\n'
} > /tmp/pair-videos.json

# Guard: if quoting got mangled in transit the file is not valid JSON and the
# frontend would silently fall back to probing. Fail loudly instead.
if ! grep -q '"files"' /tmp/pair-videos.json; then
  echo "ERROR: manifest is malformed (quotes were stripped) - not uploading"
  head -c 200 /tmp/pair-videos.json
  echo
  rm -f /tmp/*.png /tmp/*.mp4 /tmp/_mp4s.txt /tmp/pair-videos.json
  exit 1
fi

if kubectl cp /tmp/pair-videos.json "$POD:/images/people/pair-videos.json" >/dev/null 2>&1; then
  echo "manifest written: $v combo videos"
else
  echo "WARN: manifest upload failed"
fi

rm -f /tmp/*.png /tmp/*.mp4 /tmp/_mp4s.txt /tmp/pair-videos.json
echo "cleaned /tmp"
'@

  # Pipe on stdin - see the note above. Never `& ssh oke-node $remote`.
  $remote | & ssh oke-node bash -s
  if ($LASTEXITCODE -eq 0) {
    Write-Host "[ok] Done. Hard-refresh (Ctrl+Shift+R) to see new images." -ForegroundColor Green
    Write-Host "[i] Verify manifest: https://peoplesystem.tatdvsonorth.com/images/people/pair-videos.json" -ForegroundColor DarkGray
    Write-Host "[i] Then click 'build video cache' once on the palais group page." -ForegroundColor DarkGray
  } else {
    Write-Host "[!] remote step exited with code $LASTEXITCODE" -ForegroundColor Yellow
  }
}
