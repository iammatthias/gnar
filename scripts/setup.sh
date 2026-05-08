#!/bin/bash
#
# GNAR - Home Server Bootstrap for Arch
# Spaceship + Zsh + Tmux + Caddy + code-server + runtimes
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root: sudo ./setup.sh${NC}"
   exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "")}"
if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    echo -e "${RED}Could not determine the target user. Run as: sudo ./setup.sh (not as root directly).${NC}"
    exit 1
fi
REAL_HOME="/home/$REAL_USER"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGS="$REPO_ROOT/configs"
BIN="$REPO_ROOT/bin"

# Track services that fail to start so we can warn at the end.
FAILED_SERVICES=()

# Snapshot files we modify so uninstall.sh can restore the original.
# Only created on first run — re-running setup mustn't clobber the original snapshot.
snapshot() {
    local f=$1
    [ -f "$f" ] && [ ! -f "$f.gnar-orig" ] && cp -a "$f" "$f.gnar-orig" || true
}
snapshot /etc/locale.gen
snapshot /etc/locale.conf
snapshot /etc/ssh/sshd_config

echo -e "${GREEN}GNAR - Home Server Bootstrap${NC}"
echo

# On cloud images, first-boot cloud-init may still be running pacman in the
# background and hold /var/lib/pacman/db.lck. No-op on non-cloud Arch.
if command -v cloud-init &>/dev/null; then
    echo -e "${YELLOW}Waiting for cloud-init to settle...${NC}"
    cloud-init status --wait &>/dev/null || true
fi

# -----------------------------------------------------------------------------
# System packages
# -----------------------------------------------------------------------------
echo -e "${GREEN}Updating system...${NC}"
pacman -Syu --noconfirm

if ! grep -q "en_US.UTF-8 UTF-8" /etc/locale.gen 2>/dev/null; then
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
fi
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Persistent journal — without /var/log/journal, journald falls back to
# RAM-only and logs vanish on reboot, which is hostile for a home server.
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal &>/dev/null || true
systemctl kill --kill-whom=main -s USR1 systemd-journald &>/dev/null || true

echo -e "${GREEN}Installing core packages...${NC}"
pacman -S --noconfirm \
  zsh tmux neovim git curl wget unzip \
  caddy docker docker-compose \
  nodejs npm \
  python uv \
  ruby \
  go jdk-openjdk maven gradle \
  base-devel man-db man-pages

echo -e "${GREEN}Installing development tools...${NC}"
pacman -S --noconfirm \
  eza bat fd fzf zoxide ripgrep jq yq \
  fastfetch htop btop iotop nethogs lsof ncdu \
  tree bc rsync rclone p7zip imagemagick httpie \
  net-tools openssh ufw fail2ban nmap tcpdump wireshark-cli \
  postgresql valkey sqlite smartmontools

echo -e "${GREEN}Installing display stack (Hyprland kiosk dashboard)...${NC}"
# Wayland compositor + terminal for the optional attached-display dashboard.
# Only activates when a display is plugged in (see ~/.zprofile guard).
pacman -S --noconfirm hyprland foot

# Re-run locale-gen post-install. pacman -Syu earlier may have replaced
# glibc; locale-archive needs to be regenerated against the new libraries
# or postgres rejects "en_US.UTF-8" at startup.
locale-gen &>/dev/null || true

