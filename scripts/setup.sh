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
  man-pages

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

# Enhanced zsh config with lots of improvements
cat > ~/.zshrc << 'ZSHRC'
# GNAR Enhanced TTY Zsh Configuration

# History configuration
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt HIST_EXPIRE_DUPS_FIRST

# Zsh options for better UX
setopt AUTO_CD              # cd by typing directory name
setopt CORRECT              # spelling correction
setopt EXTENDED_GLOB        # better globbing
setopt NO_CASE_GLOB         # case insensitive globbing
setopt NUMERIC_GLOB_SORT    # sort numerically
setopt AUTO_PUSHD           # automatic pushd
setopt PUSHD_IGNORE_DUPS    # ignore duplicate dirs in stack

# Colors and prompt
autoload -U colors && colors

# Git prompt function
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' %F{red}[%b]%f'
zstyle ':vcs_info:*' enable git
setopt PROMPT_SUBST

# Enhanced prompt with path, git, and status
PS1='%F{cyan}┌─[%f%F{green}%n@%m%f%F{cyan}]─[%f%F{blue}%~%f%F{cyan}]%f${vcs_info_msg_0_}
%F{cyan}└─%f%F{yellow}❯%f '

# Right prompt with time
RPS1='%F{gray}[%T]%f'

# Key bindings for history search
bindkey '^[[A' history-search-backward  # Up arrow
bindkey '^[[B' history-search-forward   # Down arrow
bindkey '^R' history-incremental-search-backward

# Enhanced aliases
alias ls='ls --color=auto --group-directories-first'
alias ll='ls -la --color=auto --group-directories-first'
alias la='ls -A --color=auto --group-directories-first'
alias l='ls -CF --color=auto --group-directories-first'
alias tree='tree -C'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias diff='diff --color=auto'
alias ip='ip --color=auto'

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias -- -='cd -'

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

# Auto-start tmux on TTY login (optional - uncomment to enable)
# if [[ -z "$TMUX" && "$TERM" == "linux" ]]; then
#     tmux new-session -A -s main
# fi

# Welcome message
echo "Welcome to GNAR TTY - Enhanced Zsh Terminal"
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

# Change shell to zsh
chsh -s /usr/bin/zsh
EOF

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