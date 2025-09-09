#!/bin/bash
#
# GNAR - Streamlined TTY Setup for Arch Linux
# Focused on: Spaceship + Zsh + Tmux + Caddy + Runtime Support
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 GNAR - Streamlined TTY Setup${NC}"
echo -e "${YELLOW}Setting up: Spaceship + Zsh + Tmux + Caddy + Runtimes${NC}"
echo

# Check if root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root: sudo ./setup.sh${NC}"
   exit 1
fi

# Get actual user
REAL_USER=$(logname)

echo -e "${GREEN}📦 Updating system packages...${NC}"
pacman -Syu --noconfirm

# Ensure UTF-8 locale
if ! grep -q "en_US.UTF-8 UTF-8" /etc/locale.gen 2>/dev/null; then
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
fi
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

echo -e "${GREEN}📦 Installing core packages...${NC}"
pacman -S --noconfirm \
  zsh \
  tmux \
  neovim \
  git \
  curl \
  wget \
  unzip \
  caddy \
  docker \
  docker-compose \
  nodejs \
  npm \
  python \
  python-pip \
  python-pipx \
  python-pipenv \
  python-poetry \
  ruby \
  ruby-rdoc \
  ruby-irb \
  rust \
  go \
  jdk-openjdk \
  maven \
  gradle \
  base-devel \
  man-db \
  man-pages

echo -e "${GREEN}📦 Installing development tools...${NC}"
pacman -S --noconfirm \
  eza \
  bat \
  fd \
  fzf \
  zoxide \
  ripgrep \
  jq \
  yq \
  htop \
  tree \
  bc \
  net-tools \
  openssh \
  ufw \
  fail2ban \
  nmap \
  tcpdump \
  wireshark-cli \
  rsync \
  rclone \
  p7zip \
  imagemagick \
  httpie \
  postgresql \
  valkey \
  sqlite \
  btop \
  iotop \
  nethogs \
  lsof \
  ncdu \
  smartmontools

echo -e "${GREEN}🐚 Configuring Zsh with Spaceship...${NC}"

# Backup existing configs
if [[ -f "/home/$REAL_USER/.zshrc" ]]; then
    cp "/home/$REAL_USER/.zshrc" "/home/$REAL_USER/.zshrc.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
fi

# Configure zsh for the actual user
sudo -u $REAL_USER bash << 'EOF'

# Create zsh configuration directory
mkdir -p ~/.config/zsh