# -----------------------------------------------------------------------------
# Btrfs + Snapper (only if root filesystem is btrfs)
# -----------------------------------------------------------------------------
ROOT_FS=$(stat -f -c %T / 2>/dev/null || echo unknown)
if [ "$ROOT_FS" = "btrfs" ]; then
    echo -e "${GREEN}Detected btrfs root — configuring Snapper...${NC}"

    # snap-pac auto-snapshots before/after every pacman transaction; once
    # it's installed, every subsequent pacman call below will snapshot.
    pacman -S --noconfirm snapper snap-pac inotify-tools

    # grub-btrfs adds a "Snapshots" submenu to GRUB so you can boot into
    # any snapshot when an update breaks the system. Only meaningful on
    # GRUB; systemd-boot has no equivalent.
    if command -v grub-mkconfig &>/dev/null; then
        pacman -S --noconfirm grub-btrfs
    else
        echo -e "${YELLOW}Not on GRUB — skipping grub-btrfs.${NC}"
        echo -e "${YELLOW}For boot-into-snapshot on systemd-boot, see https://wiki.archlinux.org/title/Snapper${NC}"
    fi

    # archinstall ships @.snapshots mounted at /.snapshots (per fstab).
    # snapper wants to own /.snapshots itself. Preserve the archinstall
    # subvolume but get snapper's config files in place.
    if [ ! -f /etc/snapper/configs/root ]; then
        if mountpoint -q /.snapshots; then
            umount /.snapshots
            rmdir /.snapshots 2>/dev/null || true
            snapper -c root create-config /
            # snapper just made a fresh subvol at /.snapshots; ditch it
            # and re-mount archinstall's @.snapshots in its place.
            btrfs subvolume delete /.snapshots 2>/dev/null || true
            mkdir /.snapshots
            mount -a
        else
            snapper -c root create-config /
        fi

        snapper -c root set-config "TIMELINE_LIMIT_HOURLY=5"
        snapper -c root set-config "TIMELINE_LIMIT_DAILY=7"
        snapper -c root set-config "TIMELINE_LIMIT_WEEKLY=2"
        snapper -c root set-config "TIMELINE_LIMIT_MONTHLY=2"
        snapper -c root set-config "TIMELINE_LIMIT_YEARLY=0"
        snapper -c root set-config "ALLOW_GROUPS=wheel"

        chmod 750 /.snapshots 2>/dev/null || true
        chgrp wheel /.snapshots 2>/dev/null || true
    fi

    # Disable CoW on dirs with lots of small random writes (databases,
    # container storage). chattr +C only takes effect on NEW files, so do
    # this BEFORE postgres initdb / dockerd populates them.
    for _dir in /var/lib/postgres /var/lib/valkey /var/lib/docker; do
        [ -d "$_dir" ] || mkdir -p "$_dir"
        chattr +C "$_dir" 2>/dev/null || true
    done

    systemctl enable --now snapper-timeline.timer 2>/dev/null || true
    systemctl enable --now snapper-cleanup.timer  2>/dev/null || true
    if command -v grub-mkconfig &>/dev/null; then
        systemctl enable --now grub-btrfsd 2>/dev/null || true
    fi
fi

# -----------------------------------------------------------------------------
# Zsh + Spaceship + Oh My Zsh
# -----------------------------------------------------------------------------
echo -e "${GREEN}Configuring zsh...${NC}"

if [[ -f "$REAL_HOME/.zshrc" ]]; then
    cp "$REAL_HOME/.zshrc" "$REAL_HOME/.zshrc.gnar-backup.$(date +%Y%m%d_%H%M%S)" || true
fi

sudo -u "$REAL_USER" bash <<EOF
set -e
export HOME="$REAL_HOME"

# Oh My Zsh
if [ ! -d "\$HOME/.oh-my-zsh" ]; then
    sh -c "\$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM="\$HOME/.oh-my-zsh/custom"

# Plugins
for plugin_repo in \
    "zsh-users/zsh-autosuggestions" \
    "zsh-users/zsh-syntax-highlighting" \
    "zsh-users/zsh-completions" \
    "zsh-users/zsh-history-substring-search" \
    "agkozak/zsh-z"; do
    name=\$(basename "\$plugin_repo")
    [ ! -d "\$ZSH_CUSTOM/plugins/\$name" ] && \
        git clone "https://github.com/\$plugin_repo" "\$ZSH_CUSTOM/plugins/\$name"
done

# Spaceship prompt
if [ ! -d "\$ZSH_CUSTOM/themes/spaceship-prompt" ]; then
    git clone --depth=1 https://github.com/spaceship-prompt/spaceship-prompt.git \
        "\$ZSH_CUSTOM/themes/spaceship-prompt"
