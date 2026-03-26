#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }

# ── Parse flags ──────────────────────────────────────────────────────────────

KEEP_REPOS=true
for arg in "$@"; do
  case "$arg" in
    --all) KEEP_REPOS=false ;;
    -h|--help)
      echo "Usage: $0 [--all]"
      echo ""
      echo "Stops containers, removes images, volumes, and generated configs."
      echo ""
      echo "  --all    Also remove cloned repositories (website, chat, chat-gui, live-ws, Wikistiny)"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)"
      exit 1
      ;;
  esac
done

# ── 1. Stop containers and remove images + volumes ──────────────────────────

info "Stopping containers and removing images/volumes..."
docker compose --profile dev --profile test down --rmi local --volumes --remove-orphans
ok "Containers, images, and volumes removed"

# ── 2. Remove generated config files ────────────────────────────────────────

info "Removing generated config files..."

generated_files=(
  docker/nginx-config/dgg.local.conf
  docker/wiki-config/LocalSettings.php
  website/config/config.local.php
  website/.env
  chat/settings.cfg
  live-ws/.env
)

for f in "${generated_files[@]}"; do
  if [ -f "$f" ]; then
    rm "$f"
    ok "Removed $f"
  fi
done

# ── 3. Remove TLS certificates ──────────────────────────────────────────────

info "Removing TLS certificates..."

cert_files=(
  docker/nginx-certs/dgg.pem
  docker/nginx-certs/dgg-key.pem
  docker/ca-certs/rootCA.pem
)

for f in "${cert_files[@]}"; do
  if [ -f "$f" ]; then
    rm "$f"
    ok "Removed $f"
  fi
done

# ── 4. Remove cloned repositories (only with --all) ─────────────────────────

if [ "$KEEP_REPOS" = false ]; then
  info "Removing cloned repositories..."
  for dir in website chat chat-gui live-ws Wikistiny; do
    if [ -d "$dir" ]; then
      rm -rf "$dir"
      ok "Removed $dir/"
    fi
  done
else
  info "Keeping cloned repositories (use --all to remove them too)"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
ok "Cleanup complete. Run scripts/setup.sh to start fresh."
