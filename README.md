# claude-pod

An ephemeral [Podman](https://podman.io/) sandbox that drops you into a disposable, isolated shell scoped to a single project directory. This is intended for running Claude Code with `--dangerously-skip-permissions` without exposing your home directory or host state.

The container is long-lived for the duration of a working session--closing a shell does not stop it. Multiple terminals can attach to the same container simultaneously. Only `claude-pod --down` ends the session.

## What's inside the initial container

- Debian (trixie) base — standard FHS, so a project's own install docs just work
- `bash`, `git`, `curl`, `build-essential`, Node.js LTS, Claude Code (`claude`)
- `cla` alias for `claude --dangerously-skip-permissions`
- Passwordless `sudo` scoped to `apt-get`/`apt`/`dpkg` only
- Wayland + X11/XWayland passthrough, GPU (`/dev/dri`), audio (PulseAudio/PipeWire), D-Bus
- `xdg-open` wired through D-Bus so OAuth flows open in your host browser
- Host networking allowing any port bound inside the container to be immediately reachable on the host at the same port number with no explicit publish step
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