fi
ln -sf "\$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" \
       "\$ZSH_CUSTOM/themes/spaceship.zsh-theme"
EOF

install -m 644 -o "$REAL_USER" -g "$REAL_USER" "$CONFIGS/zshrc" "$REAL_HOME/.zshrc"
install -m 644 -o "$REAL_USER" -g "$REAL_USER" "$CONFIGS/tmux.conf" "$REAL_HOME/.tmux.conf"

install -d -o "$REAL_USER" -g "$REAL_USER" "$REAL_HOME/.config/fastfetch"
install -m 644 -o "$REAL_USER" -g "$REAL_USER" \
    "$CONFIGS/fastfetch.jsonc" "$REAL_HOME/.config/fastfetch/config.jsonc"

# Drop a CLAUDE.md at $HOME so Claude Code (and the user) sees what's
# installed. Don't clobber an existing one.
if [ ! -e "$REAL_HOME/CLAUDE.md" ]; then
    install -m 644 -o "$REAL_USER" -g "$REAL_USER" \
        "$CONFIGS/server-CLAUDE.md" "$REAL_HOME/CLAUDE.md"
fi

# -----------------------------------------------------------------------------
# Caddy
# -----------------------------------------------------------------------------
echo -e "${GREEN}Configuring Caddy...${NC}"
install -m 644 "$CONFIGS/Caddyfile" /etc/caddy/Caddyfile
if caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
    systemctl enable caddy
    systemctl start caddy || journalctl -xeu caddy.service --no-pager -n 10
else
    echo -e "${RED}Caddyfile invalid; skipping start${NC}"
fi

# -----------------------------------------------------------------------------
# Docker
# -----------------------------------------------------------------------------
echo -e "${GREEN}Configuring Docker...${NC}"
systemctl enable docker
# pacman -Syu earlier may have upgraded the kernel; iptables modules in the
# running kernel won't match until reboot. Don't let that abort the bootstrap.
if ! systemctl start docker; then
    journalctl -xeu docker.service --no-pager -n 10 || true
    FAILED_SERVICES+=("docker")
fi
usermod -aG docker "$REAL_USER"
echo -e "${YELLOW}Note: log out and back in for docker group membership.${NC}"

# -----------------------------------------------------------------------------
# Firewall rules + fail2ban + SSH
# -----------------------------------------------------------------------------
echo -e "${GREEN}Configuring firewall rules + fail2ban...${NC}"
# Configure UFW rules now, but DO NOT enable yet. If pacman -Syu upgraded the
# kernel earlier in this run, the running kernel is missing iptables modules
# (xt_addrtype, conntrack, etc.). UFW would half-apply, leaving iptables in a
# fail-closed state that blocks outbound DNS — which then breaks every
# downstream AUR/curl install. We enable UFW at the very end of the script,
# AFTER all network-dependent installs are done.
ufw default deny incoming || true
ufw default allow outgoing || true

# Detect the actual sshd port instead of trusting `ufw allow ssh` (which
# only opens 22). Critical when running setup.sh over SSH on a remote box
# with a non-default port — wrong rule = locked out, need physical access.
SSH_PORTS=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ {print $2}' /etc/ssh/sshd_config 2>/dev/null)
[ -z "$SSH_PORTS" ] && SSH_PORTS=22
for _port in $SSH_PORTS; do
    ufw allow "$_port/tcp" || true
    echo "  ufw: opened sshd port $_port/tcp"
done
ufw allow 80/tcp || true
ufw allow 443/tcp || true

install -m 644 "$CONFIGS/fail2ban-jail.local" /etc/fail2ban/jail.local
systemctl enable fail2ban
if ! systemctl start fail2ban; then
    journalctl -xeu fail2ban.service --no-pager -n 10 || true
    FAILED_SERVICES+=("fail2ban")
fi

