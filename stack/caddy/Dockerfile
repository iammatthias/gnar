# GNAR — caddy image with the Cloudflare DNS module compiled in.
#
# Stock caddy:latest can't do ACME DNS-01, which is what we need for a
# wildcard cert on $PREVIEW_APEX (LetsEncrypt won't issue wildcards via
# HTTP-01, only DNS-01).
#
# xcaddy is Caddy's standard plugin-build harness; it rebuilds the caddy
# binary with the modules listed below. CF_API_TOKEN is read at runtime
# from the environment (set in /srv/stack/.env).

FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM caddy:latest

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
