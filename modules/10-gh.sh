#!/data/data/com.termux/files/usr/bin/bash
# Module: GitHub CLI auth.
# Ensures `gh` is installed (base module covers it), authenticates against
# github.com if not already, and wires gh up as git's credential helper so
# `git push`/`git clone` over HTTPS just works.

run_gh() {
  step "GitHub CLI (gh)"

  have gh || fail "gh not installed; run the base module first."

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
