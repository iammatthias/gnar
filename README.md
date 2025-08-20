```
   ____   _   _      _      ____
  / ___| | \ | |    / \    |  _ \
 | |  _  |  \| |   / _ \   | |_) |
 | |_| | | |\  |  / ___ \  |  _ <
  \____| |_| \_| /_/   \_\ |_| \_\
```

**Shreddable TTY**

An opionated Arch setup tailored to provide a minimal yet powerful baseline remote experience.

_GNAR_ came from "Gnome + Arch", and stuck as a name despite abandoning Gnome. Along the way this project has flirted with Hyprland, PaperWM, i3, and other window managers. In the end the answer was always tmux.

## What You Get

- **Tmux** - Tiling terminal multiplexer with 10+ plugins:
  - Session persistence (survives reboots)
  - System clipboard integration
  - Enhanced search with regex
  - SSH split panes for remote work
  - Session/pane logging capabilities
- **DarkMatter Zsh** - Enhanced shell with starship prompt, eza, bat, fzf, and zoxide
- **Neovim** - Modern text editor
- **Git** - Version control with shortcuts
- **System tools** - fastfetch, htop, tree, curl, bc, net-tools
- **Helper utilities** - gnar-info, gnar-update, gnar-theme, help-gnar
- **Smart functions** - mkcd, extract, backup, weather, calc

Pure TTY experience. No desktop environment, no GUI applications.

## Install

```bash
git clone https://github.com/iammatthias/gnar.git
cd gnar
sudo ./scripts/setup.sh
```

After reboot, login to TTY and enjoy your enhanced terminal.

**SSH from any terminal:**
```bash
# Works with Terminal.app, iTerm2, Alacritty, Windows Terminal, etc.
ssh user@server
tmux  # UTF-8 is automatically enabled
```

## Enhanced Zsh Features

### Beautiful Prompt

```
┌─[user@hostname]─[~/current/path] [git-branch]
└─❯
```

### Smart Aliases & Functions

```bash
# File Listing (using eza with icons)
ls              # List files with icons
ll              # Long format with details
la              # Show all including hidden
l               # One file per line
tree            # Full directory tree
lt              # Tree limited to 2 levels

# Navigation
..              # Go up one directory
...             # Go up two directories
-               # Go to previous directory
cd              # Uses zoxide for smart jumping

# Git Shortcuts
gs              # git status - see what's changed
ga              # git add - stage files
gc              # git commit - commit changes
glog            # git log --oneline --graph --decorate

# Smart Functions
weather [city]  # Live weather report from wttr.in
calc 2+2        # Command-line calculator using bc
mkcd newdir     # Create directory and cd into it
backup file.txt # Creates file.txt.backup.20240118_143022
extract any.zip # Universal archive extractor (zip/tar/gz/7z)

# Quick Shortcuts
ff              # Fastfetch system info
c               # Clear screen
h               # History
path            # Display PATH on separate lines
now             # Current date/time
myip            # Show public IP
ports           # Show open ports

# System Info
df              # Disk usage in human-readable format
free            # Memory usage in human-readable format
ps              # All running processes
cat             # Uses bat with syntax highlighting
find            # Uses fd for faster searching
```

### Helper Commands

```bash
gnar-info       # Display system info with ASCII art header
                # Shows: OS, kernel, uptime, CPU, memory, disk usage, IP
                # Plus active TTY users and system load

gnar-update     # Full system update and maintenance
                # Runs: pacman -Syu (update all packages)
                # Then: pacman -Sc (clean old package cache)
                # Keeps system lean and current

gnar-theme      # Terminal theme switcher
                # Choose from: darkmatter, matrix, minimal, retro, ocean
                # Changes FZF colors and terminal aesthetics
                # Run 'gnar-theme list' to see all options

help-gnar       # Interactive command reference guide
                # Lists all GNAR commands, aliases, and functions
                # Includes tmux keybindings and git shortcuts
                # Your cheat sheet for the entire system
```

### Tmux Tiling

```bash
tmux            # Start new session
Ctrl-b v        # Split vertical (vim-style added)
Ctrl-b S        # Split horizontal (capital S, vim-style added)
Ctrl-b h/j/k/l  # Navigate panes (vim-style added)
Ctrl-b x        # Close current pane
Ctrl-b d        # Detach (session continues)
exit            # Exit pane/tmux
```

## Key Features

- **Git integration** - Branch shown in prompt, 10+ git shortcuts
- **Smart history** - 10k entries, shared across sessions, smart search
- **Directory navigation** - Auto-complete, directory stack, shortcuts
- **File operations** - Safe defaults (cp -i, mv -i, rm -i)
- **System monitoring** - htop, process tools, network utilities
- **Archive handling** - Extract function supports all formats
- **Spell correction** - Automatic command correction
- **Case-insensitive** - Tab completion and globbing

## Uninstall

```bash
sudo ./scripts/uninstall.sh
```

## License

MIT
