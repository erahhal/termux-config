# termux-config

One entry point for setting up my [Termux](https://termux.dev/) environment on
Android. Idempotent: works on a **fresh install** and is safe to **re-run** on
an existing one. This is the home for all future Termux setup — add a module,
don't bolt on a standalone script.

## What it sets up

| Module        | What it does |
|---------------|--------------|
| `base`        | Installs base Termux packages (`git`, `gh`, `curl`, `python`, `jq`, `openssh`, `termux-api`). |
| `gh`          | Authenticates the GitHub CLI (`gh auth login`) and wires it up as git's credential helper. |
| `vpn-nest`    | Installs [`termux-vpn-nest`](https://github.com/erahhal/termux-vpn-nest): downloads the static `tailscale`/`tailscaled` binaries, clones the repo, and runs its installer. Chains a Termux Tailscale/Headscale client through the Mullvad app. |
| `claude-code` | Runs the [`claude-code-android`](https://github.com/ferrumclaudepilgrim/claude-code-android) installer: Anthropic's native `claude` patched to run under Android. Heavy (~233 MB first time). |
| `gcam`        | Writes `/system/etc/sysconfig/pixel_experience_2019.xml` so the BSG GCam mod's power-button double-tap camera shortcut works (adds the `PIXEL_2019_EXPERIENCE` feature). `/system` is wiped by every OTA, so **re-run this module after each system update**, then soft-reboot. |
| `gcam-camhal-fix` | Installs a Magisk module that patches the OnePlus 13 (`dodge`) camera HAL config so the HDR+ merge job (`MMF_PLUS`) no longer freezes the camera preview/lens switching. Root + OnePlus 13 only; activates on reboot; OTA-resilient. Full write-up: [`assets/gcam/CAMERA-FREEZE-FINDINGS.md`](assets/gcam/CAMERA-FREEZE-FINDINGS.md). |
| `gadgetbridge` | Makes Gadgetbridge actually reconnect to a Garmin watch instead of needing a manual connect every time (which also breaks Find My Phone). Sets the per-device `prefs_key_device_reconnect_on_acl`, turns **off** `prefs_general_key_auto_reconnect_scan`, and asserts the Doze/appop exemptions. Root only. |

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
./install.sh gh vpn-nest     # run only the named modules
./install.sh --yes           # auto-confirm prompts
./install.sh --skip-claude   # skip the heavy claude-code-android install
./install.sh --list          # list module names
```

Env toggles also work on their own: `SKIP_CLAUDE=1 ./install.sh`,
`ASSUME_YES=1 ./install.sh`.

## Idempotency

Re-running is safe by design:

- **base** — `pkg install` no-ops for already-installed packages.
- **gh** — skips `gh auth login` when already authenticated; re-runs
  `gh auth setup-git` (harmless).
- **vpn-nest** — skips the tailscale download when the binaries already exist;
  `git pull --ff-only` on an existing clone (and refuses to clobber a dirty
  tree or a non-git directory).
- **claude-code** — the upstream installer classifies prior state and re-runs
  in place.
- **gcam** — no-ops if the `PIXEL_2019_EXPERIENCE` feature is already
  registered (or the file is already written and just awaiting a reboot);
  otherwise (re)writes it. Never reboots on its own. Skips cleanly without
  root. The full config-merge toolkit lives in `assets/gcam/`.
- **gcam-camhal-fix** — no-ops if the running camera config already carries
  the patch; otherwise (re)deploys the Magisk module, which activates on the
  next reboot and re-patches the current stock config each boot (OTA-safe).
  Never reboots on its own. Skips cleanly without root or on non-OnePlus-13
  hardware.
- **gadgetbridge** — checks the prefs first and leaves the app running
  untouched when they're already correct; only when something must change does
  it stop Gadgetbridge, edit, and relaunch it. Skips cleanly without root or
  when Gadgetbridge isn't installed. Touches only device-settings files that
  are actually Garmin, so other paired gadgets are left alone.

## Manual prerequisites (can't be scripted)

For the `vpn-nest` module to actually *run* (install still succeeds without it):

- Rooted Android with Magisk granting `su` to Termux.
- The official **Mullvad VPN** app, signed in and connected.
- A **Headscale** server URL + pre-auth key, entered on first `start-vpn`.

The `gh` module needs interactive GitHub authentication (browser or token) on
first run.

## Adding a module

1. Drop `modules/NN-name.sh` defining a `run_name()` function. Source helpers
   from `lib/common.sh` (logging, `confirm`, `repo_sync`, `require_termux`).
2. Register it in `install.sh`: add to `MODULE_ORDER` and `MODULE_FILE`.

Keep each module idempotent and self-describing.

## License

MIT — see [LICENSE](LICENSE).
