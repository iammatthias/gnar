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

# Ensure UTF-8 locale is configured
if ! grep -q "en_US.UTF-8 UTF-8" /etc/locale.gen 2>/dev/null; then
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
fi
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

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
  zoxide \
  bc \
  net-tools

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

# Set UTF-8 locale for proper tmux support
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

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

# File listing - Enhanced with eza
alias ls="eza --icons=always --group-directories-first"
alias ll="eza --icons=always --long --group-directories-first"
alias la="eza --icons=always --all --group-directories-first"
alias l="eza --icons=always --oneline"
alias tree="eza --icons=always --tree"
alias lt="eza --icons=always --tree --level=2"  # Tree with depth limit

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
alias ff='fastfetch'           # Quick system info display
alias nf='fastfetch'           # Alternative for neofetch users
alias cat='bat --style=plain'  # Better cat with syntax highlighting
alias realcat='/usr/bin/cat'  # Original cat for when you need it
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias diff='diff --color=auto'
alias ip='ip --color=auto'
alias find='fd'                # Modern find replacement

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

# Network & System
alias ping='ping -c 5'
alias wget='wget -c'
alias ports='netstat -tulpn'        # Show open ports
alias myip='curl -s ifconfig.me'    # Public IP address
alias localip='ip addr show | grep inet'  # Local IP addresses

# Quick shortcuts
alias c='clear'
alias h='history'
alias j='jobs -l'
alias path='echo -e ${PATH//:/\\n}'  # Display PATH on separate lines
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias week='date +%V'
alias reload='source ~/.zshrc'       # Reload shell configuration

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
    local location="${1:-}"
    if command -v curl >/dev/null 2>&1; then
        if [ -z "$location" ]; then
            curl -s "wttr.in" || echo "Failed to fetch weather. Check your internet connection."
        else
            curl -s "wttr.in/$location" || echo "Failed to fetch weather for $location"
        fi
    else
        echo "curl is required for weather function"
    fi
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

# Tmux aliases - universal UTF-8 support
alias tmux='tmux -u'  # Always use UTF-8
alias tn='tmux -u new -s'
alias ta='tmux -u attach -t'
alias tl='tmux ls'
alias tk='tmux kill-session -t'
# For iTerm2 users who want integration mode
alias tmux-cc='tmux -CC -u new -A -s main'

# Setup zoxide and starship (DarkMatter essentials)
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"

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
            "folders": "/",
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
            "format": "{login-time}{?client-ip})",
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
# GNAR Tmux Configuration - Working Base

# Universal terminal compatibility
set -g default-terminal "screen-256color"
set-option -ga terminal-overrides ",*256col*:Tc"

# Ensure prefix key works (default Ctrl-b)
set -g prefix C-b
bind C-b send-prefix

# Enable mouse support
set -g mouse on

# Vim-style pane navigation (in addition to defaults)
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Vim-style splits (in addition to defaults)
bind v split-window -h
bind S split-window -v

# Status bar
set -g status-style bg=black,fg=white
set -g status-left '#[fg=green]#S '
set -g status-right '#[fg=yellow]#H #[fg=cyan]%H:%M'

# Reload config
bind r source-file ~/.tmux.conf \; display "Config reloaded!"

# Tmux Plugin Manager (TPM) - Only if plugins directory exists
if-shell "test -d ~/.tmux/plugins/tpm" {
    # Core plugins for enhanced functionality
    set -g @plugin 'tmux-plugins/tpm'
    set -g @plugin 'tmux-plugins/tmux-sensible'       # Better tmux defaults
    set -g @plugin 'tmux-plugins/tmux-resurrect'      # Restore sessions after reboot
    set -g @plugin 'tmux-plugins/tmux-continuum'      # Auto-save sessions
    set -g @plugin 'tmux-plugins/tmux-yank'           # Copy to system clipboard
    set -g @plugin 'tmux-plugins/tmux-copycat'        # Enhanced search
    set -g @plugin 'tmux-plugins/tmux-open'           # Open files/URLs
    set -g @plugin 'tmux-plugins/tmux-sessionist'     # Session management
    set -g @plugin 'pschmitt/tmux-ssh-split'          # SSH split plugin

    # Plugin configurations
    # Resurrect - restore pane contents
    set -g @resurrect-capture-pane-contents 'on'
    set -g @resurrect-strategy-vim 'session'
    set -g @resurrect-strategy-nvim 'session'

    # Continuum - automatic restore and save
    set -g @continuum-restore 'on'
    set -g @continuum-save-interval '15'

    # SSH split keybindings
    set -g @ssh-split-h-key 'C-h'
    set -g @ssh-split-v-key 'C-v'
    set -g @ssh-split-w-key 'C-w'

    # Yank - use system clipboard
    set -g @yank_selection_mouse 'clipboard'

    # Initialize TPM (must be at bottom)
    run '~/.tmux/plugins/tpm/tpm'
}
TMUX

