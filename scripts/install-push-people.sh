#!/usr/bin/env bash
# Installs push-people into ~/.bashrc (Git Bash / Zsh / Linux).
#
# Run once:
#   bash "/f/002-workspace/ty-multiverse/peoplesystem-terraform-oke/scripts/install-push-people.sh"
#
# Appends a single `source` line pointing at push-people.sh, so future edits to
# that file take effect without touching the rc again. Safe to re-run.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$here/push-people.sh"
[ -f "$target" ] || { echo "[x] 找不到 $target"; exit 1; }

rc="$HOME/.bashrc"
[ -n "${ZSH_VERSION:-}" ] && rc="$HOME/.zshrc"
touch "$rc"

marker='# >>> ty-multiverse push-people >>>'
if grep -qF "$marker" "$rc"; then
  echo "[=] 已經安裝在 $rc"
else
  {
    printf '\n%s\n' "$marker"
    printf 'source "%s"\n' "$target"
    printf '%s\n' '# <<< ty-multiverse push-people <<<'
  } >> "$rc"
  echo "[ok] 已加入 $rc"
fi

# Git Bash 的登入 shell 讀 ~/.bash_profile，沒有的話 ~/.bashrc 不會被載入
if [ ! -f "$HOME/.bash_profile" ] && [ ! -f "$HOME/.profile" ]; then
  printf '[ -f ~/.bashrc ] && . ~/.bashrc\n' > "$HOME/.bash_profile"
  echo "[+] 建立 ~/.bash_profile 以載入 ~/.bashrc"
fi

if command -v ffmpeg >/dev/null 2>&1; then
  echo "[ok] 找到 ffmpeg"
else
  echo "[!] PATH 裡沒有 ffmpeg —— faststart 步驟需要它"
  echo "    winget install Gyan.FFmpeg"
fi

echo
echo "重新載入：  source \"$rc\""
echo "接著執行：  push-people"
