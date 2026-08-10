# claude-pod: Ephemeral Podman Sandbox for Claude Code — Build Spec

## Purpose

Provide a `claude-pod` command that drops the user into a disposable,
isolated Podman shell scoped to a single project directory — a general
sandbox for working on that project, inside which the user (or an agent
they invoke) can run `claude --dangerously-skip-permissions`, a different
agentic CLI, or the project's own tooling directly, in any combination. The
container must be destroyed automatically when the session ends, leaving no
mutated state behind. The system must handle three distinct workload shapes
without requiring per-project bespoke setup:

1. Plain CLI/headless work (default case).
2. Long-running web servers the user wants to view in a host browser.
3. GUI applications that need to open windows on the host display.

Host system is NixOS (rootless Podman available via
`virtualisation.podman.enable`). Target user is a single developer running
many unrelated, unpredictable projects — the design must not assume a fixed
set of languages/toolchains ahead of time.

## Non-goals

- Does not need to defend against a fully malicious/adversarial project
  (this is a personal dev convenience layer, not a security boundary against
  hostile code with unknown provenance).
- Does not need multi-user support.
- Does not need to persist container/project *state* across separate
  sessions by default — closing all shells and running `claude-pod --down`
  should leave nothing behind but the project directory's own files and the
  shared package cache (opt-in longer persistence beyond that is a stretch
  goal, see below). This is distinct from staying alive *within* a session
  across multiple concurrently open shells, which is a core requirement.

## Core design decisions (already made — do not re-litigate)

- **Container runtime:** rootless Podman, not Docker.
- **Lifecycle:** a container is **long-lived for the duration of a working
  session, not per-shell.** The first `claude-pod` invocation for a given
  project starts a detached, backgrounded container (`podman run -d`) and
  attaches an interactive shell to it; subsequent `claude-pod` invocations
  for the *same* project directory detect the already-running container and
  attach an additional shell to it (`podman exec -it`), rather than starting
  a new one. This is what allows one terminal to run an agent while a second
  terminal is opened alongside it to inspect files, tail logs, or poke
  around — exiting a shell (via `exit` or closing the terminal) does NOT
  stop the container; only an explicit stop command does. The container is
  still fully disposable — nothing survives an explicit stop/prune — it's
  just no longer torn down the instant one shell happens to close.
- **Isolation boundary:** filesystem access limited to the invoked project
  directory (bind-mounted) plus whatever the base image ships with. Host
  `$HOME` is NOT bind-mounted wholesale — this was a specific pain point with
  a prior Distrobox-based setup where the shared home directory caused state
  to leak and accumulate across unrelated projects. That mistake should not
  be repeated here.
- **Non-root:** container runs as a non-root user (Claude Code's
  `--dangerously-skip-permissions` refuses to start as root/sudo).
