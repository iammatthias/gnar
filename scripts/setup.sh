#!/bin/bash
#
# GNAR - Pure TTY with Enhanced Zsh
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Installing pure TTY setup with enhanced Zsh...${NC}"

# Check if root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root: sudo ./setup.sh${NC}"
   exit 1
fi

# Get actual user
REAL_USER=$(logname)

# Update system
pacman -Syu --noconfirm

# Install minimal packages - just essentials
pacman -S --noconfirm \
  zsh \
  tmux \
  neovim \
  git \
  fastfetch \
  htop \
  curl \
  tree \
  which \
  man-db \
  man-pages \
  starship \
  eza \
  bat \
  fd \
  fzf \
  zoxide

echo -e "${GREEN}Configuring enhanced Zsh...${NC}"

# Backup existing configs if present
if [[ -f "/home/$REAL_USER/.zshrc" ]]; then
    cp "/home/$REAL_USER/.zshrc" "/home/$REAL_USER/.zshrc.pre-gnar" 2>/dev/null || true
    echo "  Backed up existing .zshrc to .zshrc.pre-gnar"
fi
if [[ -f "/home/$REAL_USER/.tmux.conf" ]]; then
    cp "/home/$REAL_USER/.tmux.conf" "/home/$REAL_USER/.tmux.conf.pre-gnar" 2>/dev/null || true
    echo "  Backed up existing .tmux.conf to .tmux.conf.pre-gnar"
fi

# Configure enhanced zsh for the actual user
sudo -u $REAL_USER bash << 'EOF'

# DarkMatter-inspired Zsh configuration for GNAR
cat > ~/.zshrc << 'ZSHRC'
# GNAR DarkMatter TTY Zsh Configuration

# History setup
HISTFILE=$HOME/.zsh_history
SAVEHIST=10000
HISTSIZE=10000
setopt share_history
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_verify

# Completion using arrow keys (based on history)
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Completion using vim keys
bindkey '^k' history-search-backward
bindkey '^j' history-search-forward

# Enhanced aliases - DarkMatter style
alias ls="eza --icons=always --group-directories-first"
alias ll="eza --icons=always --long --group-directories-first"
alias la="eza --icons=always --all --group-directories-first"
alias tree="eza --icons=always --tree"

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias -- -='cd -'
alias cd='z'  # Use zoxide for smart jumping

# File operations
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias mkdir='mkdir -p'

# System info
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ps='ps aux'
alias top='htop'
alias cat='bat --style=plain'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias diff='diff --color=auto'
alias ip='ip --color=auto'
alias find='fd'

# Git shortcuts
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gb='git branch'
alias gco='git checkout'
alias glog='git log --oneline --graph --decorate'

# Text editing
alias vim='nvim'
alias vi='nvim'
alias nano='nvim'

# Network
alias ping='ping -c 5'
alias wget='wget -c'

# Exports
export BAT_THEME="ansi"
export EDITOR="nvim"
export PAGER="bat"

# FZF settings with DarkMatter colors
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude ".git"'
export FZF_DEFAULT_OPTS='
  --color=fg:#c1c1c1,fg+:#ffffff,bg:#121113,bg+:#222222
  --color=hl:#5f8787,hl+:#fbcb97,info:#e78a53,marker:#fbcb97
  --color=prompt:#e78a53,spinner:#5f8787,pointer:#fbcb97,header:#aaaaaa
  --color=border:#333333,label:#888888,query:#ffffff
  --border="rounded" --border-label="" --preview-window="border-rounded" --prompt="> "
  --marker=">" --pointer="◆" --separator="─" --scrollbar="│"'

# Useful functions
function mkcd() {
    mkdir -p "$1" && cd "$1"
}

function extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar x "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

function backup() {
    cp "$1"{,.backup.$(date +%Y%m%d_%H%M%S)}
}

function weather() {
    curl "wttr.in/${1:-}"
}

function calc() {
    echo "scale=3; $*" | bc -l
}

function find_large_files() {
    find "${1:-.}" -type f -exec du -h {} + | sort -rh | head -20
}

function pid_port() {
    netstat -tulpn | grep ":$1 "
}

# Tmux aliases
alias tmux='tmux -2'  # Force 256 colors
alias tn='tmux new -s'
alias ta='tmux attach -t'
alias tl='tmux ls'
alias tk='tmux kill-session -t'

# Setup zoxide and starship (DarkMatter essentials)
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"

# Welcome message
echo "Welcome to GNAR DarkMatter TTY"
echo "Type 'gnar-info' for system information"
echo "Type 'help-gnar' for command reference"
echo "Type 'tmux' to start tiling terminal"
ZSHRC

