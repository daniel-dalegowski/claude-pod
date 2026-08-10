# Container environment

You are running inside a disposable Debian (trixie) container managed by claude-pod.

## Package management
- `sudo apt-get install -y <pkg>`, `sudo apt`, `sudo dpkg` work without a password prompt
- All other `sudo` commands are rejected — you do not have general root access
- The apt package cache is shared across sessions so already-fetched packages install quickly

## Node.js / npm
- `npm install -g <pkg>` installs to `~/.local/bin` — no sudo needed, already on PATH

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

## Running Claude Code
- `cla` is a shorthand for `claude --dangerously-skip-permissions` — use it when you need to run Claude without permission prompts inside this container

## Display and browser
- Wayland and X11 are passed through from the host display
- GUI applications you launch will appear on the host desktop via XWayland
- `SDL_VIDEODRIVER=x11` is set globally — SDL2/pygame apps go through XWayland rather than native Wayland (native Wayland silently fails to show windows in this passthrough setup)
- `xdg-open <url>` opens URLs in the host browser via D-Bus portal
- For CLI OAuth flows (e.g. `claude`, `gh auth login`), the browser will open automatically on the host
- **Screenshot tools (`scrot`, `xwd`, GNOME D-Bus screenshot API) do not work inside the container** — the Wayland compositor blocks cross-process X11 capture for security reasons. To verify a GUI app is working, ask the user to look at their screen directly.
