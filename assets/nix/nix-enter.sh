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

# Make sure /nix exists in this namespace first (pivot is per-app-namespace).
[ -d /nix/store ] || su -c "$PREFIX/bin/nix-root /system/bin/true" >/dev/null 2>&1

# Rebuild our supplementary group list as -G args (id -G includes inet=3003,
# without which Android's paranoid-network blocks all sockets).
_g=""
for _x in $(id -G); do _g="$_g -G $_x"; done

# MagiskSU's -c takes a single command string and ignores trailing positional
# args, so serialise the requested command (%q-quoted) into that string rather
# than passing "$@" positionally. No args -> an interactive login-ish bash.
if [ "$#" -eq 0 ]; then
  _cmd="exec $PREFIX/bin/bash"
else
  _cmd="exec"
  for _a in "$@"; do _cmd="$_cmd $(printf '%q' "$_a")"; done
fi

# su gives a bare PATH, so commands handed to nix-enter (bash, nix, ...) wouldn't
# resolve. Set Termux's PATH, then layer the Nix profile on top if it exists, so
# `nix-enter nix ...` and `nix-enter <nix-installed-tool>` work non-interactively.
_env='export NIX_ROOTED=1
export USER="$(id -un)"
export HOME=/data/data/com.termux/files/home
export TMPDIR=/data/data/com.termux/files/usr/tmp
export NIX_SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
export PATH=/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin
[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"'

# shellcheck disable=SC2086
exec su -Z "$(id -Z)" -g "$(id -g)" $_g -s "$PREFIX/bin/bash" "$(id -u)" \
  -c "$_env
$_cmd" \
  || { export NIX_ROOTED=1; exec "$PREFIX/bin/bash" "$@"; }