# Install Oh My Zsh (for plugin management)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Install essential zsh plugins
echo "Installing zsh plugins..."
[ ! -d "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
[ ! -d "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
[ ! -d "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-completions" ] && git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-completions
[ ! -d "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search" ] && git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
[ ! -d "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-z" ] && git clone https://github.com/agkozak/zsh-z ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-z

# Install spaceship prompt
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/spaceship-prompt" ]; then
    git clone https://github.com/spaceship-prompt/spaceship-prompt.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/spaceship-prompt" --depth=1
fi
if [ ! -L "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/spaceship.zsh-theme" ]; then
    ln -sf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/spaceship-prompt/spaceship.zsh-theme" "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/spaceship.zsh-theme"
fi

# Create streamlined .zshrc
cat > ~/.zshrc << 'ZSHRC'
# GNAR - Streamlined Zsh Configuration

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="spaceship"

# Enhanced plugins
plugins=(
  git
  docker
  docker-compose
  node
  npm
  python
  pip
  ruby
  rust
  golang
  gradle
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-completions
  zsh-history-substring-search
  zsh-z
  zoxide
  fzf
  colored-man-pages
  command-not-found
  extract
  history
  sudo
  web-search
)

source $ZSH/oh-my-zsh.sh

# Spaceship prompt configuration
SPACESHIP_PROMPT_ORDER=(
  user          # Username section
  dir           # Current directory section
  host          # Hostname section
  git           # Git section (git_branch + git_status)
  node          # Node.js section
  python        # Python section
  ruby          # Ruby section
  docker        # Docker section
  exec_time     # Execution time
  line_sep      # Line break
  battery       # Battery level and status
  jobs          # Background jobs indicator
  exit_code     # Exit code section
  char          # Prompt character
)

# Spaceship settings
SPACESHIP_CHAR_SYMBOL="❯ "
SPACESHIP_CHAR_SUFFIX=" "
SPACESHIP_USER_SHOW="always"
SPACESHIP_USER_PREFIX=""
SPACESHIP_USER_SUFFIX=""
SPACESHIP_HOST_SHOW="always"
SPACESHIP_HOST_PREFIX="@"
SPACESHIP_DIR_PREFIX=""
SPACESHIP_DIR_TRUNC=3
SPACESHIP_GIT_PREFIX=""
SPACESHIP_GIT_SUFFIX=""
SPACESHIP_GIT_BRANCH_PREFIX=""
SPACESHIP_GIT_STATUS_PREFIX=" ["
SPACESHIP_GIT_STATUS_SUFFIX="]"

# Enhanced History configuration
HISTFILE=$HOME/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt share_history
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_verify
setopt hist_reduce_blanks
setopt hist_save_no_dups
setopt hist_find_no_dups
setopt append_history
setopt inc_append_history

# Enhanced Key bindings
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
bindkey '^R' history-incremental-search-backward
bindkey '^S' history-incremental-search-forward
bindkey '^[[Z' reverse-menu-complete
bindkey '^[[3~' delete-char
bindkey '^H' backward-delete-char
bindkey '^W' backward-kill-word
bindkey '^U' backward-kill-line
bindkey '^K' kill-line

# History substring search bindings
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

# Vi mode key bindings
bindkey -v
bindkey '^?' backward-delete-char
bindkey '^h' backward-delete-char
bindkey '^w' backward-kill-word
bindkey '^u' backward-kill-line
bindkey '^k' kill-line
bindkey '^r' history-incremental-search-backward
bindkey '^s' history-incremental-search-forward
bindkey '^[[Z' reverse-menu-complete

# Enhanced aliases with better defaults
alias ls="eza --icons --group-directories-first --color=auto"
alias ll="eza --icons --long --group-directories-first --color=auto"
alias la="eza --icons --all --group-directories-first --color=auto"
alias lt="eza --icons --tree --level=3 --group-directories-first"
alias lf="eza --icons --long --group-directories-first --color=auto --git"
alias tree="eza --icons --tree"
alias cat="bat --style=plain --paging=never"
alias less="bat --paging=always"
alias more="bat --paging=always"
alias grep="grep --color=auto --exclude-dir=.git"
alias rg="ripgrep --color=auto"
alias find="fd --hidden --exclude=.git"
alias ps="ps aux"
alias top="btop"
alias htop="btop"
alias df="df -h"
alias du="du -h"
alias free="free -h"
alias which="type -a"
alias where="type -a"

# Enhanced Navigation with Quick .. Shortcuts
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ......="cd ../../../../.."
alias .......="cd ../../../../../.."
alias ........="cd ../../../../../../.."
alias ~="cd ~"
alias -- -="cd -"
alias cd..="cd .."
alias cd...="cd ../.."
alias cd....="cd ../../.."
alias cd.....="cd ../../../.."
alias cd......="cd ../../../../.."
alias cdp="cd ~/projects"
alias cdd="cd ~/Downloads"
alias cdt="cd /tmp"
alias cdl="cd /var/log"
alias cde="cd /etc"
alias cdr="cd /"
alias cdu="cd /usr"
alias cdv="cd /var"

# Git shortcuts
alias g="git"
alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gp="git push"
alias gl="git pull"
alias gd="git diff"
alias gb="git branch"
alias gco="git checkout"
alias glog="git log --oneline --graph --decorate"

# Tmux shortcuts
alias t="tmux"
alias tn="tmux new -s"
alias ta="tmux attach -t"
alias tl="tmux list-sessions"
alias tk="tmux kill-session -t"

# Docker shortcuts - using unique names to avoid conflicts
alias dkr="docker"
alias dkc="docker-compose"
alias dkps="docker ps"
alias dkpa="docker ps -a"
alias dki="docker images"
alias dkex="docker exec -it"

# Enhanced system shortcuts
alias c="clear"
alias reload="source ~/.zshrc"
alias r="source ~/.zshrc"
alias myip="curl -s ifconfig.me"
alias localip="ip addr show | grep inet"
alias ff="fastfetch"
alias nf="fastfetch"
alias ports="netstat -tulpn"
alias now="date +\"%Y-%m-%d %H:%M:%S\""
alias week="date +%V"
alias today="date +%Y-%m-%d"
alias time="date +%H:%M:%S"
alias date="date +%Y-%m-%d"
alias timestamp="date +%s"
alias epoch="date +%s"
alias unix="date +%s"

# Enhanced system monitoring
alias top="btop"
alias htop="btop"
alias iotop="sudo iotop"
alias nethogs="sudo nethogs"
alias disk="ncdu"
alias smart="sudo smartctl -a"

# Network tools
alias nmap-local="nmap -sn 192.168.1.0/24"
alias nmap-scan="nmap -sS -O -F"
alias tcpdump="sudo tcpdump"
alias lsof-port="lsof -i"

# Database shortcuts
alias psql="psql -U $USER"
alias redis-cli="redis-cli"
alias sqlite="sqlite3"

# Security tools
alias ufw-status="sudo ufw status verbose"
alias fail2ban-status="sudo fail2ban-client status"
alias ssh-keys="ssh-keygen -l -f"

# File operations
alias rsync="rsync -avz --progress"
alias 7z="7z"
alias convert="convert"

# Caddy shortcuts
alias caddy-edit="sudo $EDITOR /etc/caddy/Caddyfile"
alias caddy-reload="sudo systemctl reload caddy"
alias caddy-logs="sudo journalctl -u caddy -f"
alias caddy-test="test-caddy"
alias caddy-restart="sudo systemctl restart caddy"

# VS Code Server shortcuts
alias vscode="vscode-status"
alias vscode-restart="vscode-restart"
alias vscode-logs="vscode-logs"

# AUR shortcuts
alias yay-update="yay -Syu"
alias yay-install="yay -S"
alias yay-remove="yay -R"
alias yay-search="yay -Ss"
alias yay-info="yay -Si"

# Environment variables
export EDITOR="nvim"
export PAGER="bat"
export BAT_THEME="ansi"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude ".git"'

# Add npm global packages to PATH
export PATH="$HOME/.npm-global/bin:$PATH"

# Add bun to PATH
export PATH="$HOME/.bun/bin:$PATH"

# Add Ruby gems to PATH
export PATH="$HOME/.local/share/gem/ruby/3.4.0/bin:$PATH"

# Add Rust cargo to PATH
export PATH="$HOME/.cargo/bin:$PATH"

# Add pipx packages to PATH
export PATH="$HOME/.local/bin:$PATH"

# Add Go tools to PATH
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"
export FZF_DEFAULT_OPTS='
  --color=fg:#c1c1c1,fg+:#ffffff,bg:#121113,bg+:#222222
  --color=hl:#5f8787,hl+:#fbcb97,info:#e78a53,marker:#fbcb97
  --color=prompt:#e78a53,spinner:#5f8787,pointer:#fbcb97,header:#aaaaaa
  --color=border:#333333,label:#888888,query:#ffffff
  --border="rounded" --border-label="" --preview-window="border-rounded" --prompt="> "
  --marker=">" --pointer="◆" --separator="─" --scrollbar="│"'

# Initialize tools
eval "$(zoxide init zsh)"

# Enhanced completion system
autoload -U compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu select
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache

# Case insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# History completion
zstyle ':completion:*:history-words' stop yes
zstyle ':completion:*:history-words' remove-all-dups yes
zstyle ':completion:*:history-words' list false
zstyle ':completion:*:history-words' menu yes

# Enhanced directory navigation
setopt auto_cd
setopt auto_pushd
setopt pushd_ignore_dups
setopt pushd_silent
setopt pushd_to_home
setopt cdable_vars

# Enhanced globbing
setopt extended_glob
setopt glob_dots
setopt numeric_glob_sort
setopt mark_dirs

# Enhanced job control
setopt auto_resume
setopt long_list_jobs
setopt notify

# Essential utility functions (using unique names to avoid conflicts)
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Quick directory up function
up() {
    local levels=${1:-1}
    local path=""
    for ((i=1; i<=levels; i++)); do
        path="../$path"
    done
    cd "$path"
}

# Simple utility aliases (avoiding function conflicts)
alias e="nvim"

# Additional utility aliases
alias edit="nvim"

# Keep only essential utility functions that don't conflict
# The extract functionality is available via the 'extract' plugin in Oh-My-Zsh

# Add site to Caddy
add-site() {
    if [ -z "$1" ]; then
        echo "Usage: add-site <name> [port|directory]"
        echo "Examples:"
        echo "  add-site myapp 3000          # Reverse proxy to localhost:3000"
        echo "  add-site static /var/www/site # Serve static files from directory"
        echo "  add-site api 8080            # Reverse proxy to localhost:8080"
        return 1
    fi
    
    local name=$1
    local target=$2
    
    # If no target provided, default to port 3000
    if [ -z "$target" ]; then
        target="3000"
    fi
    
    # Backup before modifying
    sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S)
    
    # Check if target is a directory or port
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        # It's a port number
        echo -e "\n# $name service (reverse proxy)\n$name.local:80 {\n    reverse_proxy localhost:$target\n}" | sudo tee -a /etc/caddy/Caddyfile > /dev/null
        echo "✅ Added $name.local:80 -> localhost:$target (reverse proxy)"
    else
        # It's a directory path
        if [ ! -d "$target" ]; then
            echo "❌ Directory $target does not exist"
            return 1
        fi
        echo -e "\n# $name service (static files)\n$name.local:80 {\n    root * $target\n    file_server\n}" | sudo tee -a /etc/caddy/Caddyfile > /dev/null
        echo "✅ Added $name.local:80 -> $target (static files)"
    fi
    
    # Test and reload
    if caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
        sudo systemctl reload caddy
        echo "🌐 Site available at: http://$name.local"
    else
        echo "❌ Configuration error! Rolling back..."
        sudo mv /etc/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S) /etc/caddy/Caddyfile
        return 1
    fi
}

