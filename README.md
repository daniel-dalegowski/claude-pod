# claude-pod

An ephemeral [Podman](https://podman.io/) sandbox that drops you into a disposable, isolated shell scoped to a single project directory. This is intended for running Claude Code with `--dangerously-skip-permissions` without exposing your home directory or host state.

The container is long-lived for the duration of a working session--closing a shell does not stop it. Multiple terminals can attach to the same container simultaneously. Only `claude-pod --down` ends the session.

## Prior work

Several projects solve the same basic problem and may be more effective in various respects, depending on use case.

- [trekhleb/claude-pod](https://github.com/trekhleb/claude-pod) — Docker-based, same concept, broader compatibility
- [EvanCarroll/claude-podman](https://github.com/EvanCarroll/claude-podman) — rootless Podman, simpler scope

This project differs in that it targets NixOS specifically (distributed as a flake), adds GUI passthrough (Wayland/X11, GPU, audio), D-Bus integration for host-browser OAuth flows, and persistent session semantics.

## Security scope and limitations

This sandbox limits **filesystem access** — the container sees only the mounted project directory, not your home directory, SSH keys, or other projects. That is its primary purpose.

It does **not** protect against a determined adversary. Specifically:

- **Unrestricted network egress** — code running inside can reach the internet freely. A malicious prompt or compromised dependency could exfiltrate data or make outbound connections.
- **Host networking** — ports bound inside are immediately reachable on the host; there is no network namespace isolation.
- **Shared kernel** — container escapes via kernel exploits are theoretically possible; this is not a VM.
- **D-Bus and display passthrough** — GUI and D-Bus access are forwarded from the host, which widens the attack surface.

Use this for convenience and accidental-damage prevention when working with a trusted model on your own code. Do not rely on it as a security boundary against adversarial inputs.

## What's inside the initial container

- Debian (trixie) base — standard FHS, so a project's own install docs just work
- `bash`, `git`, `curl`, `build-essential`, Node.js LTS, Claude Code (`claude`)
- `cla` alias for `claude --dangerously-skip-permissions`
- Passwordless `sudo` scoped to `apt-get`/`apt`/`dpkg` only
- Wayland + X11/XWayland passthrough, GPU (`/dev/dri`), audio (PulseAudio/PipeWire), D-Bus
- `xdg-open` wired through D-Bus so OAuth flows open in your host browser
- Host networking allowing any port bound inside the container to be immediately reachable on the host at the same port number with no explicit publish step
- `docker` and `docker-compose` — connects automatically to the host Docker or Podman socket when available; no flag needed (works out of the box with `virtualisation.docker.enable = true` on NixOS)
- Persistent apt cache volume so packages aren't re-downloaded every session
- `ANTHROPIC_API_KEY` forwarded from the host if set

## Requirements

- Rootless Podman (`virtualisation.podman.enable` on NixOS)
- Wayland or X11 display server (for GUI passthrough; headless use needs neither)

## Install

### Via Nix flake (recommended on NixOS)

Add to `home.packages` in your home-manager config:

```nix
inputs.claude-pod.url = "path:/home/daniel/Documents/claude-pod";

home.packages = [ inputs.claude-pod.packages.${system}.default ];
```

Or run without installing:

```sh
nix run /home/daniel/Documents/claude-pod
```

### Manual

Copy `claude-pod` anywhere on your `$PATH`. The `Containerfile` and supporting files (`container-xdg-open`, `container-claude.md`) must live in the same directory as the script so `podman build` can find them.

## Usage

```sh
# Drop into a shell in the current directory
claude-pod

# Explicit project path
claude-pod --path ~/src/myproject

# Run a one-off command and return (container stays alive)
claude-pod -- claude --dangerously-skip-permissions -p "fix the bug"
claude-pod -- cla -p "fix the bug"   # same thing, shorter

# Stop and remove this project's container.
# Must be run from the same directory (or with the same --path) used to start it,
# because the container name is derived from the project path.
claude-pod --down
claude-pod --path ~/src/myproject --down   # if started with --path

# List all running claude-pod containers
claude-pod --list

# Force-stop all claude-pod containers
claude-pod --prune

# Rebuild the base image (e.g. after Claude Code updates)
claude-pod --rebuild
```

Each project directory gets its own container, identified by a hash of the path. Running `claude-pod` a second time from a different terminal attaches a new shell to the same container, allowing for inspection of the coding agent's work..

## Rebuilding the image

The base image is built automatically the first time you run `claude-pod` — no manual step required.

To update it later (e.g. when a new Claude Code version is released):

```sh
claude-pod --rebuild
```

`--rebuild` re-runs `npm install -g @anthropic-ai/claude-code`, which pulls the latest published version from npm. It also rebuilds any other image layers, so Debian security updates will be picked up at the same time.

## Network firewall extension point

By default the container has unrestricted egress. To add an outbound allowlist later, place an `init-firewall.sh` in the container and run with `--cap-add NET_ADMIN --cap-add NET_RAW`. See the comment in `Containerfile` for the extension point.