- **Credentials:** Claude Code auth/session data must NOT be baked into the
  image or bind-mounted from `~/.claude` on the host wholesale. Prefer
  passing `ANTHROPIC_API_KEY` as an environment variable per-run (already
  scoped, revocable, doesn't expose other host credential files) when it's
  set on the host. If interactive OAuth login inside the container is
  preferred instead for a given session, that's fine too — the launcher
  shouldn't force either path, since the user decides inside the shell
  whether/how to invoke `claude` at all.

## Required components

### 1. Base sandbox image

The base image must stay toolchain-agnostic without relying on Nix inside
the container. Nix was considered (to mirror the user's host workflow) but
rejected for this specific role: most arbitrary open-source projects assume
a standard FHS filesystem layout in their own install docs (`apt-get
install ...`, prebuilt binaries, native npm/pip packages with compiled
extensions), and translating those instructions into a correct `shell.nix`
is extra agent-side translation work with a less googleable failure mode
when it goes wrong — a cost not worth paying here, since these containers
are single-session and thrown away (`--rm`), so Nix's actual strength,
long-term reproducibility, isn't even being used. Nix remains the right
tool for the user's own host-side, long-lived project environments; it's
just the wrong fit for provisioning inside this disposable sandbox.

Containerfile contents:

- **Debian (`debian:trixie` or similar stable base)** — standard FHS
  layout, so an arbitrary project's own README/install instructions
  (`apt-get install`, `pip install -r requirements.txt`, `npm install`,
  `cargo build`, etc.) work the way their authors intended, with no
  translation step required.
- A real POSIX shell (`bash`), `git`, `curl`, `ca-certificates`, and common
  build essentials (`build-essential` or equivalent) so native extensions
  compile without an extra install step for the common case.
- Node.js (LTS) and `@anthropic-ai/claude-code` installed globally, OR the
  `sadjow/claude-code-nix` self-contained binary approach if that proves
  simpler to keep current inside a container build — pick whichever is less
  fragile to rebuild and document the choice.
- A non-root user (e.g. `sandbox`, uid/gid mapped sensibly for
  `--userns=keep-id` so bind-mounted files aren't owned by a mismatched UID)
  with **passwordless `sudo` scoped to package management only** (`apt-get`,
  `apt`, `dpkg` — not full unrestricted sudo). This is acceptable here
  specifically because the container is single-session and disposable: a
  privilege-escalation concern that would matter in a long-lived system has
  no lasting consequence in a container that's destroyed at the end of the
  session.
- `/workspace` as the working directory and mount point for the project.
- No secrets embedded in any layer.

Expected in-container workflow: Claude Code follows the project's own
install/setup documentation directly, using `sudo apt-get install ...`,
`pip`, `npm`, or whatever the project's own README specifies, the same way
it would on a bare Debian machine. No environment-description file needs to
be authored first — this is the ecosystem's default path for an unfamiliar
repo, and it's what Claude Code has the most training exposure to.

**Package cache persistence:** because the container is destroyed (`--rm`)
after every session, a bare container would re-download every apt package
from scratch on every single invocation. Mitigate with an optional
persistent volume over the apt cache:

```
podman run --rm \
  -v claude-pod-apt-cache:/var/cache/apt/archives \
  ...
```

This is safe to share across all `claude-pod` invocations regardless of
project — it's a package cache, not project state or credentials, so it
doesn't reintroduce the "shared `$HOME` muddling projects together" problem
from the Distrobox setup. Treat this named volume as a core requirement,
not a stretch goal — without it, every `claude-pod` session on a
dependency-heavy project pays a real cold-start cost.

The image should build reproducibly and be rebuildable on demand (e.g. a
`claude-pod --rebuild` flag or a separate `claude-pod-build` script) since
Claude Code itself updates frequently — this sandbox will go stale the same
way the nixpkgs package did, and the rebuild path should be a single command.

### 2. Network policy

Default: unrestricted egress is acceptable for this personal-use case
(this is not the high-assurance CI-firewall scenario), BUT the mechanism to
add an egress allowlist later (via an `init-firewall.sh`-style script and
`NET_ADMIN`/`NET_RAW` caps, following Anthropic's reference devcontainer
pattern) should be left as a clearly marked extension point, not built now.
Document how to add it later; do not implement it in v1.

### 3. The `claude-pod` launcher script

A single script (bash), installed on `$PATH` (e.g. via home-manager
`home.file` or a flake-provided package), implementing **start-or-attach**
semantics:

- Takes the current working directory as the project root by default, with
  an optional explicit path argument.
- Derives a **stable container name from the project directory path**
  (e.g. a hash or sanitized path, not a timestamp) — this is what makes
  "is there already a container for this project" a well-defined question.
- On invocation:
  1. Check whether a container with that project's name is already
     running (`podman ps --filter name=<name>`).
  2. **If not running:** start one detached —
     `podman run -d --name <name> ... <image> sleep infinity` (or an
     equivalent long-lived no-op PID 1) — with the project directory
     bind-mounted (`--userns=keep-id`) and any `--web`/`--gui` flags applied
     at this creation step only, since port publishing and device/socket
     mounts must be set at `run` time and can't be added to an already-running
     container. Then attach an interactive shell:
     `podman exec -it <name> bash`, landing at `/workspace`.
  3. **If already running:** ignore any `--web`/`--gui` flags passed this
     time (warn if they were given but don't match what the running
     container was actually started with — the user needs to stop and
     restart to change those), and just attach another shell:
     `podman exec -it <name> bash`. This is the multi-terminal case — a
     second `claude-pod` call in the same project directory, from a
     different terminal, drops into a second shell in the *same* container
     the agent is already running in, so files/processes are shared and
     visible between the two.
- Passes `ANTHROPIC_API_KEY` through from the host environment into the
  container at creation time if it's set (do not fail if it's unset — not
  every session inside the container will necessarily invoke `claude`).
- Supports the same explicit mode flags, meaningful only at creation time:

  - `claude-pod` (default / headless): no GUI, no port publishing.
  - `claude-pod --web [PORT...]`: publish the given container port(s) to the
    host (`-p 127.0.0.1:PORT:PORT`), bound to localhost only. Should accept
    one or more ports (e.g. `claude-pod --web 3000 5432`).
  - `claude-pod --gui`: enable GUI passthrough (see below).

  Flags should be combinable (a project might run a GUI app that also serves
  a debug web page).

- **Drops the user into an interactive shell (`bash`) at `/workspace`,
  not directly into a `claude` session.** The container is a general-purpose
  disposable environment for the project — the user decides what to run
  inside it once they're in: `claude --dangerously-skip-permissions`,
  a different agentic CLI, the project's own build/run commands directly,
  or any combination of these across the session, in as many concurrent
  shells as needed.
- Passes through any trailing args after `--` as a command to run in a new
  `exec` (not the shell) instead — e.g. `claude-pod -- claude
  --dangerously-skip-permissions -p "fix the bug"` runs that one command
  in the (already-running-or-newly-started) container and returns, without
  handing over an interactive shell. This does not stop the container
  afterward — it's just a one-off command against the existing session.
- **Explicit teardown:** `claude-pod --down` (or `--stop`) stops and
  removes the named container for the current project directory
  (`podman stop <name>`, relying on `--rm` at creation time to auto-remove
  once stopped). This is the only thing that ends the session — closing
  shells does not.

### 4. GUI passthrough

The host is NixOS; determine and support **whichever display server the
user is actually running** — check for Wayland first (`$WAYLAND_DISPLAY`),
fall back to X11 (`$DISPLAY`). Implement both code paths since the user may
switch or use different machines:

- **Wayland:** bind-mount the Wayland socket
  (`$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`) into the container at the same path,
  and set `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR` env vars inside the container
  to match.
- **X11 fallback:** bind-mount `/tmp/.X11-unix`, pass `DISPLAY` through, and
  document that the user will need to run `xhost +local:` (or a more scoped
  `xhost +SI:localuser:<container-user>` if achievable) before launching, or
  the script can attempt this automatically with a printed warning about
  what it just did to X access control.
- GPU passthrough (`/dev/dri`) should be optionally enabled via the `--gui`
  flag for apps that render with hardware acceleration; keep it off by
  default in headless/web modes.

### 5. Cleanup / observability

- Containers are removed on **explicit `claude-pod --down`**, not on shell
  exit — `--rm` at creation time means `podman stop` triggers removal, but
  nothing stops the container automatically just because a shell inside it
  closed. Verify a closed/crashed shell (including SIGKILL of a `podman
  exec` session) does not affect the container's continued running.
- A `claude-pod --list` (or documented `podman ps` filter) shows all
  currently running project containers, since multiple may run concurrently
  across different projects.
- A `claude-pod --prune` convenience command force-stops/removes any
  stragglers across all projects at once (e.g. if the user forgets to
  `--down` several sessions and wants to reclaim resources).

## Stretch goals (do not implement unless the above is solid first)

- Optional named/persistent variant (`claude-pod --persist <name>`) for the
  rare project where warm caches (e.g. installed node_modules) across runs
  are worth trading away the "fully ephemeral" guarantee — must be opt-in,
  never the default.
- Egress allowlist firewall script per Anthropic's reference pattern.
- Per-project Containerfile override, for the rare project needing
  something beyond what a Debian base plus package-manager sudo access can
  reasonably provide (unusual kernel modules, exotic hardware access).

## Acceptance criteria

- [ ] `claude-pod` from an arbitrary project directory starts a new
      container (if none is running for that project) and drops the user
      into an interactive shell at `/workspace` — it does not auto-launch
      `claude` or any other specific program.
- [ ] Running `claude-pod` a second time, from a **different terminal**, in
      the **same project directory** while the first shell is still open
      attaches a second shell to the *same* container — a file created from
      the first shell is immediately visible from the second, and a process
      started in one (e.g. a long-running agent) keeps running unaffected
      by the second shell opening or closing.
- [ ] Closing one of the shells (via `exit`, or killing the terminal) does
      NOT stop or remove the container — the other shell's session and any
      background processes continue unaffected.
- [ ] `claude-pod --down` stops and removes the container for the current
      project, and a subsequent `claude-pod` call starts a genuinely fresh
      one (no leftover state from the previous session, other than the
      project directory's own files and the persistent apt-cache volume).
- [ ] From a shell, manually running `claude --dangerously-skip-permissions`
      works correctly, as does running the project's own build/test/run
      commands directly, without needing to restart the container.
- [ ] `claude-pod -- <command>` runs the given command in the (existing or
      newly started) container and returns, without leaving an interactive
      shell open and without stopping the container afterward.
- [ ] Files created/edited by Claude Code inside the container are owned by
      the invoking host user afterward, not root or a mismatched UID.
- [ ] No trace of the container remains after `claude-pod --down`
      (`podman ps -a` clean for that project's name).
- [ ] `claude-pod --web 3000` makes a server started inside the container
      reachable at `localhost:3000` on the host.
- [ ] `claude-pod --gui` successfully opens a simple test GUI app (e.g.
      `xclock` or `xeyes` for X11, or a minimal Wayland client) on the host
      display, on whichever display server is currently active.
- [ ] Running two `claude-pod` instances concurrently in two different
      project directories does not conflict (container names, ports, mounts
      all independent).
- [ ] `ANTHROPIC_API_KEY` being unset on the host does not block
      `claude-pod` from starting a shell — it should only matter once/if
      `claude` is actually invoked inside that shell.
- [ ] Base image rebuild is a single documented command.
- [ ] Inside a fresh container, the sandbox user can `sudo apt-get install`
      a package without a password prompt, and cannot use `sudo` for
      anything outside package management (verify with a non-package `sudo`
      command that it's rejected).
- [ ] Following the plain install instructions for two dissimilar sample
      projects (e.g. a Python project with a `requirements.txt`, and a Rust
      project with a `Cargo.toml`) succeeds with no environment-description
      file authored ahead of time, using only the project's own docs.
- [ ] With the persistent apt-cache volume attached, a second `claude-pod`
      invocation on the same project does not re-download packages already
      fetched by the first invocation.
