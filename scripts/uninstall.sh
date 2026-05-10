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

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "")}"
if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    echo -e "${RED}Could not determine the target user. Run as: sudo ./uninstall.sh${NC}"
    exit 1
fi
REAL_HOME="/home/$REAL_USER"
TS=$(date +%Y%m%d_%H%M%S)

# Restore a file from its setup-time .gnar-orig snapshot. The current state
# is moved aside as .gnar-backup.<ts> so the user can audit the diff.
restore_orig() {
    local f=$1
    if [ -f "$f.gnar-orig" ]; then
        [ -f "$f" ] && mv "$f" "$f.gnar-backup.$TS"
        mv "$f.gnar-orig" "$f"
        echo "Restored $f from setup-time snapshot"
    fi
}

echo -e "${YELLOW}Reverting GNAR configuration for $REAL_USER...${NC}"
echo

# -----------------------------------------------------------------------------
# Stop / disable services
# -----------------------------------------------------------------------------
for svc in caddy fail2ban valkey postgresql ufw; do
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

# tty1 auto-login drop-in
if [ -d /etc/systemd/system/getty@tty1.service.d ]; then
    rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
    rmdir --ignore-fail-on-non-empty /etc/systemd/system/getty@tty1.service.d
fi

# grub-btrfsd — disable but leave snapper config + snapshots alone
# (those are user data; the user can `snapper -c root delete-config` manually).
systemctl is-enabled --quiet grub-btrfsd 2>/dev/null && \
    systemctl disable --now grub-btrfsd >/dev/null 2>&1 || true

# Hermes user services — disable both. Leave ~/.hermes/ alone (it has the
# user's OAuth tokens, kanban db, MEMORY.md — that's user data).
sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
    systemctl --user disable --now hermes-gateway hermes-dashboard 2>/dev/null || true
rm -f "$REAL_HOME/.config/systemd/user/hermes-gateway.service" \
      "$REAL_HOME/.config/systemd/user/hermes-dashboard.service"
loginctl disable-linger "$REAL_USER" 2>/dev/null || true

# Drop the agent-mode passwordless-sudo grant. Other sudoers config left alone.
rm -f "/etc/sudoers.d/gnar-${REAL_USER}-nopasswd"

# Restore /etc/ssh/sshd_config and locale files from the setup-time snapshots
# if they exist; otherwise fall back to best-effort sed reverts.
if [ -f /etc/ssh/sshd_config.gnar-orig ]; then
    restore_orig /etc/ssh/sshd_config
elif [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^PermitRootLogin no$/#PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication no$/#PasswordAuthentication yes/' /etc/ssh/sshd_config
fi
systemctl reload sshd 2>/dev/null || true

restore_orig /etc/locale.gen
restore_orig /etc/locale.conf

# Remove user from the docker group (added by setup.sh).
if getent group docker >/dev/null 2>&1 && id -nG "$REAL_USER" 2>/dev/null | grep -qw docker; then
    gpasswd -d "$REAL_USER" docker >/dev/null || true
    echo "Removed $REAL_USER from docker group"
fi

# Restore login shell. We don't know the user's original shell, so we default
# to bash if zsh is currently set. If they've since changed it, leave it alone.
if [ "$(getent passwd "$REAL_USER" | cut -d: -f7)" = "/usr/bin/zsh" ] && [ -x /bin/bash ]; then
    chsh -s /bin/bash "$REAL_USER" 2>/dev/null && echo "Login shell restored to /bin/bash"
fi

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
backup_and_remove "$REAL_HOME/.zprofile"
backup_and_remove "$REAL_HOME/.tmux.conf"
backup_and_remove "$REAL_HOME/.config/fastfetch/config.jsonc"
backup_and_remove "$REAL_HOME/.config/mango/config.conf"
backup_and_remove "$REAL_HOME/.config/foot/foot.ini"

# Only back up CLAUDE.md if it's the one GNAR installed (sentinel: first
# line is "# GNAR Server"). Hand-written ones are left alone.
if [ -f "$REAL_HOME/CLAUDE.md" ] && head -n1 "$REAL_HOME/CLAUDE.md" | grep -q "^# GNAR Server$"; then
    mv "$REAL_HOME/CLAUDE.md" "$REAL_HOME/CLAUDE.md.gnar-backup.$TS"
fi

# Oh My Zsh + Spaceship + plugins
sudo -u "$REAL_USER" rm -rf "$REAL_HOME/.oh-my-zsh" || true

# Helper scripts
rm -f /usr/local/bin/gnar-info /usr/local/bin/gnar-update /usr/local/bin/gnar-help \
      /usr/local/bin/gnar-dashboard /usr/local/bin/gnar-services-status \
      /usr/local/bin/gnar-claude-stats /usr/local/bin/gnar-hermes-status \
      /usr/local/bin/gnar-project-init

echo
echo -e "${GREEN}GNAR configuration removed.${NC}"
echo
echo "Backups: *.gnar-backup.$TS"
echo
echo "Packages remain installed. To remove the GNAR package set:"
echo "  sudo pacman -Rns zsh tmux neovim caddy docker docker-compose \\"
echo "    nodejs npm python uv ruby go jdk-openjdk maven gradle \\"
echo "    eza bat fd fzf zoxide ripgrep jq yq fastfetch htop btop \\"
echo "    iotop nethogs ncdu rsync rclone p7zip imagemagick httpie \\"
echo "    ufw fail2ban nmap tcpdump wireshark-cli postgresql valkey \\"
echo "    sqlite smartmontools foot"
echo "  yay -Rns mangowm-git"
