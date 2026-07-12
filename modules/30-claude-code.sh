#!/data/data/com.termux/files/usr/bin/bash
# Module: claude-code-android.
# https://github.com/ferrumclaudepilgrim/claude-code-android
#
# Installs Anthropic's official linux-arm64 claude binary, patched via
# glibc-runner to run under Android's bionic kernel, with an auto-updating
# wrapper at $PREFIX/bin/claude.
#
# We don't reimplement any of that — we fetch and run the upstream installer,
# which is itself idempotent (it classifies prior state and re-runs safely).
# Heavy: first install downloads ~233 MB and takes 5-10 min.

CCA_INSTALLER_URL="https://raw.githubusercontent.com/ferrumclaudepilgrim/claude-code-android/main/install.sh"

run_claude_code() {
  step "claude-code-android"

  if [ "${SKIP_CLAUDE:-0}" = "1" ]; then
    warn "SKIP_CLAUDE=1 set; skipping claude-code-android."
    return 0
  fi

  # The upstream installer warns that Android's low-memory killer can SIGKILL
  # the heavy glibc step when run inside a claude session. Surface that early.
  if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_EXECPATH:-}" ]; then
    warn "Running inside a claude session — Android may kill the install under"
    warn "memory pressure. A plain Termux shell is safer for this step."
    if ! confirm "Run the claude-code-android installer anyway?"; then
      warn "Skipped claude-code-android. Re-run from a plain Termux shell:"
      warn "  curl -fsSL $CCA_INSTALLER_URL -o install.sh && bash install.sh"
      return 0
    fi
  fi

  local tmp
  mktempdir tmp
  info "Fetching upstream installer"
  curl -fsSL "$CCA_INSTALLER_URL" -o "$tmp/install.sh" \
    || fail "Couldn't download claude-code-android installer."
  info "Running claude-code-android installer (this can take several minutes)"
  bash "$tmp/install.sh" || fail "claude-code-android installer failed."

  # Upstream prints its own "claude --version" with stderr merged in (2>&1), so a
  # harmless Android quirk gets glued onto that line: the claude binary walks the
  # dir tree at startup and readdir()s "/", which this app's uid can't read ->
  # 'Cannot read directory "/": EACCES'. It exits 0 and the TUI never shows it.
  # Print our own clean readout with stderr dropped so the final status is tidy.
  if command -v claude >/dev/null 2>&1; then
    local ver; ver="$(claude --version 2>/dev/null | head -n1)"
    ok "claude-code-android installed: ${ver:-ok}. Run 'claude' to start."
  else
    ok "claude-code-android installed. Run 'claude' to start."
  fi
}
