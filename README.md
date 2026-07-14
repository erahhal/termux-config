# termux-config

One entry point for setting up my [Termux](https://termux.dev/) environment on
Android. Idempotent: works on a **fresh install** and is safe to **re-run** on
an existing one. This is the home for all future Termux setup — add a module,
don't bolt on a standalone script.

## What it sets up

| Module        | What it does |
|---------------|--------------|
| `base`        | Installs the pre-Nix bootstrap packages (`git`, `curl`, `busybox`). Other modules pull their own Termux deps. |
| `nix`         | Installs **Nix natively in Termux** — no proot, no Nix-on-Droid. Synthesises a root filesystem holding `/nix` in the Termux mount namespace (nothing written to the read-only system partition, so incremental OTAs stay intact), then runs a single-user Nix install. New interactive shells re-exec seccomp-free so Nix's glibc binaries run. Root only. See [Nix module](#nix-module) below. |
| `gh`          | Authenticates the GitHub CLI (`gh auth login`) and wires it up as git's credential helper. |
| `claude-code` | Runs the [`claude-code-android`](https://github.com/ferrumclaudepilgrim/claude-code-android) installer: Anthropic's native `claude` patched to run under Android. Heavy (~233 MB first time). |

### Device config lives in `termux-nixcfg` now

The GCam pixel-feature, GCam camera-HAL freeze fix, Gadgetbridge Garmin-reconnect,
and **vpn-nest** modules were **retired from this repo**. Their config is declared in
[`termux-nixcfg`](https://github.com/erahhal/termux-nixcfg) — one source of truth
instead of two:

- **gcam / gcam-camhal-fix / gadgetbridge** — built as Nix artifacts (Magisk modules,
  app-prefs specs), applied by its `./apply-device.sh`.
- **vpn-nest** — now *entirely* Nix: `start-vpn` + `mullvad_dns.py` are packaged from
  the pinned upstream source, `h2` comes from nixpkgs (no more `pip install --user`,
  which is why this repo no longer needs an `ensure_pip` workaround), and
  tailscale/tailscaled + `HEADSCALE_URL` come from Home Manager. Nothing imperative
  is left, so the module is gone.

Not converted, still here: the GCam config-merge (`assets/gcam/install-gcam-config.sh`).

## Quick start

```sh
git clone https://github.com/erahhal/termux-config.git
cd termux-config
./install.sh
```

Run it as your **normal Termux user**, not `su`.

## Usage

```sh
./install.sh                 # run every module, in order
./install.sh gh claude-code  # run only the named modules
./install.sh --yes           # auto-confirm prompts
./install.sh --skip-claude   # skip the heavy claude-code-android install
./install.sh --list          # list module names
```

Env toggles also work on their own: `SKIP_CLAUDE=1 ./install.sh`,
`ASSUME_YES=1 ./install.sh`.

## Idempotency

Re-running is safe by design:

- **base** — `pkg install` no-ops for already-installed packages.
- **nix** — reuses an existing store and install; re-establishes the `/nix`
  mount if the app was restarted; heals SELinux labels; only appends the login
  hook once. Skips cleanly without root.
- **gh** — skips `gh auth login` when already authenticated; re-runs
  `gh auth setup-git` (harmless).
- **claude-code** — the upstream installer classifies prior state and re-runs
  in place.

## Manual prerequisites (can't be scripted)

- Rooted Android with Magisk granting `su` to Termux (needed by the `nix` module).

The VPN prerequisites (Mullvad app, Headscale URL + pre-auth key) now live with the
vpn-nest config in [`termux-nixcfg`](https://github.com/erahhal/termux-nixcfg).

The `gh` module needs interactive GitHub authentication (browser or token) on
first run.

## Nix module

Runs a real, native Nix — `aarch64-linux` glibc binaries from `cache.nixos.org`,
executing directly on the Android kernel. Not Nix-on-Droid (which fakes `/nix`
with proot/ptrace and, because proot is not a mount namespace, can never let a
`su` root shell see the store). This uses root instead of ptrace, so it's faster
*and* keeps `/nix` visible to root — every other `su`-based module here keeps
working unchanged.

**How it works.** Nix hardcodes `/nix/store` into every binary it builds, so a
`nix` directory must exist at the filesystem root. Android's `/` is the
read-only system partition. Rather than write there:

1. `nix-root` builds a **tmpfs mirror** of `/` that adds a `nix` entry,
   `--rbind`s the live submounts across (so `/system`, `/data`, `/proc` and
   Magisk's magic mounts all come through), binds the store dir onto `/nix`, and
   `pivot_root`s onto it. `pivot_root` re-roots the whole mount namespace, and
   Magisk's requester-namespace mode (`mnt_ns=1`) means `su` joins it too.
2. A synthesised `/etc` supplies the `passwd`/`group`/`resolv.conf`/`ssl` that
   glibc needs and bionic doesn't provide.
3. `nix-enter` re-execs the shell **seccomp-free** via `su -Z`, keeping Termux's
   uid, groups and SELinux context — necessary because Android's zygote seccomp
   filter SIGSYSes `set_robust_list`, which glibc calls on every thread start.
   The exec-based domain transition is granted by a small Magisk module
   (`termux_nix_selinux`, a generated `sepolicy.rule`).

Nothing is written to any system partition, so **incremental OTAs are
unaffected**.

Quick install (just Nix):

```sh
./install-nix.sh          # = ./install.sh base nix  (flags forwarded, e.g. --yes)
```

**Caveats.**

- **Root required** (Magisk, with `su` granted to Termux).
- The `sepolicy.rule` names Termux's SELinux domain (`untrusted_app_NN`, keyed to
  the app's `targetSdk`). It's generated at install from the live domain —
  **re-run `./install.sh nix` if a Termux update changes its `targetSdk`**, then
  reboot (or `magiskpolicy --live` is re-applied on the next run anyway).
- Only **interactive** shells auto-enter the seccomp-free environment. To run a
  Nix-built binary from a non-interactive context (a script, `ssh host cmd`),
  wrap it: `nix-enter <cmd>`.
- The store lives at `/data/data/com.termux/files/nix` (alongside Termux's
  `home` and `usr`) and counts against app storage.

## Adding a module

1. Drop `modules/NN-name.sh` defining a `run_name()` function. Source helpers
   from `lib/common.sh` (logging, `confirm`, `repo_sync`, `require_termux`).
2. Register it in `install.sh`: add to `MODULE_ORDER` and `MODULE_FILE`.

Keep each module idempotent and self-describing.

## License

MIT — see [LICENSE](LICENSE).
