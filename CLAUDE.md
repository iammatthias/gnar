# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

GNAR is an opinionated home-server bootstrap for Arch Linux. One script
provisions a headless Arch box for remote development over SSH: enhanced
zsh, tmux, Docker, PostgreSQL + Valkey, a broad set of language runtimes
(Node, Python via uv, Ruby, Rust, Go, Java), plus a docker-compose stack
under /srv/stack for the network-ingress + agent layer (Tailscale, Caddy,
Hermes orchestrator, Claude Code).

It also installs sway (Wayland compositor) + foot so an optional attached
display becomes a live kiosk dashboard (auto-login on tty1 → sway → six
`gnar-board <panel>` foot tiles arranged 3×2 by `gnar-kiosk-tiles`;
`bin/gnar-dashboard` runs the same board as a single tmux view for ssh
sessions). The DRM-status guard in `~/.zprofile` is a no-op on truly
headless boxes. sway is used (not a minimal dwl-style WM like mango) because
it exposes `wl_touch` — the rack touch panel's tap interactions
(tap a tile → fullscreen; action buttons in the fullscreen OPS view) only
work under a compositor that delivers touch to clients.

### Container stack (`/srv/stack`)

The network ingress + agent surface is a docker-compose stack — atomically
updatable via `git pull && docker compose up -d --build` and isolated from
the host substrate.

- `gnar-tailscale` (image: `tailscale/tailscale`) — tailnet identity. Other
  services share its network namespace (`network_mode: service:tailscale`)
  so they reach the tailnet directly + can talk to one another on
  `localhost`.
- `gnar-caddy` (image: `caddy:latest`) — reverse proxy. Caddyfile lives at
  `/srv/stack/Caddyfile`, mounted into the container.
  `add-site`/`remove-site` shell helpers edit it and reload via
  `docker compose exec`.
- `gnar-hermes-gateway` + `gnar-hermes-dashboard` (image: built from
  `stack/hermes/Dockerfile`) — Telegram-bot orchestrator brain + web UI.
  Bundles `hermes-cli`, `claude` (Claude Code), `chainlink`. `~/.hermes` and
  `~/.claude` mount from `/srv/stack/data/{hermes,claude}` so state is
  inspectable on host and survives rebuilds.

State on host:
- `/srv/stack/Caddyfile` — caddy config (user-editable)
- `/srv/stack/.env` — TS_AUTHKEY, TS_HOSTNAME (chmod 600)
- `/srv/stack/data/tailscale/` — tailnet identity
- `/srv/stack/data/caddy/{data,config}/` — caddy data + cert cache
- `/srv/stack/data/hermes/{auth.json,MEMORY.md,kanban.db,...}`
- `/srv/stack/data/claude/` — subscription auth + session transcripts
- `/srv/stack/skills/` — skill files shipped with the repo (read-only mount)
- `/srv/projects/` — bind-mounted into hermes-gateway at the same path

When root is btrfs, the script installs Snapper + snap-pac (auto-snapshot
on every pacman transaction) and grub-btrfs (boot-into-snapshot from GRUB).
`/var/lib/{postgres,valkey,docker}` get `chattr +C` to skip CoW on
high-churn database/container files.

The top-level AI surface is **Hermes** (`hermes` CLI; AUR `hermes-agent`),
not Claude Code directly. Hermes runs the orchestrator brain on a ChatGPT
OAuth credential and exposes a Telegram bot + Kanban dashboard (port 9119,
expected to be Tailscale-gated). Claude Code is still installed and used
by Hermes as a subprocess tool via the `claude-with-chainlink` skill;
`chainlink` (cargo install) provides per-project issue tracking that the
skill threads through. OAuth + Telegram setup is interactive and not
automated by `setup.sh` — see the closing banner.

It is intentionally heavy — this is a personal home-server bootstrap, not a
"minimal TTY" distribution.

## Repository Structure

