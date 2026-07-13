#!/data/data/com.termux/files/usr/bin/bash
# Module: base packages (pre-Nix bootstrap core only).
#
# Deliberately minimal: just the three Termux packages needed BEFORE Nix exists,
# so a Nix-based setup carries no redundant Termux copies of tools Nix provides.
# Every other module installs its own Termux deps via `ensure_pkgs` (lib/common),
# and only when that module runs — e.g. the gh module pulls Termux `gh`, but a
# `base nix` install never does, because Nix's gh covers it. `pkg install` is a
# no-op for already-present packages, so this is safe to re-run.

run_base() {
  step "Base packages (bootstrap core)"

  # The irreducible pre-Nix trio. Everything else is per-module:
  #   git    — clone this repo + the module source repos (before any Nix binary)
  #   curl   — download the Nix installer (05-nix) and other installers
  #   busybox— pivot_root + mount --rbind/--make-rprivate for the nix module
  #            (Android's toybox mount has neither)
  local pkgs=(git curl busybox)

  info "Updating package lists (pkg update)"
  pkg update -y >/dev/null 2>&1 || warn "pkg update reported errors; continuing."

  ensure_pkgs "${pkgs[@]}"
  ok "Base packages step complete."
}
