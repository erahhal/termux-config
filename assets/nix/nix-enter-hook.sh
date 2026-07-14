# termux-config: bootstrap every interactive shell into Nix.
#
# WHY THIS LIVES HERE AND NOT IN ~/.bashrc
# ---------------------------------------
# This hook is what re-execs a shell into the seccomp-free, nix-rooted namespace.
# It must live on the *Termux* filesystem, because it has to be readable when
# /nix does NOT exist:
#
#   * The declarative layer (home-manager) makes ~/.bashrc, ~/.profile and
#     ~/.bash_profile symlinks into /nix/store.
#   * /nix only exists inside the pivoted mount namespace, which is per-app and
#     is LOST whenever the Termux app process restarts.
#   * So after a restart those dotfiles are dangling symlinks. bash silently
#     skips unreadable startup files — no error, it just doesn't run them.
#
# A hook in ~/.bashrc therefore could never fire after a restart: the file that
# creates /nix would itself be unreadable until /nix already existed. That
# deadlock is exactly what this file breaks — it has no /nix dependency, so it
# can always bootstrap, and once nix-enter has pivoted, the store symlinks
# resolve and home-manager's real config loads normally.
#
# Sourced from two places, covering every interactive bash:
#   * $PREFIX/etc/profile  -> profile.d/*.sh  (LOGIN shells: Termux terminal,
#                                              tmux panes — tmux runs $SHELL -l)
#   * $PREFIX/etc/bash.bashrc                 (interactive non-login shells)
#
# Paths are absolute: nix-enter's inner environment does not export $PREFIX.

# nix-enter sets NIX_ROOTED, which breaks the recursion. Non-interactive shells
# are left alone (they'd break scripts and can't prompt for su); they reach Nix
# by calling `nix-enter <cmd>` explicitly. nix-enter self-heals the pivot, so no
# separate "is /nix mounted" check is needed here.
if [ -x /data/data/com.termux/files/usr/bin/nix-enter ] && [ -z "${NIX_ROOTED:-}" ]; then
  case $- in
    *i*) exec /data/data/com.termux/files/usr/bin/nix-enter ;;
  esac
fi

# Already inside (NIX_ROOTED). Two fix-ups, in order:
#
# 1. PATH. MagiskSU always imposes its own PATH (/debug_ramdisk:/sbin:...:/system/bin)
#    — even with -m, which does preserve HOME and USER. Left alone, the entered
#    shell has no Termux bin dir at all. Put it back (idempotently, so re-sourcing
#    or a nested shell doesn't stack duplicates).
case ":$PATH:" in
  *":/data/data/com.termux/files/usr/bin:"*) ;;
  *) PATH="/data/data/com.termux/files/usr/bin:$PATH"; export PATH ;;
esac

# 2. The Nix profile, layered on top so Nix's tools win over Termux's. Guarded by
#    -e: it lives under /nix and is absent if the pivot somehow isn't up.
[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"
