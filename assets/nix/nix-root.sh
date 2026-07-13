#!/system/bin/sh
# Synthesise a root filesystem containing /nix, then pivot_root onto it.
#
# Nix bakes /nix/store into the ELF interpreter and RPATH of every binary it
# builds, and cache.nixos.org only serves paths under /nix. So a `nix` dentry
# must exist in the root directory. On Android / is the read-only system
# partition: creating the directory there means remounting system_b rw, which
# dirties the partition and makes incremental OTAs fail their source-hash check.
#
# So we don't. We build a tmpfs mirror of / that has the extra dentry, rbind the
# live submounts into it (which carries Magisk's magic mounts across intact),
# and pivot_root onto that. Not one byte is written to any system partition.
#
# pivot_root changes the root of the *mount namespace*, not just of the calling
# process -- so every process already running in the namespace is re-rooted too,
# and Magisk's requester-namespace mode (mnt_ns=1) means `su` setns()es into
# that same namespace and lands on this root. Root and Nix therefore share one
# view of the filesystem. That is the thing proot cannot do, and the reason this
# replaces Nix-on-Droid rather than sitting beside it.
#
# Run as root, in the mount namespace you want re-rooted. The Termux app's
# namespace dies with the app, so the shell hook re-runs this once per start.
#
#   usage: nix-root.sh <cmd> [args...]
set -eu

# Always have a command to exec, so `exec "$@"` never falls through to a second
# pivot when invoked bare.
[ "$#" -eq 0 ] && set -- /system/bin/true

BB="${PREFIX:-/data/data/com.termux/files/usr}/bin/busybox"
PREFIX=/data/data/com.termux/files/usr
TERMUX_HOME=/data/data/com.termux/files/home
TERMUX_UID=$(stat -c %u "$TERMUX_HOME")
# bionic has no /etc/passwd -- it maps uid -> name from built-in AID tables, and
# reports u0_aNNN. glibc will read the passwd we write below. The two must agree
# on the name or Nix (glibc) and the shell (bionic) disagree about $USER and end
# up with divergent /nix/var/nix/profiles/per-user paths.
#
# The name is configurable via a one-line file so a declarative config layer can
# pick a stable handle (e.g. "erahhal") instead of Android's per-install u0_aNNN.
# Absent -> fall back to the derived name, so this script stands alone unchanged.
# nix-enter.sh reads the same file for $USER; keep the two in sync.
TERMUX_USER="$(head -n1 "$TERMUX_HOME/.config/termux-config/username" 2>/dev/null || true)"
[ -n "$TERMUX_USER" ] || TERMUX_USER=$(stat -c %U "$TERMUX_HOME")
# Android tags each app's files with per-app MLS categories, e.g.
#   u:object_r:app_data_file:s0:c90,c257,c512,c768
# and mlsconstrain lets the app touch only files whose categories match exactly.
# This script runs as root (magisk, no categories), so everything it creates in
# the mirror is unreadable to the app until relabelled to the app's own context.
# The label on $TERMUX_HOME is exactly that context, so derive it from there.
APPCTX=$(ls -Zd "$TERMUX_HOME" | awk '{print $1}')
NIX_SRC=/data/data/com.termux/files/nix
STAGE=/data/local/tmp/nixroot

# Already re-rooted? Then just run the command.
[ -d /nix/store ] && exec "$@"

[ -d "$NIX_SRC" ] || { echo "nix-root: $NIX_SRC missing" >&2; exit 1; }

$BB mount --make-rprivate /

mkdir -p "$STAGE"
$BB mount -t tmpfs -o mode=0755 tmpfs "$STAGE"