EOF

# Install TPM (Tmux Plugin Manager)
if [ ! -d "/home/$REAL_USER/.tmux/plugins/tpm" ]; then
    echo "Installing Tmux Plugin Manager..."
    sudo -u $REAL_USER git clone https://github.com/tmux-plugins/tpm /home/$REAL_USER/.tmux/plugins/tpm
fi

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

# Create tmux diagnostic tool
cat > /usr/local/bin/gnar-tmux-test << 'SCRIPT'
#!/bin/bash
# GNAR Tmux Diagnostic Tool

echo "=== GNAR Tmux Diagnostic ==="
echo "Terminal: $TERM"
echo "Tmux version: $(tmux -V 2>/dev/null || echo 'Not installed')"
echo "Inside tmux: ${TMUX:-No}"
echo "SSH connection: ${SSH_CONNECTION:-Local}"
echo ""

if [ -n "$TMUX" ]; then
    echo "✓ You are inside tmux"
    echo ""
    echo "Testing prefix key (Ctrl-b)..."
    echo "Try these commands:"
    echo "  Ctrl-b ?    - Show all keybindings"
    echo "  Ctrl-b d    - Detach from session"
    echo "  Ctrl-b c    - Create new window"
    echo "  Ctrl-b v    - Split vertically"
    echo ""
    echo "If Ctrl-b doesn't work:"
    echo "  1. Check if your Mac terminal is intercepting it"
    echo "  2. Try using iTerm2 instead of Terminal.app"
    echo "  3. Run: export TERM=xterm-256color"
else
    echo "✗ You are NOT in tmux"
    echo ""
    echo "Start tmux with: tmux"
    echo "Or attach to existing: tmux attach"
fi

if [ -n "$SSH_CONNECTION" ]; then
    echo ""
    echo "=== SSH Info ==="
    echo "Connected from: $(echo $SSH_CONNECTION | awk '{print $1}')"
    echo ""
    echo "For better tmux over SSH:"
    echo "  1. Use iTerm2 on your Mac"
    echo "  2. Set TERM=xterm-256color"
    echo "  3. Use 'ssh -t' for proper TTY allocation"
fi
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
echo "  Ctrl-b v        - Split vertical (vim-style)"
echo "  Ctrl-b S        - Split horizontal (vim-style)"
echo "  Ctrl-b h/j/k/l  - Navigate panes (vim-style)"
echo "  Ctrl-b x        - Close pane"
echo "  Ctrl-b d        - Detach session"
echo "  Ctrl-b I        - Install plugins (capital i)"
echo "  exit            - Exit pane/tmux"
echo
echo "File Operations:"
echo "  ls              - List with icons (eza)"
echo "  ll              - Long listing with details"
echo "  la              - Show all including hidden"
echo "  l               - One file per line"
echo "  tree            - Full directory tree"
echo "  lt              - Tree limited to 2 levels"
echo "  mkcd <dir>      - Create and enter directory"
echo "  backup <file>   - Backup file with timestamp"
echo "  extract <file>  - Extract any archive"
echo

echo "Quick Aliases:"
echo "  ff              - Fastfetch system info"
echo "  c               - Clear screen"
echo "  h               - History"
echo "  j               - Jobs list"
echo "  path            - Show PATH clearly"
echo "  now             - Current date/time"
echo "  myip            - Public IP address"
echo "  localip         - Local IP addresses"
echo "  ports           - Open ports"
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
echo "Tmux Setup:"
echo "  1. Start tmux: tmux"
echo "  2. Basic keybindings work immediately (Ctrl-b v, Ctrl-b h/j/k/l, etc.)"
echo "  3. Install plugins: Press Ctrl-b I (capital i) for enhanced features"
echo "  4. Plugin features activate after installation"
echo
echo "Reboot and enjoy your enhanced TTY!"