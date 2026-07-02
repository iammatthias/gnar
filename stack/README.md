# GNAR stack

Single-host docker-compose for the network ingress surface.

```
┌────────────── tailscale (network namespace) ──────────────┐
│                                                           │
│  caddy                     cloudflared                    │
│  :80, :443, :8080          tunnel connector               │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

The containers share the `tailscale` container's network namespace
(`network_mode: service:tailscale`). They reach each other on `localhost`,
and the outside world reaches them via the tailnet IP / hostname tailscale
hands out — or, for opt-in public sites, via the Cloudflare tunnel.

## Layout

```
/srv/stack/
├── docker-compose.yml
├── Caddyfile                # bind-mounted into caddy:/etc/caddy/Caddyfile
│                            # LIVE copy accumulates add-site blocks — the
│                            # repo version is boilerplate only
├── .env                     # secrets — copy from .env.example, chmod 600
├── caddy/Dockerfile         # custom image: + caddy-dns/cloudflare module
├── homepage/                # static "online" page (default :80 + apex)
├── preview-handles/         # one .caddy fragment per preview site
└── data/                    # bind-mounted state (persists across `compose down`)
    ├── tailscale/           # tailscale identity
    └── caddy/               # caddy data + config (certs)
```

## Lifecycle

```
docker compose up -d --build      # bring up, build caddy image if needed
docker compose ps                 # what's running
docker compose logs -f tailscale  # follow one service
docker compose pull               # newer base images
docker compose down               # stop everything
```

`gnar-stack.service` (a systemd system unit, installed by `setup.sh`) does
`up -d` on boot.

## First-boot interactive

One thing has to happen interactively, once:

**Tailscale.** Either fill `TS_AUTHKEY=` in `.env` and let it auto-auth on
first boot, or:
```
docker compose exec tailscale tailscale up
```

`gnar-bootstrap` walks this (plus Claude Code login on the host).

## Adding a website

Edit `Caddyfile`, then reload caddy without restarting:

```
docker compose exec caddy caddy reload
```

The `add-site myapp 3000` zsh helper does this for you.

## Two listeners: private vs public

Caddy listens on separate ports inside the tailscale netns:

| Port  | Listener  | Reached by             | Helper                |
|-------|-----------|------------------------|-----------------------|
| 80    | private   | tailnet                | `add-site`            |
| 443   | private   | tailnet (LE wildcard)  | `add-preview-site`    |
| 8080  | public    | cloudflared tunnel     | `add-public-site`     |

The split is intentional. Cloudflared only ever delivers traffic to
`localhost:8080`, so it physically can't reach any private vhost.

## Public sites via Cloudflare Tunnel

1. **Create a tunnel.** Cloudflare Zero Trust dashboard → Networks →
   Tunnels → Create a tunnel. Save the connector token.
2. **Configure routes.** In that tunnel's "Public Hostnames" tab, add
   each public hostname (e.g. `myapp.example.com`) and route each to
   `http://localhost:8080`. They all share the same single route on
   the tunnel side — caddy distinguishes them by Host header.
3. **Set the token.** In `/srv/stack/.env`, set
   `CLOUDFLARED_TOKEN=...`.
4. **Bring the stack up** (the connector is always-on once the token
   is set): `cd /srv/stack && docker compose up -d`.
5. **Publish a site.** From a shell on the box:
   ```
   add-public-site myapp.example.com 3000
   ```
   That writes a vhost block to the Caddyfile and reloads caddy. The
   site is now live at `https://myapp.example.com`.

One tunnel covers every site you publish — `add-public-site` per
hostname.
