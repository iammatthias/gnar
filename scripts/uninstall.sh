#!/bin/bash
#
# GNAR - Uninstall Script
# Removes GNAR configuration and reverts to clean state
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🗑️  GNAR Uninstall${NC}"
echo "This will remove GNAR configurations and revert to clean state."
echo

# Check if root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root: sudo ./uninstall.sh${NC}"
   exit 1
fi

# Get actual user
REAL_USER=$(logname)

echo -e "${YELLOW}Removing GNAR configurations...${NC}"

# Remove GNAR scripts
rm -f /usr/local/bin/gnar-*

# Stop and disable services
systemctl stop caddy 2>/dev/null || true
systemctl disable caddy 2>/dev/null || true

# Remove Caddy configuration
rm -f /etc/caddy/Caddyfile

# Remove user configurations (with backup)
if [[ -f "/home/$REAL_USER/.zshrc" ]]; then
    cp "/home/$REAL_USER/.zshrc" "/home/$REAL_USER/.zshrc.gnar-backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    echo "Backed up .zshrc to .zshrc.gnar-backup.$(date +%Y%m%d_%H%M%S)"
fi

if [[ -f "/home/$REAL_USER/.tmux.conf" ]]; then
    cp "/home/$REAL_USER/.tmux.conf" "/home/$REAL_USER/.tmux.conf.gnar-backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    echo "Backed up .tmux.conf to .tmux.conf.gnar-backup.$(date +%Y%m%d_%H%M%S)"
fi

# Remove Oh My Zsh and spaceship
sudo -u $REAL_USER rm -rf /home/$REAL_USER/.oh-my-zsh 2>/dev/null || true
sudo -u $REAL_USER rm -rf /home/$REAL_USER/.spaceship-prompt 2>/dev/null || true

# Remove zsh configuration
rm -f /home/$REAL_USER/.zshrc
rm -f /home/$REAL_USER/.tmux.conf

# Remove zsh history
rm -f /home/$REAL_USER/.zsh_history

# Remove config directories
sudo -u $REAL_USER rm -rf /home/$REAL_USER/.config/zsh 2>/dev/null || true
sudo -u $REAL_USER rm -rf /home/$REAL_USER/.config/spaceship 2>/dev/null || true

echo -e "${GREEN}✅ GNAR uninstalled successfully!${NC}"
echo
echo "What was removed:"
echo "  • GNAR helper scripts"
echo "  • Zsh configuration with Spaceship"
echo "  • Tmux configuration"
echo "  • Caddy web server"
echo "  • Oh My Zsh and plugins"
echo
echo "Backups created:"
echo "  • .zshrc.gnar-backup.*"
echo "  • .tmux.conf.gnar-backup.*"
echo
echo "System packages remain installed. To remove them:"
echo "  sudo pacman -Rns zsh tmux neovim caddy docker nodejs python ruby rust go"
echo
echo -e "${GREEN}System reverted to clean state! 🧹${NC}"