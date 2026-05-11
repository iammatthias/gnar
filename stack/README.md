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

## Two listeners: private vs public

Caddy listens on two separate ports inside the tailscale netns:

| Port  | Listener  | Reached by             | Helper            |
|-------|-----------|------------------------|-------------------|
| 80    | private   | tailnet                | `add-site`        |
| 8080  | public    | cloudflared tunnel     | `add-public-site` |

The split is intentional. Cloudflared only ever delivers traffic to
`localhost:8080`, so it physically can't reach the dashboard or any
other private vhost — the dashboard isn't on that listener.

## Public sites via Cloudflare Tunnel (optional)

The cloudflared service is in the compose file but disabled (behind the
`cloudflared` profile). To turn it on:

1. **Create a tunnel.** Cloudflare Zero Trust dashboard → Networks →
   Tunnels → Create a tunnel. Save the connector token.
2. **Configure routes.** In that tunnel's "Public Hostnames" tab, add
   each public hostname (e.g. `myapp.example.com`) and route each to
   `http://localhost:8080`. They all share the same single route on
   the tunnel side — caddy distinguishes them by Host header.
3. **Set the token.** In `/srv/stack/.env`, set
   `CLOUDFLARED_TOKEN=...`.
4. **Start the connector.**
   ```
   cd /srv/stack
   docker compose --profile cloudflared up -d
   ```
5. **Publish a site.** From a shell on the box:
   ```
   add-public-site myapp.example.com 3000
   ```
   That writes a vhost block to the Caddyfile and reloads caddy. The
   site is now live at `https://myapp.example.com`.

One tunnel covers every site you publish — `add-public-site` per
hostname.

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
