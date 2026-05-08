# GNAR Server

This machine was bootstrapped by [GNAR](https://github.com/iammatthias/gnar).
It is a single-tenant home server intended for remote development over SSH.

## Available tooling

### Shells / multiplexers
- `zsh` (default shell, Spaceship prompt, Oh My Zsh)
- `tmux` (prefix `Ctrl-a`, vim-style splits/navigation)

### Editors
- `nvim`
- `code-server` — VS Code in the browser at `http://vscode.local` (password
  in `~/.config/code-server/config.yaml`, mode 600)

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

### AI / LLM tooling
- **Claude Code** (`claude`) — Anthropic's official CLI. `claude --help`.
  Reads CLAUDE.md (this file) for system context.

### Web / proxy
- `caddy` — reverse proxy with automatic HTTPS. `add-site <name> <port|dir>`
  to add a virtual host, `list-sites`, `remove-site <name>`.

### Databases
- `postgresql` (systemd unit `postgresql`, default user matches `$USER`)
- `valkey` (Redis-compatible, systemd unit `valkey`)
- `sqlite3`

### Containers
- `docker`, `docker-compose` (the user is in the `docker` group)

### Display / kiosk dashboard
- `hyprland` + `foot` (Wayland). Headless by default. If a display is
  attached, `getty@tty1` auto-logs the user in and `~/.zprofile` exec's
  Hyprland, which fullscreens `btop` as a live system dashboard.
- Edit `~/.config/hypr/hyprland.conf` to swap the dashboard process
  (e.g. `tmux new -A -s dash`, `glances`, `wtfutil`).

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
- code-server: `vs` (status), `vsr` (restart), `vsl` (logs),
  `vscode-password`, `vscode-change-password <pw>`
- PM2: `pm2-start`, `pm2-add-site`, `pm2-remove`, `pm2-restart`,
  `pm2-logs`, `pm2-status`
- Status: `system-status`, `db-status`, `security-status`,
  `port-check <port>`
- Backup: `backup-system` snapshots configs to `~/backups/<timestamp>`
- Project scaffold: `create-react-hono <name>` (React + Hono boilerplate
  in `~/projects/<name>`)

## Conventions

- New web services should live under `~/projects/<name>` and be exposed
  via Caddy with `add-site <name> <port>`.
- Long-running Node services use PM2. Use `pm2-add-site` to do both
  steps at once.
- Python projects use `uv` — never `pip install` into the system Python
  (Arch's Python is externally-managed).
- Secrets do not live in the repo — code-server's password is in
  `~/.config/code-server/config.yaml` (mode 600).

## Reverting

`sudo /path/to/gnar/scripts/uninstall.sh` reverts the GNAR configuration
(stops services, restores stock sshd, backs up user configs as
`*.gnar-backup.<timestamp>`). Pacman packages are not removed.
