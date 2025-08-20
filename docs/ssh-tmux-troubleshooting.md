# SSH + Tmux Troubleshooting Guide

## Common Issues When SSHing from macOS to Linux

### Issue: Tmux keybindings don't work, keys just print to screen

This is a common issue when SSHing from macOS terminals to Linux machines running tmux.

#### Quick Fixes:

1. **Check if you're inside tmux**
```bash
echo $TMUX
# Should show something like: /tmp/tmux-1000/default,1234,0
# If empty, you're not in tmux
```

2. **Test the prefix key**
```bash
# The default prefix is Ctrl-b
# Press Ctrl-b, then ? (question mark)
# This should show tmux key bindings
```

3. **If Ctrl-b doesn't work, try these:**

**Option A: Use a different terminal on Mac**
- iTerm2 (recommended): Works best with tmux over SSH
- Alacritty: Excellent tmux compatibility
- Avoid: Terminal.app (has known issues with tmux)

**Option B: Check your SSH settings**
```bash
# SSH with proper terminal type
ssh -t user@server 'export TERM=xterm-256color; tmux'

# Or add to your ~/.ssh/config:
Host myserver
    HostName server.example.com
    User myuser
    RequestTTY yes
    RemoteCommand tmux new-session -A -s main
```

**Option C: Fix terminal settings**
```bash
# On the Linux machine, before starting tmux:
export TERM=xterm-256color
tmux

# Or add to your ~/.zshrc on the Linux machine:
if [[ -n $SSH_CONNECTION ]]; then
  export TERM=xterm-256color
fi
```

### Issue: Prefix key conflicts

If Ctrl-b isn't working, it might be intercepted by your Mac terminal or SSH client.

**Alternative prefix options:**
```bash
# Edit ~/.tmux.conf on Linux machine
# Try Ctrl-a (like GNU Screen):
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# Or try Ctrl-Space:
set -g prefix C-Space
unbind C-b
bind C-Space send-prefix
```

### Issue: Keys work but feel laggy

**Fix escape time:**
```bash
# Add to ~/.tmux.conf
set -sg escape-time 0
set -sg repeat-time 0
```

### Testing Tmux Without SSH

First, test tmux locally on the Linux machine:
```bash
# SSH to the machine
ssh user@server

# Start tmux
tmux

# Test basic commands:
# Ctrl-b c     (create new window)
# Ctrl-b d     (detach)
# Ctrl-b ?     (show help)
```

If it works locally but not over SSH, the issue is with your SSH/terminal setup.

### Universal Setup for Any Terminal

1. **Configure SSH properly (optional but recommended)**
```bash
# ~/.ssh/config on your client machine
Host gnar
    HostName your-linux-server
    User your-username
    ForwardAgent yes
    ServerAliveInterval 60
    RequestTTY yes
    SetEnv LANG=en_US.UTF-8
    SetEnv LC_ALL=en_US.UTF-8
```

2. **Connect from any terminal**
```bash
# Works with Terminal.app, iTerm2, Alacritty, Windows Terminal, PuTTY, etc.
ssh user@server

# Start tmux (UTF-8 is automatically enabled by GNAR)
tmux

# Or attach to existing session
tmux attach
```

### Terminal-Specific Tips

**macOS Terminal.app**
- Works out of the box with GNAR's UTF-8 configuration
- Use Ctrl-b as prefix (may need to press and release, then next key)

**iTerm2** (optional integration mode)
```bash
# For native iTerm2 panes (optional feature)
ssh user@server -t 'tmux -CC -u new -A -s main'
# Or after SSH: tmux-cc
```

**Windows Terminal / PuTTY**
- Ensure UTF-8 encoding in settings
- Works normally with standard tmux commands

**Alacritty / Kitty / Other Modern Terminals**
- Work perfectly with default GNAR configuration
- No special setup needed

### Emergency Escape

If you get stuck in tmux and can't use keybindings:
```bash
# From another SSH session:
tmux kill-server

# Or kill specific session:
tmux kill-session -t session-name
```

### Verify Your Setup

Run this diagnostic script:
```bash
#!/bin/bash
echo "=== Tmux Diagnostic ==="
echo "Terminal: $TERM"
echo "Tmux version: $(tmux -V)"
echo "Inside tmux: ${TMUX:-No}"
echo "SSH connection: ${SSH_CONNECTION:-No}"
echo ""
echo "Testing prefix key..."
echo "Press Ctrl-b then ? to see if tmux responds"
echo "Press q to exit the help screen"
```

### Still Not Working?

Try the nuclear option - minimal tmux config:
```bash
# Backup existing config
mv ~/.tmux.conf ~/.tmux.conf.bak

# Create minimal config
cat > ~/.tmux.conf << 'EOF'
# Minimal tmux config for testing
set -g prefix C-a
unbind C-b
bind C-a send-prefix
set -g mouse on
EOF

# Restart tmux
tmux kill-server
tmux
```

If this works, gradually add back your configurations to find the issue.