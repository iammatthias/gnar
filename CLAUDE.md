# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

GNAR is an opinionated home-server bootstrap for Arch Linux. One script provisions
a headless Arch box for remote development over SSH: enhanced zsh, tmux, Caddy
reverse proxy, code-server (browser VS Code), Docker, PostgreSQL + Valkey, a
broad set of language runtimes (Node, Python via uv, Ruby, Rust, Go, Java),
and Claude Code (`claude`).

It also installs Hyprland + foot so an optional attached display becomes a
live kiosk dashboard (auto-login on tty1 → Hyprland → fullscreen `btop`).
The dashboard guard in `~/.zprofile` is a no-op on truly headless boxes.

When root is btrfs, the script installs Snapper + snap-pac (auto-snapshot
on every pacman transaction) and grub-btrfs (boot-into-snapshot from GRUB).
`/var/lib/{postgres,valkey,docker}` get `chattr +C` to skip CoW on
high-churn database/container files.

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
│   ├── code-server-config.yaml      # __PASSWORD__ placeholder
│   ├── code-server-settings.json
│   ├── code-server.service          # systemd template unit
│   └── server-CLAUDE.md             # installed to ~/CLAUDE.md (system context for Claude Code)
├── bin/                  # Helper scripts installed to /usr/local/bin
│   ├── gnar-info
│   ├── gnar-update
│   └── gnar-help
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
   enable systemd units (Caddy, Docker, Postgres, Valkey, code-server).
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
- `~/.config/code-server/config.yaml` — generated from template with random password (chmod 600)
- `~/CLAUDE.md`                       — copied from `configs/server-CLAUDE.md` (only if not already present); gives Claude Code system context

## Design principles

- **Opinionated, not minimal** — assumes a single-tenant home server, not a
  general-purpose distribution.
- **Idempotent-ish** — re-running setup.sh re-applies configs, backing up
  existing `~/.zshrc` first. Most steps tolerate already-configured state.
- **No secrets in repo** — the code-server password is generated at install
  time and printed once; the config file is chmod 600.
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
