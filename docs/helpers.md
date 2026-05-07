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

## VS Code Server

```bash
vs                             # status, URL, current password
vsr                            # restart
vsl                            # tail logs
vscode-password                # print the password
vscode-change-password <pw>    # change it (restarts code-server)
```

Reach it at `http://vscode.local` once you've added `vscode.local` to your
client's `/etc/hosts` pointing at the server.

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
