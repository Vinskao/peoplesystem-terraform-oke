# push-people (Bash / Git Bash / Zsh)
#
# Source this file from ~/.bashrc:
#   source "/f/002-workspace/ty-multiverse/peoplesystem-terraform-oke/scripts/push-people.sh"
# Run scripts/install-push-people.sh once to add that line automatically.

push-people() {
  local src="$HOME/Pictures/images/characters"
  local work="$src/.faststart"
  (
    shopt -s nullglob
    cd "$src" || { echo "找不到資料夾: $src"; exit 1; }

    local pngs=( *.png )
    local mp4s=( *.mp4 )
    if (( ${#pngs[@]} + ${#mp4s[@]} == 0 )); then
      echo "$src 裡沒有 png/mp4 可上傳"
      exit 1
    fi

    # [0/3] mp4 一律轉成 faststart（moov 移到檔頭）。
    # 沒做這步的話，前端 hover 必須把整支下載完才能播第一格。
    # -c copy 不重新編碼，畫質無損、速度接近純複製。
    local uploads=( "${pngs[@]}" )
    if (( ${#mp4s[@]} > 0 )); then
      if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "找不到 ffmpeg，無法處理 faststart。請先安裝 ffmpeg 再執行。"
        exit 1
      fi
      mkdir -p "$work"
      echo "[0/3] faststart 處理 ${#mp4s[@]} 個 mp4（-c copy，不重新編碼）..."
      local n=0 skipped=0 f out
      for f in "${mp4s[@]}"; do
        out="$work/$f"
        # 已處理過且比原檔新 → 沿用，不重跑
        if [ -f "$out" ] && [ "$out" -nt "$f" ]; then
          uploads+=( "$out" ); skipped=$((skipped+1)); continue
        fi
        if ffmpeg -y -v error -i "$f" -c copy -movflags +faststart "$out" </dev/null; then
          uploads+=( "$out" ); n=$((n+1))
        else
          echo "  ! $f 轉檔失敗，改上傳原檔"
          uploads+=( "$f" )
        fi
      done
      echo "      轉換 $n 個，沿用快取 $skipped 個"
    fi

    echo "[1/3] 上傳 ${#uploads[@]} 個檔案到 oke-node:/tmp/ ..."
    scp "${uploads[@]}" oke-node:/tmp/ || { echo "scp 失敗"; exit 1; }

    echo "[2/3] 搬進 image-server pod（覆蓋、保留其餘）..."
    echo "[3/3] 產生 pair-videos.json 影片清單並清 /tmp ..."
    # 用 quoted heredoc 餵 stdin：遠端腳本內可自由使用單/雙引號，本機不做任何展開。
    # （舊寫法 ssh oke-node '...' 會讓遠端腳本不能出現單引號，manifest 那段一定會壞。）
    ssh oke-node bash -s <<'REMOTE'
set -u
POD=$(kubectl get pod -l app=image-server -o jsonpath="{.items[0].metadata.name}")
if [ -z "$POD" ]; then echo "ERROR: image-server pod not found"; exit 1; fi

n=0
for f in /tmp/*.png /tmp/*.mp4; do
  [ -f "$f" ] || continue
  kubectl cp "$f" "$POD:/images/people/$(basename "$f")" >/dev/null 2>&1 && n=$((n+1))
done
echo "migrated $n files into $POD"

# 影片清單 manifest：前端「建立影片快取」靠它一次 GET 取代數千次 HEAD 探測，
# 也是三人以上影片（A_B_C.mp4）唯一能被發現的途徑 —— 用猜的是 O(N^3)。
kubectl exec "$POD" -- ls -1 /images/people 2>/dev/null | grep '\.mp4$' > /tmp/_mp4s.txt
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

if kubectl cp /tmp/pair-videos.json "$POD:/images/people/pair-videos.json" >/dev/null 2>&1; then
  echo "manifest written: $v videos"
else
  echo "WARN: manifest upload failed"
fi

rm -f /tmp/*.png /tmp/*.mp4 /tmp/_mp4s.txt /tmp/pair-videos.json
echo "cleaned /tmp"
REMOTE
    echo "完成，硬重整頁面（Ctrl+Shift+R）即可看到新圖"
    echo "驗證 manifest: https://peoplesystem.tatdvsonorth.com/images/people/pair-videos.json"
    echo "然後到 palais group 頁按一次「建立影片快取」"
  )
}
