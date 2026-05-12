# GNAR Server

This machine was bootstrapped by [GNAR](https://github.com/iammatthias/gnar).
It is a single-tenant home server intended for remote development over SSH.

## Available tooling

### Shells / multiplexers
- `zsh` (default shell, Spaceship prompt, Oh My Zsh)
- `tmux` (prefix `Ctrl-a`, vim-style splits/navigation)

### Editors
- `nvim`

### Modern CLI
- `eza` (ls), `bat` (cat/pager), `fd` (find), `ripgrep` / `rg` (grep),
  `fzf`, `zoxide`, `jq`, `yq`, `httpie`, `fastfetch`
- `btop`, `htop`, `iotop`, `nethogs`, `ncdu`, `smartctl`

### Languages / runtimes
- **Node.js** (`node`, `npm`, `yarn`, `pnpm`, `bun`, `pm2`)
- **Python** via **`uv`** — `uv` replaces `pip`/`pipx`/`pipenv`/`poetry`.
  Use `uv venv`, `uv pip install`, `uv tool install <pkg>`, `uv run <cmd>`.
  Installed `uv tool`s: `ruff`, `pytest`, `black`.
- **Ruby** (`gem`, `bundler`)
- **Rust** (rustup, `cargo`)
- **Go** (`go`, `dlv`)
- **Java** (`java`, `mvn`, `gradle`)

### AI / LLM tooling (containerized in /srv/stack)
- **Hermes** — top-level orchestrator. Runs as `gnar-hermes-gateway`
  (Telegram bot + agent brain) and `gnar-hermes-dashboard` (web UI on
  :9119). Don't invoke directly on host — `docker compose exec
  hermes-gateway hermes ...` for one-shot work, or just message the
  Telegram bot.
- **Claude Code** — bundled inside the hermes container image. Used as
  a subprocess tool by the `claude-with-chainlink` skill. Auth at
  `/srv/stack/data/claude/` (mounted into container).
- **chainlink** — per-project issue tracker, also bundled in the
  hermes image. Run `chainlink init` inside a project before pointing
  the agent at it.
- **New projects** — message the bot: "set up a new project at
  /srv/projects/foo, it's a FastAPI + Postgres backend." Hermes uses
  the `init-project` skill to mkdir, `chainlink init`, drop a CLAUDE.md
  template, and register the project in MEMORY.md. Default project
  root is `/srv/projects` (bind-mounted into the agent container at the
  same path).
  - For setting up a project without Hermes (rare): `gnar-project-init
    <path> [<description>]` on the host.

### Web / proxy + agent stack
The network ingress + agent layer runs as a docker-compose stack at
`/srv/stack` (not on host). Three containers share the tailscale
container's network namespace:
- `gnar-tailscale` — tailnet identity, ingress
- `gnar-caddy` — reverse proxy (`add-site <name> <port>` writes to
  `/srv/stack/Caddyfile` and reloads via `docker compose exec caddy
  caddy reload`)
- `gnar-hermes-gateway` + `gnar-hermes-dashboard` — Telegram bot brain +
  web UI

Stack lifecycle is `cd /srv/stack && docker compose <cmd>`. The
`gnar-stack` systemd unit runs `docker compose up -d --build` at boot.

### Databases
- `postgresql` (systemd unit `postgresql`, default user matches `$USER`)
- `valkey` (Redis-compatible, systemd unit `valkey`)
- `sqlite3`

### Containers
- `docker`, `docker-compose` (the user is in the `docker` group)

### Display / kiosk dashboard
- `mango` (Wayland WM, AUR `mangowm-git`) + `foot`. Headless by default.
  If a display is attached, `getty@tty1` auto-logs the user in and
  `~/.zprofile` exec's `mango`, which fullscreens `gnar-dashboard` —
  a 4-pane tmux session showing system, services, containers, and
  Claude Code metrics.
- Edit `~/.config/mango/config.conf` to swap the dashboard process or
  rebind keys.

### Snapshots (btrfs only)
- `snapper` + `snap-pac` — automatic pre/post snapshots for every
  pacman transaction. Recover from a bad `pacman -Syu` via
  `snapper -c root rollback` or by booting an older snapshot from
  GRUB's "Snapshots" submenu.
- Retention: 5 hourly, 7 daily, 2 weekly, 2 monthly.
- `/var/lib/postgres`, `/var/lib/valkey`, `/var/lib/docker` are marked
  `chattr +C` (no CoW) — important for write-heavy DB/container files.

### Network / security
- `ufw` (deny-incoming except 22/80/443)
- `fail2ban` (sshd jail, 3 retries, 1h ban)
- `nmap`, `tcpdump`, `wireshark-cli`

## GNAR helpers (in PATH as `/usr/local/bin/gnar-*`)

- `gnar-info`   — fastfetch system report
- `gnar-update` — `pacman -Syu` + cache clean
- `gnar-help`   — full alias / function reference

## Useful shell shortcuts

The full list is `gnar-help`, `gnar-aliases` (fzf), `gnar-functions` (fzf).
Highlights:

- Caddy: `add-site myapp 3000`, `list-sites`, `remove-site myapp`,
  `caddy-edit`, `caddy-reload`, `caddy-logs`, `test-caddy`
- PM2: `pm2-start`, `pm2-add-site`, `pm2-remove`, `pm2-restart`,
  `pm2-logs`, `pm2-status`
- Status: `system-status`, `db-status`, `security-status`,
  `port-check <port>`
- Backup: `backup-system` snapshots configs to `~/backups/<timestamp>`
- Project scaffold: `create-react-hono <name>` (React + Hono boilerplate
  in `~/projects/<name>`)

## Don't do

- Don't change tailscale prefs (`tailscale up --advertise-tags=...`,
  `--advertise-routes=...`, etc.) without explicit user instruction.
  Tags that aren't pre-approved in the tailnet ACL cause auth rejection
  and a restart loop. If you must change network state, ask first.
- Don't reach for Tailscale **Services** (`svc:foo` hostnames,
  `tailscale serve --service=...`) or spin up per-site tailscale
  sidecars. Both work but add admin friction. Previews here go
  through Cloudflare instead — see below.
- Don't hand-roll subpath routing (`handle_path /<name>*` in the
  shared caddy). Each preview gets its own subdomain on the
  preview apex.
- **Preview sites use `add-preview-site <name> <port-or-dir>`**
  (zsh function from the user shell). It writes a vhost into
  `/srv/stack/Caddyfile` for `<name>.$PREVIEW_APEX` and reloads
  caddy. `$PREVIEW_APEX` is the user-owned domain set in
  `/srv/stack/.env` (e.g. `previews.example.com`); read it from
  there if you need the actual value. The cloudflared connector
  (compose profile `cloudflared`) fronts the same apex + wildcard
  and terminates TLS at Cloudflare, so the resulting URL is
  `https://<name>.$PREVIEW_APEX` — public, real cert, no extra
  wiring on the box.
- A future tailnet-only path is gated on Tailscale enabling the
  `dns-subdomain-resolve` nodeAttr for this tailnet (control-plane
  feature, currently denied). If it ever lights up we can revisit;
  until then, previews are Cloudflare-fronted.
- Don't modify `/srv/stack/docker-compose.yml` or `/srv/stack/Caddyfile`
  by hand inside a single agent turn; the user iterates the source-of-
  truth in `~/gnar/stack/` and copies into `/srv/stack/`. If you want
  to change stack config, edit the repo and tell the user to pull.

## Conventions

- New web services should live under `~/projects/<name>` and be exposed
  via Caddy with `add-site <name> <port>`.
- Long-running Node services use PM2. Use `pm2-add-site` to do both
  steps at once.
- Python projects use `uv` — never `pip install` into the system Python
  (Arch's Python is externally-managed).
- Secrets do not live in the repo. Hermes OAuth tokens live at
  `~/.hermes/auth.json` (mode 600).

## Reverting

`sudo /path/to/gnar/scripts/uninstall.sh` reverts the GNAR configuration
(stops services, restores stock sshd, backs up user configs as
`*.gnar-backup.<timestamp>`). Pacman packages are not removed.
