#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
skip()  { printf '\033[1;33m[SKIP]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
err()   { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*" >&2; }

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

# ── 2. TLS certificates (mkcert) ────────────────────────────────────────────

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

# ── 3. Clone repositories ───────────────────────────────────────────────────

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

# ── 4. Copy config files ────────────────────────────────────────────────────

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

# ── 5. Install dependencies & build ─────────────────────────────────────────

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

# ── 6. Build Docker images ───────────────────────────────────────────────────

info "Building Docker images (this may take a while on first run)..."
docker compose --profile dev build
ok "Docker images built"

# ── 7. Run database migrations ───────────────────────────────────────────────

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
info "Access the site at https://localhost:8080"
info "Log in as admin: https://localhost:8080/impersonate?username=admin"
