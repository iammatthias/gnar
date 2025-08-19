# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

GNAR is a pure TTY setup with enhanced Zsh for Arch Linux. It provides a minimal, powerful terminal computing experience with no GUI, no desktop environment - just enhanced shell capabilities.

## Repository Structure

```
gnar/
├── README.md           # Main documentation with comprehensive guide
├── LICENSE             # MIT license
├── CLAUDE.md           # This file - AI assistant guidance
├── .gitignore          # Git ignore file
├── scripts/
│   ├── setup.sh        # Main installation script (Pure TTY + Enhanced Zsh)
│   └── uninstall.sh    # Safe removal script
└── docs/
    ├── configuration.md   # Zsh customization guide
    ├── helpers.md         # GNAR utilities reference
    └── troubleshooting.md # Comprehensive troubleshooting guide
```

## Key Commands

### Installation
```bash
# Run the setup script (Linux users may need: chmod +x scripts/setup.sh)
./scripts/setup.sh
```

### Post-Installation
```bash
# System information
gnar-info

# Update system
gnar-update

# Command reference
help-gnar
```

### Uninstall
```bash
# Safe removal with backup
./scripts/uninstall.sh
```

## Architecture & Structure

### 1. Main Setup Script (`setup.sh`)
**Pure TTY Installation** with essential components:

**Core Components Installed:**
- `zsh` - Enhanced shell with DarkMatter-inspired configuration
- `starship` - Cross-shell prompt with modern styling
- `tmux` - Terminal multiplexer for tiling window management in TTY
- `neovim` - Modern text editor
- `git` - Version control with integrated shortcuts
- `fastfetch` - System information display
- `eza` - Modern replacement for ls with icons
- `bat` - Cat replacement with syntax highlighting
- `fd` - Modern find replacement
- `fzf` - Fuzzy finder with custom DarkMatter colors
- `zoxide` - Smart directory jumping
- `htop` - Process monitor
- `curl` - HTTP client
- `tree` - Directory tree viewer
- `which` - Command location finder
- `man-db`, `man-pages` - Documentation

### 2. Helper Scripts
**GNAR Management Tools** (created in `/usr/local/bin/`):
- `gnar-info` - Pretty TTY system information display
- `gnar-update` - Update system and clean cache
- `gnar-theme` - Switch between 5 terminal themes (darkmatter, matrix, minimal, retro, ocean)
- `help-gnar` - Complete command reference

**Configuration Files Generated:**
- `~/.zshrc` - Enhanced shell with 50+ aliases, smart functions, git integration, beautiful 2-line prompt
- `~/.tmux.conf` - Tmux configuration with vim-style navigation, mouse support, and custom keybindings
- `~/.config/fastfetch/config.jsonc` - Custom GNAR Machine Report display inspired by TR-100
- Shell changed to zsh with comprehensive history and productivity features

## Key Design Principles

- **Security-focused**: Uses only official Arch repositories for maximum security
- **Minimal**: Pure TTY, no GUI applications, no desktop environment
- **Performance**: Ultra-lightweight, minimal resource usage
- **Productivity**: Enhanced shell with smart aliases, functions, and git integration
- **Terminal computing**: Pure command-line experience with powerful enhancements
- **Comprehensive**: One script creates complete terminal-based development environment

## Documentation Files

- **README.md**: Comprehensive guide with installation, usage, and features
- **docs/configuration.md**: Zsh customization and configuration guide
- **docs/helpers.md**: GNAR utilities and command reference
- **docs/troubleshooting.md**: Comprehensive troubleshooting guide

## Enhanced Zsh Features

### Key Aliases and Functions
- `ll` - Detailed file listing
- `..` / `...` - Directory navigation shortcuts
- `gs` - git status
- `glog` - git log with graph
- `mkcd <dir>` - Create and enter directory
- `backup <file>` - Backup file with timestamp
- `extract <archive>` - Universal archive extraction
- `weather [city]` - Weather report
- `calc <expr>` - Calculator

### Helper Commands
- `gnar-info` - System information display
- `gnar-update` - System update and cleanup
- `help-gnar` - Complete command reference

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
NEVER run chmod commands on macOS - files are already executable when created. Only mention chmod in documentation for Linux users.