# SSH hardening — only disable password auth if user has authorized keys
sed -i 's/#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
if [ -s "$REAL_HOME/.ssh/authorized_keys" ]; then
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    echo "SSH password auth disabled (authorized_keys present)"
else
    echo -e "${YELLOW}No authorized_keys for $REAL_USER; leaving PasswordAuthentication unchanged.${NC}"
    echo -e "${YELLOW}Add your key with: ssh-copy-id $REAL_USER@<host>${NC}"
fi
# Reload — not restart — so the connection running this script doesn't get dropped.
# sshd re-reads its config on SIGHUP; no need to bounce the daemon.
systemctl reload sshd || systemctl restart sshd || true

# -----------------------------------------------------------------------------
# Databases
# -----------------------------------------------------------------------------
echo -e "${GREEN}Configuring PostgreSQL + Valkey...${NC}"
if [ ! -d "/var/lib/postgres/data" ] || [ -z "$(ls -A /var/lib/postgres/data 2>/dev/null)" ]; then
    # Use C.UTF-8 — always available regardless of glibc state, no
    # locale-archive dependency. (en_US.UTF-8 fails to start post-reboot
    # when pacman upgraded glibc earlier in this same script run, because
    # the locale-archive needs to be regenerated by the new glibc.)
    sudo -u postgres initdb -D /var/lib/postgres/data --locale=C.UTF-8 --encoding=UTF8
fi

systemctl enable postgresql
systemctl start postgresql || journalctl -xeu postgresql.service --no-pager -n 10

if systemctl is-active --quiet postgresql; then
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$REAL_USER'" | grep -q 1; then
        sudo -u postgres createuser -s "$REAL_USER" || true
        sudo -u postgres createdb "$REAL_USER" || true
    fi
fi

systemctl enable valkey
if ! systemctl start valkey; then
    journalctl -xeu valkey.service --no-pager -n 10 || true
    FAILED_SERVICES+=("valkey")
fi

install -m 644 "$CONFIGS/logrotate-gnar.conf" /etc/logrotate.d/gnar

# -----------------------------------------------------------------------------
# code-server
# -----------------------------------------------------------------------------
echo -e "${GREEN}Configuring code-server...${NC}"

CODE_SERVER_CFG="$REAL_HOME/.config/code-server/config.yaml"
install -d -o "$REAL_USER" -g "$REAL_USER" "$REAL_HOME/.config/code-server"

# Re-running setup.sh must NOT clobber an existing password — preserve it
# and only generate a fresh one on first install.
if [ -f "$CODE_SERVER_CFG" ] && \
   ! grep -q "__PASSWORD__" "$CODE_SERVER_CFG" && \
   grep -q "^password:" "$CODE_SERVER_CFG"; then
    VSCODE_PASSWORD=$(awk '/^password:/ {print $2; exit}' "$CODE_SERVER_CFG")
    echo "Reusing existing code-server password from $CODE_SERVER_CFG"
else
    VSCODE_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-25)
    sed "s|__PASSWORD__|$VSCODE_PASSWORD|" "$CONFIGS/code-server-config.yaml" \
        > "$CODE_SERVER_CFG"
    chown "$REAL_USER:$REAL_USER" "$CODE_SERVER_CFG"
    chmod 600 "$CODE_SERVER_CFG"
fi

install -d -o "$REAL_USER" -g "$REAL_USER" "$REAL_HOME/.local/share/code-server/User"
install -m 644 -o "$REAL_USER" -g "$REAL_USER" \
    "$CONFIGS/code-server-settings.json" \
    "$REAL_HOME/.local/share/code-server/User/settings.json"

install -m 644 "$CONFIGS/code-server.service" /etc/systemd/system/code-server@.service

# -----------------------------------------------------------------------------
# yay (AUR helper)
# -----------------------------------------------------------------------------
install_yay() {
    sudo -u "$REAL_USER" bash <<'EOF'
set -e
cd /tmp
rm -rf yay
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd /tmp && rm -rf yay
EOF
}
if ! command -v yay &>/dev/null; then
    echo -e "${GREEN}Installing yay...${NC}"
    # AUR builds + git clone over the network can flake. One retry, then tolerate.
    if ! install_yay; then
        echo -e "${YELLOW}yay install failed; retrying once...${NC}"
        sleep 5
        install_yay || FAILED_SERVICES+=("yay")
    fi