# List configured sites
list-sites() {
    echo "=== Caddy Sites ==="
    if [ -f "/etc/caddy/Caddyfile" ]; then
    sudo grep -E "^[a-zA-Z0-9.-]+(.local)?(:[0-9]+)? {" /etc/caddy/Caddyfile 2>/dev/null | sed 's/ {//' || echo "No sites configured"
    else
        echo "No Caddyfile found"
    fi
}

# Remove site from Caddy
remove-site() {
    if [ -z "$1" ]; then
        echo "Usage: remove-site <name>"
        echo "Example: remove-site myapp"
        return 1
    fi
    
    local name=$1
    
    # Backup before modifying
    sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S)
    
    # Remove site block (from site name to closing brace)
    sudo sed -i "/^$name\.local:80 {/,/^}/d" /etc/caddy/Caddyfile
    
    # Test and reload
    if caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
        sudo systemctl reload caddy
        echo "✅ Removed $name.local from Caddy"
    else
        echo "❌ Configuration error! Rolling back..."
        sudo mv /etc/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S) /etc/caddy/Caddyfile
        return 1
    fi
}

# Test Caddy configuration
test-caddy() {
    echo "Testing Caddy configuration..."
    if caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
        echo "✅ Caddy configuration is valid"
    else
        echo "❌ Caddy configuration has errors:"
        caddy validate --config /etc/caddy/Caddyfile
    fi
}

# Show Caddy status and logs
caddy-status() {
    echo "=== Caddy Service Status ==="
    sudo systemctl status caddy --no-pager
    echo
    echo "=== Recent Caddy Logs ==="
    sudo journalctl -u caddy --no-pager -n 10
}

# PM2 management functions
pm2-start() {
    if [ -z "$1" ]; then
        echo "Usage: pm2-start <ecosystem-file>"
        echo "Example: pm2-start ecosystem.config.js"
        return 1
    fi
    
    local ecosystem_file=$1
    
    if [ ! -f "$ecosystem_file" ]; then
        echo "❌ Ecosystem file $ecosystem_file not found"
        return 1
    fi
    
    echo "🚀 Starting PM2 app with $ecosystem_file"
    pm2 start "$ecosystem_file"
    
    echo "📊 PM2 Status:"
    pm2 list
}

pm2-add-site() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        echo "Usage: pm2-add-site <name> <port> <ecosystem-file>"
        echo "Example: pm2-add-site myapp 3000 ecosystem.config.js"
        return 1
    fi
    
    local name=$1
    local port=$2
    local ecosystem_file=$3
    
    # Start PM2 app
    pm2-start "$ecosystem_file"
    
    # Add to Caddy
    add-site "$name" "$port"
    
    echo "✅ PM2 app started and added to Caddy: $name.local"
}

pm2-remove() {
    if [ -z "$1" ]; then
        echo "Usage: pm2-remove <name>"
        echo "Example: pm2-remove myapp"
        return 1
    fi
    
    local name=$1
    
    echo "🛑 Stopping PM2 app: $name"
    pm2 stop "$name" 2>/dev/null || true
    pm2 delete "$name" 2>/dev/null || true
    
    echo "✅ PM2 app removed: $name"
}

pm2-restart() {
    if [ -z "$1" ]; then
        echo "Usage: pm2-restart <name>"
        echo "Example: pm2-restart myapp"
        return 1
    fi
    
    local name=$1
    
    echo "🔄 Restarting PM2 app: $name"
    pm2 restart "$name"
    
    echo "📊 PM2 Status:"
    pm2 list
}

pm2-logs() {
    if [ -z "$1" ]; then
        echo "Usage: pm2-logs <name>"
        echo "Example: pm2-logs myapp"
        echo "Or: pm2-logs all (for all apps)"
        return 1
    fi
    
    local name=$1
    
    pm2 logs "$name"
}

pm2-status() {
    echo "=== PM2 Apps ==="
    pm2 list
    echo
    echo "=== Caddy Sites ==="
    list-sites
}

# System monitoring functions
system-status() {
    echo "=== System Status ==="
    echo "Uptime: $(uptime -p)"
    echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
    echo "Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
    echo "Disk: $(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 " used)"}')"
    echo
    echo "=== Top Processes ==="
    ps aux --sort=-%cpu | head -10
    echo
    echo "=== Network Connections ==="
    netstat -tulpn | grep LISTEN | head -10
}

# Database management
db-status() {
    echo "=== PostgreSQL Status ==="
    sudo systemctl status postgresql --no-pager
    echo
    echo "=== Valkey/Redis Status ==="
    sudo systemctl status valkey --no-pager
    echo
    echo "=== Database Connections ==="
    psql -c "SELECT count(*) as connections FROM pg_stat_activity;" 2>/dev/null || echo "PostgreSQL not accessible"
    redis-cli info clients 2>/dev/null | grep connected_clients || valkey-cli info clients 2>/dev/null | grep connected_clients || echo "Valkey/Redis not accessible"
}

# Security status
security-status() {
    echo "=== Firewall Status ==="
    ufw-status
    echo
    echo "=== Fail2ban Status ==="
    fail2ban-status
    echo
    echo "=== SSH Status ==="
    sudo systemctl status sshd --no-pager
    echo
    echo "=== Recent SSH Logins ==="
    sudo journalctl -u sshd --no-pager -n 10
}

# Port management
port-check() {
    if [ -z "$1" ]; then
        echo "Usage: port-check <port>"
        echo "Example: port-check 3000"
        return 1
    fi
    
    local port=$1
    echo "Checking port $port..."
    
    if lsof -i :$port >/dev/null 2>&1; then
        echo "❌ Port $port is in use:"
        lsof -i :$port
    else
        echo "✅ Port $port is available"
    fi
}