# --- mirror every top-level entry of / --------------------------------------
# Symlinks are copied. Directories are rbind'ed, so live submounts come across:
# /data, /proc, /sys, /storage, and Magisk's magic mounts under /system.
for e in /*; do
  n=${e#/}
  [ "$n" = "etc" ] && continue            # rebuilt below
  if [ -L "$e" ]; then
    cp -a "$e" "$STAGE/$n"
  elif [ -d "$e" ]; then
    mkdir "$STAGE/$n"
    $BB mount --rbind "$e" "$STAGE/$n"
  else
    : > "$STAGE/$n"
    $BB mount --bind "$e" "$STAGE/$n"
  fi
done

# --- /etc: a real directory, not the usual symlink to /system/etc ------------
# Every Nix binary links against glibc, which wants /etc/passwd and
# /etc/resolv.conf. Android provides neither in a form glibc can use, and
# /system/etc is read-only so we can't add them. Since we own the mirror, /etc
# becomes a directory that symlinks through to each real /system/etc entry and
# adds the handful of files glibc needs.
mkdir "$STAGE/etc"
for e in /system/etc/*; do
  ln -s "$e" "$STAGE/etc/$(basename "$e")"
done

# Android ships passwd and group, but they are zero bytes -- bionic never reads
# them, it uses built-in AID tables. Drop the symlinks or the heredocs below
# would follow them onto the read-only partition and fail with EROFS.
rm -f "$STAGE/etc/passwd" "$STAGE/etc/group" "$STAGE/etc/ssl" "$STAGE/etc/nix"

# glibc's getpwuid() returns NULL without this, and Nix refuses to start.
cat > "$STAGE/etc/passwd" <<EOF
root:x:0:0:root:/root:/system/bin/sh
$TERMUX_USER:x:$TERMUX_UID:$TERMUX_UID:termux:$TERMUX_HOME:$PREFIX/bin/bash
nobody:x:9999:9999:nobody:/:/system/bin/sh
EOF

cat > "$STAGE/etc/group" <<EOF
root:x:0:
$TERMUX_USER:x:$TERMUX_UID:
nogroup:x:9999:
EOF

# glibc resolves through /etc/resolv.conf; bionic asks netd over a socket
# instead, so Android has no resolv.conf at all and every Nix download dies with
# "Could not resolve host". Take the nameservers from whichever network actually
# carries our uid: Termux sits inside the Tailscale VPN's uid range, so this
# picks up MagicDNS instead of leaking DNS around the tailnet.
dumpsys connectivity 2>/dev/null | awk -v uid="$TERMUX_UID" '
  /NetworkAgentInfo/ && /CONNECTED/ {
    if (!match($0, /DnsAddresses: \[[^]]*\]/)) next
    dns = substr($0, RSTART, RLENGTH)
    if (match($0, /Uids: <\{[^}]*\}>/)) {          # only VPNs carry a uid range
      u = substr($0, RSTART, RLENGTH)
      gsub(/[^0-9,-]/, "", u)
      n = split(u, parts, ",")
      for (i = 1; i <= n; i++) {
        if (split(parts[i], r, "-") == 2) {
          if (uid >= r[1] + 0 && uid <= r[2] + 0) { print "1 " dns; next }
        } else if (parts[i] + 0 == uid)           { print "1 " dns; next }
      }
    } else {
      print "2 " dns                               # plain network: lower priority
    }
  }' | sort -n | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | awk '!seen[$0]++' \
     | head -3 | sed 's/^/nameserver /' > "$STAGE/etc/resolv.conf"

mkdir -p "$STAGE/etc/ssl/certs"
ln -s "$PREFIX/etc/tls/cert.pem" "$STAGE/etc/ssl/certs/ca-certificates.crt"

# Android has no unprivileged user namespaces, so Nix's build sandbox can't
# work; and there are no build users in a single-user install.
mkdir -p "$STAGE/etc/nix"
cat > "$STAGE/etc/nix/nix.conf" <<EOF
build-users-group =
sandbox = false
experimental-features = nix-command flakes
EOF

# Relabel the whole synthesised /etc -- the real files and the symlinks -- to the
# app's context, or the app (untrusted_app:cNN) can't read its own resolv.conf,
# passwd or nix.conf. -h is essential: without it chcon dereferences each symlink
# and tries to relabel the read-only /system/etc target, failing with EROFS and
# aborting the whole pass. With -h it relabels the symlink inode itself.
chcon -h -R "$APPCTX" "$STAGE/etc" 2>/dev/null || true

# Android's hidepid stops the app reading /proc/stat, which makes libgc (used by
# Nix) print "Could not open /proc/stat" and skip its CPU-count optimisation.
# Harmless, but noisy on every Nix invocation. Shadow it with a readable stub,
# labelled for the app like everything else here.
printf 'cpu  0 0 0 0 0 0 0 0 0 0\n' > "$STAGE/etc/.fake-proc-stat"
chcon -h "$APPCTX" "$STAGE/etc/.fake-proc-stat" 2>/dev/null || true

# --- the whole point: a /nix dentry -----------------------------------------
mkdir "$STAGE/nix"
$BB mount --bind "$NIX_SRC" "$STAGE/nix"

# --- pivot -------------------------------------------------------------------
mkdir -p "$STAGE/oldroot"
cd "$STAGE"
$BB pivot_root . oldroot
cd /
# Bind the readable stub over /proc/stat now that the real /proc is in place
# under the new root. Best-effort: a failure here only brings the warning back.
$BB mount --bind /etc/.fake-proc-stat /proc/stat 2>/dev/null || true
$BB umount -l /oldroot
rmdir /oldroot 2>/dev/null || true

exec "$@"
