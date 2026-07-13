#!/data/data/com.termux/files/usr/bin/bash
# Module: Nix, natively in Termux — no proot, no Nix-on-Droid.
#
# Nix bakes /nix/store into every binary it builds, and cache.nixos.org only
# serves paths under /nix, so a `nix` dentry has to exist in the root directory.
# Android's / is the read-only system partition; creating the directory there
# means remounting system_b rw, which dirties the partition and makes
# incremental OTAs fail their source-hash check — so we don't.
#
# assets/nix/nix-root.sh instead synthesises a root: a tmpfs mirror of / that
# carries the extra dentry, with the live submounts rbind'ed across, then
# pivot_root onto it. Nothing is written to any system partition.
#
# Nix-on-Droid solves the same problem with proot — faking /nix by trapping
# syscalls with ptrace. That has two costs this avoids: every syscall is trapped,
# and because proot is not a mount namespace, a root shell spawned by magiskd is
# never traced, so root can never see /nix. Here pivot_root re-roots the whole
# mount namespace, and Magisk's requester-namespace mode (mnt_ns=1) makes su
# join it — so root and Nix share one filesystem view and every existing
# su-based module in this repo keeps working untouched.
#
# Two Android obstacles beyond the mountpoint, both handled here:
#   * SELinux MLS — app files carry per-app categories; anything a root shell
#     creates is unreadable to the app until relabelled. nix-root.sh relabels
#     its /etc; nix_fix_labels relabels the store.
#   * seccomp — the zygote installs a filter that SIGSYSes set_robust_list, which
#     glibc (hence every Nix binary) calls. Filters are inherited and can't be
#     dropped, so Nix must run from a magiskd-spawned, filter-free process:
#     nix-enter re-execs the shell via `su -Z`, which needs one SELinux
#     transition rule — shipped as a Magisk module so it survives reboot.

NIX_STORE_DIR="/data/data/com.termux/files/nix"
NIX_ROOT_BIN="$PREFIX/bin/nix-root"
NIX_ENTER_BIN="$PREFIX/bin/nix-enter"
NIX_INSTALLER_URL="https://nixos.org/nix/install"
NIX_SEPOL_MODID="termux_nix_selinux"
NIX_HOOK_MARK="# >>> termux-config: nix >>>"

# Relabel a root-created store to this app's SELinux context. -h so store-internal
# symlinks are relabelled in place rather than dereferenced. Idempotent no-op once
# labels match. Never hardcodes the categories — they are per-app.
nix_fix_labels() {
  local want probe
  # install.sh runs with pipefail; a missing store must not trip set -e.
  want="$(ls -Zd "$HOME" 2>/dev/null | awk '{print $1}')" || true
  probe="$(ls -Zd "$NIX_STORE_DIR/store" 2>/dev/null | awk '{print $1}')" || true
  [ -n "$want" ] && [ -n "$probe" ] || return 0
  [ "$want" = "$probe" ] && return 0
  info "Relabelling the store: $probe -> $want"
  su -c "chcon -h -R '$want' '$NIX_STORE_DIR'" \
    || warn "chcon failed; Nix may be unable to read its own store."
}

# Install (and live-load) the Magisk module carrying the SELinux transition rule
# that lets `su -Z` re-enter Termux's app domain from an exec. The domain name
# (untrusted_app_NN) is derived from the *targetSdk* of the Termux build, so it
# is read live rather than hardcoded — re-run this module if Termux's targetSdk
# ever changes.
nix_install_sepolicy() {
  local appdom magiskdom moddir rule
  appdom="$(id -Z | cut -d: -f3)"                         # e.g. untrusted_app_27
  magiskdom="$(su -c 'id -Z' 2>/dev/null | cut -d: -f3)"  # e.g. magisk
  [ -n "$appdom" ] && [ -n "$magiskdom" ] \
    || { warn "Couldn't derive SELinux domains; skipping policy rule."; return 1; }

  rule=$(cat <<EOF
allow $magiskdom $appdom process { transition dyntransition siginh rlimitinh noatsecure }
allow $appdom app_data_file file entrypoint
allow $appdom $magiskdom process sigchld
EOF
)

  # Persist as a Magisk module (loaded by magiskpolicy at early boot).
  moddir="/data/adb/modules/$NIX_SEPOL_MODID"
  info "Installing SELinux Magisk module ($magiskdom -> $appdom transition)"
  su -c "mkdir -p '$moddir'" || { warn "Couldn't create $moddir."; return 1; }
  su -c "cp '$SCRIPT_DIR/assets/nix/magisk-module/module.prop' '$moddir/module.prop'"
  printf '%s\n' "$rule" | su -c "tee '$moddir/sepolicy.rule' >/dev/null"
  su -c "rm -f '$moddir/disable' '$moddir/remove'"

  # Load it now too, so no reboot is needed for this run.
  local live; live="$(printf '%s' "$rule" | awk 'NF' | sed 's/^/"/;s/$/"/' | tr '\n' ' ')"
  su -c "magiskpolicy --live $live" \
    || warn "magiskpolicy --live failed; rule will still apply after reboot."
}

