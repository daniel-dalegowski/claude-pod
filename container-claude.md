# Container environment

You are running inside a disposable Debian (trixie) container managed by claude-pod.

## Package management
- `sudo apt-get install -y <pkg>`, `sudo apt`, `sudo dpkg` work without a password prompt
- All other `sudo` commands are rejected — you do not have general root access
- The apt package cache is shared across sessions so already-fetched packages install quickly

## Node.js / npm
- `npm install -g <pkg>` installs to `~/.local/bin` — no sudo needed, already on PATH

## Python / pip
- `pip install <pkg>` installs to `/usr/local` — no sudo, no `--user`, no virtualenv required
- `python3 -m venv` is available if a project requires an isolated environment

## Other installers
- `/usr/local` is owned by the sandbox user, so any tool that installs there works without sudo: `gem install`, `make install`, `cmake --install .`, `cargo install --root /usr/local`, curl-based install scripts, etc.
- For tools that install to `~/.local` or `~/.<tool>` by default (Rust/cargo, Go, etc.) those paths work as-is

## Filesystem
- `/workspace` is the project directory, bind-mounted from the host — changes here persist across container restarts
- Everything outside `/workspace` is ephemeral — gone when the container stops
- `~` resolves to `/home/sandbox` inside this container, not the host user's home directory
- Do not attempt to access the host user's home directory; it is not mounted

## Network
- The container shares the host network namespace
- Any server you start is immediately reachable at `localhost:<port>` on the host — no port mapping needed
- Verified working: Vite dev server (and similar Node.js/web servers) are accessible in the host browser as soon as they bind
- Full internet access is available
- `/etc/resolv.conf` is a snapshot taken when the container was created, not a live view of the host's — if the host switches networks (wifi <-> mobile hotspot, VPN) while this container stays running, DNS lookups can start hanging/failing even though raw IP connectivity still works. Sudo cannot fix this (it's scoped to package management only). From the host, `claude-pod --fix-dns` copies the host's current resolv.conf into the container.

## Running Claude Code
- `cla` is a shorthand for `claude --dangerously-skip-permissions` — use it when you need to run Claude without permission prompts inside this container
- Authentication uses OAuth via the host browser (opened automatically via D-Bus portal), or `ANTHROPIC_API_KEY` if set on the host
- Tool permissions are pre-approved in `~/.claude/settings.json`; all standard tools (Bash, Read, Edit, Write, WebFetch, etc.) are allowed without prompting

## Docker / containers
- `docker` and `docker-compose` are available
- When the host Podman socket is active, they connect to it via `/var/run/docker.sock` — Podman is Docker API-compatible so `docker build`, `docker run`, `docker compose up`, etc. all work
- Containers you start this way are siblings on the host Podman, not nested inside this container — they bind to the host network namespace the same way this container does
- If `/var/run/docker.sock` is absent, the host socket was not running when this container started; the user can run `systemctl --user start podman.socket` and then restart the container

## Display and browser
- Wayland and X11 are passed through from the host display
- GUI applications you launch will appear on the host desktop via XWayland
- `SDL_VIDEODRIVER=x11` is set globally — SDL2/pygame apps go through XWayland rather than native Wayland (native Wayland silently fails to show windows in this passthrough setup)
- `xdg-open <url>` opens URLs in the host browser via D-Bus portal
- For CLI OAuth flows (e.g. `claude`, `gh auth login`), the browser will open automatically on the host
- **Screenshot tools (`scrot`, `xwd`, GNOME D-Bus screenshot API) do not work inside the container** — the Wayland compositor blocks cross-process X11 capture for security reasons. To verify a GUI app is working, ask the user to look at their screen directly.

## Escalation
- Two failed fixes on the same problem → stop and hand off to `debugger`. Don't try a third time yourself.
- `debugger` says it's a design problem, or a subsystem keeps breaking → `architect`.
- Before writing code for geometry, camera/projection math, coordinate transforms,
  numerics, concurrency, or anything with subtle invariants → `architect` first, then implement from its spec.
- When escalating, include: the symptom, what you tried, and the relevant file paths. Don't include your theory as fact.
