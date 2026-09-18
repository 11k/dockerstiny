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
      echo "Removes every environment (containers, volumes, worktrees — discarding"
      echo "uncommitted changes in them), the proxy, base images, database"
      echo "snapshots, TLS certs and dgg.conf. Branches and config/ are kept."
      echo ""
      echo "  --all    Also remove config/ and the cloned repositories"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)"
      exit 1
      ;;
  esac
done

# ── 1. Remove every environment ─────────────────────────────────────────────

if [ -f dgg.conf ] && [ -d envs ]; then
  for env_file in envs/*/env; do
    [ -f "$env_file" ] || continue
    name="$(basename "$(dirname "$env_file")")"
    info "Removing environment '$name'..."
    bin/dgg rm "$name" --force
  done
fi
rm -rf envs

# ── 2. Remove the proxy, base worktrees, images and snapshots ───────────────

if [ -f dgg.conf ]; then
  info "Stopping the proxy..."
  bin/dgg proxy down || warn "Couldn't stop the proxy"
fi
rm -f proxy/dynamic/tunnel.yml

for svc in chat live-ws; do
  if [ -d ".dgg/base/$svc" ] && [ -d "$svc/.git" ]; then
    git -C "$svc" worktree remove --force "$PWD/.dgg/base/$svc" || warn "Couldn't remove the $svc base worktree"
  fi
done
rm -rf .dgg

info "Removing base images..."
for image in dgg/website:dev dgg/worker:dev dgg/chat:base dgg/live-ws:base dgg/wikistiny:dev; do
  docker image rm "$image" >/dev/null 2>&1 && ok "Removed $image" || true
done

# ── 3. Remove TLS certificates and settings ─────────────────────────────────

info "Removing TLS certificates and settings..."
for f in docker/nginx-certs/wildcard.pem docker/nginx-certs/wildcard-key.pem \
         docker/nginx-certs/wildcard.domain docker/ca-certs/rootCA.pem dgg.conf; do
  if [ -f "$f" ]; then
    rm "$f"
    ok "Removed $f"
  fi
done

# ── 4. Remove shared config and cloned repositories (only with --all) ───────

if [ "$KEEP_REPOS" = false ]; then
  info "Removing shared config and cloned repositories..."
  rm -rf config
  for dir in website chat chat-gui live-ws Wikistiny; do
    if [ -d "$dir" ]; then
      rm -rf "$dir"
      ok "Removed $dir/"
    fi
  done
else
  info "Keeping config/ and the cloned repositories (use --all to remove them too)"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
ok "Cleanup complete. Run bin/dgg init to start fresh."
