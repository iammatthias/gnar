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

### Key Bindings (Prefix: Ctrl-b)

#### Pane Management
```bash
Ctrl-b "        # Split window horizontally (default)
Ctrl-b %        # Split window vertically (default)
Ctrl-b v        # Split window vertically (vim-style - added)
Ctrl-b S        # Split window horizontally (capital S, vim-style - added)
Ctrl-b h/j/k/l  # Navigate panes (vim-style - added)
Ctrl-b arrows   # Navigate panes (default arrows)
Ctrl-b x        # Close current pane (with confirmation)
Ctrl-b q        # Show pane numbers (press number to jump)
Ctrl-b z        # Toggle pane zoom (fullscreen)
Ctrl-b space    # Cycle through pane layouts
Ctrl-b {        # Move pane left
Ctrl-b }        # Move pane right
```

#### SSH Remote Splits (Plugin)
```bash
Ctrl-b Ctrl-h   # Split horizontally and SSH to server
Ctrl-b Ctrl-v   # Split vertically and SSH to server
Ctrl-b Ctrl-w   # New window and SSH to server
# After pressing these, you'll be prompted for the SSH destination
```

#### Window Management
```bash
Ctrl-b c        # Create new window
Ctrl-b n        # Next window
Ctrl-b p        # Previous window
Ctrl-b 0-9      # Jump to window by number
Ctrl-b ,        # Rename current window
Ctrl-b &        # Close current window (with confirmation)
Ctrl-b w        # List all windows
```

#### Session Control
```bash
Ctrl-b d        # Detach from session (keeps running)
Ctrl-b D        # Choose client to detach
Ctrl-b s        # List and switch sessions
Ctrl-b $        # Rename current session
```

#### Other Commands
```bash
Ctrl-b r        # Reload tmux config
Ctrl-b ?        # Show all key bindings
Ctrl-b :        # Enter command mode
Ctrl-b [        # Enter copy mode (scroll/select)
```

#### Plugin Features (Auto-installed)

**Session Management (resurrect/continuum)**
```bash
Ctrl-b Ctrl-s   # Save current session manually
Ctrl-b Ctrl-r   # Restore saved session
# Sessions auto-save every 15 minutes
# Sessions auto-restore after reboot
```

**Enhanced Search (copycat)**
```bash
Ctrl-b /        # Search with regex support
Ctrl-b Ctrl-f   # Search for files
Ctrl-b Ctrl-u   # Search for URLs
Ctrl-b Ctrl-d   # Search for digits
Ctrl-b Ctrl-i   # Search for IP addresses
```

**Copy/Paste (yank)**
```bash
# In copy mode (Ctrl-b [):
y               # Copy selection to system clipboard
Y               # Copy current line to system clipboard
# Normal mode:
Ctrl-b y        # Copy current pane's command line to clipboard
Ctrl-b Y        # Copy current pane's working directory
```

**File/URL Opening (open)**
```bash
# In copy mode, highlight a file/URL then:
o               # Open file/URL
Ctrl-o          # Open with $EDITOR
S               # Search highlighted text in browser
```

**Better Pane Control (pain-control)**
```bash
Ctrl-b |        # Split pane vertically
Ctrl-b -        # Split pane horizontally
Ctrl-b \        # Split full width vertically
Ctrl-b _        # Split full height horizontally
Ctrl-b <        # Move pane left
Ctrl-b >        # Move pane right
```

**Session Utils (sessionist)**
```bash
Ctrl-b g        # Switch to session by name (with completion)
Ctrl-b C        # Create new session by name
Ctrl-b X        # Kill current session without detaching
Ctrl-b S        # Switch to last session
Ctrl-b @        # Promote current pane to new session
```

**Logging (logging)**
```bash
Ctrl-b P        # Toggle logging current pane to file
Ctrl-b alt-p    # Save visible text to file
Ctrl-b alt-P    # Save complete pane history to file
Ctrl-b alt-c    # Clear pane history
# Logs saved to ~/tmux-logs/
```

### Exiting Tmux

There are several ways to exit tmux:

1. **Exit a pane**: Type `exit` or press `Ctrl-d` in the shell
2. **Close a pane**: `Ctrl-b x` (will ask for confirmation)
3. **Detach from session**: `Ctrl-b d` (session continues running)
4. **Kill entire session**: Exit all panes, or from outside tmux: `tmux kill-session -t session-name`

### Copy Mode (Scrolling & Selection)
```bash
Ctrl-b [        # Enter copy mode
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
- **Config location**: `~/.tmux.conf`
- **Windows vs Panes**: Windows are like tabs, panes split the current window
- **Session naming**: Use descriptive names like 'work', 'personal', 'servers'
- **Install plugins**: After first tmux start, press `Ctrl-b I` (capital i) to install plugins
- **Update plugins**: Press `Ctrl-b U` to update all plugins

### Common Workflows

#### Remote Development
```bash
# On remote server
tmux new -s dev
# Do work, split panes as needed
Ctrl-b d        # Detach before disconnecting

# Later, reconnect
ssh server
tmux attach -t dev  # Resume exactly where you left off
```

#### Multiple Projects
```bash
tmux new -s project1
# Work on project1
Ctrl-b d

tmux new -s project2
# Work on project2
Ctrl-b s        # Switch between sessions
```

#### Multiple SSH Servers
```bash
tmux new -s servers
# Start with local pane
Ctrl-b Ctrl-v   # Split vertically and SSH to server1
Ctrl-b Ctrl-h   # Split horizontally and SSH to server2
# Now you have local + server1 + server2 in one session
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
reload          # Reload shell configuration (source ~/.zshrc)
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