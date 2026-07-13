#!/data/data/com.termux/files/usr/bin/bash
# Module: base packages.
# Installs the Termux packages every other module depends on. `pkg install`
# is a no-op for already-installed packages, so this is safe to re-run.

run_base() {
  step "Base packages"

  # start-vpn re-execs under su and relies on Android's root `ip`/iptables,
  # so no Termux iptables package is needed here.
  local pkgs=(
    git          # repo cloning, gh git ops
    gh           # GitHub CLI (auth handled in the gh module)
    curl         # downloads (tailscale, claude installer)
    python       # mullvad gRPC client in termux-vpn-nest
    jq           # parsing the tailscale release JSON
    openssh      # ssh / scp; commonly needed
    termux-api   # bridge to Termux:API app (optional but handy)
    busybox      # pivot_root + mount --rbind/--make-rprivate, for the nix module
                 # (Android's toybox mount has neither)
  )

  info "Updating package lists (pkg update)"
  pkg update -y >/dev/null 2>&1 || warn "pkg update reported errors; continuing."

  # Install individually so one unavailable package doesn't abort the rest.
  local p failed=()
  for p in "${pkgs[@]}"; do
    if pkg install -y "$p" >/dev/null 2>&1; then
      info "installed/present: $p"
    else
      warn "could not install: $p"
      failed+=("$p")
    fi
  done

  if [ "${#failed[@]}" -gt 0 ]; then
    warn "Some packages failed: ${failed[*]}"
    warn "Continuing — modules that need them will report if they're missing."
  fi
  ok "Base packages step complete."
}
