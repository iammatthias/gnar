# GNAR

**Opinionated home-server bootstrap for Arch Linux**

A single setup script that turns a fresh Arch install into a headless
home server for remote development over SSH. Spaceship + Zsh + Tmux,
Caddy reverse proxy, Docker, PostgreSQL +
Valkey, and a full set of language runtimes.

This is intentionally opinionated and intentionally heavy — it's a
personal home-server bootstrap, not a minimal TTY distribution.

## What You Get

- **Kiosk Dashboard** - Mango (Wayland WM) + foot auto-launches `gnar-dashboard` (4-pane TUI: btop + services + containers + Claude metrics) on an attached display (no-op when headless)
- **Spaceship Prompt** - Beautiful, fast, and customizable Zsh prompt
- **Zsh with Essential Plugins** - Autosuggestions, syntax highlighting, completions
- **Tmux as Default** - Tiling terminal multiplexer with vim keybindings
- **Caddy Web Server** - Automatic HTTPS, reverse proxy, and site management
- **PM2 Process Management** - Node.js app process management
- **Database Support** - PostgreSQL and Valkey (Redis-compatible) databases
- **Btrfs + Snapper** - Auto-snapshot before/after every pacman transaction; boot-into-snapshot via GRUB submenu when an update breaks the system (only when root is btrfs)
- **Security Features** - UFW firewall, Fail2ban, SSH hardening
- **System Monitoring** - btop, iotop, nethogs, smartmontools
- **AI Orchestrator** - Hermes (ChatGPT OAuth brain, Telegram bot, Kanban dashboard) with Claude Code as a subprocess tool, chainlink for per-project issue tracking
- **Runtime Support** - Node.js, Bun, Python, Ruby, Rust, Go, Java, Docker
- **Development Tools** - eza, bat, fd, fzf, zoxide, ripgrep, and more

## Initial Arch Linux Setup

Before installing GNAR, you need to set up a fresh Arch Linux system with basic tools.

### 1. Install Arch Linux

Follow the [Arch Linux Installation Guide](https://wiki.archlinux.org/title/Installation_guide) to install Arch Linux.

### 2. Prerequisites

Ensure your Arch system has:

- A non-root user with sudo access
- SSH access configured
- Basic packages: `git`, `curl`, `wget`, `base-devel`

`setup.sh` installs `yay` (AUR helper) and the rest of the toolchain itself —
you do not need to bootstrap an AUR helper first.

## Quick Start

Once your Arch system is set up:

```bash
# Clone GNAR
git clone https://github.com/iammatthias/gnar.git
cd gnar

# Run setup as root
sudo ./scripts/setup.sh

# Reboot
sudo reboot
```

After reboot, login and start tmux:

```bash
tmux
```

## SSH from macOS

```bash
ssh user@your-server
tmux
```

## Core Features

### Spaceship Prompt

- Shows git branch, status, and staging
- Displays active runtime environments (Node, Python, Ruby, etc.)
- Battery level and execution time
- Clean, fast, and highly customizable

### Zsh Configuration

- **Plugins**: Autosuggestions, syntax highlighting, completions
- **Smart History**: 10k entries, shared across sessions
- **Navigation**: `..`, `...`, `-` for directory jumping
- **File Operations**: `ls` with icons, `cat` with syntax highlighting

### Tmux Integration

- **Vim Keybindings**: `Ctrl-a v` (split vertical), `Ctrl-a s` (split horizontal)
- **Pane Navigation**: `Ctrl-a h/j/k/l` (vim-style movement)
- **Session Management**: `tn <name>` (new), `ta <name>` (attach)
- **UTF-8 Support**: Works perfectly over SSH

### Caddy Web Server

- **Automatic HTTPS**: Let's Encrypt certificates
- **Reverse Proxy**: Easy site management
- **Static Files**: Serve directories directly
- **Add Sites**: `add-site myapp 3000` (reverse proxy) or `add-site static /var/www` (static files)
- **Site Management**: `remove-site`, `list-sites`, `test-caddy`
- **Configuration**: `caddy-edit` to modify Caddyfile

### Runtime Environments

- **Node.js**: npm, yarn, pnpm, bun, pm2
- **Python**: [`uv`](https://docs.astral.sh/uv/) (replaces pip / pipx /
  pipenv / poetry); preinstalled `uv tool`s: ruff, pytest, black
- **Ruby**: gem, bundler
- **Rust**: cargo, rustup
- **Go**: go, delve debugger
- **Java**: OpenJDK, Maven, Gradle
- **Docker**: docker, docker-compose
- **Claude Code**: `claude` (Anthropic's CLI; reads `~/CLAUDE.md` for
  system context)

## Essential Commands

### System

```bash
gnar-info      # System information
gnar-update    # Update system
gnar-help      # Command reference
```

### Tmux

```bash
t              # Start tmux
tn <name>      # New named session
ta <name>      # Attach to session
tl             # List sessions
Ctrl-a v       # Split vertical
Ctrl-a s       # Split horizontal
Ctrl-a h/j/k/l # Navigate panes
```

### Docker

```bash
d              # docker
dc             # docker-compose
dps            # docker ps
di             # docker images
dex <container> # docker exec -it
```

### Caddy

```bash
add-site <name> [port|dir]  # Add site (port=reverse proxy, dir=static files)
remove-site <name>          # Remove site from Caddy
list-sites                  # List configured sites
caddy-edit                  # Edit Caddyfile
caddy-reload                # Reload Caddy
caddy-test                  # Test Caddy configuration
caddy-status                # Check Caddy status and logs
```

### Git

```bash
gs             # git status
ga             # git add
gc             # git commit
gp             # git push
gl             # git pull
glog           # git log --oneline --graph
```

### Navigation

```bash
..             # Go up one directory
...            # Go up two directories
-              # Previous directory
ls             # List with icons
ll             # Long format
tree           # Directory tree
```

## Configuration

### Spaceship Prompt

Edit `~/.zshrc` to customize the prompt:

```bash
# Show/hide sections
SPACESHIP_NODE_SHOW=true
SPACESHIP_PYTHON_SHOW=true
SPACESHIP_DOCKER_SHOW=true

# Customize symbols
SPACESHIP_CHAR_SYMBOL="❯ "
SPACESHIP_GIT_BRANCH_PREFIX=""
```

### Tmux

Edit `~/.tmux.conf` for custom keybindings:

```bash
# Change prefix key
set -g prefix C-b

# Add custom bindings
bind C-r source-file ~/.tmux.conf
```

### Caddy

Edit `/etc/caddy/Caddyfile` for web server configuration:

```caddy
# Add your sites
myapp.local:80 {
    reverse_proxy localhost:3000
}

api.local:80 {
    reverse_proxy localhost:8080
}
```

## Development Workflow

1. **Start tmux**: `tmux`
2. **Create project**: `mkdir myproject && cd myproject`
3. **Initialize runtime**: `npm init`, `uv init`, `cargo init`, etc.
4. **Add to Caddy**: `add-site myproject 3000`
5. **Access**: `http://myproject.local` (or your domain)

## Uninstall

```bash
sudo ./scripts/uninstall.sh
```

This removes GNAR configurations but keeps system packages installed.

## Philosophy

GNAR is designed for:

- **Remote Development**: SSH from macOS to an Arch home server
- **Web Development**: Caddy for reverse proxy and HTTPS
- **Terminal-First**: Tmux as the primary interface
- **Runtime Agnostic**: Support for the major language runtimes
- **Versioned Configs**: Every file the bootstrap installs lives under
  `configs/`, so changes are reviewable in diff form rather than buried
  in heredocs

## License

MIT
