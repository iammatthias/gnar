# GNAR Helpers

## Tmux - Tiling Terminal

Tmux provides tiling terminal functionality in pure TTY. The answer was always tmux.

### Starting & Managing Sessions
```bash
tmux                    # Start new session
tmux new -s work        # New named session
tmux attach -t work     # Attach to session (or 'ta work' with our alias)
tmux ls                 # List all sessions (or 'tl' with our alias)
tmux kill-session -t work # Kill specific session
tmux kill-server        # Kill all sessions
```

### Key Bindings (Prefix: Ctrl-a)

#### Pane Management
```bash
Ctrl-a |        # Split window vertically
Ctrl-a -        # Split window horizontally
Ctrl-a h/j/k/l  # Navigate panes (vim-style)
Ctrl-a H/J/K/L  # Resize panes (5 units)
Ctrl-a x        # Close current pane (with confirmation)
Ctrl-a q        # Show pane numbers (press number to jump)
Ctrl-a z        # Toggle pane zoom (fullscreen)
Ctrl-a space    # Cycle through pane layouts
Ctrl-a {        # Move pane left
Ctrl-a }        # Move pane right
```

#### Window Management
```bash
Ctrl-a c        # Create new window
Ctrl-a n        # Next window
Ctrl-a p        # Previous window
Ctrl-a 0-9      # Jump to window by number
Ctrl-a ,        # Rename current window
Ctrl-a &        # Close current window (with confirmation)
Ctrl-a w        # List all windows
```

#### Session Control
```bash
Ctrl-a d        # Detach from session (keeps running)
Ctrl-a D        # Choose client to detach
Ctrl-a s        # List and switch sessions
Ctrl-a $        # Rename current session
```

#### Other Commands
```bash
Ctrl-a r        # Reload tmux config
Ctrl-a ?        # Show all key bindings
Ctrl-a :        # Enter command mode
Ctrl-a [        # Enter copy mode (scroll/select)
```

### Exiting Tmux

There are several ways to exit tmux:

1. **Exit a pane**: Type `exit` or press `Ctrl-d` in the shell
2. **Close a pane**: `Ctrl-a x` (will ask for confirmation)
3. **Detach from session**: `Ctrl-a d` (session continues running)
4. **Kill entire session**: Exit all panes, or from outside tmux: `tmux kill-session -t session-name`

### Copy Mode (Scrolling & Selection)
```bash
Ctrl-a [        # Enter copy mode
# In copy mode:
h/j/k/l         # Navigate (vim-style)
g               # Go to top
G               # Go to bottom
/               # Search forward
?               # Search backward
Space           # Start selection
Enter           # Copy selection
q               # Exit copy mode
```

### Tips & Tricks
- **Mouse support**: Click to select panes, scroll to navigate
- **Persistent sessions**: Detached sessions survive logout/disconnect
- **Nested tmux**: Press `Ctrl-a a` to send prefix to inner tmux
- **Config location**: `~/.tmux.conf`
- **Windows vs Panes**: Windows are like tabs, panes split the current window
- **Session naming**: Use descriptive names like 'work', 'personal', 'servers'

### Common Workflows

#### Remote Development
```bash
# On remote server
tmux new -s dev
# Do work, split panes as needed
Ctrl-a d        # Detach before disconnecting

# Later, reconnect
ssh server
tmux attach -t dev  # Resume exactly where you left off
```

#### Multiple Projects
```bash
tmux new -s project1
# Work on project1
Ctrl-a d

tmux new -s project2
# Work on project2
Ctrl-a s        # Switch between sessions
```

## Quick Aliases

GNAR includes many helpful aliases for common tasks:

### System Information
```bash
ff              # Fastfetch - quick system info with GNAR theme
nf              # Alternative alias for neofetch users
gnar-info       # Full GNAR machine report
```

### File Operations
```bash
ls              # List files with icons (eza)
ll              # Long format with details
la              # Show all including hidden
l               # One file per line
tree            # Full directory tree
lt              # Tree limited to 2 levels
```

### Navigation
```bash
..              # Go up one directory
...             # Go up two directories
....            # Go up three directories
-               # Previous directory
cd              # Smart jumping with zoxide (aliased to z)
```

### Quick Shortcuts
```bash
c               # Clear screen
h               # History
j               # Jobs list
path            # Display PATH on separate lines
now             # Current date/time (YYYY-MM-DD HH:MM:SS)
week            # Current week number
myip            # Public IP address
localip         # Local IP addresses
ports           # Show open ports
```

### Enhanced Commands
```bash
cat             # Uses bat with syntax highlighting
find            # Uses fd for faster searching
grep            # Auto-colored output
diff            # Auto-colored output
```

## Built-in Commands

### gnar-info
Comprehensive system information display with custom GNAR Machine Report.

```bash
gnar-info
```

**What it shows:**
- Professional box-drawing machine report inspired by TR-100
- Complete system overview in structured format:
  - **Header**: GNAR MACHINE REPORT with fastfetch version
  - **System**: OS, Kernel
  - **Network**: Hostname, IP, MAC address, DNS, User
  - **Hardware**: Processor name, cores/threads, CPU frequency, load average
  - **Memory**: Usage with visual progress bar
  - **Storage**: Disk usage with visual progress bar
  - **Session**: Last login info and system uptime

**Display Features:**
- Clean box-drawing characters for professional appearance
- Progress bars for memory and disk usage
- Organized sections with clear separators
- Optimized for TTY display