# Project scaffolding
create-react-hono() {
    if [ -z "$1" ]; then
        echo "Usage: create-react-hono <project-name>"
        echo "Example: create-react-hono myapp"
        return 1
    fi
    
    local name=$1
    local dir="$HOME/projects/$name"
    
    echo "🚀 Creating React + Hono project: $name"
    
    # Create project directory
    mkdir -p "$dir"
    cd "$dir"
    
    # Initialize package.json
    npm init -y
    
    # Install dependencies
    npm install hono @hono/node-server
    npm install -D @types/node typescript tsx
    npm install -D vite @vitejs/plugin-react
    npm install react react-dom
    npm install -D @types/react @types/react-dom
    
    # Create basic structure
    mkdir -p src/{client,server}
    
    # Create Hono server
    cat > src/server/index.ts << 'HONO'
import { Hono } from 'hono'
import { serve } from '@hono/node-server'

const app = new Hono()

app.get('/', (c) => {
  return c.json({ message: 'Hello Hono!' })
})

app.get('/api/health', (c) => {
  return c.json({ status: 'ok', timestamp: new Date().toISOString() })
})

const port = 3000
console.log(`Server is running on port ${port}`)

serve({
  fetch: app.fetch,
  port
})
HONO

    # Create React app
    cat > src/client/App.tsx << 'REACT'
import React from 'react'

function App() {
  return (
    <div className="App">
      <h1>React + Hono App</h1>
      <p>Hello from React!</p>
    </div>
  )
}

export default App
REACT

    # Create Vite config
    cat > vite.config.ts << 'VITE'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': 'http://localhost:3000'
    }
  }
})
VITE

    # Create TypeScript config
    cat > tsconfig.json << 'TSCONFIG'
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
TSCONFIG

    # Create tsconfig.node.json
    cat > tsconfig.node.json << 'TSCONFIGNODE'
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts"]
}
TSCONFIGNODE

    # Create package.json scripts
    cat > package.json << 'PACKAGE'
{
  "name": "$name",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "concurrently \"npm run dev:server\" \"npm run dev:client\"",
    "dev:server": "tsx watch src/server/index.ts",
    "dev:client": "vite",
    "build": "npm run build:client && npm run build:server",
    "build:client": "vite build",
    "build:server": "tsc --project tsconfig.server.json",
    "start": "node dist/server/index.js"
  },
  "dependencies": {
    "hono": "^3.0.0",
    "@hono/node-server": "^1.0.0",
    "react": "^18.0.0",
    "react-dom": "^18.0.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "@types/react": "^18.0.0",
    "@types/react-dom": "^18.0.0",
    "@vitejs/plugin-react": "^4.0.0",
    "concurrently": "^8.0.0",
    "tsx": "^4.0.0",
    "typescript": "^5.0.0",
    "vite": "^5.0.0"
  }
}
PACKAGE

    # Install concurrently
    npm install -D concurrently
    
    echo "✅ React + Hono project created: $dir"
    echo "📁 Project structure:"
    tree -I node_modules
    echo
    echo "🚀 To start development:"
    echo "  cd $dir"
    echo "  npm run dev"
    echo
    echo "🌐 To add to Caddy:"
    echo "  add-site $name 3000"
}

# VS Code Server management
vscode-status() {
    echo "=== VS Code Server Status ==="
    sudo systemctl status code-server@$USER --no-pager
    echo
    echo "=== VS Code Server Logs ==="
    sudo journalctl -u code-server@$USER --no-pager -n 10
    echo
    echo "🌐 Access VS Code at: http://vscode.local"
    echo "🔑 Password: $(grep 'password:' /home/$USER/.config/code-server/config.yaml | cut -d' ' -f2)"
}

vscode-restart() {
    echo "🔄 Restarting VS Code Server..."
    sudo systemctl restart code-server@$USER
    echo "✅ VS Code Server restarted"
    vscode-status
}

vscode-logs() {
    echo "📋 VS Code Server Logs:"
    sudo journalctl -u code-server@$USER -f
}

vscode-change-password() {
    if [ -z "$1" ]; then
        echo "Usage: vscode-change-password <new-password>"
        echo "Example: vscode-change-password mynewpassword"
        return 1
    fi
    
    local new_password=$1
    
    # Update config file
    sudo -u $REAL_USER sed -i "s/password: .*/password: $new_password/" /home/$REAL_USER/.config/code-server/config.yaml
    
    # Restart service
    sudo systemctl restart code-server@$REAL_USER
    
    echo "✅ VS Code Server password updated"
    echo "🌐 Access VS Code at: http://vscode.local"
    echo "🔑 New password: $new_password"
}

vscode-password() {
    echo "🔑 VS Code Server Password:"
    echo "$(grep 'password:' /home/$USER/.config/code-server/config.yaml | cut -d' ' -f2)"
    echo
    echo "🌐 Access at: http://vscode.local"
}

# Backup functions
backup-system() {
    local backup_dir="/home/$REAL_USER/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    echo "🔄 Creating system backup to $backup_dir"
    
    # Backup important configs
    sudo cp -r /etc/caddy "$backup_dir/"
    sudo cp -r /etc/ssh "$backup_dir/"
    sudo cp -r /etc/ufw "$backup_dir/"
    sudo cp -r /etc/fail2ban "$backup_dir/"
    
    # Backup user configs
    cp -r ~/.zshrc "$backup_dir/"
    cp -r ~/.tmux.conf "$backup_dir/"
    cp -r ~/.config "$backup_dir/"
    
    # Fix permissions
    sudo chown -R $REAL_USER:$REAL_USER "$backup_dir"
    
    echo "✅ Backup created: $backup_dir"
    echo "📁 Backup contents:"
    ls -la "$backup_dir"
}

# Enhanced help commands using fzf
alias ?='alias | fzf --height=80% --prompt="Search aliases: "'
alias ??='print -l ${(ok)functions} | grep -v "^_" | fzf --preview "which {}" --height=80% --prompt="Search functions: "'
alias ???='alias | bat --style=plain --language=bash'
alias ????='print -l ${(ok)functions} | grep -v "^_" | bat --style=plain --language=bash'

# Quick access to common directories
alias projects="cd ~/projects"
alias downloads="cd ~/Downloads"
alias tmp="cd /tmp"
alias logs="cd /var/log"
alias etc="cd /etc"
alias home="cd ~"
alias root="cd /"
alias usr="cd /usr"
alias var="cd /var"
alias opt="cd /opt"
alias srv="cd /srv"
alias mnt="cd /mnt"
alias media="cd /media"
alias dev="cd /dev"
alias proc="cd /proc"
alias sys="cd /sys"

# System monitoring shortcuts (using unique names)
alias mem="free -h"
alias disk="df -h"
alias cpu="lscpu"

# Development tool shortcuts (using unique names)
alias nodeversion="node --version"
alias npmversion="npm --version"
alias python="python3"
alias pip="pip3"
alias rubyversion="ruby --version"
alias rustversion="rustc --version"
alias goversion="go version"
alias javaversion="java -version"

ZSHRC

# Create tmux configuration
cat > ~/.tmux.conf << 'TMUX'
# GNAR - Streamlined Tmux Configuration

# Basic settings
set -g default-terminal "screen-256color"
set-option -ga terminal-overrides ",*256col*:Tc"
set -g mouse on
set -g history-limit 10000

# Key bindings
set -g prefix C-a
bind C-a send-prefix

# Vim-style navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Vim-style splits
bind v split-window -h
bind s split-window -v

# Status bar
set -g status-style bg=black,fg=white
set -g status-left '#[fg=green]#S '
set -g status-right '#[fg=yellow]#H #[fg=cyan]%H:%M'

# Reload config
bind r source-file ~/.tmux.conf \; display "Config reloaded!"

# Start windows and panes at 1
set -g base-index 1
setw -g pane-base-index 1

# Renumber windows when a window is closed
set -g renumber-windows on

# Increase scrollback buffer size
set -g history-limit 10000

# Enable focus events
set -g focus-events on

# Set default shell
set -g default-command /bin/zsh
TMUX

EOF

echo -e "${GREEN}🔧 Configuring Caddy...${NC}"

# Configure Caddy with VS Code Server pre-configured
cat > /etc/caddy/Caddyfile << 'CADDYFILE'
# GNAR - Caddy Configuration

# Default site
:80 {
    respond "GNAR Server - Add sites with: add-site <name> <port>"
}

