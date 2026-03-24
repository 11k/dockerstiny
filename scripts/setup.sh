#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
skip()  { printf '\033[1;33m[SKIP]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
err()   { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }

prompt_value() {
  local varname="$1" default="$2" description="$3"
  local current="${!varname:-$default}"
  read -rp "  $description [$current]: " input
  printf '%s' "${input:-$current}"
}

# ── 1. Check prerequisites ──────────────────────────────────────────────────

missing=()
for cmd in docker npm mkcert; do
  command -v "$cmd" &>/dev/null || missing+=("$cmd")
done
# docker compose is a subcommand, not a standalone binary
if command -v docker &>/dev/null && ! docker compose version &>/dev/null; then
  missing+=("docker compose")
fi

if [ ${#missing[@]} -gt 0 ]; then
  err "Missing required tools: ${missing[*]}"
  err "Install them and re-run this script. See README.md for details."
  exit 1
fi
ok "All prerequisites found"

# ── 2. Configure ports ───────────────────────────────────────────────────────

ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

info "Configure host-facing ports (press Enter to accept defaults):"
PORT_WWW=$(prompt_value PORT_WWW 8080 "Website HTTPS port")
echo
PORT_CDN=$(prompt_value PORT_CDN 8081 "CDN HTTPS port")
echo
PORT_WIKI=$(prompt_value PORT_WIKI 8084 "MediaWiki port")
echo
PORT_MYSQL=$(prompt_value PORT_MYSQL 3333 "MySQL host port")
echo
COMPOSE_PROJECT_NAME=$(prompt_value COMPOSE_PROJECT_NAME dockerstiny "Compose project name")
echo

cat > "$ENV_FILE" <<EOF
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME
PORT_WWW=$PORT_WWW
PORT_CDN=$PORT_CDN
PORT_WIKI=$PORT_WIKI
PORT_MYSQL=$PORT_MYSQL
EOF
ok "Port configuration saved to .env"

# ── 3. TLS certificates (mkcert) ────────────────────────────────────────────

CERT="docker/nginx-certs/dgg.pem"
KEY="docker/nginx-certs/dgg-key.pem"
CA_DEST="docker/ca-certs/rootCA.pem"

if [ -f "$CERT" ] && [ -f "$KEY" ] && [ -f "$CA_DEST" ]; then
  skip "TLS certs already exist (delete docker/nginx-certs/dgg*.pem to regenerate)"
else
  info "Installing local CA with mkcert..."
  mkcert -install

  info "Generating TLS certificate..."
  mkcert -cert-file "$CERT" -key-file "$KEY" localhost 127.0.0.1 host.docker.internal

  info "Copying CA root certificate..."
  cp "$(mkcert -CAROOT)/rootCA.pem" "$CA_DEST"

  ok "TLS certificates generated"
fi

# ── 4. Clone repositories ───────────────────────────────────────────────────

declare -A repos=(
  [website]="git@github.com:destinygg/website-private.git"
  [chat]="git@github.com:destinygg/chat-private.git"
  [chat-gui]="git@github.com:destinygg/chat-gui.git"
  [live-ws]="git@github.com:destinygg/live-ws.git"
  [Wikistiny]="git@github.com:destinygg/Wikistiny.git"
)

for dir in website chat chat-gui live-ws Wikistiny; do
  if [ -d "$dir/.git" ]; then
    skip "Repo '$dir' already cloned"
  else
    info "Cloning $dir..."
    git clone "${repos[$dir]}" "$dir"
    ok "Cloned $dir"
  fi
done

# ── 5. Copy config files ────────────────────────────────────────────────────

copy_config() {
  local src="$1" dest="$2"
  if [ -f "$dest" ]; then
    skip "Config already exists: $dest"
  else
    cp "$src" "$dest"
    ok "Copied $src -> $dest"
  fi
}

copy_config docker/website-config/config.local.php website/config/config.local.php
copy_config docker/website-config/.env              website/.env
copy_config docker/chat-config/settings.cfg         chat/settings.cfg
copy_config docker/live-ws-config/.env              live-ws/.env

# ── 6. Apply port configuration ─────────────────────────────────────────────

info "Generating config files from templates..."

# Generate nginx config from template (replace known defaults with configured ports)
sed \
  -e "s/listen 8081 ssl;/listen $PORT_CDN ssl;/" \
  -e "s/listen 8080 ssl;/listen $PORT_WWW ssl;/" \
  -e "s/:8080/:$PORT_WWW/g" \
  docker/nginx-config/dgg.local.conf.template > docker/nginx-config/dgg.local.conf

# Generate wiki config from template
sed \
  -e "s/localhost:8084/localhost:$PORT_WIKI/" \
  -e "s/:8080/:$PORT_WWW/g" \
  docker/wiki-config/LocalSettings.php.template > docker/wiki-config/LocalSettings.php

ok "Generated config files from templates"

info "Patching copied config files with port settings..."

# Patch website config (use -E for extended regex; patterns match any port number)
sed -i '' -E \
  -e "s|https://localhost:[0-9]+|https://localhost:$PORT_WWW|g" \
  -e "s|wss://localhost:[0-9]+|wss://localhost:$PORT_WWW|g" \
  -e "s|127\.0\.0\.1:[0-9]+','protocol|127.0.0.1:$PORT_CDN','protocol|" \
  -e "s|'/wiki' => 'http://localhost:[0-9]+'|'/wiki' => 'http://localhost:$PORT_WIKI'|" \
  website/config/config.local.php

# Patch website .env
sed -i '' -E \
  -e "s|wss://localhost:[0-9]+|wss://localhost:$PORT_WWW|" \
  -e "s|https://127\.0\.0\.1:[0-9]+|https://127.0.0.1:$PORT_CDN|" \
  website/.env

# Patch chat config
sed -i '' -E \
  -e "s|allowedoriginhost = localhost:[0-9]+|allowedoriginhost = localhost:$PORT_WWW|" \
  -e "s|host\.docker\.internal:[0-9]+/api|host.docker.internal:$PORT_WWW/api|" \
  chat/settings.cfg

# Patch live-ws .env
sed -i '' -E \
  -e "s|host\.docker\.internal:[0-9]+/api|host.docker.internal:$PORT_WWW/api|" \
  live-ws/.env

ok "Port configuration applied to all config files"

# ── 7. Install dependencies & build ─────────────────────────────────────────

info "Installing chat-gui dependencies..."
(cd chat-gui && npm ci)
ok "chat-gui dependencies installed"

info "Installing website dependencies..."
(cd website && npm ci)
ok "website dependencies installed"

info "Linking local chat-gui into website..."
(cd website && npm link ../chat-gui)
ok "chat-gui linked"

info "Building website static assets..."
(cd website && npm run build)
ok "Website built"

# ── 8. Build Docker images ───────────────────────────────────────────────────

info "Building Docker images (this may take a while on first run)..."
docker compose --profile dev build
ok "Docker images built"

# ── 9. Run database migrations ───────────────────────────────────────────────

info "Starting containers temporarily to run migrations..."
docker compose --profile dev up -d

info "Waiting for website container to be ready..."
retries=30
until docker compose --profile dev exec website true 2>/dev/null; do
  retries=$((retries - 1))
  if [ "$retries" -le 0 ]; then
    err "Timed out waiting for website container"
    exit 1
  fi
  sleep 2
done

info "Running database migrations..."
docker compose --profile dev exec website vendor/bin/doctrine-migrations migrations:migrate -q
ok "Migrations complete"

info "Stopping containers..."
docker compose --profile dev down
ok "Containers stopped"

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
ok "Setup complete!"
info "Run 'docker compose --profile dev up' to start the dev environment"
info "Access the site at https://localhost:$PORT_WWW"
info "Log in as admin: https://localhost:$PORT_WWW/impersonate?username=admin"
