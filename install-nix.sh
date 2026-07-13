#!/data/data/com.termux/files/usr/bin/bash
# Convenience wrapper: set up just Nix in Termux (the `base` + `nix` modules).
# Equivalent to `./install.sh base nix`, with any extra flags forwarded:
#
#   ./install-nix.sh            # base + nix
#   ./install-nix.sh --yes      # same, auto-confirming prompts
#
# See modules/05-nix.sh for what this does and README.md for prerequisites
# (rooted with Magisk; grant Termux su on the first prompt).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
exec "$SCRIPT_DIR/install.sh" base nix "$@"