fi

# code-server (from AUR or official). Both paths can fail under poor network
# or transient AUR issues — tolerate so the rest of the bootstrap proceeds.
echo -e "${GREEN}Installing code-server...${NC}"
if command -v yay &>/dev/null; then
    sudo -u "$REAL_USER" yay -S --noconfirm code-server || \
        FAILED_SERVICES+=("code-server-install")
else
    sudo -u "$REAL_USER" bash -c 'curl -fsSL https://code-server.dev/install.sh | sh' || \
        FAILED_SERVICES+=("code-server-install")
fi

systemctl daemon-reload
# Only enable code-server if its binary actually landed; otherwise the unit
# loops in 203/EXEC at every boot.
if command -v code-server &>/dev/null; then
    systemctl enable "code-server@$REAL_USER"
    if ! systemctl start "code-server@$REAL_USER"; then
        journalctl -xeu "code-server@$REAL_USER" --no-pager -n 5 || true
        FAILED_SERVICES+=("code-server@$REAL_USER")
    fi
else
    echo -e "${YELLOW}code-server not installed; skipping enable.${NC}"
    FAILED_SERVICES+=("code-server@$REAL_USER")
fi

# -----------------------------------------------------------------------------
# Per-user runtime tooling
# -----------------------------------------------------------------------------
echo -e "${GREEN}Installing per-user tooling (npm, bun, python, ruby, rust, go)...${NC}"

# Whole heredoc is wrapped in `|| true` — every step has its own `|| true`
# inside, but the heredoc as a whole shouldn't be allowed to abort the
# bootstrap if (e.g.) the rustup curl-installer hits a network blip.
sudo -u "$REAL_USER" bash <<'EOF' || true
# Don't `set -e` — each command guards itself, and any single failure
# (npm registry hiccup, AUR mirror flake, rustup curl glitch) shouldn't
# stop the rest of the per-user tooling from being installed.
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
npm install -g yarn pnpm pm2 eslint prettier jest @anthropic-ai/claude-code || true

# Bun
curl -fsSL https://bun.sh/install | bash || true

# Python (uv)
# uv replaces pip / pipx / pipenv / poetry. uv tool installs land in ~/.local/bin.
uv tool install ruff || true
uv tool install pytest || true
uv tool install black || true

# Ruby
gem install bundler || true

# Rust (rustup)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || true
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
command -v rustup &>/dev/null && rustup default stable || true

# Go
export GOPATH="$HOME/go"
mkdir -p "$GOPATH/bin"
go install github.com/go-delve/delve/cmd/dlv@latest || true
EOF

# -----------------------------------------------------------------------------
# Helper scripts
# -----------------------------------------------------------------------------
echo -e "${GREEN}Installing helper scripts...${NC}"
install -m 755 "$BIN/gnar-info"             /usr/local/bin/gnar-info
install -m 755 "$BIN/gnar-update"           /usr/local/bin/gnar-update
install -m 755 "$BIN/gnar-help"             /usr/local/bin/gnar-help
install -m 755 "$BIN/gnar-dashboard"        /usr/local/bin/gnar-dashboard
install -m 755 "$BIN/gnar-services-status"  /usr/local/bin/gnar-services-status
install -m 755 "$BIN/gnar-claude-stats"     /usr/local/bin/gnar-claude-stats

# -----------------------------------------------------------------------------
# Kiosk dashboard (Hyprland on tty1 when a display is attached)
# -----------------------------------------------------------------------------
echo -e "${GREEN}Configuring kiosk dashboard (auto-login + Hyprland on tty1)...${NC}"
install -d -o "$REAL_USER" -g "$REAL_USER" "$REAL_HOME/.config/hypr"
install -m 644 -o "$REAL_USER" -g "$REAL_USER" \
    "$CONFIGS/hyprland.conf" "$REAL_HOME/.config/hypr/hyprland.conf"
