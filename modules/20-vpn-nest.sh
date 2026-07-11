#!/data/data/com.termux/files/usr/bin/bash
# Module: termux-vpn-nest (Tailscale/Headscale chained through Mullvad).
# https://github.com/erahhal/termux-vpn-nest
#
# Three idempotent pieces:
#   1. tailscale + tailscaled static binaries at ~/tailscale, ~/tailscaled
#      (vpn-nest expects them there but doesn't fetch them itself)
#   2. clone/update the repo
#   3. run its install.sh (pip install --user h2 + symlink start-vpn)

VPN_NEST_URL="https://github.com/erahhal/termux-vpn-nest.git"
VPN_NEST_DIR="$HOME/termux-vpn-nest"

# Download & extract the static tailscale + tailscaled into $HOME if missing.
_install_tailscale_binaries() {
  if [ -x "$HOME/tailscale" ] && [ -x "$HOME/tailscaled" ]; then
    local ver
    ver="$("$HOME/tailscale" version 2>/dev/null | head -1)"
    ok "tailscale binaries present (version ${ver:-unknown}); skipping download."
    return 0
  fi

  local arch tarball url tmp
  arch="$(ts_arch)"
  info "Resolving latest stable tailscale tarball for $arch..."
  tarball="$(curl -fsSL 'https://pkgs.tailscale.com/stable/?mode=json' \
    | jq -r ".Tarballs.${arch}")" || fail "Couldn't query tailscale releases."
  [ -n "$tarball" ] && [ "$tarball" != "null" ] || fail "No tarball listed for arch $arch."
  url="https://pkgs.tailscale.com/stable/${tarball}"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  info "Downloading $url"
  curl -fSL --progress-bar "$url" -o "$tmp/ts.tgz" || fail "tailscale download failed."
  info "Extracting tailscale + tailscaled into \$HOME"
  # Tarball layout: tailscale_<ver>_<arch>/{tailscale,tailscaled}
  tar -xzf "$tmp/ts.tgz" -C "$tmp" --strip-components=1 \
    --wildcards '*/tailscale' '*/tailscaled' || fail "tailscale extract failed."
  install -m 0755 "$tmp/tailscale"  "$HOME/tailscale"
  install -m 0755 "$tmp/tailscaled" "$HOME/tailscaled"
  ok "Installed tailscale binaries to \$HOME."
}

run_vpn_nest() {
  step "termux-vpn-nest (Tailscale via Mullvad)"

  _install_tailscale_binaries
  repo_sync "$VPN_NEST_URL" "$VPN_NEST_DIR"

  # Its install.sh runs bare `pip install --user h2`; a prior python major
  # upgrade can leave pip's launcher pointing at a removed interpreter. Repair
  # pip first so a routine `pkg upgrade` doesn't break this module.
  ensure_pip || warn "pip repair incomplete; termux-vpn-nest install.sh may fail."

  info "Running termux-vpn-nest/install.sh"
  ( cd "$VPN_NEST_DIR" && ./install.sh ) || fail "termux-vpn-nest install.sh failed."

  ok "termux-vpn-nest installed. 'start-vpn' is on PATH."
  cat <<'EOF'

        Manual prerequisites (one-time, can't be scripted):
          - Rooted Android with Magisk granting su to Termux.
          - Official Mullvad VPN app installed, signed in, and connected.
          - A Headscale server URL + pre-auth key (entered on first run).

        First run:  start-vpn
          You'll be prompted for the Headscale URL (saved to
          ~/.config/termux-vpn-nest/config) and a pre-auth key.
EOF
}
