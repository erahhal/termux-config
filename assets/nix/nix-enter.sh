#!/data/data/com.termux/files/usr/bin/bash
# Enter a seccomp-free shell that still carries Termux's own uid, groups and
# SELinux context, inside the nix-rooted mount namespace. With arguments, run
# them there; with none, start an interactive shell.
#
# Why this exists: Android's zygote installs a seccomp-bpf filter on every app
# process, and that filter kills set_robust_list with SIGSYS. glibc calls
# set_robust_list during thread setup, so *every* Nix binary — and everything
# Nix installs — dies instantly under a normal Termux shell. Seccomp filters are
# inherited and cannot be removed, so the only way to run these binaries is to
# start from a process that never had the filter. A process spawned by magiskd
# (via su) is one. `su -Z <ctx> -g/-G <groups> <uid>` keeps our exact identity,
# so files stay correctly labelled and owned, while shedding the filter.
#
# The exec-based transition back into the app domain is what the companion
# Magisk module's sepolicy.rule permits.
set -u
PREFIX=/data/data/com.termux/files/usr

# Fast path: if we're already inside a seccomp-free rooted context (a prior
# nix-enter set NIX_ROOTED and the pivot is live), the su -Z re-exec is redundant
# — just run directly. This keeps `nix-enter <cmd>` ~free when called from an
# already-entered shell (e.g. a git credential helper firing on every push),
# instead of paying a magiskd round-trip each time. The Nix profile is already on
# PATH here (the entering shell sourced it), so commands still resolve.
if [ "${NIX_ROOTED:-}" = 1 ] && [ -d /nix/store ]; then
  if [ "$#" -eq 0 ]; then exec "$PREFIX/bin/bash"; else exec "$@"; fi
fi

# Make sure /nix exists in this namespace first (pivot is per-app-namespace).
[ -d /nix/store ] || su -c "$PREFIX/bin/nix-root /system/bin/true" >/dev/null 2>&1

# Rebuild our supplementary group list as -G args (id -G includes inet=3003,
# without which Android's paranoid-network blocks all sockets).
_g=""
for _x in $(id -G); do _g="$_g -G $_x"; done

# The username to present. A one-line config file lets a declarative layer pin a
# stable handle (e.g. "erahhal") instead of Android's per-install u0_aNNN; absent
# -> the derived name. Must match what nix-root.sh stamps into /etc/passwd, or
# glibc getpwuid and $USER disagree. Absolute path: $HOME may be unset out here.
_user="$(head -n1 /data/data/com.termux/files/home/.config/termux-config/username 2>/dev/null || true)"
[ -n "$_user" ] || _user="$(id -un)"

# MagiskSU preserves the environment across the su call, so export what the inner
# shell needs rather than injecting it as shell text. su hands us a bare PATH, so
# restore Termux's; the Nix profile is layered on top by the shell hook (which
# sources nix.sh when NIX_ROOTED is set) and, for -c commands, by the line below.
export NIX_ROOTED=1
export USER="$_user"
export HOME=/data/data/com.termux/files/home
export TMPDIR=/data/data/com.termux/files/usr/tmp
export NIX_SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
export PATH=/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin

# INTERACTIVE (no args): invoke su WITHOUT -c, but WITH -m. Both halves matter.
#
# no -c: with -c, MagiskSU forks the shell from magiskd and merely passes our fds
#   through. The pts is then an open file but NOT the new session's controlling
#   terminal, so bash cannot tcsetpgrp and degrades to
#     "cannot set terminal process group (-1): Inappropriate ioctl for device"
#     "no job control in this shell"
#   and anything wanting a real terminal (claude's TUI) sees a crippled one — it
#   decides it is non-interactive and drops into --print mode. Without -c, MagiskSU
#   allocates a proper pty (/debug_ramdisk/.magisk/pts/N) and makes the shell its
#   session leader, so job control works.
#
# -m: without -c, su also "logs us in" — it resets HOME to /data, USER to u0_aNNN
#   and PATH to magisk's. HOME=/data means bash looks for /data/.bashrc, so the
#   home-manager config never loads and no Nix tool is on PATH. -m
#   (--preserve-environment) keeps the HOME/USER we exported above.
#
# PATH is the one thing -m does NOT protect — MagiskSU always imposes its own. The
# shell hook ($PREFIX/etc/bash.bashrc -> profile.d/nix-enter.sh) puts Termux's bin
# back and layers the Nix profile on top, which is why PATH isn't fought over here.
if [ "$#" -eq 0 ]; then
  # shellcheck disable=SC2086
  exec su -m -Z "$(id -Z)" -g "$(id -g)" $_g -s "$PREFIX/bin/bash" "$(id -u)" \
    || exec "$PREFIX/bin/bash"
fi

# COMMAND (args given): -c is required, since MagiskSU ignores trailing positional
# args. No pty here — that's fine, these are non-interactive contexts (credential
# helpers, ssh commands, scripts). Anything wanting a terminal is already running
# inside an entered shell and takes the fast path above.
_cmd="exec"
for _a in "$@"; do _cmd="$_cmd $(printf '%q' "$_a")"; done

# shellcheck disable=SC2086
exec su -Z "$(id -Z)" -g "$(id -g)" $_g -s "$PREFIX/bin/bash" "$(id -u)" \
  -c '[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"
'"$_cmd" \
  || exec "$PREFIX/bin/bash" "$@"
