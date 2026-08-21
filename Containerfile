FROM docker.io/library/debian:trixie-slim

# Core tools needed before Node.js setup
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    gnupg \
    ca-certificates \
    git \
    build-essential \
    sudo \
    procps \
    less \
    xdg-utils \
    libglib2.0-bin \
    libpulse0 \
    libx11-6 \
    libxext6 \
    libxrender1 \
    libxcursor1 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    docker.io \
    docker-compose \
    python3-pip \
    python3-venv \
    tmux \
    locales \
    unzip \
    tar \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen

# Allow pip to install to /usr/local without requiring a virtualenv.
# Debian's PEP 668 "externally managed" guard adds no value in a disposable container.
RUN printf '[global]\nbreak-system-packages = true\n' > /etc/pip.conf

# Install uv (fast Python package/project manager)
RUN pip3 install uv

# Install Node.js LTS via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code globally (available to all users via /usr/local/bin)
RUN npm install -g @anthropic-ai/claude-code@2.1.237

# Create the sandbox user.
# UID 1000 is the most common first-user UID on Linux.
# If your host UID differs, rebuild with: claude-pod --rebuild
# (The rebuild script passes --build-arg USER_UID=$(id -u) USER_GID=$(id -g))
ARG USER_UID=1000
ARG USER_GID=1000
RUN (getent group "${USER_GID}" > /dev/null 2>&1 || groupadd -g "${USER_GID}" sandbox) \
    && useradd -u "${USER_UID}" -g "${USER_GID}" -m -s /bin/bash sandbox

# Passwordless sudo scoped to package management only.
# Defaults:sandbox !authenticate prevents sudo from prompting for a password for
# commands that are NOT in the allowlist — they are rejected immediately instead
# of asking for a password the sandbox user doesn't have.
RUN printf '%s\n' \
    'Defaults:sandbox !authenticate, passwd_tries=0' \
    'sandbox ALL=(root) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt, /usr/bin/dpkg, /usr/bin/dpkg-reconfigure, /usr/sbin/update-ca-certificates' \
    > /etc/sudoers.d/sandbox-apt \
    && chmod 440 /etc/sudoers.d/sandbox-apt

# xdg-open override: calls xdg-desktop-portal over the mounted D-Bus session so
# CLI OAuth flows (claude auth, gh auth, etc.) open the host browser automatically.
# Placed in /usr/local/bin so it shadows the /usr/bin/xdg-open from xdg-utils.
COPY container-xdg-open /usr/local/bin/xdg-open
RUN chmod +x /usr/local/bin/xdg-open

# BROWSER fallback for tools that exec $BROWSER directly instead of xdg-open
ENV BROWSER=/usr/local/bin/xdg-open

# Prevent Claude Code from auto-updating inside the container
ENV DISABLE_AUTOUPDATER=1

# UTF-8 locale so box-drawing characters and Unicode render correctly
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# SDL2 (and pygame) silently try the native Wayland backend first when
# WAYLAND_DISPLAY is set, but the passthrough lacks xdg-shell so the window
# never surfaces — no error, just invisible. Force X11 (XWayland) which works.
ENV SDL_VIDEODRIVER=x11

# User-level Claude Code context: informs claude about the container's constraints
# so it doesn't need to re-discover them (sudo scope, npm prefix, ephemeral fs, etc.)
RUN mkdir -p /home/sandbox/.claude
COPY container-claude.md /home/sandbox/.claude/CLAUDE.md

# Pre-configure Claude Code for the container: allow all tools and enable
# dangerously-skip-permissions by default so 'cla' starts without consent prompts.
RUN printf '%s\n' \
    '{' \
    '  "dangerouslySkipPermissions": true,' \
    '  "workspaceTrust": false,' \
    '  "permissions": {' \
    '    "allow": ["Bash(*)", "Read(*)", "Edit(*)", "Write(*)", "WebFetch(*)", "WebSearch(*)", "NotebookEdit(*)", "Agent(*)"]' \
    '  }' \
    '}' \
    > /home/sandbox/.claude/settings.json

# tmux defaults: large scrollback and mouse support
RUN printf '%s\n' \
    'set -g default-terminal "tmux-256color"' \
    'set -g history-limit 100000' \
    'set -g mouse on' \
    > /home/sandbox/.tmux.conf

# npm global installs by sandbox go to ~/.local so 'npm install -g' works without sudo.
# NPM_CONFIG_PREFIX must be set AFTER the root-level 'npm install -g @anthropic-ai/claude-code'
# above, otherwise that install would also land in /home/sandbox/.local.
ENV NPM_CONFIG_PREFIX=/home/sandbox/.local
ENV PATH=/home/sandbox/.local/bin:$PATH
RUN mkdir -p /home/sandbox/.local/bin \
    && chown -R "${USER_UID}:${USER_GID}" /home/sandbox/.local /home/sandbox/.claude /home/sandbox/.tmux.conf

# Short alias for running Claude Code with --dangerously-skip-permissions.
# A wrapper script (not a .bashrc alias) so it works in non-interactive shells too.
RUN printf '%s\n' \
    '#!/bin/bash' \
    'exec claude --dangerously-skip-permissions "$@"' \
    > /usr/local/bin/cla \
    && chmod +x /usr/local/bin/cla

# Mount point for the project directory
RUN mkdir -p /workspace && chown "${USER_UID}:${USER_GID}" /workspace

# Init script: refresh package lists when the container first starts, then idle.
# This runs as the sandbox user (which has NOPASSWD apt-get), so no root needed.
RUN printf '%s\n' \
    '#!/bin/bash' \
    'echo "[claude-pod] Refreshing package index..."' \
    'sudo apt-get update -qq 2>&1 || echo "[claude-pod] Warning: apt-get update failed (continuing anyway)"' \
    'echo "[claude-pod] Ready."' \
    'exec sleep infinity' \
    > /usr/local/bin/claude-pod-init \
    && chmod +x /usr/local/bin/claude-pod-init

# Egress firewall extension point:
# To add a per-session outbound allowlist, place an init-firewall.sh here that
# calls iptables/nftables rules and run the container with --cap-add NET_ADMIN
# --cap-add NET_RAW. Not implemented in v1 — unrestricted egress is acceptable
# for personal use.

# /usr/local is writable by sandbox so non-apt installers (pip, gem, make install,
# cmake --install, curl-based scripts) can drop files there without sudo.
# Placed after all root-level installs to /usr/local above (claude, cla, etc.).
RUN chown -R "${USER_UID}:${USER_GID}" /usr/local

WORKDIR /workspace
USER sandbox
# sleep infinity ignores SIGTERM; skip straight to SIGKILL so --stop is instant.
STOPSIGNAL SIGKILL
CMD ["/usr/local/bin/claude-pod-init"]
