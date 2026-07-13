#!/data/data/com.termux/files/usr/bin/bash
# Module: seccomp-free sshd (optional).
#
# Android's app seccomp filter kills Nix's glibc binaries (see the nix module),
# and incoming ssh is one of the few entry points that does NOT pass through the
# interactive shell's nix-enter re-exec: `ssh host '<nix-tool>'` runs a
# non-interactive `$SHELL -c`, which stays seccomp-filtered. This installs a
# ForceCommand wrapper so ssh sessions run seccomp-free via nix-enter, while sftp
# file transfer still works.
#
# Not part of the default run — enable when you actually run sshd and want Nix
# tools reachable over ssh: ./install.sh sshd-nix
#
# No-op-safe to re-run. Needs the nix module (for $PREFIX/bin/nix-enter).

SSHD_WRAPPER="$PREFIX/bin/ssh-nix-enter"
SSHD_CONF_D="$PREFIX/etc/ssh/sshd_config.d"
SSHD_SNIPPET="$SSHD_CONF_D/10-nix-enter.conf"

run_sshd_nix() {
  step "seccomp-free sshd (ssh -> nix-enter)"

  if [ ! -x "$PREFIX/bin/nix-enter" ]; then
    warn "nix-enter not installed; run the nix module first: ./install.sh nix"
    return 0
  fi

  # The stock Termux sshd_config already has `Include sshd_config.d/*.conf`, so a
  # drop-in snippet is cleaner than editing the main file. Confirm it before
  # relying on it — an old config without the Include would silently do nothing.
  if ! grep -qE '^\s*Include\s+.*sshd_config\.d' "$PREFIX/etc/ssh/sshd_config" 2>/dev/null; then
    warn "sshd_config has no 'Include sshd_config.d/*.conf'; add it, or put"
    warn "'ForceCommand $SSHD_WRAPPER' directly in sshd_config."
  fi

  info "Installing ForceCommand wrapper -> $SSHD_WRAPPER"
  install -m 0755 "$SCRIPT_DIR/assets/nix/ssh-nix-enter.sh" "$SSHD_WRAPPER" \
    || fail "Could not install ssh-nix-enter wrapper."

  info "Writing $SSHD_SNIPPET"
  mkdir -p "$SSHD_CONF_D"
  cat > "$SSHD_SNIPPET" <<EOF
# Installed by termux-config (sshd-nix). Route ssh sessions through nix-enter so
# Nix binaries work over ssh; sftp is dispatched unwrapped by the wrapper.
ForceCommand $SSHD_WRAPPER
EOF

  ok "sshd wrapper installed. Restart sshd to apply (e.g. pkill sshd; sshd)."
  info "Interactive ssh and 'ssh host <cmd>' become seccomp-free; sftp unaffected."
}
