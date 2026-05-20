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

# Default workdir + state location.
WORKDIR /root
RUN mkdir -p /root/.hermes /root/.claude

ENTRYPOINT []
CMD ["hermes", "--help"]