# Create fastfetch configuration directory and config
mkdir -p ~/.config/fastfetch
cat > ~/.config/fastfetch/config.jsonc << 'FASTFETCH'
// GNAR TTY Machine Report - Inspired by TR-100
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": null,
    "display": {
        "pipe": true,
        "key": {
            "width": 16
        },
        "separator": "│ ",
        "percent": {
            "type": ["bar", "hide-others"]
        },
        "bar": {
            "border": null,
            "char": {
                "elapsed": "█",
                "total": "░"
            },
            "width": 40
        },
        "constants": [
            "\u001b[42C"
        ]
    },
    "modules": [
        {
            "type": "custom",
            "format": "┌┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┐"
        },
        {
            "type": "custom",
            "format": "├┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┤"
        },
        {
            "type": "version",
            "key": " ",
            "format": "│                   FASTFETCH v{version}                   │"
        },
        {
            "type": "custom",
            "format": "│                  GNAR MACHINE REPORT                  │"
        },
        {
            "type": "custom",
            "format": "├────────────┬──────────────────────────────────────────┤"
        },
        {
            "type": "os",
            "key": "│ OS         │{$1}"
        },
        {
            "type": "kernel",
            "key": "│ KERNEL     │{$1}"
        },
        {
            "type": "custom",
            "format": "├────────────┼──────────────────────────────────────────┤"
        },
        {
            "type": "title",
            "key": "│ HOSTNAME   │{$1}",
            "format": "{host-name}"
        },
        {
            "type": "localip",
            "key": "│ CLIENT IP  │{$1}",
            "format": "{ipv4}"
        },
        {
            "type": "localip",
            "key": "│ MAC ADDR   │{$1}",
            "format": "{mac} ({ifname})",
            "showIpv4": false,
            "showMac": true
        },
        {
            "type": "dns",
            "key": "│ DNS        │{$1}",
            "showType": "ipv4"
        },
        {
            "type": "title",
            "key": "│ USER       │{$1}",
            "format": "{user-name}"
        },
        {
            "type": "host",
            "key": "│ MACHINE    │{$1}",
            "format": "{name}"
        },
        {
            "type": "custom",
            "format": "├────────────┼──────────────────────────────────────────┤"
        },
        {
            "type": "cpu",
            "key": "│ PROCESSOR  │{$1}",
            "format": "{name}"
        },
        {
            "type": "cpu",
            "key": "│ CORES      │{$1}",
            "format": "{cores-physical} PHYSICAL CORES / {cores-logical} THREADS",
            "showPeCoreCount": false
        },
        {
            "type": "cpu",
            "key": "│ CPU FREQ   │{$1}",
            "format": "{freq-max}{/freq-max}{freq-base}{/}"
        },
        {
            "type": "loadavg",
            "compact": false,
            "key": "│ LOAD  {duration>2}m  │{$1}"
        },
        {
            "type": "custom",
            "format": "├────────────┼──────────────────────────────────────────┤"
        },
        {
            "type": "memory",
            "key": "│ MEMORY     │{$1}",
            "format": "{used} / {total} [{percentage}]",
            "percent": {
                "type": ["num"]
            }
        },
        {
            "type": "memory",
            "key": "│ USAGE      │{$1}",
            "format": "",
            "percent": {
                "type": ["bar", "hide-others"]
            }
        },
        {
            "type": "custom",
            "format": "├────────────┼──────────────────────────────────────────┤"
        },
        {
            "type": "disk",
            "key": "│ VOLUME     │{$1}",
            "format": "{size-used} / {size-total} [{size-percentage}]",
            "folders": "/",
            "percent": {
                "type": ["num"]
            }
        },
        {
            "type": "disk",
            "key": "│ DISK USAGE │{$1}",
            "format": "",
            "percent": {
                "type": ["bar", "hide-others"]
            }
        },
        {
            "type": "custom",
            "format": "├────────────┼──────────────────────────────────────────┤"
        },
        {
            "type": "users",
            "key": "│ LAST LOGIN │{$1}",
            "format": "{login-time}{?client-ip} ({client-ip})",
            "myselfOnly": true
        },
        {
            "type": "uptime",
            "key": "│ UPTIME     │{$1}"
        },
        {
            "type": "custom",
            "format": "└────────────┴──────────────────────────────────────────┘"
        }
    ]
}
FASTFETCH

# Create tmux configuration
cat > ~/.tmux.conf << 'TMUX'
# GNAR Tmux Configuration

# Set prefix to Ctrl-a (like screen)
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# Enable mouse support
set -g mouse on

# Start windows and panes at 1, not 0
set -g base-index 1
setw -g pane-base-index 1

# Split panes with | and -
bind | split-window -h
bind - split-window -v
unbind '"'
unbind %

# Vim-style pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Resize panes with vim keys
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Enable 256 colors
set -g default-terminal "screen-256color"

# Status bar
set -g status-style bg=black,fg=white
set -g status-left '#[fg=green]#S '
set -g status-right '#[fg=yellow]#H #[fg=cyan]%H:%M'

