# push-people (Bash / Git Bash / Zsh)
#
# Source this file from ~/.bashrc:
#   source "/f/002-workspace/ty-multiverse/peoplesystem-terraform-oke/scripts/push-people.sh"
# Run scripts/install-push-people.sh once to add that line automatically.

# 每次改動就更新版本號。它會在每次執行時印出來，
# 貼 log 給人看時一眼就知道跑的是哪一版 —— profile 只在載入時讀這個檔，
# session 停在舊版是很容易忽略的陷阱。
PUSH_PEOPLE_VERSION='2026.08.01-1'

push-people() {
  echo "push-people v$PUSH_PEOPLE_VERSION"
  local src="${PUSH_PEOPLE_SRC:-$HOME/person}"
  local work="$src/.faststart"
  (
    if [ -n "${ZSH_VERSION:-}" ]; then
      setopt local_options null_glob
    else
      shopt -s nullglob
    fi
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
      local n=0 skipped=0 renamed=0 dup=0 f out target first
      local ordered=() taken=" " failed=()

      # 先處理名稱本來就正確的，這樣 A_B.mp4 與 A__B.mp4 並存時，
      # 正確的那個先佔位，手誤那份會被當重複丟掉。
      for f in "${mp4s[@]}"; do case "$f" in *__*) ;; *) ordered+=( "$f" );; esac; done
      for f in "${mp4s[@]}"; do case "$f" in *__*) ordered+=( "$f" );; esac; done

      for f in "${ordered[@]}"; do
        # 收斂多打的底線：A__B__C.mp4 -> A_B_C.mp4。
        # 前端用 '_' 切成員，連續底線會切出空字串而整支被拒收，在來源端修掉最乾淨。
        target=$(printf '%s' "$f" | sed 's/__*/_/g')

        case "$taken" in
          *" $target "*)
            echo "  - 正規化後重複，略過: $f"
            dup=$((dup+1)); continue ;;
        esac
        taken="$taken$target "

        if [ "$target" != "$f" ]; then
          echo "  ~ $f -> $target"
          renamed=$((renamed+1))
        fi

        out="$work/$target"
        # 已處理過且比原檔新 → 沿用，不重跑
        if [ -f "$out" ] && [ "$out" -nt "$f" ]; then
          uploads+=( "$out" ); skipped=$((skipped+1)); continue
        fi
        if ffmpeg -y -v error -i "$f" -c copy -movflags +faststart "$out" </dev/null; then
          uploads+=( "$out" ); n=$((n+1))
        else
          echo "  ! $f 轉檔失敗，改上傳原檔（這支仍不是 faststart）"
          failed+=( "$f" )
          uploads+=( "$f" )
        fi
      done
      echo "      轉換 $n 個，沿用 $skipped 個，改名 $renamed 個，略過重複 $dup 個"

      # 驗證產出真的是 faststart：moov 必須排在 mdat 前面。
      # 只看 ffmpeg 的結束碼不夠 —— 之前就是有幾支「成功」了卻仍不是 faststart，
      # 而失敗時的退回原檔又只印一行警告，很容易被洗掉。
      local notfs=()
      for out in "${uploads[@]}"; do
        case "$out" in *.mp4) ;; *) continue ;; esac
        first=$(head -c 2048 "$out" 2>/dev/null | LC_ALL=C grep -aob -m1 -E 'moov|mdat' | head -1 | cut -d: -f2)
        [ "$first" = "mdat" ] && notfs+=( "$(basename "$out")" )
      done
      # 兩種都要報：moov 在檔尾的（會卡），以及 ffmpeg 根本轉不動的（通常是壞檔）。
      # 壞檔既沒有 moov 也沒有 mdat，光靠上面的偵測抓不到，所以要併進來一起列。
      if (( ${#notfs[@]} > 0 || ${#failed[@]} > 0 )); then
        echo
        echo "  ================ 注意 ================"
        if (( ${#notfs[@]} > 0 )); then
          echo "  ${#notfs[@]} 支上傳後仍不是 faststart（hover 會卡）："
          for f in "${notfs[@]}"; do echo "    - $f"; done
          echo "  試試重新編碼：ffmpeg -i in.mp4 -movflags +faststart out.mp4"
        fi
        if (( ${#failed[@]} > 0 )); then
          echo "  ${#failed[@]} 支 ffmpeg 無法處理（多半是檔案損毀）："
          for f in "${failed[@]}"; do echo "    - $f"; done
          echo "  用 ffprobe 檢查：ffprobe <檔名>"
        fi
        echo "  ======================================"
        echo
      else
        echo "      已驗證：全部 mp4 的 moov 都在檔頭"
      fi
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
# 清掉 PVC 上殘留的雙底線手誤檔。
# 只有在「收斂後的檔名也存在」時才刪，內容確定還在，絕不會刪到唯一的檔案。
kubectl exec "$POD" -- sh -c 'cd /images/people 2>/dev/null || exit 0
for f in *__*.mp4; do
  [ -e "$f" ] || continue
  g=$(printf "%s" "$f" | sed "s/__*/_/g")
  if [ "$g" != "$f" ] && [ -e "$g" ]; then
    rm -f "$f" && echo "removed redundant $f (kept $g)"
  fi
done'

# 只有組合影片有意義：前端要的是 A_B.mp4 / A_B_C.mp4。
# 單人影片（Wavo.mp4、Draeny2.mp4…）沒有底線，前端本來就會略過，
# 在這裡先濾掉可以縮小清單，也順便跳過編碼壞掉的檔名。
kubectl exec "$POD" -- ls -1 /images/people 2>/dev/null \
  | grep '\.mp4$' | grep '_' > /tmp/_mp4s.txt
v=$(wc -l < /tmp/_mp4s.txt | tr -d ' ')

# 這段刻意「完全不出現雙引號字元」。
# 之前 PowerShell 5.1 把參數傳給原生執行檔時吃掉了雙引號，
# printf '{"files":[' 變成 printf '{files:[' ，產出不是合法 JSON 卻沒人發現。
# 引號改成執行期用 \042 生成，任何傳輸方式都不可能再破壞它。
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

# 護欄：確認開頭真的是 {"files":[ ，不是被吃掉引號的版本。
expected_head=$(printf '{%sfiles%s:[' "$Q" "$Q")
actual_head=$(head -c 10 /tmp/pair-videos.json)
if [ "$actual_head" != "$expected_head" ]; then
  echo "ERROR: manifest 格式錯誤，不上傳（引號可能被吃掉）"
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
REMOTE
    # [驗證] 從「前端實際會走的公開網址」把 manifest 抓回來驗一次。
    # 光看上傳成功不夠 —— 之前就發生過檔案上去了但內容不是合法 JSON，
    # 前端靜默退回 probe，於是三人組永遠讀不到卻沒人發現。
    local url="https://peoplesystem.tatdvsonorth.com/images/people/pair-videos.json"
    echo
    echo "[驗證] $url"
    local body
    body=$(curl -fsS --max-time 20 "$url?t=$(date +%s)" 2>/dev/null || true)
    # 必須逐字元比對開頭是不是 {"files":[ 。
    # 用 grep 找 'files' 是不夠的：壞掉的 {files:[...] 也含有 files，會誤判成功。
    local vq expect actual
    vq=$(printf '\042')
    expect="{${vq}files${vq}:["
    actual=$(printf '%s' "$body" | head -c 10)

    if [ -z "$body" ]; then
      echo "  X 讀不到（404 或網路問題）—— 前端會退回 probe，三人組不會出現"
    elif [ "$actual" != "$expect" ]; then
      echo "  X 不是合法 JSON（前端會 JSON.parse 失敗並退回 probe）"
      echo "     預期開頭: $expect"
      echo "     實際開頭: $actual"
    else
      local total tri
      total=$(printf '%s' "$body" | tr ',' '\n' | grep -c '\.mp4' || true)
      tri=$(printf '%s' "$body" | tr ',' '\n' | grep -c '_.*_.*\.mp4' || true)
      echo "  OK manifest 合法：$total 支影片，其中三人以上 $tri 支"
      if [ "$tri" -eq 0 ]; then
        echo "  ! 沒有任何三人以上的影片 —— 檢查檔名是否為 A_B_C.mp4 格式"
      fi
    fi

    echo
    echo "完成，硬重整頁面（Ctrl+Shift+R）即可看到新圖"
    echo "然後到 palais group 頁按一次「建立影片快取」"
  )
}