**Use cases:**
- Quick system health check
- Verifying system specs
- Monitoring resource usage
- Checking after reboot

### gnar-update
Complete system update and maintenance tool.

```bash
gnar-update
```

**What it does:**
1. **Updates system packages** (`pacman -Syu`)
   - Syncs package databases
   - Updates all installed packages
   - Handles dependencies automatically
   
2. **Cleans package cache** (`pacman -Sc`)
   - Removes old package versions from cache
   - Keeps only current versions
   - Frees up disk space

**Why use it:**
- Keep system secure with latest patches
- Save disk space by removing old packages
- Single command for full system maintenance
- No need to remember pacman flags

### gnar-theme
Terminal theme switcher with multiple aesthetic options.

```bash
gnar-theme           # Show usage and current theme
gnar-theme list      # List all available themes
gnar-theme set       # Interactive theme selection
gnar-theme set matrix  # Apply specific theme directly
```

**Available Themes:**
- **darkmatter** - Sleek dark theme with warm accents (default)
- **matrix** - Classic green-on-black hacker aesthetic
- **minimal** - Clean monochrome, distraction-free
- **retro** - 80s terminal with vibrant neon colors
- **ocean** - Deep blue nautical theme

**What it changes:**
- FZF color scheme
- Terminal color palette for fuzzy finding
- Border styles and prompt characters

**Usage example:**
```bash
# View available themes
gnar-theme list

# Apply the matrix theme
gnar-theme set matrix

# Interactive selection
gnar-theme set
```

### help-gnar
Interactive command reference for the entire GNAR system.

```bash
help-gnar
```

**Sections included:**
- **System Commands** - GNAR utilities and system monitors
- **Tmux Commands** - Full tiling terminal reference
- **File Operations** - Enhanced navigation and manipulation
- **Git Shortcuts** - All git aliases configured
- **Utilities** - Weather, calculator, and helper functions

**Features:**
- Clean formatted output with section dividers
- Complete tmux keybinding reference
- All custom aliases and functions
- Examples for each command type

**Use as your cheat sheet for:**
- Remembering tmux keybindings
- Finding that git alias
- Discovering helper functions
- Learning the custom setup

## System Monitoring

### htop
Interactive process viewer (installed by default).

```bash
htop
```

Useful keys:
- `F9` - Kill process
- `F6` - Sort by column
- `q` - Quit

### System Information
```bash
# Detailed hardware info
lscpu              # CPU information
lsmem              # Memory information
lsblk              # Block devices
lspci              # PCI devices
lsusb              # USB devices

# System status
uptime             # System uptime and load
free -h            # Memory usage
df -h              # Disk usage
```

## Network Tools

```bash
# Network status
ip addr show       # Show IP addresses
ping google.com    # Test connectivity
curl ifconfig.me   # Show public IP

# Download files
curl -O <url>      # Download file
wget <url>         # Alternative download tool
```

## File Operations

```bash
# File management
ls -la             # List files (detailed)
find /path -name "file"  # Find files
du -sh *           # Directory sizes

# Text processing
grep "pattern" file     # Search in files
head -n 10 file        # First 10 lines
tail -f file           # Follow file changes
```

## Git Shortcuts

```bash
# Basic git (already installed)
git status         # Repository status
git add .          # Stage all changes
git commit -m "msg" # Commit with message
git push           # Push to remote
git pull           # Pull from remote
git log --oneline  # Compact log
```

## Smart Functions Included

These functions are pre-configured in your `~/.zshrc`:

### mkcd - Make and Enter Directory
```bash
mkcd new-project
# Creates 'new-project' directory and changes into it
# Equivalent to: mkdir -p new-project && cd new-project
```

### extract - Universal Archive Extractor
```bash
extract file.tar.gz
extract archive.zip
extract backup.tar.bz2
# Automatically detects format and extracts:
# tar.gz, tar.bz2, zip, rar, gz, tar, 7z, Z
```

### backup - Timestamped Backup
```bash
backup important.conf
# Creates: important.conf.backup.20240118_143022
# Preserves original, adds timestamp to copy
```

### weather - Live Weather Report
```bash
weather           # Your location (IP-based)
weather Tokyo     # Specific city
weather "New York" # Multi-word cities
# ASCII art weather from wttr.in
```

### calc - Command-Line Calculator
```bash
calc 2+2          # Returns: 4
calc "sqrt(16)"   # Returns: 4
calc "2^8"        # Returns: 256
# Uses bc with 3 decimal precision
```

### find_large_files - Disk Space Hunter
```bash
find_large_files          # Current directory
find_large_files /var     # Specific directory
# Shows top 20 largest files sorted by size
```

### pid_port - Find Process on Port
```bash
pid_port 8080
# Shows what process is using port 8080
# Useful for debugging "port already in use"
```

## Creating Custom Helpers

Add your own functions to `~/.zshrc`:

```bash
# Example: Quick git commit and push
function gcp() {
    git add -A
    git commit -m "$1"
    git push
}

# Example: System backup
function sysbackup() {
    tar -czf ~/backup-$(date +%Y%m%d).tar.gz \
        ~/.zshrc ~/.tmux.conf ~/.config/nvim
    echo "Backup saved to ~/backup-$(date +%Y%m%d).tar.gz"
}

# Example: Quick server SSH
function srv() {
    ssh user@server-$1.example.com
}
```

After adding functions, reload your shell:
```bash
source ~/.zshrc
```