```
gnar/
├── README.md
├── LICENSE
├── CLAUDE.md
├── .gitignore
├── scripts/
│   ├── setup.sh          # Bootstrap (run as root)
│   └── uninstall.sh      # Revert configuration
├── configs/              # Files installed verbatim by setup.sh
│   ├── zshrc
│   ├── tmux.conf
│   ├── Caddyfile
│   ├── fastfetch.jsonc
│   ├── fail2ban-jail.local
│   ├── logrotate-gnar.conf
│   └── server-CLAUDE.md             # installed to ~/CLAUDE.md (system context for Claude Code)
├── bin/                  # Helper scripts installed to /usr/local/bin
│   ├── gnar-info
│   ├── gnar-update
│   └── gnar-help
├── board/                # gnar-board — fullscreen ratatui kiosk TUI
│   ├── Cargo.toml        #   (built by setup.sh; host + container graphs)
│   └── src/main.rs
└── docs/
    ├── configuration.md
    ├── helpers.md
    └── troubleshooting.md
```

## Key Commands

### Install / Update / Uninstall

```bash
sudo ./scripts/setup.sh        # Bootstrap a fresh Arch system
gnar-update                    # Pacman -Syu + cache clean
sudo ./scripts/uninstall.sh    # Revert configuration (with backups)
```

### Post-install reference

```bash
gnar-info     # fastfetch report (TR-100 style)
gnar-help     # Full command reference
```

## Architecture

### setup.sh — three phases

1. **System packages** via `pacman -S`: shells/editors, Caddy, Docker, runtimes,
   databases, security tooling, modern CLI replacements.
2. **System configuration**: install configs from `configs/` to their canonical
   locations, configure UFW + fail2ban + SSH hardening, init Postgres cluster,
   enable systemd units (Caddy, Docker, Postgres, Valkey).
3. **Per-user tooling** (run as `$REAL_USER` via `sudo -u`): Oh My Zsh, plugins,
   Spaceship prompt, npm globals (yarn/pnpm/pm2/eslint/prettier/jest +
   `@anthropic-ai/claude-code`), Bun, `uv tool install` (ruff/pytest/black),
   Ruby bundler, rustup, Go delve.

Setup is run as root. The script derives the target user via `logname`, and
all per-user work runs through `sudo -u "$REAL_USER"`.

### Helper scripts (`/usr/local/bin/`)

- `gnar-info`  — wraps `fastfetch` with the GNAR config
- `gnar-update`— `pacman -Syu` + cache clean
- `gnar-help`  — printed reference of installed aliases / functions

### Generated user files

- `~/.zshrc`                          — copied from `configs/zshrc`
- `~/.tmux.conf`                      — copied from `configs/tmux.conf`
- `~/.config/fastfetch/config.jsonc`  — copied from `configs/fastfetch.jsonc`
- `~/CLAUDE.md`                       — copied from `configs/server-CLAUDE.md` (only if not already present); gives Claude Code system context

## Design principles

- **Opinionated, not minimal** — assumes a single-tenant home server, not a
  general-purpose distribution.
- **Idempotent-ish** — re-running setup.sh re-applies configs, backing up
  existing `~/.zshrc` first. Most steps tolerate already-configured state.
- **No secrets in repo** — Hermes OAuth tokens land at `~/.hermes/auth.json`
  (chmod 600) at runtime, never committed.
- **Configs are tracked** — every file the bootstrap installs lives under
  `configs/` so changes are reviewable in diff form rather than buried in
  heredocs.

## Editing tips

- To change shell behavior, edit `configs/zshrc` and re-run setup, or just
  copy it onto `~/.zshrc` (it overrides existing).
- To add a Caddy site at runtime, use the `add-site` shell function from
  `configs/zshrc`; don't hand-edit `/etc/caddy/Caddyfile`.
- To change the package set, edit the two `pacman -S` blocks at the top of
  `scripts/setup.sh`.

## Documentation

- **README.md** — user-facing install + usage guide
- **docs/configuration.md** — customization recipes
- **docs/helpers.md** — full alias / keybinding reference
- **docs/troubleshooting.md** — common issues

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
NEVER run chmod commands on macOS - files are already executable when created. Only mention chmod in documentation for Linux users.