# Reload config
bind r source-file ~/.tmux.conf \; display "Config reloaded!"
TMUX

EOF

# Change shell to zsh (needs to be done as root for the actual user)
echo -e "${GREEN}Setting zsh as default shell...${NC}"
chsh -s /usr/bin/zsh "$REAL_USER"

echo -e "${GREEN}Creating enhanced helper utilities...${NC}"

# Create gnar-info that uses our custom fastfetch config
cat > /usr/local/bin/gnar-info << 'SCRIPT'
#!/bin/bash
# GNAR TTY system information

# Use fastfetch with our custom config
fastfetch
SCRIPT

# Create gnar-update
cat > /usr/local/bin/gnar-update << 'SCRIPT'
#!/bin/bash
# GNAR system update

echo "Updating GNAR TTY system..."
sudo pacman -Syu
echo
echo "Cleaning package cache..."
sudo pacman -Sc --noconfirm
echo
echo "Update complete!"
SCRIPT

# Create theme switcher
cat > /usr/local/bin/gnar-theme << 'SCRIPT'
#!/bin/bash
# GNAR Theme Switcher

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

show_themes() {
    echo "Available GNAR Themes:"
    echo
    echo "  1) darkmatter  - Sleek dark theme with starship prompt"
    echo "  2) matrix      - Green-on-black hacker aesthetic"
    echo "  3) minimal     - Clean, distraction-free"
    echo "  4) retro       - 80s terminal vibes"
    echo "  5) ocean       - Deep blue nautical theme"
    echo
    echo "Current theme: $(cat ~/.gnar_theme 2>/dev/null || echo "darkmatter")"
}

apply_theme() {
    local theme=$1
    echo "$theme" > ~/.gnar_theme
    
    case "$theme" in
        darkmatter)
            # DarkMatter FZF colors
            sed -i '/^export FZF_DEFAULT_OPTS=/,/'"'"'$/d' ~/.zshrc
            cat >> ~/.zshrc << 'EOF'
export FZF_DEFAULT_OPTS='
  --color=fg:#c1c1c1,fg+:#ffffff,bg:#121113,bg+:#222222
  --color=hl:#5f8787,hl+:#fbcb97,info:#e78a53,marker:#fbcb97
  --color=prompt:#e78a53,spinner:#5f8787,pointer:#fbcb97,header:#aaaaaa
  --color=border:#333333,label:#888888,query:#ffffff
  --border="rounded" --border-label="" --preview-window="border-rounded" --prompt="> "
  --marker=">" --pointer="◆" --separator="─" --scrollbar="│"'
EOF
            echo -e "${GREEN}DarkMatter theme applied!${NC}"
            ;;
            
        matrix)
            # Matrix green theme
            sed -i '/^export FZF_DEFAULT_OPTS=/,/'"'"'$/d' ~/.zshrc
            cat >> ~/.zshrc << 'EOF'
export FZF_DEFAULT_OPTS='
  --color=fg:#00ff00,fg+:#00ff00,bg:#000000,bg+:#001100
  --color=hl:#00aa00,hl+:#00ff00,info:#00ff00,marker:#00ff00
  --color=prompt:#00ff00,spinner:#00aa00,pointer:#00ff00,header:#00aa00
  --color=border:#00aa00,label:#00ff00,query:#00ff00
  --border="rounded" --border-label="" --preview-window="border-rounded" --prompt="> "
  --marker=">" --pointer=">" --separator="─" --scrollbar="│"'
EOF
            echo -e "${GREEN}Matrix theme applied!${NC}"
            ;;
            
        minimal)
            # Minimal monochrome
            sed -i '/^export FZF_DEFAULT_OPTS=/,/'"'"'$/d' ~/.zshrc
            cat >> ~/.zshrc << 'EOF'
export FZF_DEFAULT_OPTS='
  --color=fg:#ffffff,fg+:#ffffff,bg:#000000,bg+:#222222
  --color=hl:#888888,hl+:#ffffff,info:#cccccc,marker:#ffffff
  --color=prompt:#ffffff,spinner:#888888,pointer:#ffffff,header:#888888
  --color=border:#444444,label:#888888,query:#ffffff
  --border="sharp" --border-label="" --preview-window="border-sharp" --prompt="> "
  --marker=">" --pointer=">" --separator="─" --scrollbar="│"'
EOF
            echo -e "${GREEN}Minimal theme applied!${NC}"
            ;;
            
        retro)
            # Retro 80s colors
            sed -i '/^export FZF_DEFAULT_OPTS=/,/'"'"'$/d' ~/.zshrc
            cat >> ~/.zshrc << 'EOF'
