#!/bin/bash
#
# GNAR Comprehensive Uninstall
# Reverses ALL changes made by setup.sh
#

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root: sudo ./uninstall.sh${NC}"
   exit 1
fi

echo -e "${RED}╔════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║     GNAR Complete Uninstall                   ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════╝${NC}"
echo
echo -e "${YELLOW}This will:${NC}"
echo "  • Remove all GNAR packages (tmux, zsh, neovim, etc.)"
echo "  • Delete configuration files (.zshrc, .tmux.conf)"
echo "  • Remove all helper scripts"
echo "  • Reset shell to bash"
echo "  • Restore system to pre-GNAR state"
echo
read -p "Are you sure you want to completely remove GNAR? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# Get actual user
REAL_USER=$(logname)
USER_HOME="/home/$REAL_USER"

echo
echo -e "${YELLOW}Starting comprehensive uninstall...${NC}"

# Step 1: Backup current configs (just in case)
echo "Creating backup of current configs..."
BACKUP_DIR="$USER_HOME/gnar-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup existing files if they exist
[[ -f "$USER_HOME/.zshrc" ]] && cp "$USER_HOME/.zshrc" "$BACKUP_DIR/" 2>/dev/null || true
[[ -f "$USER_HOME/.tmux.conf" ]] && cp "$USER_HOME/.tmux.conf" "$BACKUP_DIR/" 2>/dev/null || true
[[ -d "$USER_HOME/.config/fastfetch" ]] && cp -r "$USER_HOME/.config/fastfetch" "$BACKUP_DIR/" 2>/dev/null || true
[[ -f "$USER_HOME/.zsh_history" ]] && cp "$USER_HOME/.zsh_history" "$BACKUP_DIR/" 2>/dev/null || true

echo "  Backup saved to: $BACKUP_DIR"

# Step 2: Kill any running tmux sessions
echo "Stopping tmux sessions..."
sudo -u "$REAL_USER" tmux kill-server 2>/dev/null || true

# Step 3: Reset shell to bash BEFORE removing zsh
echo "Resetting default shell to bash..."
if grep -q "$REAL_USER.*zsh" /etc/passwd; then
    chsh -s /bin/bash "$REAL_USER"
    echo "  Shell reset to /bin/bash"
fi

# Step 4: Remove GNAR configuration files and restore originals
echo "Removing GNAR configuration files..."

# Check for pre-GNAR backups and restore them
if [[ -f "$USER_HOME/.zshrc.pre-gnar" ]]; then
    echo "  Restoring original .zshrc..."
    mv "$USER_HOME/.zshrc.pre-gnar" "$USER_HOME/.zshrc"
else
    rm -f "$USER_HOME/.zshrc" 2>/dev/null || true
fi

if [[ -f "$USER_HOME/.tmux.conf.pre-gnar" ]]; then
    echo "  Restoring original .tmux.conf..."
    mv "$USER_HOME/.tmux.conf.pre-gnar" "$USER_HOME/.tmux.conf"
else
    rm -f "$USER_HOME/.tmux.conf" 2>/dev/null || true
fi

# Remove fastfetch config and theme file
rm -rf "$USER_HOME/.config/fastfetch" 2>/dev/null || true
rm -f "$USER_HOME/.gnar_theme" 2>/dev/null || true

rm -f "$USER_HOME/.zsh_history" 2>/dev/null || true
echo "  Configuration files handled"

# Step 5: Remove helper scripts
echo "Removing helper scripts..."
rm -f /usr/local/bin/gnar-info 2>/dev/null || true
rm -f /usr/local/bin/gnar-update 2>/dev/null || true
rm -f /usr/local/bin/help-gnar 2>/dev/null || true
echo "  Helper scripts removed"

# Step 6: Remove packages (optional - ask user)
echo
echo -e "${YELLOW}Package removal options:${NC}"
echo "  1) Remove all GNAR packages (tmux, zsh, neovim, etc.)"
echo "  2) Keep essential tools (git, curl, which, man-db)"
echo "  3) Keep all packages"
echo
read -p "Choose option (1-3) [3]: " -n 1 -r
echo

case "$REPLY" in
    1)
        echo "Removing ALL GNAR packages..."
        PACKAGES="zsh tmux neovim fastfetch htop tree starship eza bat fd fzf zoxide git curl which man-db man-pages bc net-tools"
        for pkg in $PACKAGES; do
            if pacman -Qi "$pkg" &>/dev/null; then
                echo "  Removing $pkg..."
                pacman -Rns --noconfirm "$pkg" 2>/dev/null || true
            fi
        done
        echo "  All packages removed"
        ;;
    2)
        echo "Removing non-essential GNAR packages..."
        PACKAGES="zsh tmux neovim fastfetch htop tree starship eza bat fd fzf zoxide bc net-tools"
        for pkg in $PACKAGES; do
            if pacman -Qi "$pkg" &>/dev/null; then
                echo "  Removing $pkg..."
                pacman -Rns --noconfirm "$pkg" 2>/dev/null || true
            fi
        done
        echo "  Non-essential packages removed (kept git, curl, which, man-db)"
        ;;
    *)
        echo "  Keeping all installed packages"
        ;;
esac

# Step 7: Clean up any remaining GNAR references
echo "Cleaning up..."
# Remove any GNAR environment variables from other shell configs
for file in "$USER_HOME/.bashrc" "$USER_HOME/.bash_profile" "$USER_HOME/.profile"; do
    if [[ -f "$file" ]]; then
        sed -i '/GNAR/d' "$file" 2>/dev/null || true
        sed -i '/gnar/d' "$file" 2>/dev/null || true
    fi
done

# Step 8: Final report
echo
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     GNAR Uninstall Complete!                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo
echo "Summary:"
echo "  ✓ Shell reset to bash"
if [[ -f "$USER_HOME/.zshrc.pre-gnar" ]] || [[ -f "$USER_HOME/.tmux.conf.pre-gnar" ]]; then
    echo "  ✓ Original configuration files restored"
else
    echo "  ✓ Configuration files removed"
fi
echo "  ✓ Helper scripts removed"
case "$REPLY" in
    1) echo "  ✓ All packages removed" ;;
    2) echo "  ✓ Non-essential packages removed" ;;
    *) echo "  ✓ Packages kept" ;;
esac
echo "  ✓ Backup saved to: $BACKUP_DIR"
echo
echo -e "${YELLOW}Note: Log out and back in for shell changes to take effect.${NC}"
echo -e "${YELLOW}To restore configs: cp $BACKUP_DIR/* ~/  ${NC}"