# VS Code Server (pre-configured)
vscode.local:80 {
    reverse_proxy localhost:8080
}
CADDYFILE

# Test Caddy configuration
if caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
    echo "✅ Caddy configuration is valid"
    # Enable and start Caddy
    systemctl enable caddy
    if systemctl start caddy; then
        echo "✅ Caddy service started successfully"
    else
        echo "⚠️  Caddy failed to start, checking logs..."
        journalctl -xeu caddy.service --no-pager -n 10
    fi
else
    echo "❌ Caddy configuration has errors:"
    caddy validate --config /etc/caddy/Caddyfile
    echo "⚠️  Caddy service not started due to configuration errors"
fi

echo -e "${GREEN}🐳 Configuring Docker...${NC}"

# Enable Docker
systemctl enable docker
systemctl start docker

# Add user to docker group
usermod -aG docker "$REAL_USER"

echo -e "${GREEN}🔒 Configuring security...${NC}"

# Configure UFW firewall
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3000:8000/tcp  # Development ports
ufw allow 5432/tcp       # PostgreSQL
ufw allow 6379/tcp       # Redis

# Ensure UFW service is enabled and started
systemctl enable ufw
if systemctl start ufw; then
    echo "✅ UFW service started successfully"
else
    echo "⚠️  UFW service failed to start"
fi

# Configure Fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Create fail2ban jail for SSH
cat > /etc/fail2ban/jail.local << 'FAIL2BAN'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
FAIL2BAN

# Configure SSH hardening
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

echo -e "${GREEN}🗄️ Configuring databases...${NC}"

# Configure PostgreSQL
echo "Setting up PostgreSQL database..."
if [ ! -d "/var/lib/postgres/data" ] || [ -z "$(ls -A /var/lib/postgres/data 2>/dev/null)" ]; then
    echo "Initializing PostgreSQL database cluster..."
    sudo -u postgres initdb -D /var/lib/postgres/data --locale=en_US.UTF-8 --encoding=UTF8
fi

# Enable and start PostgreSQL
systemctl enable postgresql
if systemctl start postgresql; then
    echo "✅ PostgreSQL started successfully"
else
    echo "⚠️  PostgreSQL failed to start. Checking logs..."
    journalctl -xeu postgresql.service --no-pager -n 10
    echo "❌ PostgreSQL startup failed - will continue with other services"
fi

# Create database user (only if PostgreSQL is running and user doesn't exist)
if systemctl is-active --quiet postgresql; then
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$REAL_USER'" | grep -q 1 2>/dev/null; then
        sudo -u postgres createuser -s "$REAL_USER" 2>/dev/null || echo "⚠️  Could not create PostgreSQL user"
        sudo -u postgres createdb "$REAL_USER" 2>/dev/null || echo "⚠️  Could not create PostgreSQL database"
        echo "✅ PostgreSQL user and database created for $REAL_USER"
    else
        echo "✅ PostgreSQL user $REAL_USER already exists"
    fi
else
    echo "⚠️  PostgreSQL not running, skipping user creation"
fi

# Configure Valkey (Redis replacement)
systemctl enable valkey
systemctl start valkey

# Create redis-cli alias for compatibility
if ! command -v redis-cli &> /dev/null; then
    ln -sf /usr/bin/valkey-cli /usr/local/bin/redis-cli 2>/dev/null || true
fi

# Configure logrotate
cat > /etc/logrotate.d/gnar << 'LOGROTATE'
/var/log/gnar/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
}

# Code-server logs
/var/log/code-server/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
}
LOGROTATE

echo -e "${GREEN}💻 Configuring VS Code Server...${NC}"

# Create code-server config directory
sudo -u $REAL_USER mkdir -p /home/$REAL_USER/.config/code-server

