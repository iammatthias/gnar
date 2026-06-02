# GNAR — Hermes orchestrator image.
#
# Bundles the agent brain + everything it shells out to:
#   - hermes-cli (the orchestrator)
#   - claude (Claude Code, used as a subprocess tool by the
#             claude-with-chainlink skill)
#   - chainlink (per-project issue tracker)
#   - docker CLI (so the agent can manage host containers via the
#                 mounted /var/run/docker.sock)
#
# Single image used by both hermes-gateway and hermes-dashboard services.

FROM archlinux:base

# qemu/buildx + Arch's alpm sandbox don't get along; turn it off for the build.
RUN printf '[options]\nDisableSandbox\n' > /etc/pacman.conf.sandbox-off \
 && cat /etc/pacman.conf.sandbox-off /etc/pacman.conf > /etc/pacman.conf.new \
 && mv /etc/pacman.conf.new /etc/pacman.conf \
 && rm /etc/pacman.conf.sandbox-off

RUN pacman -Syu --noconfirm \
 && pacman -S --noconfirm \
      base-devel git curl wget unzip openssh \
      python python-pip uv \
      nodejs npm \
      rustup \
      go \
      docker docker-compose \
      jq yq \
      github-cli \
      cloudflared \
 && pacman -Scc --noconfirm \
 && rm -rf /var/cache/pacman/pkg/*

# Rust toolchain for chainlink.
RUN rustup default stable
ENV PATH=/root/.cargo/bin:/root/.local/bin:$PATH

# chainlink — per-project issue tracker
# (https://github.com/dollspace-gay/chainlink). The crate is published as
# `chainlink-tracker`; the binary it produces is `chainlink`. Install to
# /usr/local so the binary survives the rustup teardown afterwards.
# Arch's rustup disables `rustup self uninstall`, so we go through pacman.
RUN cargo install --root /usr/local chainlink-tracker \
 && pacman -Rns --noconfirm rustup \
 && rm -rf /root/.cargo /root/.rustup

# Claude Code (used as a subprocess tool by the claude-with-chainlink skill).
RUN npm install -g @anthropic-ai/claude-code \
 && npm cache clean --force

# Hermes — install via uv from upstream (matches the spec's manual path).
# Extras the base install doesn't pull but specific subcommands need:
#   - fastapi + uvicorn : `hermes dashboard` web UI
#   - python-telegram-bot: the Telegram gateway adapter
RUN git clone --depth=1 https://github.com/NousResearch/hermes-agent.git /opt/hermes-agent \
 && cd /opt/hermes-agent \
 && uv venv --python 3.11 \
 && uv pip install -e . fastapi uvicorn python-telegram-bot \
 && ln -sf /opt/hermes-agent/.venv/bin/hermes /usr/local/bin/hermes

# The dashboard's live connection (used by the web UI and the Hermes desktop
# app) is a WebSocket at /api/ws; uvicorn needs a ws backend to serve it. The
# base `uvicorn` install omits one, so add it explicitly.
RUN cd /opt/hermes-agent && uv pip install websockets

# Let the dashboard serve the Hermes desktop app over the tailnet.
# Upstream's dashboard is localhost-only: an ephemeral per-start session token
# (injected into its SPA) plus a localhost-only CORS regex. Make both honor an
# env override so a remote client can authenticate with a pinned token and an
# allowed origin. Defaults to upstream behavior when the env vars are unset.
# `grep -q` fails the build if upstream ever renames the lines we patch.
RUN sed -i 's|_SESSION_TOKEN = secrets.token_urlsafe(32)|_SESSION_TOKEN = os.environ.get("HERMES_DASHBOARD_TOKEN") or secrets.token_urlsafe(32)|' /opt/hermes-agent/hermes_cli/web_server.py \
 && sed -i 's|allow_origin_regex=r"|allow_origin_regex=os.environ.get("HERMES_DASHBOARD_CORS_REGEX") or r"|' /opt/hermes-agent/hermes_cli/web_server.py \
 && sed -i 's|if path.startswith("/api/") and path not in _PUBLIC_API_PATHS:|if request.method != "OPTIONS" and path.startswith("/api/") and path not in _PUBLIC_API_PATHS:|' /opt/hermes-agent/hermes_cli/web_server.py \
 && grep -q 'os.environ.get("HERMES_DASHBOARD_TOKEN")' /opt/hermes-agent/hermes_cli/web_server.py \
 && grep -q 'os.environ.get("HERMES_DASHBOARD_CORS_REGEX")' /opt/hermes-agent/hermes_cli/web_server.py \
 && grep -q 'request.method != "OPTIONS"' /opt/hermes-agent/hermes_cli/web_server.py

# Default workdir + state location.
WORKDIR /root
RUN mkdir -p /root/.hermes /root/.claude

# Entrypoint configures the agent's git identity from gh on boot (see script).
COPY docker-entrypoint.sh /usr/local/bin/gnar-hermes-entrypoint
RUN chmod +x /usr/local/bin/gnar-hermes-entrypoint

ENTRYPOINT ["/usr/local/bin/gnar-hermes-entrypoint"]
CMD ["hermes", "--help"]
