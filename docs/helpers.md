# GNAR Helpers

Quick reference for the aliases, functions, and tools that GNAR sets up.
Run `gnar-help` on the box for a printed cheat sheet, or `gnar-aliases` /
`gnar-functions` for an fzf-driven search.

## Tmux

Prefix is **`Ctrl-a`** (not the default `Ctrl-b`).

### Sessions

```bash
t              # tmux
tn <name>      # new named session
ta <name>      # attach
tl             # list sessions
tk <name>      # kill session
```

### Inside tmux (prefix `Ctrl-a`)

```text
Ctrl-a v         split window vertically (pane to the right)
Ctrl-a s         split window horizontally (pane below)
Ctrl-a h/j/k/l   navigate panes (vim-style)
Ctrl-a c         new window
Ctrl-a n / p     next / previous window
Ctrl-a 0-9       jump to window N
Ctrl-a x         close current pane
Ctrl-a z         toggle pane zoom
Ctrl-a d         detach (session keeps running)
Ctrl-a r         reload ~/.tmux.conf
Ctrl-a [         enter copy mode (vim keys)
Ctrl-a ?         list all bindings
```

Sessions survive disconnects — `tmux attach` after re-`ssh` to pick up where
you left off. No plugin manager is installed; if you want one, see
[tpm](https://github.com/tmux-plugins/tpm).

## Caddy site management

Defined as zsh functions; they edit `/etc/caddy/Caddyfile` (with a backup)
and reload Caddy on success.

```bash
add-site <name> <port>         # reverse proxy: name.local:80 -> localhost:port
add-site <name> /path/to/dir   # static files: name.local:80 serves dir
list-sites                     # list configured virtual hosts
remove-site <name>             # remove a site block
test-caddy                     # validate the Caddyfile
caddy-status                   # systemd status + recent journal
caddy-edit                     # $EDITOR /etc/caddy/Caddyfile
caddy-reload                   # systemctl reload caddy
caddy-restart                  # systemctl restart caddy
caddy-logs                     # journalctl -fu caddy
```

## Kiosk dashboard (attached display)

GNAR is headless by default, but `setup.sh` also installs **Mango**
(Wayland WM, AUR `mangowm-git`) + `foot` and configures `getty@tty1`
to auto-log the user in. When a display is plugged into the box, on
next login `~/.zprofile` exec's `mango`, which fullscreens
`gnar-dashboard` — a tmux session running **gnar-board**, a fullscreen
ratatui TUI (Rust, built from `board/` at setup time):

```
┌ CPU 12% · 54°C ────────────┐┌ MEM 2.6G/27G ───────────────┐
│ ▂▃▂▁▂▆▂▁ (history graph)   ││ ▆▆▆▆▆▆▆▆ (history graph)    │
│ cores ▁▃▂▁▅▁▁▂▁▁▁▁▁▁▁▁     ││ swap 137M/4.0G              │
├ NET ↓↑ rates + sparklines ─┤├ DISK fill bar · io r/w ─────┤
├ CONTAINERS ────────────────┤├ STATUS ─────────────────────┤
│ name CPU ▁▂▁ 0.4% MEM NET  ││ services · sites · top      │
│ … one row per container    ││ procs · HERMES · backup     │
└────────────────────────────┘└─────────────────────────────┘
```

Host metrics are sampled natively from `/proc` + `/sys` (CPU total +
per-core, memory/swap, default-route NIC throughput, whole-disk I/O,
hwmon temperature); container CPU/MEM sparklines + net rates come
straight off the Docker socket every 2s. Rendering is diff-based —
no flicker, no full repaints. `q` quits (the kiosk respawns it).

If `gnar-board` isn't built (no cargo at setup time), the dashboard
falls back to btop + the shell boards (`gnar-metrics-board` +
`gnar-status-board`), which remain installed as one-shot CLIs.

You can also run `gnar-dashboard` from any shell — it attaches the
same session if it already exists, or builds it. Run over plain ssh
(no tty) it creates/refreshes the session detached, which is how you
rebuild the kiosk layout remotely.

The dashboard helpers are stand-alone too:

```bash
gnar-metrics-board     # container CPU/MEM sparklines + net + host (one-shot)
gnar-status-board      # the unified dashboard board (one-shot)
gnar-services-status   # Caddy sites + service health (one-shot)
gnar-docker-status     # docker containers + pm2 processes
gnar-hermes-status     # Hermes containers, auth, kanban, cron
gnar-claude-stats      # Claude Code sessions + token usage
```

`gnar-claude-stats` reads `~/.claude/projects/*/*.jsonl` to compute
total token usage across all sessions, count active `claude` processes,
and break down sessions by project. Token computation is skipped if
total session data exceeds 50 MB.

To swap the dashboard for something else, edit
`~/.config/mango/config.conf` and change the `exec-once` line:

```ini
exec-once=foot --fullscreen -e gnar-dashboard
exec-once=foot --fullscreen -e btop
exec-once=foot --fullscreen -e glances
exec-once=foot --fullscreen -e tmux new -A -s dash
```

In-Mango keybindings (only matter if you walk up to the box):

| Keybinding | Action |
|---|---|
| `Alt + Return` | Open another `foot` terminal |
| `Alt + Q` | Close the focused window |
| `Super + F` | Toggle fullscreen |
| `Super + Shift + R` | Reload `config.conf` |
| `Super + M` | Quit Mango |

## Snapshots (btrfs only)

If your root is btrfs, `setup.sh` configures Snapper and `snap-pac`:

- `snap-pac` auto-snapshots **before and after every pacman transaction** —
  so a bad `pacman -Syu` is recoverable in 30 seconds.
- `snapper-timeline.timer` keeps rolling snapshots: 5 hourly, 7 daily,
  2 weekly, 2 monthly.
- `snapper-cleanup.timer` prunes old snapshots automatically.
- On GRUB systems, `grub-btrfs` adds a "Snapshots" submenu so you can
  boot into any snapshot when an update breaks the system.
- `chattr +C` is set on `/var/lib/postgres`, `/var/lib/valkey`, and
  `/var/lib/docker` to skip CoW on database/container files (these
  get tons of small random writes; CoW makes them slow + bloats
  snapshot sizes).

```bash
snapper -c root list                    # list snapshots
snapper -c root create -d "before X"    # manual snapshot with description
snapper -c root status N..M             # diff between two snapshots
snapper -c root undochange N..M         # selectively revert files
snapper -c root delete N                # delete a specific snapshot
```

If a `pacman -Syu` breaks boot: reboot, hold Shift to enter GRUB, pick
"Arch Linux snapshots" submenu, choose the most recent pre-update entry,
boot into it (read-only), then either `snapper rollback` from there or
`btrfs subvolume set-default` to make it the new root.

systemd-boot users: GRUB-style boot-into-snapshot is GRUB-only. Snapper
itself still works (so `undochange` and timeline retention are useful),
but recovery from a non-bootable system needs a USB.

## PM2

```bash
pm2-start <ecosystem.config.js>   # start an ecosystem file
pm2-add-site <name> <port> <eco>  # pm2-start + add-site in one shot
pm2-remove <name>
pm2-restart <name>
pm2-logs <name>
pm2-status                        # pm2 list + Caddy site list
```

## System status

```bash
system-status      # uptime, load, memory, disk, top procs, listening ports
db-status          # postgresql + valkey systemd status + connection counts
security-status    # ufw + fail2ban + sshd status
port-check <port>  # is anything listening on this port?
gnar-info          # fastfetch machine report (TR-100 style)
gnar-update        # pacman -Syu + cache clean
gnar-help          # full alias / function reference
```

## File operations

```bash
ls / ll / la / lf / lt / tree     # eza variants (icons, --git, --tree, …)
cat                                # bat (paged, syntax-highlighted)
less / more                        # bat with paging
df / du / free                     # human-readable (-h)
e / edit                           # nvim
mkcd <dir>                         # mkdir + cd
```

## Navigation

```bash
.. ... .... ..... ......           # cd up N levels
~                                  # cd ~
-                                  # cd -
cdp / cdd / cdt / cdl / cde        # ~/projects, ~/Downloads, /tmp, /var/log, /etc
projects / downloads               # cd ~/projects, ~/Downloads
up <n>                             # cd ../../… n times (function)
```

`zoxide` is initialized — once you've `cd`'d into a directory, `z partial`
will jump back without typing the full path.

## Git

```bash
g gs ga gc gp gl gd gb gco         # short forms
glog                               # git log --oneline --graph --decorate
```

## Docker

```bash
dkr      # docker
dkc      # docker-compose
dkps     # docker ps
dkpa     # docker ps -a
dki      # docker images
dkex     # docker exec -it
```

## AUR (yay)

```bash
yay-update / yay-install / yay-remove / yay-search / yay-info
```

## Misc

```bash
ff / nf                # fastfetch
myip                   # public IP (curl ifconfig.me)
localip                # local IPv4 addresses
ports                  # ss -tulpn
sqlite                 # sqlite3
smart                  # sudo smartctl -a
ufw-status / fail2ban-status
nmap-local             # nmap -sn 192.168.1.0/24
nmap-scan              # nmap -sS -O -F
lsof-port <port>       # lsof -i :<port>
c                      # clear
reload / r             # source ~/.zshrc
```

## Backup

```bash
backup-system    # snapshot /etc/{caddy,ufw,fail2ban}, ~/.zshrc, ~/.tmux.conf,
                 # ~/.config to ~/backups/<timestamp>
```

## Adding your own

Drop functions/aliases into `~/.zshrc` and `source ~/.zshrc`. Or, for a
cleaner override pattern, create `~/.zshrc.local` and add this near the top
of `~/.zshrc`:

```bash
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
```

Editing `~/.zshrc` in place works fine — re-running `setup.sh` will back up
the existing file as `~/.zshrc.gnar-backup.<timestamp>` before reinstalling.