# Configure code-server with better security
cat > /home/$REAL_USER/.config/code-server/config.yaml << 'CODESERVER'
bind-addr: 0.0.0.0:8080
auth: password
password: $(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
cert: false
disable-telemetry: true
disable-update-check: true
disable-workspace-trust: true
CODESERVER

# Generate secure password  
VSCODE_PASSWORD="gnar-vscode-2024"
sed -i "s/password: .*/password: $VSCODE_PASSWORD/" /home/$REAL_USER/.config/code-server/config.yaml

# Configure VS Code settings for proper terminal shell
sudo -u $REAL_USER mkdir -p /home/$REAL_USER/.local/share/code-server/User
cat > /home/$REAL_USER/.local/share/code-server/User/settings.json << 'VSCODESETTINGS'
{
    "terminal.integrated.shell.linux": "/usr/bin/zsh",
    "terminal.integrated.defaultProfile.linux": "zsh"
}
VSCODESETTINGS

# Create systemd service for code-server
cat > /etc/systemd/system/code-server@$REAL_USER.service << 'CODESERVICESERVICE'
[Unit]
Description=code-server
After=network.target

[Service]
Type=simple
User=%i
WorkingDirectory=/home/%i
Environment=PATH=/usr/bin:/usr/local/bin
ExecStart=/usr/bin/code-server
Restart=always

[Install]
WantedBy=multi-user.target
CODESERVICESERVICE

# Enable and start code-server
systemctl daemon-reload
systemctl enable code-server@$REAL_USER
if systemctl start code-server@$REAL_USER; then
    echo "✅ Code-server started successfully"
else
    echo "⚠️  Code-server failed to start, checking logs..."
    journalctl -xeu code-server@$REAL_USER --no-pager -n 5
fi

# VS Code Server is already configured in Caddyfile above
echo "✅ VS Code Server pre-configured in Caddy: http://vscode.local"

echo -e "${GREEN}🔧 Setting up runtime environments...${NC}"

# Configure Node.js global packages with proper permissions
echo "Setting up Node.js global packages..."

# Create a temporary script to avoid variable expansion issues
cat > /tmp/setup_npm.sh << EOF
#!/bin/bash
export HOME=/home/$REAL_USER
mkdir -p "\$HOME/.npm-global"
npm config set prefix "\$HOME/.npm-global"
export PATH="\$HOME/.npm-global/bin:\$PATH"
npm install -g yarn pnpm pm2 eslint prettier jest
EOF

chmod +x /tmp/setup_npm.sh
sudo -u "$REAL_USER" /tmp/setup_npm.sh || echo "⚠️  Some npm packages failed to install"
rm -f /tmp/setup_npm.sh

# Add to PATH in .bashrc and .zshrc
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "/home/$REAL_USER/.bashrc" 2>/dev/null || true

# Install yay (AUR helper) if not present
if ! command -v yay &> /dev/null; then
    echo -e "${GREEN}📦 Installing yay (AUR helper)...${NC}"
    
    # Create script for yay installation
    cat > /tmp/install_yay.sh << EOF
#!/bin/bash
export HOME=/home/$REAL_USER
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
EOF
    
    chmod +x /tmp/install_yay.sh
    sudo -u "$REAL_USER" /tmp/install_yay.sh || echo "⚠️  Yay installation failed"
    rm -f /tmp/install_yay.sh
    rm -rf /tmp/yay
fi

# Install bun separately (has its own installer)
echo "Installing Bun..."
cat > /tmp/install_bun.sh << EOF
#!/bin/bash
export HOME=/home/$REAL_USER
curl -fsSL https://bun.sh/install | bash
EOF

chmod +x /tmp/install_bun.sh
sudo -u "$REAL_USER" /tmp/install_bun.sh || echo "⚠️  Bun installation failed"
rm -f /tmp/install_bun.sh

# Install code-server using proper method for Arch Linux
echo -e "${GREEN}💻 Installing VS Code Server...${NC}"
if command -v yay &> /dev/null; then
    echo "Installing code-server via yay (AUR)..."
    cat > /tmp/install_codeserver.sh << EOF
#!/bin/bash
export HOME=/home/$REAL_USER
yay -S --noconfirm code-server
EOF
    chmod +x /tmp/install_codeserver.sh
    sudo -u "$REAL_USER" /tmp/install_codeserver.sh || echo "⚠️  Code-server AUR installation failed"
    rm -f /tmp/install_codeserver.sh
else
    echo "Installing code-server via official installer..."
    cat > /tmp/install_codeserver_official.sh << EOF
#!/bin/bash
export HOME=/home/$REAL_USER
curl -fsSL https://code-server.dev/install.sh | sh
EOF
    chmod +x /tmp/install_codeserver_official.sh
    sudo -u "$REAL_USER" /tmp/install_codeserver_official.sh || echo "⚠️  Code-server installation failed"
    rm -f /tmp/install_codeserver_official.sh
fi

# Configure Python
echo "Setting up Python packages..."
cat > /tmp/setup_python.sh << EOF
#!/bin/bash
export HOME=/home/$REAL_USER
# Use pipx for Python applications (avoids externally-managed-environment error)
pipx install black
pipx install pytest
pipx ensurepath
# pipenv and poetry are installed via pacman above
# Add pipx bin to PATH
echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> \$HOME/.bashrc
echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> \$HOME/.zshrc
echo "✅ Python packages configured (pipenv, poetry, black, pytest)"
EOF
chmod +x /tmp/setup_python.sh
sudo -u "$REAL_USER" /tmp/setup_python.sh || echo "⚠️  Some Python packages failed to install"
rm -f /tmp/setup_python.sh

# Configure Ruby
echo "Setting up Ruby gems..."
cat > /tmp/setup_ruby.sh << EOF
#!/bin/bash
export HOME=/home/$REAL_USER
gem install bundler
# Add Ruby gem bin directory to PATH
echo 'export PATH="\$HOME/.local/share/gem/ruby/3.4.0/bin:\$PATH"' >> \$HOME/.bashrc
echo 'export PATH="\$HOME/.local/share/gem/ruby/3.4.0/bin:\$PATH"' >> \$HOME/.zshrc
echo "✅ Ruby bundler installed and PATH configured"
EOF
chmod +x /tmp/setup_ruby.sh
sudo -u "$REAL_USER" /tmp/setup_ruby.sh || echo "⚠️  Ruby bundler installation failed"
rm -f /tmp/setup_ruby.sh

# Configure Rust (check for system rust conflict first)
echo "Setting up Rust toolchain..."
if pacman -Q rust &>/dev/null; then
    echo "⚠️  System Rust detected. Removing to install rustup properly..."
    pacman -R --noconfirm rust
fi

cat > /tmp/setup_rust.sh << EOF
#!/bin/bash
export HOME=/home/$REAL_USER
# Install rustup (the proper way)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source \$HOME/.cargo/env
rustup default stable
# Add cargo bin to PATH
echo 'export PATH="\$HOME/.cargo/bin:\$PATH"' >> \$HOME/.bashrc
echo 'export PATH="\$HOME/.cargo/bin:\$PATH"' >> \$HOME/.zshrc
echo "✅ Rust toolchain configured with rustup"
EOF
chmod +x /tmp/setup_rust.sh
sudo -u "$REAL_USER" /tmp/setup_rust.sh || echo "⚠️  Rust setup failed"
rm -f /tmp/setup_rust.sh

# Configure Go
echo "Installing Go tools..."
cat > /tmp/setup_go.sh << EOF
#!/bin/bash
export HOME=/home/$REAL_USER
export PATH="/usr/bin:\$PATH"
export GOPATH="\$HOME/go"
export GOBIN="\$GOPATH/bin"
mkdir -p "\$GOPATH/bin"
echo "Installing Go Delve debugger..."
go install github.com/go-delve/delve/cmd/dlv@latest
# Add Go bin to PATH
echo 'export GOPATH="\$HOME/go"' >> \$HOME/.bashrc
echo 'export PATH="\$GOPATH/bin:\$PATH"' >> \$HOME/.bashrc
echo 'export GOPATH="\$HOME/go"' >> \$HOME/.zshrc
echo 'export PATH="\$GOPATH/bin:\$PATH"' >> \$HOME/.zshrc
echo "✅ Go tools installed (dlv debugger)"
EOF
chmod +x /tmp/setup_go.sh
sudo -u "$REAL_USER" /tmp/setup_go.sh || echo "⚠️  Go tools installation failed"
rm -f /tmp/setup_go.sh

echo -e "${GREEN}🛠️ Creating helper scripts...${NC}"

# Create fastfetch configuration directory and config
sudo -u $REAL_USER mkdir -p /home/$REAL_USER/.config/fastfetch
cat > /home/$REAL_USER/.config/fastfetch/config.jsonc << 'FASTFETCH'
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

# Create gnar-info script that uses fastfetch
cat > /usr/local/bin/gnar-info << 'SCRIPT'
#!/bin/bash
# GNAR TTY system information using fastfetch

# Use fastfetch with our custom config
fastfetch
SCRIPT

# Create gnar-update script
cat > /usr/local/bin/gnar-update << 'SCRIPT'
#!/bin/bash
echo "🔄 Updating GNAR system..."
sudo pacman -Syu
echo "🧹 Cleaning package cache..."
sudo pacman -Sc --noconfirm
echo "✅ Update complete!"
SCRIPT

# Create gnar-help script
cat > /usr/local/bin/gnar-help << 'SCRIPT'
#!/bin/bash
echo "=== GNAR Help ==="
echo
echo "Core Commands:"
echo "  gnar-info     - System information (fastfetch)"
echo "  gnar-update   - Update system"
echo "  gnar-help     - This help"
echo
echo "System Info:"
echo "  ff            - fastfetch system info"
echo "  nf            - fastfetch (alternative)"
echo "  info          - System information (or info cpu/mem/disk/net/proc)"
echo "  myip          - Public IP address"
echo "  localip       - Local IP addresses"
echo "  ports         - Show open ports"
echo "  now           - Current date/time"
echo "  today         - Current date"
echo "  time          - Current time"
echo "  timestamp     - Unix timestamp"
echo "  week          - Current week number"
echo "  p             - Process list (or p <pattern>)"
echo "  process       - Enhanced process management"
echo
echo "Tmux:"
echo "  t             - Start tmux"
echo "  tn <name>     - New named session"
echo "  ta <name>     - Attach to session"
echo "  tl            - List sessions"
echo "  tk <name>     - Kill session"
echo "  Ctrl-a v      - Split vertical"
echo "  Ctrl-a s      - Split horizontal"
echo "  Ctrl-a h/j/k/l - Navigate panes"
echo
echo "Docker:"
echo "  d             - docker"
echo "  dc            - docker-compose"
echo "  dps           - docker ps"
echo "  dpa           - docker ps -a"
echo "  di            - docker images"
echo "  dex <container> - docker exec -it"
echo
echo "Caddy:"
echo "  add-site <name> [port|dir] - Add site (port=reverse proxy, dir=static files)"
echo "  remove-site <name> - Remove site from Caddy"
echo "  list-sites    - List configured sites"
echo "  caddy-edit    - Edit Caddyfile"
echo "  caddy-reload  - Reload Caddy"
echo "  caddy-restart - Restart Caddy service"
echo "  caddy-test    - Test Caddy configuration"
echo "  caddy-status  - Check Caddy status and logs"
echo "  caddy-logs    - View live Caddy logs"
echo
echo "PM2:"
echo "  pm2-start <ecosystem-file> - Start PM2 app from ecosystem file"
echo "  pm2-add-site <name> <port> <ecosystem-file> - Start PM2 app and add to Caddy"
echo "  pm2-remove <name> - Stop and remove PM2 app"
echo "  pm2-restart <name> - Restart PM2 app"
echo "  pm2-logs <name> - View PM2 app logs"
echo "  pm2-status - Show PM2 apps and Caddy sites"
echo
echo "System Monitoring:"
echo "  system-status - System overview and top processes"
echo "  db-status - Database status (PostgreSQL, Redis)"
echo "  security-status - Security status (firewall, fail2ban, SSH)"
echo "  port-check <port> - Check if port is available"
echo "  top - Enhanced process monitor (btop)"
echo "  iotop - I/O monitoring"
echo "  nethogs - Network monitoring"
echo "  disk - Disk usage analyzer"
echo
echo "Development:"
echo "  create-react-hono <name> - Create React + Hono project"
echo "  backup-system - Create system backup"
echo "  port-check <port> - Check port availability"
echo
echo "Security:"
echo "  ufw-status - Firewall status"
echo "  fail2ban-status - Fail2ban status"
echo "  ssh-keys - List SSH keys"
echo
echo "Network:"
echo "  nmap-local - Scan local network"
echo "  nmap-scan - Network scan"
echo "  tcpdump - Packet capture"
echo "  lsof-port - List processes on port"
echo
echo "Database:"
echo "  psql - PostgreSQL client"
echo "  redis-cli - Redis client"
echo "  sqlite - SQLite client"
echo
echo "VS Code Server:"
echo "  vscode - VS Code Server status"
echo "  vscode-restart - Restart VS Code Server"
echo "  vscode-logs - View VS Code Server logs"
echo "  vscode-password - Show current password"
echo "  vscode-change-password <new-password> - Change password"
echo "  🌐 Access at: http://vscode.local"
echo
echo "AUR (yay):"
echo "  yay-update - Update all packages (AUR + official)"
echo "  yay-install <package> - Install AUR package"
echo "  yay-remove <package> - Remove AUR package"
echo "  yay-search <package> - Search AUR packages"
echo "  yay-info <package> - Show package info"
echo
echo "Navigation:"
echo "  ..            - Go up one directory"
echo "  ...           - Go up two directories"
echo "  ....          - Go up three directories"
echo "  .....         - Go up four directories"
echo "  ......        - Go up five directories"
echo "  .......       - Go up six directories"
echo "  ........      - Go up seven directories"
echo "  -             - Previous directory"
echo "  ~             - Home directory"
echo "  up <n>        - Go up n directories (e.g., up 3)"
echo "  up1-up9       - Go up 1-9 directories quickly"
echo "  cdp           - Go to ~/projects"
echo "  cdd           - Go to ~/Downloads"
echo "  cdt           - Go to /tmp"
echo "  cdl           - Go to /var/log"
echo "  cde           - Go to /etc"
echo "  cdr           - Go to / (root)"
echo "  cdu           - Go to /usr"
echo "  cdv           - Go to /var"
echo "  1-9           - Jump to directory history (1-9)"
echo "  d             - Show directory stack"
echo "  cd <pattern>  - Smart directory search (finds matching dirs)"
echo
echo "File Operations:"
echo "  ls            - List with icons (eza)"
echo "  ll            - Long format with details"
echo "  la            - Show all including hidden"
echo "  lt            - Tree view (3 levels)"
echo "  lf            - Long format with git info"
echo "  l             - Quick long listing"
echo "  list          - Enhanced directory listing"
echo "  tree          - Directory tree"
echo "  cat           - Syntax highlighted (bat)"
echo "  view          - Enhanced file viewing"
echo "  edit          - Quick file editing"
echo "  find          - Modern find (fd)"
echo "  grep          - Colorized grep"
echo "  g             - Enhanced grep with context"
echo "  rg            - Ripgrep search"
echo "  cp            - Copy with progress (rsync)"
echo "  m             - Move files"
echo "  rm            - Remove with confirmation"
echo "  mkdir         - Create directories (with -p)"
echo "  mkcd          - Create and enter directory"
echo
echo "Git:"
echo "  gs            - git status"
echo "  ga            - git add"
echo "  gc            - git commit"
echo "  gp            - git push"
echo "  gl            - git pull"
echo "  gd            - git diff"
echo "  gb            - git branch"
echo "  gco           - git checkout"
echo "  glog          - git log --oneline --graph"
echo
echo "Utilities:"
echo "  weather [city] - Weather report"
echo "  calc <expr>   - Calculator"
echo "  backup <file> - Backup file with timestamp"
echo "  extract <file> - Extract any archive"
echo "  mkcd <dir>    - Create and enter directory"
echo "  find_large_files [dir] - Find large files"
echo "  pid_port <port> - Find process on port"
echo
echo "Help Commands:"
echo "  ?             - Search aliases with fzf"
echo "  ??            - Search functions with fzf"
echo "  ???           - List all aliases with syntax highlighting"
echo "  ????          - List all functions with syntax highlighting"
echo
echo "Quick Shortcuts:"
echo "  c             - Clear screen"
echo "  h             - History (or h <pattern>)"
echo "  reload        - Reload zsh config"
echo "  projects      - Go to ~/projects"
echo "  downloads     - Go to ~/Downloads"
echo "  tmp           - Go to /tmp"
echo "  logs          - Go to /var/log"
echo "  etc           - Go to /etc"
echo "  home          - Go to ~"
echo "  root          - Go to / (root directory)"
echo "  usr           - Go to /usr"
echo "  var           - Go to /var"
echo "  opt           - Go to /opt"
echo "  srv           - Go to /srv"
echo "  mnt           - Go to /mnt"
echo "  media         - Go to /media"
echo "  dev           - Go to /dev"
echo "  proc          - Go to /proc"
echo "  sys           - Go to /sys"
echo
echo "Enhanced Commands:"
echo "  e             - Quick file editing"
echo "  view          - Enhanced file viewing"
echo "  edit          - Quick file editing"
echo "  find          - Modern file search"
echo "  g             - Enhanced grep"
echo "  rg            - Ripgrep search"
echo "  p             - Process list"
echo "  process       - Enhanced process management"
echo "  info          - System information"
echo "  mem           - Memory usage"
echo "  disk          - Disk usage"
echo "  cpu           - CPU information"
echo "  uptime        - System uptime"
echo "  load          - System load"
echo "  ping          - Ping with 4 packets"
echo "  traceroute    - Traceroute without DNS"
echo "  netstat       - Network connections"
echo "  ss            - Socket statistics"
SCRIPT

# Make scripts executable
chmod +x /usr/local/bin/gnar-*

# Change shell to zsh
echo -e "${GREEN}🐚 Setting zsh as default shell...${NC}"
if chsh -s /usr/bin/zsh "$REAL_USER"; then
    echo "✅ Shell changed to zsh successfully"
else
    echo "⚠️  Shell change failed - user may need to run 'chsh -s /usr/bin/zsh' manually"
fi

# Final service status check
echo
echo -e "${GREEN}🔍 Checking service status...${NC}"
echo "=== Service Status ==="
for service in caddy docker postgresql valkey fail2ban ufw "code-server@$REAL_USER"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "✅ $service: running"
    else
        echo "❌ $service: not running"
        # Try to start failed services
        case $service in
            "ufw")
                echo "   Attempting to start UFW..."
                systemctl start ufw 2>/dev/null && echo "   ✅ UFW started" || echo "   ❌ UFW failed to start"
                ;;
            "code-server@$REAL_USER")
                echo "   Attempting to start code-server..."
                systemctl start "code-server@$REAL_USER" 2>/dev/null && echo "   ✅ Code-server started" || echo "   ❌ Code-server failed to start"
                ;;
        esac
    fi
