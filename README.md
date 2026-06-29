# termux-config

One entry point for setting up my [Termux](https://termux.dev/) environment on
Android. Idempotent: works on a **fresh install** and is safe to **re-run** on
an existing one. This is the home for all future Termux setup — add a module,
don't bolt on a standalone script.

## What it sets up

| Module        | What it does |
|---------------|--------------|
| `base`        | Installs base Termux packages (`git`, `gh`, `curl`, `python`, `iptables`, `jq`, `openssh`, `termux-api`). |
| `gh`          | Authenticates the GitHub CLI (`gh auth login`) and wires it up as git's credential helper. |
| `vpn-nest`    | Installs [`termux-vpn-nest`](https://github.com/erahhal/termux-vpn-nest): downloads the static `tailscale`/`tailscaled` binaries, clones the repo, and runs its installer. Chains a Termux Tailscale/Headscale client through the Mullvad app. |
| `claude-code` | Runs the [`claude-code-android`](https://github.com/ferrumclaudepilgrim/claude-code-android) installer: Anthropic's native `claude` patched to run under Android. Heavy (~233 MB first time). |

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
