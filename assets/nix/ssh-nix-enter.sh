#!/data/data/com.termux/files/usr/bin/bash
# sshd ForceCommand wrapper: make INCOMING ssh sessions seccomp-free, so Nix
# binaries (glibc — killed by Android's app seccomp filter otherwise) work over
# ssh without the caller having to remember `nix-enter`.
#
# Set as `ForceCommand` in sshd_config; it runs for every session and dispatches:
#   * remote command  (ssh host 'cmd', scp, git-over-ssh)  -> run via nix-enter
#   * interactive login (tty, no command)                  -> nix-enter shell
#   * sftp subsystem   (no tty, no command)                -> real sftp-server,
#                                                             UNWRAPPED, so file
#                                                             transfer still works
#
# The three cases are distinguished by $SSH_ORIGINAL_COMMAND and whether stdin is
# a tty. Interactive ssh already re-execs via ~/.bashrc, but going through
# nix-enter here too is harmless and idempotent (NIX_ROOTED short-circuits it).
PREFIX=/data/data/com.termux/files/usr

if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
  exec "$PREFIX/bin/nix-enter" bash -c "$SSH_ORIGINAL_COMMAND"
elif [ -t 0 ]; then
  exec "$PREFIX/bin/nix-enter"
else
  exec "$PREFIX/libexec/sftp-server"
fi
