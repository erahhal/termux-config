#!/data/data/com.termux/files/usr/bin/bash
# Module: GitHub CLI auth (repo1-standalone path).
# Installs Termux `gh`, authenticates against github.com if not already, and
# wires gh up as git's credential helper so HTTPS `git push`/`clone` just works.
#
# Note: the declarative (Nix) setup does NOT run this module — it gets gh from
# Nix and points git's credential helper at `nix-enter gh` (see termux-nixcfg).
# This module is for using termux-config on its own, without the Nix config.

run_gh() {
  step "GitHub CLI (gh)"

  ensure_pkgs gh
  have gh || fail "gh not installed and could not be installed."

  if gh auth status >/dev/null 2>&1; then
    ok "Already authenticated with GitHub:"
    gh auth status 2>&1 | sed 's/^/        /'
  else
    info "Not authenticated. Launching 'gh auth login' (interactive)."
    info "Pick: GitHub.com -> HTTPS -> authenticate via browser or token."
    if [ ! -t 0 ]; then
      warn "No TTY available; cannot run interactive 'gh auth login'."
      warn "Run 'gh auth login' yourself, then re-run this module."
      return 0
    fi
    gh auth login || fail "gh auth login failed or was cancelled."
    ok "Authenticated."
  fi

  # Idempotent: rewrites the helper lines in ~/.gitconfig each time.
  info "Configuring gh as git's credential helper (gh auth setup-git)."
  gh auth setup-git || warn "gh auth setup-git failed; HTTPS pushes may prompt."

  ok "GitHub CLI ready."
}
