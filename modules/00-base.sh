#!/data/data/com.termux/files/usr/bin/bash
# Module: base packages.
# Installs the Termux packages every other module depends on. `pkg install`
# is a no-op for already-installed packages, so this is safe to re-run.

run_base() {
  step "Base packages"

  local pkgs=(
    git          # repo cloning, gh git ops
    gh           # GitHub CLI (auth handled in the gh module)
    curl         # downloads (tailscale, claude installer)
    python       # mullvad gRPC client in termux-vpn-nest
    iptables     # routing fixes in start-vpn
    jq           # parsing the tailscale release JSON
    openssh      # ssh / scp; commonly needed
    termux-api   # bridge to Termux:API app (optional but handy)
  )

  info "Updating package lists (pkg update)"
  pkg update -y >/dev/null 2>&1 || warn "pkg update reported errors; continuing."

  info "Installing: ${pkgs[*]}"
  pkg install -y "${pkgs[@]}" || fail "pkg install failed."

  ok "Base packages present."
}
