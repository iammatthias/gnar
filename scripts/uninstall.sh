#!/bin/bash
#
# GNAR - Uninstall
# Reverts the configuration installed by setup.sh.
# Does NOT remove pacman packages — keep or remove those manually.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root: sudo ./uninstall.sh${NC}"
   exit 1
fi

REAL_USER=$(logname)
REAL_HOME="/home/$REAL_USER"
TS=$(date +%Y%m%d_%H%M%S)

echo -e "${YELLOW}Reverting GNAR configuration for $REAL_USER...${NC}"
echo

# -----------------------------------------------------------------------------
# Stop / disable services
# -----------------------------------------------------------------------------
for svc in "code-server@$REAL_USER" caddy fail2ban valkey postgresql ufw; do
    systemctl is-active --quiet "$svc" && systemctl stop "$svc" || true
    systemctl is-enabled --quiet "$svc" 2>/dev/null && systemctl disable "$svc" || true
done

# Reset UFW to default deny-all-allow-all (before disabling) so reinstall is clean
if command -v ufw &>/dev/null; then
    ufw --force reset >/dev/null || true
fi

# -----------------------------------------------------------------------------
# System config files
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Removing system config...${NC}"

[ -f /etc/caddy/Caddyfile ] && \
    mv /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.gnar-backup.$TS"

[ -f /etc/fail2ban/jail.local ] && \
    mv /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.gnar-backup.$TS"

[ -f /etc/logrotate.d/gnar ] && rm -f /etc/logrotate.d/gnar

[ -f /etc/systemd/system/code-server@.service ] && \
    rm -f /etc/systemd/system/code-server@.service

# Restore stock sshd_config flags (best-effort: only revert what setup.sh forced)
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^PermitRootLogin no$/#PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication no$/#PasswordAuthentication yes/' /etc/ssh/sshd_config
fi
systemctl reload sshd 2>/dev/null || true

systemctl daemon-reload

# -----------------------------------------------------------------------------
# User-level config (with backups)
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Removing user config from $REAL_HOME...${NC}"

backup_and_remove() {
    local f=$1
    if [ -e "$f" ]; then
        mv "$f" "${f}.gnar-backup.$TS"
    fi
}

backup_and_remove "$REAL_HOME/.zshrc"
backup_and_remove "$REAL_HOME/.tmux.conf"
backup_and_remove "$REAL_HOME/.config/fastfetch/config.jsonc"
backup_and_remove "$REAL_HOME/.config/code-server/config.yaml"
backup_and_remove "$REAL_HOME/.local/share/code-server/User/settings.json"

# Oh My Zsh + Spaceship + plugins
sudo -u "$REAL_USER" rm -rf "$REAL_HOME/.oh-my-zsh" || true

# Helper scripts
rm -f /usr/local/bin/gnar-info /usr/local/bin/gnar-update /usr/local/bin/gnar-help

echo
echo -e "${GREEN}GNAR configuration removed.${NC}"
echo
echo "Backups: *.gnar-backup.$TS"
echo
echo "Packages remain installed. To remove the GNAR package set:"
echo "  sudo pacman -Rns zsh tmux neovim caddy docker docker-compose \\"
echo "    nodejs npm python ruby go jdk-openjdk maven gradle \\"
echo "    eza bat fd fzf zoxide ripgrep jq yq fastfetch htop btop \\"
echo "    iotop nethogs ncdu rsync rclone p7zip imagemagick httpie \\"
echo "    ufw fail2ban nmap tcpdump wireshark-cli postgresql valkey \\"
echo "    sqlite smartmontools"