install -d -o "$REAL_USER" -g "$REAL_USER" "$REAL_HOME/.config/foot"
install -m 644 -o "$REAL_USER" -g "$REAL_USER" \
    "$CONFIGS/foot.ini" "$REAL_HOME/.config/foot/foot.ini"
install -m 644 -o "$REAL_USER" -g "$REAL_USER" \
    "$CONFIGS/zprofile" "$REAL_HOME/.zprofile"

# Auto-login on tty1 only — other TTYs still prompt for a password.
install -d /etc/systemd/system/getty@tty1.service.d
sed "s|__USER__|$REAL_USER|g" "$CONFIGS/getty-autologin.conf" \
    > /etc/systemd/system/getty@tty1.service.d/autologin.conf
chmod 644 /etc/systemd/system/getty@tty1.service.d/autologin.conf
systemctl daemon-reload
systemctl enable getty@tty1.service &>/dev/null || true

# Default shell
chsh -s /usr/bin/zsh "$REAL_USER" || \
    echo -e "${YELLOW}Could not change shell; run: chsh -s /usr/bin/zsh${NC}"

# -----------------------------------------------------------------------------
# Enable UFW (last — see comment in firewall rules section above for why).
# -----------------------------------------------------------------------------
echo -e "${GREEN}Enabling firewall...${NC}"
# Always enable the systemd unit so ufw will start on boot regardless of
# whether the immediate `ufw enable` succeeds. If it fails now (kernel module
# mismatch from pacman -Syu), the unit will retry post-reboot when modules
# match — and at that point everything we configured will Just Work.
systemctl enable ufw &>/dev/null
if ! ufw --force enable; then
    echo -e "${YELLOW}UFW enable failed now (running kernel missing iptables modules).${NC}"
    echo -e "${YELLOW}Marked enabled in /etc/ufw/ufw.conf — will activate on next boot.${NC}"
    # ufw refused to flip ENABLED=yes because iptables-restore failed; do it
    # manually so /usr/lib/ufw/ufw-init brings it up cleanly post-reboot.
    sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf 2>/dev/null || true
    FAILED_SERVICES+=("ufw")
else
    systemctl start ufw || true
fi

# -----------------------------------------------------------------------------
# Status
# -----------------------------------------------------------------------------
echo
echo -e "${GREEN}=== Service status ===${NC}"
for svc in caddy docker postgresql valkey fail2ban ufw "code-server@$REAL_USER"; do
    if systemctl is-active --quiet "$svc"; then
        echo "  [+] $svc"
    else
        echo "  [-] $svc"
    fi
done

echo
echo -e "${GREEN}=== Setup complete ===${NC}"
echo
echo "VS Code Server: http://vscode.local"
echo "  password: $VSCODE_PASSWORD"
echo "  (saved at $REAL_HOME/.config/code-server/config.yaml)"
echo "  Add 'vscode.local' to your client /etc/hosts pointing at this server."
echo
if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo -e "${YELLOW}Some services did not start cleanly:${NC} ${FAILED_SERVICES[*]}"
    echo -e "${YELLOW}This is usually because pacman -Syu upgraded the kernel — reboot will resolve it.${NC}"
    echo
fi
echo "Next steps:"
echo "  1. sudo reboot"
echo "  2. ssh in, run: tmux"
echo "  3. add-site myapp 3000   # reverse proxy a service"
echo "  4. gnar-help             # full reference"
if [ "$ROOT_FS" = "btrfs" ]; then
    echo
    echo "Btrfs detected — Snapper is enabled. Useful commands:"
    echo "  snapper -c root list          # list snapshots"
    echo "  snapper -c root create        # manual snapshot"
    echo "  snapper -c root undochange N..M  # selectively roll back files"
    echo "  (snap-pac auto-snapshots before/after each pacman transaction)"
fi
