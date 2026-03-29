# dockerstiny

Docker-based local development environment for [Destiny.gg](https://www.destiny.gg) — a streaming and community platform. Runs the full stack (website, chat, wiki) locally via Docker Compose.

## Services

All services use the `dev` Docker Compose profile unless noted.

| Service | Tech | Role | Internal Port |
|------------|-------------------------------|-----------------------------------------------|---------------|
| **nginx** | Nginx 1.20 (Alpine) | Reverse proxy with TLS (mkcert). Routes to website, chat, live-ws | `$PORT_WWW` (default 8080), `$PORT_CDN` (default 8081) |
| **website** | PHP 8.4 FPM, Doctrine ORM, Twig, Symfony components | Main web application | 9000 (FPM) |
| **cron** | Same image as website | Scheduled tasks (`cron/index.php`) | — |
| **chat** | Go 1.21, Gorilla WebSocket | Real-time WebSocket chat server | 1118 |
| **live-ws** | TypeScript, ws, Redis | Live WebSocket API for streaming updates | 42069 |
| **redis** | Redis 5.0 (Alpine) | Caching, sessions, pub/sub messaging | 6379 |
| **mysql** | MariaDB 10.11.6 | Relational database (`destinygg` DB, user: `destiny`) | 3306 |
| **wikistiny** | MediaWiki + Wikistiny extension | Community wiki (SQLite) | `$PORT_WIKI` (default 8084) |

Test profile (`test`): `website-test` and `mysql-test` run PHPUnit against an isolated DB.

## Directory Structure

```
website/          PHP app — lib/ (Destiny namespace), views/ (Twig), assets/ (JS/TS), public/ (web root), config/
chat/             Go chat server — main.go, connection.go, settings.cfg
live-ws/          TypeScript WebSocket API — index.ts, src/, .env
chat-gui/         Chat UI component library (JS)
Wikistiny/        MediaWiki + extensions/Wikistiny/
docker/           Dockerfiles, nginx/php/mysql/wiki configs, TLS certs
scripts/          setup.sh (full env setup), cleanup.sh (teardown)
```

## Networking

```
Client → nginx (TLS) ─┬→ website (PHP-FPM :9000)
                       ├→ chat (WebSocket :1118)
                       └→ live-ws (WebSocket :42069)

website ↔ mysql (queries, Doctrine ORM)
website ↔ redis (sessions, cache)
chat    ↔ mysql (user data, persistence)
chat    ↔ redis (pub/sub)
live-ws ↔ redis (pub/sub for live streaming updates)
```

## Key Config Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service orchestration |
| `.env` | Port configuration (`PORT_WWW`, `PORT_CDN`, `PORT_WIKI`) |
| `website/config/config.local.php` | Website app config (CORS, crypto keys, embeds) |
| `chat/settings.cfg` | Chat server settings (Redis, MySQL, API) |
| `live-ws/.env` | Live WS config (ports, API URL/key, Redis) |
| `docker/nginx-config/dgg.local.conf` | Nginx routing and SSL |
| `docker/wiki-config/LocalSettings.php` | MediaWiki configuration |

## Common Commands

```bash
# Start/stop the dev environment
docker compose --profile dev up -d
docker compose --profile dev down

# Full setup from scratch
./scripts/setup.sh

# Tear down everything (containers, volumes, certs)
./scripts/cleanup.sh

# Rebuild a single service
docker compose --profile dev build <service>
docker compose --profile dev up -d <service>

# Run website tests
docker compose --profile test run --rm website-test

# Website frontend (from website/ dir)
npm run dev      # watch mode
npm run build    # production build

# Database migrations (from website container)
docker compose --profile dev exec website php migrations.php

# Generate a diff migration (from website container)
docker compose --profile dev exec website vendor/bin/doctrine-migrations migrations:diff
# Note: the generated migration file may need manual edits for changes not managed by the ORM.

# Impersonate a user (in browser) — port depends on PORT_WWW in .env
# https://localhost:$PORT_WWW/impersonate?username=admin
```

## Frontend Stack (website)

Webpack, Bootstrap 5.3, Hotwired Stimulus, ESLint, Prettier. Source in `website/assets/`, built output in `website/static/`.
