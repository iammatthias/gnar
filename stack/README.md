# GNAR stack

Single-host docker-compose for the network ingress + agent surface.

```
┌──────────────────────────── tailscale (network namespace) ─────────────────────────────┐
│                                                                                        │
│  caddy            hermes-gateway        hermes-dashboard                               │
│  :80, :443        Telegram poller       :9119                                          │
│                                                                                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

All four containers share the `tailscale` container's network namespace
(`network_mode: service:tailscale`). They reach each other on `localhost`,
and the outside world reaches them via the tailnet IP / hostname tailscale
hands out.

## Layout

```
/srv/stack/
├── docker-compose.yml
├── Caddyfile                # bind-mounted into caddy:/etc/caddy/Caddyfile
├── .env                     # TS_AUTHKEY, TS_HOSTNAME — copy from .env.example
├── hermes/Dockerfile        # custom image: hermes + claude + chainlink
├── skills/                  # mounted read-only into /root/.hermes/skills/gnar
│   └── claude-with-chainlink/SKILL.md
└── data/                    # bind-mounted state (persists across `compose down`)
    ├── tailscale/           # tailscale identity
    ├── caddy/               # caddy data + config
    ├── hermes/              # ~/.hermes (auth, MEMORY.md, kanban.db)
    └── claude/              # ~/.claude (subscription auth, sessions)
```

## Lifecycle

```
docker compose up -d --build      # bring up, build hermes image if needed
docker compose ps                 # what's running
docker compose logs -f tailscale  # follow one service
docker compose pull               # newer base images
docker compose down               # stop everything
```

`gnar-stack.service` (a systemd system unit, installed by `setup.sh`) does
`up -d` on boot.

## First-boot interactive

Three things have to happen interactively, once. Easiest is to do them via
`docker compose exec` so they happen in the right container.

1. **Tailscale.** Either fill `TS_AUTHKEY=` in `.env` and let it auto-auth on
   first boot, or:
   ```
   docker compose exec tailscale tailscale up
   ```
2. **Claude Code subscription.** From inside hermes-gateway:
   ```
   docker compose exec hermes-gateway claude
   # /login, finish browser flow, /exit
   ```
3. **Hermes brain auth.** Pick a provider:
   ```
   docker compose exec hermes-gateway hermes auth add anthropic --type oauth
   docker compose exec hermes-gateway hermes gateway setup    # Telegram
   ```

After all three: `docker compose restart hermes-gateway hermes-dashboard`.

## Adding a website

Edit `Caddyfile`, then reload caddy without restarting:

```
docker compose exec caddy caddy reload
```

The `add-site myapp 3000` zsh helper does this for you.

## Public ingress via Cloudflare Tunnel (optional)

Cloudflared is in the compose file but disabled by default (behind the
`cloudflared` profile). To enable it, create a tunnel + connector token
in the Cloudflare Zero Trust dashboard, paste it into `/srv/stack/.env`
as `CLOUDFLARED_TOKEN=...`, route the tunnel's public hostname to
`http://localhost:80` in the dashboard, then:

```
cd /srv/stack
docker compose --profile cloudflared up -d
```

Cloudflared runs in the tailscale netns alongside caddy. The tunnel
delivers traffic to `localhost:80` (caddy), which dispatches by hostname
per the Caddyfile. So you get one tunnel that fronts every site `add-site`
adds.

## Agent has git + gh + cloudflared

The hermes container ships with `git`, `gh` (GitHub CLI), `cloudflared`,
and `openssh`. Host's `~/.ssh` and `~/.gitconfig` bind-mount in read-only,
so anything the agent does over SSH/git authenticates as you.

GitHub API access (issues, PRs, releases) needs an interactive
`gh auth login` once:

```
docker compose exec hermes-gateway gh auth login
```

Cloudflared CLI tunnel management (creating/listing/deleting tunnels,
not the long-running connector) similarly:

```
docker compose exec hermes-gateway cloudflared tunnel login
```

Both store credentials in `data/agent-tools/` on host (mounted as
`/root/.config` in the container), so they survive `docker compose down`
and image rebuilds.
