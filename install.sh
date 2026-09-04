#!/usr/bin/env bash
# install.sh — pasang `workflow` ke PATH (symlink). Default: /usr/local/bin/workflow
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/workflow"
BIN="${1:-/usr/local/bin/workflow}"

if [ ! -x "$SRC" ]; then
  echo "workflow belum executable — perbaiki dulu: chmod +x $SRC"
  exit 1
fi
ln -sf "$SRC" "$BIN"
echo "OK. '$BIN' -> $SRC"
echo "Coba:  cd ~/nevgo && workflow init"
