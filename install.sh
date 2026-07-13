#!/data/data/com.termux/files/usr/bin/bash
# termux-config — one entry point for setting up a Termux environment.
#
# Idempotent: safe on a fresh install and safe to re-run on an existing one.
# Each piece of setup is a module under modules/; this script just orders and
# runs them. Run as your normal Termux user (NOT su).
#
#   ./install.sh                 # run everything
#   ./install.sh gh vpn-nest     # run only the named modules
#   ./install.sh --yes           # auto-confirm prompts
#   ./install.sh --list          # list available modules
#
# Flags:
#   --yes / -y      assume "yes" to confirmation prompts (sets ASSUME_YES=1)
#   --skip-claude   skip the heavy claude-code-android install (SKIP_CLAUDE=1)
#   --list          print module names and exit
#
# Per-module env toggles also work standalone, e.g.:
#   SKIP_CLAUDE=1 ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# Module registry: friendly-name -> "file:function".
# Order here is the run order when no specific modules are requested.
MODULE_ORDER=(base nix gh vpn-nest claude-code gcam gcam-camhal-fix gadgetbridge)
declare -A MODULE_FILE=(
  [base]="00-base.sh:run_base"
  [nix]="05-nix.sh:run_nix"
  [gh]="10-gh.sh:run_gh"
  [vpn-nest]="20-vpn-nest.sh:run_vpn_nest"
  [claude-code]="30-claude-code.sh:run_claude_code"
  [gcam]="40-gcam.sh:run_gcam"
  [gcam-camhal-fix]="50-gcam-camhal-fix.sh:run_gcam_camhal_fix"
  [gadgetbridge]="60-gadgetbridge.sh:run_gadgetbridge"
  # Optional, not in MODULE_ORDER (so a plain ./install.sh won't change sshd).
  # Run explicitly: ./install.sh sshd-nix
  [sshd-nix]="70-sshd-nix.sh:run_sshd_nix"
)

# Print the leading comment header (everything from line 2 up to the first
# non-comment line), with the leading "# " stripped.
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$SCRIPT_DIR/install.sh"; }

list_modules() {
  printf 'Available modules (run order):\n'
  for m in "${MODULE_ORDER[@]}"; do printf '  %s\n' "$m"; done
}

# --- Parse args --------------------------------------------------------------
REQUESTED=()
for arg in "$@"; do
  case "$arg" in
    -y|--yes)     export ASSUME_YES=1 ;;
    --skip-claude) export SKIP_CLAUDE=1 ;;
    --list)       list_modules; exit 0 ;;
    -h|--help)    usage; exit 0 ;;
    -*)           fail "Unknown flag: $arg (try --help)" ;;
    *)
      [ -n "${MODULE_FILE[$arg]:-}" ] || fail "Unknown module: $arg (try --list)"
      REQUESTED+=("$arg")
      ;;
  esac
done
[ "${#REQUESTED[@]}" -gt 0 ] || REQUESTED=("${MODULE_ORDER[@]}")

# --- Run ---------------------------------------------------------------------
require_termux

printf '%s%s termux-config %s\n' "$_C_BOLD" "$_C_CYAN" "$_C_RST"
info "Modules: ${REQUESTED[*]}"

for m in "${REQUESTED[@]}"; do
  spec="${MODULE_FILE[$m]}"
  file="$SCRIPT_DIR/modules/${spec%%:*}"
  func="${spec##*:}"
  [ -f "$file" ] || fail "Module file missing: $file"
  # shellcheck disable=SC1090
  . "$file"
  "$func"
done

step "Done"
ok "termux-config finished: ${REQUESTED[*]}"
