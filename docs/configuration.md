# Configuration Guide

## TTY Console

GNAR uses pure TTY with no GUI. Configure TTY appearance:

```bash
# Set console font (requires root)
sudo setfont /usr/share/kbd/consolefonts/ter-132n.psf.gz

# Make permanent by editing /etc/vconsole.conf
echo 'FONT=ter-132n' | sudo tee -a /etc/vconsole.conf
```

## Enhanced Zsh Shell

The setup creates a comprehensive `~/.zshrc` with 50+ aliases and smart functions. Customize further:

```bash
# Add personal aliases to ~/.zshrc
alias myproject='cd ~/projects/myapp'
alias serve='python -m http.server 8000'
alias mylog='tail -f /var/log/myapp.log'

# Custom functions
function gitclone() {
    git clone "$1" && cd "$(basename "$1" .git)"
}

function ports() {
    netstat -tulpn | grep LISTEN
}

# Environment variables
export EDITOR=nvim
export BROWSER=links  # text browser
export PAGER=less
```

## Neovim

Create `~/.config/nvim/init.lua`:

```lua
-- Basic settings
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.mouse = 'a'
vim.opt.clipboard = 'unnamedplus'

-- Dark colorscheme
vim.cmd.colorscheme('habamax')

-- Key mappings
vim.keymap.set('n', '<leader>w', ':w<CR>')
vim.keymap.set('n', '<leader>q', ':q<CR>')
vim.g.mapleader = ' '
```

## Installing Additional Software

```bash
# Essential CLI tools for development
sudo pacman -S bat eza ripgrep fd fzf jq

# Development languages
sudo pacman -S nodejs npm python python-pip go rust

# Text browsers for TTY
sudo pacman -S links lynx w3m

# Database tools
sudo pacman -S sqlite postgresql-clients

# AUR helper (if needed)
git clone https://aur.archlinux.org/yay.git
cd yay && makepkg -si
```

## Custom Helpers

Create TTY-optimized scripts in `~/.local/bin/`:

```bash
mkdir -p ~/.local/bin

# Quick note script
cat > ~/.local/bin/note << 'EOF'
#!/bin/bash
echo "$(date '+%Y-%m-%d %H:%M'): $*" >> ~/notes.txt
echo "Note saved: $*"
EOF

# System monitoring script
cat > ~/.local/bin/sysmon << 'EOF'
#!/bin/bash
clear
echo "=== System Monitor ==="
echo "Load: $(uptime | cut -d',' -f3-)"
echo "Memory: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "Disk: $(df -h / | tail -1 | awk '{print $3"/"$2" ("$5" used)"}')"
echo "Processes: $(ps aux | wc -l)"
EOF

# Make executable
chmod +x ~/.local/bin/*

# Add to PATH in ~/.zshrc if not already there
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```