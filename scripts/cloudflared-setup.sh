#!/bin/bash
# GNAR — fully-CLI Cloudflare Tunnel setup.
#
# No dashboard required. One interactive step: when `cloudflared tunnel
# login` prints a URL, click it in your browser and authorize the zone.
# The rest (tunnel create, DNS routes, config.yml) is scripted.
#
# Re-runnable: skips steps already done.
#
# Reads PREVIEW_APEX and CLOUDFLARED_TUNNEL_NAME from /srv/stack/.env
# (see stack/.env.example). All state lands in /srv/stack/data/cloudflared/:
#   - cert.pem                     (CF API cert from the login flow)
#   - <tunnel-id>.json             (per-tunnel credentials)
#   - config.yml                   (tunnel ingress rules)
#
# After this script: `cd /srv/stack && docker compose --profile cloudflared up -d`

set -euo pipefail

STACK=/srv/stack
ENV_FILE="$STACK/.env"
DATA="$STACK/data/cloudflared"
IMG=cloudflare/cloudflared:latest

# Read PREVIEW_APEX + CLOUDFLARED_TUNNEL_NAME from /srv/stack/.env so
# the repo stays generic. Env vars on the command line take precedence.
_read_env() {
    awk -F= -v k="$1" '$1 == k {sub(/^[^=]+=/, ""); print; exit}' "$ENV_FILE" 2>/dev/null \
        | tr -d "\"' "
}
: "${PREVIEW_APEX:=$(_read_env PREVIEW_APEX)}"
: "${CLOUDFLARED_TUNNEL_NAME:=$(_read_env CLOUDFLARED_TUNNEL_NAME)}"
: "${CLOUDFLARED_TUNNEL_NAME:=gnar}"

if [ -z "${PREVIEW_APEX:-}" ] || [ "$PREVIEW_APEX" = "previews.example.com" ]; then
    echo "PREVIEW_APEX is unset or still the placeholder in $ENV_FILE."
    echo "Set it to the domain you own (e.g. previews.yourdomain.com) and re-run."
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
step()  { printf "\n%b━━━ %s ━━━%b\n" "$GREEN" "$1" "$NC"; }
ok()    { printf "%b✓%b %s\n" "$GREEN" "$NC" "$1"; }
warn()  { printf "%b!%b %s\n" "$YELLOW" "$NC" "$1"; }
info()  { printf "  %s\n" "$1"; }

cf() {
    sudo docker run --rm -i \
        --network=host \
        --user 0:0 \
        -v "$DATA":/root/.cloudflared \
        "$IMG" "$@"
}

# Login flow — same as `cf` but with stdout unbuffered so the URL streams
# to the caller as soon as cloudflared prints it. No -t (TTY) so the
# script works fine over a non-interactive SSH session too.
cf_login() {
    sudo docker run --rm -i \
        --network=host \
        --user 0:0 \
        -v "$DATA":/root/.cloudflared \
        "$IMG" "$@"
}

sudo install -d -m 755 "$DATA"

# ---------------------------------------------------------------------------
step "Cloudflare account auth"
# ---------------------------------------------------------------------------
if sudo test -f "$DATA/cert.pem"; then
    ok "Already authenticated (cert.pem present)"
else
    warn "Logging in to Cloudflare."
    info "A URL will print below — open it in your browser and authorize"
    info "the zone for $PREVIEW_APEX. cloudflared blocks until you finish."
    echo
    cf_login tunnel login
    if sudo test -f "$DATA/cert.pem"; then
        ok "Logged in."
    else
        echo "cert.pem still missing — aborting."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
step "Tunnel: $CLOUDFLARED_TUNNEL_NAME"
# ---------------------------------------------------------------------------
TUNNEL_ID=$(cf tunnel list 2>/dev/null \
    | awk -v n="$CLOUDFLARED_TUNNEL_NAME" '$2 == n {print $1; exit}' \
    | tr -d '\r')

if [ -n "$TUNNEL_ID" ]; then
    ok "Tunnel '$CLOUDFLARED_TUNNEL_NAME' already exists ($TUNNEL_ID)"
else
    info "Creating tunnel '$CLOUDFLARED_TUNNEL_NAME'..."
    cf tunnel create "$CLOUDFLARED_TUNNEL_NAME"
    TUNNEL_ID=$(cf tunnel list 2>/dev/null \
        | awk -v n="$CLOUDFLARED_TUNNEL_NAME" '$2 == n {print $1; exit}' \
        | tr -d '\r')
    [ -n "$TUNNEL_ID" ] || { echo "Tunnel create reported success but list is empty"; exit 1; }
    ok "Created ($TUNNEL_ID)"
fi

# ---------------------------------------------------------------------------
step "DNS routes"
# ---------------------------------------------------------------------------
for host in "$PREVIEW_APEX" "*.$PREVIEW_APEX"; do
    if cf tunnel route dns "$CLOUDFLARED_TUNNEL_NAME" "$host" 2>&1 | tee /tmp/cf-dns.out | grep -qiE '(added|propagated|created)'; then
        ok "$host → $CLOUDFLARED_TUNNEL_NAME"
    elif grep -qiE '(already exists|with the same name exists)' /tmp/cf-dns.out; then
        ok "$host already routed"
    else
        warn "$host routing returned an unexpected result:"
        sed 's/^/    /' /tmp/cf-dns.out
    fi
done
rm -f /tmp/cf-dns.out

# ---------------------------------------------------------------------------
step "config.yml"
# ---------------------------------------------------------------------------
# The cloudflared container mounts $DATA at /etc/cloudflared, so the
# credentials path here uses that container-side prefix.
CONFIG="$DATA/config.yml"
sudo tee "$CONFIG" > /dev/null <<EOF
tunnel: $TUNNEL_ID
credentials-file: /etc/cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: "*.$PREVIEW_APEX"
    service: http://localhost:8080
  - hostname: "$PREVIEW_APEX"
    service: http://localhost:8080
  - service: http_status:404
EOF
ok "Wrote $CONFIG"

# ---------------------------------------------------------------------------
step "Done"
# ---------------------------------------------------------------------------
cat <<EOF

Bring the connector up:
  cd /srv/stack && sudo docker compose --profile cloudflared up -d

Verify:
  curl -sI https://$PREVIEW_APEX           # → 200, the "online" homepage
  curl -sI https://hello.$PREVIEW_APEX     # → 404 until you add-preview-site it

Add a preview:
  add-preview-site hello /srv/projects/hello-world
  open https://hello.$PREVIEW_APEX
EOF