done

# Additional checks
echo
echo "=== Additional Checks ==="
echo "🌐 VS Code Server: http://localhost:8080 $(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null | grep -q "200\|302\|401" && echo "✅ responding" || echo "❌ not responding")"
echo "🌐 Caddy: http://localhost:80 $(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null | grep -q "200" && echo "✅ responding" || echo "❌ not responding")"
# Source user's shell config to get updated PATH for checks
export PATH="/home/$REAL_USER/.local/bin:/home/$REAL_USER/.local/share/gem/ruby/3.4.0/bin:/home/$REAL_USER/.npm-global/bin:/home/$REAL_USER/.bun/bin:/home/$REAL_USER/.cargo/bin:$PATH"

echo "📦 npm global packages: $(sudo -u "$REAL_USER" bash -c "export PATH=\"/home/$REAL_USER/.npm-global/bin:\$PATH\" && which yarn pnpm pm2 2>/dev/null | wc -l")/3 installed"
echo "💎 Ruby bundler: $(sudo -u "$REAL_USER" bash -c "export PATH=\"/home/$REAL_USER/.local/share/gem/ruby/3.4.0/bin:\$PATH\" && which bundle 2>/dev/null && echo \"✅ available\" || echo \"❌ not in PATH\"")"
echo "🦀 Rust toolchain: $(sudo -u "$REAL_USER" bash -c "export PATH=\"/home/$REAL_USER/.cargo/bin:\$PATH\" && which rustc cargo 2>/dev/null | wc -l")/2 installed"
echo "🐹 Go tools: $(sudo -u "$REAL_USER" bash -c "export GOPATH=\"/home/$REAL_USER/go\" && export PATH=\"\$GOPATH/bin:\$PATH\" && which dlv 2>/dev/null && echo \"✅ available\" || echo \"❌ not available\"")"
echo "🐍 Python tools: $(sudo -u "$REAL_USER" bash -c "export PATH=\"/home/$REAL_USER/.local/bin:\$PATH\" && which black pytest 2>/dev/null | wc -l")/2 installed"

