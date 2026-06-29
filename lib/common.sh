#!/data/data/com.termux/files/usr/bin/bash
# Shared helpers for termux-config modules.
# Sourced by install.sh and each modules/*.sh — not meant to run standalone.

# --- Logging -----------------------------------------------------------------
if [ -t 1 ]; then
  _C_CYAN=$'\033[0;36m'; _C_GREEN=$'\033[0;32m'; _C_YELLOW=$'\033[0;33m'
  _C_RED=$'\033[0;31m'; _C_BOLD=$'\033[1m'; _C_RST=$'\033[0m'
else
  _C_CYAN=; _C_GREEN=; _C_YELLOW=; _C_RED=; _C_BOLD=; _C_RST=
fi

info() { printf '%s[info]%s  %s\n' "$_C_CYAN" "$_C_RST" "$*"; }
ok()   { printf '%s[ok]%s    %s\n' "$_C_GREEN" "$_C_RST" "$*"; }
warn() { printf '%s[warn]%s  %s\n' "$_C_YELLOW" "$_C_RST" "$*" >&2; }
fail() { printf '%s[fail]%s  %s\n' "$_C_RED" "$_C_RST" "$*" >&2; exit 1; }
step() { printf '\n%s==>%s %s%s%s\n' "$_C_CYAN" "$_C_RST" "$_C_BOLD" "$*" "$_C_RST"; }

have() { command -v "$1" >/dev/null 2>&1; }

# --- Environment guards ------------------------------------------------------
require_termux() {
  [ -n "${PREFIX:-}" ] || fail "PREFIX unset. Run this inside Termux, not adb/proot shell."
  case "$PREFIX" in
    */com.termux/*) : ;;
    *) warn "PREFIX ($PREFIX) doesn't look like Termux; continuing anyway." ;;
  esac
  [ "${EUID:-$(id -u)}" -ne 0 ] || fail "Run as your normal Termux user, not root (su)."
}

# Map `uname -m` to the arch slug used by tailscale's static tarballs.
ts_arch() {
  case "$(uname -m)" in
    aarch64|arm64) echo arm64 ;;
    armv7l|armv8l|armv7) echo arm ;;
    x86_64|amd64) echo amd64 ;;
    i686|i386) echo 386 ;;
    *) fail "Unsupported arch for tailscale: $(uname -m)" ;;
  esac
}

# --- Interaction -------------------------------------------------------------
# ASSUME_YES=1 (or --yes on install.sh) auto-confirms every prompt.
confirm() {
  local prompt="${1:-Continue?}" reply
  if [ "${ASSUME_YES:-0}" = "1" ]; then return 0; fi
  if [ ! -t 0 ]; then
    warn "No TTY and ASSUME_YES unset; assuming 'no' for: $prompt"
    return 1
  fi
  read -r -p "$prompt [y/N] " reply
  case "${reply,,}" in y|yes) return 0 ;; *) return 1 ;; esac
}

# --- Git repo sync (idempotent) ---------------------------------------------
# repo_sync <git-url> <target-dir>
#   - absent      -> clone
#   - clean repo  -> fast-forward pull
#   - dirty repo  -> leave alone, warn
#   - non-repo    -> fail loudly (don't clobber)
repo_sync() {
  local url="$1" dir="$2"
  if [ ! -e "$dir" ]; then
    info "Cloning $url -> $dir"
    git clone "$url" "$dir"
    return 0
  fi
  [ -d "$dir/.git" ] || fail "$dir exists but is not a git repo; refusing to touch it."
  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    warn "$dir has local changes; skipping pull. Resolve manually to update."
    return 0
  fi
  info "Updating $dir (git pull --ff-only)"
  git -C "$dir" pull --ff-only || warn "Fast-forward pull failed for $dir; leaving as-is."
}
