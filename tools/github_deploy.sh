#!/usr/bin/env bash
# github_deploy.sh — bantu push ~/nevgo ke GitHub (aman, tanpa simpan token).
#
# 3 mode, pilih salah satu:
#
#   1) Repo sudah dibuat di github.com, tinggal push (URL & token dari Anda):
#        GITHUB_TOKEN=<token> ./tools/github_deploy.sh https://github.com/<user>/ai-workflow-ledger.git
#
#   2) Buat repo + push via gh CLI (butuh gh terpasang & sudah `gh auth login`):
#        ./tools/github_deploy.sh --gh ai-workflow-ledger
#
#   3) Buat repo via API + push (token perlu scope repo baru):
#        GITHUB_TOKEN=<token> ./tools/github_deploy.sh --create ai-workflow-ledger
#
# Prinsip keamanan:
#   - Token hanya dipakai perintah, TIDAK ditulis ke .git/config (remote tetap
#     ber-URL bersih tanpa token). URL dengan token dipakai sekali lewat
#     http.extraHeader lalu dihapus.
#   - Tidak ada kredensial yang disimpan; kalau ragu, cabut token di GitHub.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[31mGAGAL: %s\033[0m\n' "$*" >&2; exit 1; }

# --- validasi repo lokal ---------------------------------------------------
[ -d .git ] || die "belum ada repo git — jalankan dulu ./workflow init"
git rev-parse --verify main >/dev/null 2>&1 || die "branch main tidak ditemukan"
if [ -n "$(git status --porcelain)" ]; then
  say "Ada perubahan belum di-commit. Commit dulu:"
  git status --short
  die "berhenti sampai working tree bersih (atau: ./workflow commit)"
fi

# --- pilih mode ------------------------------------------------------------
MODE="$1"
case "${MODE:-}" in
  --gh) shift; NAME="${1:?nama repo}"; GH=1;;
  --create) shift; NAME="${1:?nama repo}"; CREATE=1;;
  -*|"") die "pakai: $0 <repo-url.git> | $0 --gh <nama> | $0 --create <nama>";;
  *) URL="$MODE"; shift;;
esac

TOKEN="${GITHUB_TOKEN:-}"

# helper: remote clean (tanpa token) lalu push memakai header token sekali pakai
push_with_token() {
  local clean_url="$1"
  git remote remove origin 2>/dev/null || true
  git remote add origin "$clean_url"
  if [ -n "$TOKEN" ]; then
    # token tidak pernah masuk ke .git/config — hanya header pada perintah ini
    git -c http.extraHeader="Authorization: Bearer ${TOKEN}" push -u origin main \
      || die "push gagal (token salah/kadaluarsa atau repo belum diberi akses?)"
  else
    git push -u origin main || die "push gagal — login GitHub dulu (lihat docs/DEPLOY-GITHUB.md)"
  fi
}

# --- mode 2: gh CLI ----------------------------------------------------------
if [ "${GH:-0}" = "1" ]; then
  command -v gh >/dev/null || die "gh belum terpasang — mode 1/3 bisa tanpa gh"
  gh auth status >/dev/null 2>&1 || die "jalankan dulu: gh auth login"
  gh repo create "$NAME" --public --source . --remote origin --push \
    && say "OK -> https://github.com/$(gh api user -q .login)/$NAME"
  exit 0
fi

# --- mode 3: buat repo via API + push ----------------------------------------
if [ "${CREATE:-0}" = "1" ]; then
  [ -n "$TOKEN" ] || die "set GITHUB_TOKEN=<token> untuk mode --create"
  USER=$(curl -sS -H "Authorization: Bearer $TOKEN" https://api.github.com/user | python3 -c 'import sys,json;print(json.load(sys.stdin)["login"])') \
    || die "token tidak valid untuk API GitHub"
  curl -sS -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/user/repos \
    -d "{\"name\":\"$NAME\",\"public\":true,\"description\":\"Satu ledger & state machine untuk semua divisi yang dikerjakan banyak platform AI — CLI append-only + memori lintas sesi (dream).\"}" >/dev/null \
    || die "API menolak membuat repo (cek scope token: repo / public_repo)"
  say "Repo dibuat: https://github.com/$USER/$NAME"
  push_with_token "https://github.com/$USER/$NAME.git"
  exit 0
fi

# --- mode 1: repo sudah ada, tinggal push -------------------------------------
case "$URL" in
  *://*) clean="${URL#*://}"; clean="https://$clean";;
  *) clean="$URL";;
esac
push_with_token "$clean"
say "OK -> $clean"