echo
echo -e "${GREEN}✅ GNAR Home Server Setup Complete!${NC}"
echo
echo "What's installed:"
echo "  • Zsh with Spaceship prompt + essential plugins"
echo "  • Tmux with vim keybindings"
echo "  • VS Code Server (browser-based IDE)"
echo "  • Caddy web server with reverse proxy"
echo "  • Docker + Docker Compose"
echo "  • PM2 process management"
echo "  • PostgreSQL + Valkey/Redis databases"
echo "  • Security: UFW firewall + Fail2ban + SSH hardening"
echo "  • Monitoring: btop, iotop, nethogs, smartmontools"
echo "  • Development: Node.js, Python, Ruby, Rust, Go, Java"
echo "  • Tools: eza, bat, fd, fzf, zoxide, ripgrep, httpie"
echo "  • Network: nmap, tcpdump, wireshark-cli"
echo "  • File ops: rsync, rclone, p7zip, imagemagick"
echo
echo "Quick start:"
echo "  1. Reboot: sudo reboot"
echo "  2. SSH in: ssh user@server"
echo "  3. Start tmux: tmux"
echo "  4. Create project: create-react-hono myapp"
echo "  5. Add to Caddy: add-site myapp 3000"
echo "  6. Open VS Code: http://vscode.local (password: gnar-vscode-2024)"
echo "     Note: Add 'vscode.local' to your hosts file pointing to this server's IP"
echo "  7. Reload shell: source ~/.zshrc"
echo "  8. Get help: gnar-help"
echo
echo "System management:"
echo "  • system-status - System overview"
echo "  • security-status - Security status"
echo "  • db-status - Database status"
echo "  • backup-system - Create backup"
echo
echo "Two ways to work:"
echo "  🌐 VS Code in browser: http://vscode.local"
echo "  💻 SSH + Tmux: ssh user@server && tmux"
echo
echo -e "${GREEN}Your home server is ready! 🏠🚀${NC}"
echo
echo "🔧 Troubleshooting:"
echo "  If Caddy failed to start:"
echo "    sudo systemctl status caddy"
echo "    sudo journalctl -xeu caddy.service"
echo "    sudo caddy validate --config /etc/caddy/Caddyfile"
echo
echo "  If VS Code Server failed to start:"
echo "    sudo systemctl status code-server@$REAL_USER"
echo "    sudo journalctl -xeu code-server@$REAL_USER"
echo
echo "  If PostgreSQL failed to start:"
echo "    sudo systemctl status postgresql"
echo "    sudo journalctl -xeu postgresql"
echo
echo "  To fix Caddy and add VS Code Server:"
echo "    add-site vscode 8080"
echo
echo "  To check all services:"
echo "    system-status"
echo
echo "🌐 VS Code Server Access:"
echo "  If vscode.local doesn't work from your Mac:"
echo "  1. Add to your Mac's /etc/hosts file:"
echo "     echo \"\$(ip route get 1 | awk '{print \$7}') vscode.local\" | sudo tee -a /etc/hosts"
echo "  2. Or access directly: http://\$(ip route get 1 | awk '{print \$7}'):80"
echo "  3. Check Caddy status: sudo systemctl status caddy"
echo "  4. Test Caddy config: sudo caddy validate --config /etc/caddy/Caddyfile"