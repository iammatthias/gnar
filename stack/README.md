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
