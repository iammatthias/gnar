#!/bin/bash
#
# GNAR - Home Server Bootstrap for Arch Linux
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

REAL_USER=$(logname)
REAL_HOME="/home/$REAL_USER"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGS="$REPO_ROOT/configs"
BIN="$REPO_ROOT/bin"

echo -e "${GREEN}GNAR - Home Server Bootstrap${NC}"
echo

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
systemctl start docker
usermod -aG docker "$REAL_USER"
echo -e "${YELLOW}Note: log out and back in for docker group membership.${NC}"

# -----------------------------------------------------------------------------
# Firewall + fail2ban + SSH
# -----------------------------------------------------------------------------
echo -e "${GREEN}Configuring firewall + fail2ban...${NC}"
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
systemctl enable ufw
systemctl start ufw || true

install -m 644 "$CONFIGS/fail2ban-jail.local" /etc/fail2ban/jail.local
systemctl enable fail2ban
systemctl start fail2ban

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
systemctl restart sshd

# -----------------------------------------------------------------------------
# Databases
# -----------------------------------------------------------------------------
echo -e "${GREEN}Configuring PostgreSQL + Valkey...${NC}"
if [ ! -d "/var/lib/postgres/data" ] || [ -z "$(ls -A /var/lib/postgres/data 2>/dev/null)" ]; then
    sudo -u postgres initdb -D /var/lib/postgres/data --locale=en_US.UTF-8 --encoding=UTF8
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
systemctl start valkey

install -m 644 "$CONFIGS/logrotate-gnar.conf" /etc/logrotate.d/gnar

# -----------------------------------------------------------------------------
# code-server
# -----------------------------------------------------------------------------
echo -e "${GREEN}Configuring code-server...${NC}"

VSCODE_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-25)

install -d -o "$REAL_USER" -g "$REAL_USER" "$REAL_HOME/.config/code-server"
sed "s|__PASSWORD__|$VSCODE_PASSWORD|" "$CONFIGS/code-server-config.yaml" \
    > "$REAL_HOME/.config/code-server/config.yaml"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/code-server/config.yaml"
chmod 600 "$REAL_HOME/.config/code-server/config.yaml"

install -d -o "$REAL_USER" -g "$REAL_USER" "$REAL_HOME/.local/share/code-server/User"
install -m 644 -o "$REAL_USER" -g "$REAL_USER" \
    "$CONFIGS/code-server-settings.json" \
    "$REAL_HOME/.local/share/code-server/User/settings.json"

install -m 644 "$CONFIGS/code-server.service" /etc/systemd/system/code-server@.service

# -----------------------------------------------------------------------------
# yay (AUR helper)
# -----------------------------------------------------------------------------
if ! command -v yay &>/dev/null; then
    echo -e "${GREEN}Installing yay...${NC}"
    sudo -u "$REAL_USER" bash <<'EOF'
set -e
cd /tmp
rm -rf yay
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd /tmp && rm -rf yay
EOF
fi

# code-server (from AUR or official)
echo -e "${GREEN}Installing code-server...${NC}"
if command -v yay &>/dev/null; then
    sudo -u "$REAL_USER" yay -S --noconfirm code-server || true
else
    sudo -u "$REAL_USER" bash -c 'curl -fsSL https://code-server.dev/install.sh | sh'
fi

systemctl daemon-reload
systemctl enable "code-server@$REAL_USER"
systemctl start "code-server@$REAL_USER" || \
    journalctl -xeu "code-server@$REAL_USER" --no-pager -n 5

# -----------------------------------------------------------------------------
# Per-user runtime tooling
# -----------------------------------------------------------------------------
echo -e "${GREEN}Installing per-user tooling (npm, bun, python, ruby, rust, go)...${NC}"

sudo -u "$REAL_USER" bash <<'EOF'
set -e
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
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
. "$HOME/.cargo/env"
rustup default stable

# Go
export GOPATH="$HOME/go"
mkdir -p "$GOPATH/bin"
go install github.com/go-delve/delve/cmd/dlv@latest || true
EOF

# -----------------------------------------------------------------------------
# Helper scripts
# -----------------------------------------------------------------------------
echo -e "${GREEN}Installing helper scripts...${NC}"
install -m 755 "$BIN/gnar-info"   /usr/local/bin/gnar-info
install -m 755 "$BIN/gnar-update" /usr/local/bin/gnar-update
install -m 755 "$BIN/gnar-help"   /usr/local/bin/gnar-help

# Default shell
chsh -s /usr/bin/zsh "$REAL_USER" || \
    echo -e "${YELLOW}Could not change shell; run: chsh -s /usr/bin/zsh${NC}"

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
echo "Next steps:"
echo "  1. sudo reboot"
echo "  2. ssh in, run: tmux"
echo "  3. add-site myapp 3000   # reverse proxy a service"
echo "  4. gnar-help             # full reference"
