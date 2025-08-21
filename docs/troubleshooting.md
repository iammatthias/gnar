# Troubleshooting

## TTY Issues

### Console Font Problems
```bash
# List available console fonts
ls /usr/share/kbd/consolefonts/

# Set larger font temporarily
sudo setfont /usr/share/kbd/consolefonts/ter-132n.psf.gz

# Make permanent
echo 'FONT=ter-132n' | sudo tee /etc/vconsole.conf
```

### TTY Not Accessible
```bash
# Switch between TTYs
# Ctrl+Alt+F1 through Ctrl+Alt+F6

# Check current TTY
tty

# If locked out, boot from USB and chroot to fix
```

## Tmux Issues

### Prefix Key Not Working
```bash
# Test if keyboard input is working
/usr/bin/cat -v
# Press Ctrl+b, should show: ^B
# Press Ctrl+c to exit

# Check if you're actually in tmux
echo $TMUX
# Should show something like: /tmp/tmux-1000/default,1234,0

# Check tmux keybindings
tmux list-keys | grep "C-b"
```

### Clean Config for Testing
```bash
# Kill all tmux sessions
tmux kill-server

# Create minimal test config
cat > ~/.tmux.conf.test << 'EOF'
set -g prefix C-b
bind C-b send-prefix
set -g mouse on
EOF

# Test with minimal config
tmux -f ~/.tmux.conf.test
# Try: Ctrl+b then d (should detach)
```

### Plugin Issues
```bash
# Check if plugins are installed
ls -la ~/.tmux/plugins/

# Install plugins manually
# In tmux: Press Ctrl+b I (capital i)

# If plugins break tmux, remove them
rm -rf ~/.tmux/plugins/
# Restart tmux - should work with built-in features
```

## Zsh Issues

### History Not Working
```bash
# Check history file permissions
ls -la ~/.zsh_history

# Fix permissions
chmod 600 ~/.zsh_history
```

### Shell Not Changing
```bash
# Verify zsh is installed
which zsh

# Check current shell
echo $SHELL

# Manually change shell
chsh -s /usr/bin/zsh
```

## System Issues

### Package Installation Fails
```bash
# Update package database
sudo pacman -Sy

# Clear package cache
sudo pacman -Scc

# Check disk space
df -h
```

### Performance Issues
```bash
# Check running processes
htop

# Check system load
uptime

# Check memory usage
free -h
```

## Recovery

### Reset Configuration
```bash
# Backup current configs
mkdir ~/config-backup
cp -r ~/.config ~/config-backup/
cp ~/.zshrc ~/config-backup/

# Remove GNAR configs
rm ~/.zshrc

# Re-run setup
cd ~/gnar
sudo ./scripts/setup.sh
```

### Emergency Shell Access
If you have shell issues:
1. Press `Ctrl+Alt+F2` to switch to different TTY
2. Login with username/password
3. Fix configuration issues
4. Switch back with `Ctrl+Alt+F1`