run_nix() {
  step "Nix (native, no proot)"

  if ! su -c 'id' 2>/dev/null | grep -q 'uid=0'; then
    warn "root (su) not available; skipping nix."
    warn "Grant Termux root in Magisk, then re-run: ./install.sh nix"
    return 0
  fi
  have busybox || fail "busybox missing — the base module installs it."

  # --- helpers on PATH ------------------------------------------------------
  info "Installing nix-root and nix-enter"
  install -m 0755 "$SCRIPT_DIR/assets/nix/nix-root.sh"  "$NIX_ROOT_BIN"  || fail "install nix-root failed."
  install -m 0755 "$SCRIPT_DIR/assets/nix/nix-enter.sh" "$NIX_ENTER_BIN" || fail "install nix-enter failed."
  mkdir -p "$NIX_STORE_DIR"

  # --- SELinux transition rule (needed before any su -Z) --------------------
  nix_install_sepolicy

  # --- re-root this mount namespace -----------------------------------------
  # su joins our namespace (mnt_ns=1), so pivot_root re-roots every process
  # already running in it, including this shell — /nix is usable immediately.
  if [ ! -d /nix/store ] && ! grep -q ' /nix ' /proc/self/mountinfo 2>/dev/null; then
    info "Re-rooting the Termux mount namespace (pivot_root)"
    su -c "$NIX_ROOT_BIN /system/bin/true" || fail "nix-root failed."
  fi
  [ -d /nix ] || fail "/nix not visible after nix-root — the pivot did not take."
  ok "/nix is live (tmpfs mirror; system partition untouched)"

  # --- bootstrap nix --------------------------------------------------------
  # Through nix-enter: seccomp-free (or the installer's own nix-store SIGSYSes),
  # but still as the Termux user so store paths get this app's categories.
  if [ -x "$HOME/.nix-profile/bin/nix" ]; then
    nix_fix_labels    # heal a store left mislabelled by an earlier run
    info "Nix already installed: $("$NIX_ENTER_BIN" "$HOME/.nix-profile/bin/nix" --version 2>/dev/null)"
  else
    local tmp; mktempdir tmp
    info "Fetching the Nix installer"
    curl -fsSL "$NIX_INSTALLER_URL" -o "$tmp/install.sh" \
      || fail "Couldn't download the Nix installer."
    info "Running single-user install through nix-enter (downloads ~100 MB)"
    "$NIX_ENTER_BIN" sh "$tmp/install.sh" --no-daemon --no-modify-profile \
      || fail "Nix installer failed."
    nix_fix_labels
  fi

  # --- login hook -----------------------------------------------------------
  if grep -qF "$NIX_HOOK_MARK" "$HOME/.bashrc" 2>/dev/null; then
    info "Login hook already present in ~/.bashrc"
  else
    info "Adding the login hook to ~/.bashrc"
    cat >> "$HOME/.bashrc" <<'EOF'

# >>> termux-config: nix >>>
# nix-enter re-execs an interactive shell seccomp-free (so Nix's glibc binaries
# run) inside the nix-rooted namespace, keeping our uid/groups/SELinux context.
# NIX_ROOTED, which nix-enter sets, breaks the recursion; non-interactive shells
# are left alone. nix-enter self-heals the pivot if the app was restarted.
if [ -x "$PREFIX/bin/nix-enter" ]; then
  if [ -z "${NIX_ROOTED:-}" ]; then
    case $- in *i*) exec "$PREFIX/bin/nix-enter" ;; esac
  fi
  [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi
# <<< termux-config: nix <<<
EOF
  fi

  ok "Nix installed. Open a new Termux shell (it re-execs seccomp-free), then 'nix --version'."
}