export FZF_DEFAULT_OPTS='
  --color=fg:#ff00ff,fg+:#00ffff,bg:#000033,bg+:#000066
  --color=hl:#ffff00,hl+:#ff00ff,info:#00ffff,marker:#ff00ff
  --color=prompt:#ff00ff,spinner:#00ffff,pointer:#ffff00,header:#ff00ff
  --color=border:#ff00ff,label:#00ffff,query:#ffffff
  --border="double" --border-label="" --preview-window="border-double" --prompt="> "
  --marker="▸" --pointer="▶" --separator="═" --scrollbar="║"'
EOF
            echo -e "${GREEN}Retro theme applied!${NC}"
            ;;
            
        ocean)
            # Ocean blue theme
            sed -i '/^export FZF_DEFAULT_OPTS=/,/'"'"'$/d' ~/.zshrc
            cat >> ~/.zshrc << 'EOF'
export FZF_DEFAULT_OPTS='
  --color=fg:#a0c4e0,fg+:#ffffff,bg:#001122,bg+:#002244
  --color=hl:#4488cc,hl+:#66aaff,info:#3377bb,marker:#5599dd
  --color=prompt:#66aaff,spinner:#4488cc,pointer:#88ccff,header:#5599dd
  --color=border:#334466,label:#6699cc,query:#ffffff
  --border="rounded" --border-label="" --preview-window="border-rounded" --prompt="~ "
  --marker="~" --pointer="◈" --separator="─" --scrollbar="│"'
EOF
            echo -e "${GREEN}Ocean theme applied!${NC}"
            ;;
            
        *)
            echo -e "${RED}Unknown theme: $theme${NC}"
            show_themes
            exit 1
            ;;
    esac
    
    echo "Restart your shell or run: source ~/.zshrc"
}

case "$1" in
    list|ls)
        show_themes
        ;;
    set|apply)
        if [ -z "$2" ]; then
            show_themes
            echo
            read -p "Select theme (1-5): " choice
            case "$choice" in
                1) apply_theme "darkmatter" ;;
                2) apply_theme "matrix" ;;
                3) apply_theme "minimal" ;;
                4) apply_theme "retro" ;;
                5) apply_theme "ocean" ;;
                *) echo -e "${RED}Invalid choice${NC}" ;;
            esac
        else
            apply_theme "$2"
        fi
        ;;
    *)
        echo "Usage: gnar-theme [command] [theme]"
        echo
        echo "Commands:"
        echo "  list, ls       - Show available themes"
        echo "  set, apply     - Apply a theme"
        echo
        show_themes
        ;;
esac
SCRIPT

# Create help command
cat > /usr/local/bin/help-gnar << 'SCRIPT'
#!/bin/bash
# GNAR command reference

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  GNAR TTY Command Reference"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "System Commands:"
echo "  gnar-info        - System information"
echo "  gnar-update      - Update system"
echo "  gnar-theme       - Switch terminal themes"
echo "  htop            - Process monitor"
echo "  fastfetch       - Quick system info"
echo
echo "Tmux (Tiling Terminal):"
echo "  tmux            - Start new session"
echo "  tn <name>       - New named session"
echo "  ta <name>       - Attach to session"
echo "  tl              - List sessions"
echo "  Ctrl-a |        - Split vertical"
echo "  Ctrl-a -        - Split horizontal"
echo "  Ctrl-a h/j/k/l  - Navigate panes"
echo "  Ctrl-a x        - Close pane"
echo "  Ctrl-a d        - Detach session"
echo "  exit            - Exit pane/tmux"
echo
echo "File Operations:"
echo "  ll              - Detailed file list"
echo "  tree            - Directory tree"
echo "  mkcd <dir>      - Create and enter directory"
echo "  backup <file>   - Backup file with timestamp"
echo "  extract <file>  - Extract archives"
echo
echo "Navigation:"
echo "  ..              - Go up one directory"
echo "  ...             - Go up two directories"
echo "  -               - Go to previous directory"
echo
echo "Git Shortcuts:"
echo "  gs              - git status"
echo "  ga              - git add"
echo "  gc              - git commit"
echo "  glog            - git log graph"
echo
echo "Utilities:"
echo "  weather [city]  - Weather report"
echo "  calc <expr>     - Calculator"
echo "  find_large_files - Find large files"
echo "  pid_port <port> - Find process on port"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SCRIPT

# Make scripts executable
chmod +x /usr/local/bin/gnar-*
chmod +x /usr/local/bin/help-gnar

echo
echo -e "${GREEN}Done!${NC}"
echo "Installed: Enhanced Zsh, Tmux, Neovim, Git, System tools"
echo
echo "Helper commands:"
echo "  • gnar-info - Pretty TTY system information"
echo "  • gnar-update - Update system and clean cache"
echo "  • help-gnar - Complete command reference"
echo
echo "Start tmux for tiling terminal experience!"
echo "Reboot and enjoy your enhanced TTY!"